# AQ Graph Engine — Обзорный документ: бизнес-логика, архитектура и production-готовность

> Составлено на основе анализа: `aq_schema`, `aq_graph_engine`, `aq_graph_worker`  
> Дата: апрель 2026

---

## 1. Идея и бизнес-ценность

### Концепция «Граф как Закон»

Ядро системы построено вокруг принципа: **любая активность в платформе — это выполнение графа**. Это сильная и состоятельная архитектурная идея:

- Написание кода агентом → WorkflowGraph
- Переиспользуемая логика → InstructionGraph
- Генерация промпта → PromptGraph

Такой подход даёт несколько ценных свойств из коробки: версионирование каждого процесса, визуализация логики, портабельность через JSON, композиция графов друг из друга. Для платформы агентов (AQ Studio) это правильное стратегическое решение — пользователь видит и может редактировать поведение агента как граф, а не как чёрный ящик.

### Три типа графов — чёткое разделение ответственности

| Тип | Роль | Suspend/Resume | Циклы |
|-----|------|---------------|-------|
| **WorkflowGraph** | Полный сценарий агента | ✅ Да | ❌ Нет |
| **InstructionGraph** | Переиспользуемая атомарная логика | ❌ Нет | ✅ Да (maxSteps=20) |
| **PromptGraph** | Компилятор промптов | ❌ Нет | ❌ Нет |

Разделение осмысленное. WorkflowGraph — это "пайплайн с паузами для человека", InstructionGraph — это "функция", PromptGraph — это "шаблонизатор". Каждый тип решает свою задачу без лишнего усложнения.

---

## 2. Архитектура системы

### Общая схема

```
┌─────────────────────────────────────────────┐
│               AQ Studio (UI)                │
└─────────────────────────┬───────────────────┘
                          │ HTTP / Redis
┌─────────────────────────▼───────────────────┐
│         graph_engine_server                  │
│  (Shelf HTTP, graceful shutdown, /metrics)  │
└─────────────────────────┬───────────────────┘
                          │
┌─────────────────────────▼───────────────────┐
│              GraphEngine (фасад)             │
│  ┌──────────────────────────────────────┐   │
│  │    IEngineTransport                  │   │
│  │    └─ LocalEngineTransport           │   │
│  │          ├─ PolymorphicWorkflowRunner│   │
│  │          ├─ InstructionRunner        │   │
│  │          └─ PromptRunner             │   │
│  └──────────────────────────────────────┘   │
│  ┌──────────────────────────────────────┐   │
│  │ IRunRepository  IGraphRepository     │   │
│  │ (абстракции — dart_vault адаптеры)   │   │
│  └──────────────────────────────────────┘   │
└─────────────────────────────────────────────┘
                          │
┌─────────────────────────▼───────────────────┐
│            aq_graph_worker                   │
│  Redis BRPOP → GraphWorker → GraphEngine    │
│  concurrency=N параллельных потребителей     │
└─────────────────────────────────────────────┘
```

### Качество архитектуры — что сделано правильно

**Чистые абстракции.** `IRunRepository` и `IGraphRepository` — правильные порты. Движок не знает о Drift, PostgreSQL или HTTP — он работает только с интерфейсами. Это делает движок тестируемым и переносимым.

**Stateless Worker (12-factor).** `GraphWorker` не хранит состояние выполнения — оно живёт в `IRunRepository`. Можно поднять N воркеров горизонтально без изменения кода.

**Полиморфизм вместо switch.** Движок полностью перешёл от `switch(nodeType)` к `node.execute(context, tools)`. Это правильно архитектурно — добавление нового типа узла не требует правки runner.

**Suspend/Resume.** Механизм сохранения состояния через `suspendRun()` и восстановления через `resumeStateJson` реализован и работает. Это критически важно для интерактивных агентов.

**Transport pattern.** `IEngineTransport` позволяет одному и тому же движку работать локально (десктоп), через HTTP (сервер) или через любой кастомный транспорт.

---

## 3. Production-готовность — детальная оценка

### 3.1. ✅ Что уже готово к production

**Prometheus + Grafana мониторинг**
- 8 метрик: счётчики запусков (started/completed/failed/suspended), счётчик node executions, retry счётчик, гистограммы длительности, gauges активных и очередных запусков
- Docker Compose стек с Prometheus scraping каждые 10s и prebuilt Grafana dashboard
- Endpoint `/metrics` работает

**Graceful Shutdown**
- SIGINT/SIGTERM перехватываются
- Воркер дожидается завершения активных jobs до 30 секунд
- HTTP сервер возвращает 503 новым запросам во время остановки

**Retry с экспоненциальным backoff**
- `maxRetries`, `retryDelayMs`, `useExponentialBackoff` настраиваются на уровне каждого узла
- Фильтрация по типу ошибки через `retryableExceptions`
- Метрика `graph_node_retries_total` пишется

**Redis Job Queue**
- BRPOP-based consumer с timeout polling
- `JobStatus` enum: pending → running → done/failed/timeout
- `setStatus`, `setResult` — контракт между адаптером и воркером чёткий

**Join Strategies**
- `waitAll`, `firstCome`, `waitPriority` реализованы в runner
- Отслеживание прибытия рёбер через `_arrivedEdges`

**Auth**
- JWT + offline validation через `jwtSecret`
- API key → access token flow через `AQSecurityClient`

---

### 3.2. 🚨 Критические блокеры перед production

#### БЛОКЕР 1: `isSystemTool` бросает `UnimplementedError` в воркере

Все три hands в `worker_hands_registry.dart` содержат:
```dart
@override
bool get isSystemTool => throw UnimplementedError();
```

Это не заглушка — это падение в рантайме при первом обращении к этому свойству. Если `ToolRegistry` или движок вызывает `isSystemTool` на любом hand — воркер упадёт с необработанным исключением.

#### БЛОКЕР 2: Нет реальных LLM и инструментов

`worker_hands_registry.dart` содержит только три тривиальных hand:
- `StateModifierHand` — устанавливает переменную
- `StringReplaceHand` — заменяет строку
- `JsonParserHand` — парсит JSON

Закомментировано:
```dart
// registry.register(GenericLlmHand(apiKey: llmApiKey, provider: llmProvider));
// registry.register(FsReadHand(basePath: sessionDir));
// registry.register(FsWriteHand(basePath: sessionDir));
```

Без `GenericLlmHand` `LlmActionNode` и `LlmQueryNode` не могут выполниться — агент не умеет обращаться к LLM. Это фундаментальный пробел: весь граф нельзя запустить с реальной задачей.

#### БЛОКЕР 3: MCP — нет ни одной реализации

В документации и pubspec упоминается MCP (Model Context Protocol) как способ подключения внешних сервисов. В коде нет ни одного MCP-адаптера, ни транспорта, ни регистрации инструментов через MCP. `aq_schema` содержит `mcp/models/mcp_tool.dart` (импортируется в worker_models), но это только модель данных — реализации нет.

#### БЛОКЕР 4: `WorkflowNodeFactory` помечен `@Deprecated` но используется везде

`PolymorphicWorkflowRunner` использует `WorkflowNodeFactory.fromJson()` в 4 местах (строки 2255, 2268, 2277, 2496). Сама фабрика помечена `@Deprecated('РУДИМЕНТ!')` с комментарием «Удалить после миграции». При этом `node_factory.dart` в движке поддерживает только тип `runInstruction` (остальные закомментированы как TODO). Налицо незавершённая миграция на полиморфную систему.

#### БЛОКЕР 5: Conditional edges не реализованы

В `PolymorphicWorkflowRunner._processNode()`:
```dart
case WorkflowEdgeType.conditional:
  // TODO: Реализовать оценку conditionExpression
  return true;
```

Любое условное ребро всегда возвращает `true`. Граф с ветвлением по условию будет работать неправильно.

---

### 3.3. ⚠️ Серьёзные риски

**Истечение access token при долгих графах**

Комментарий в коде:
```dart
// Access token живёт 15 минут — достаточно для одного job.
// При необходимости: воркер перезапускается (Docker restart policy).
```

Граф с интерактивными узлами (suspend/resume) может длиться часы или дни. После 15 минут токен истечёт, и все обращения к data service упадут с 401. Это требует механизма refresh токена или использования долгоживущего service account токена.

**Состояние гонки в параллельных ветках**

При параллельном выполнении рёбер (`EdgeExecutionMode.parallel`) несколько goroutine-подобных потоков пишут в `_logs` и `_visitedEdges` без синхронизации. Dart однопоточен в рамках одного Isolate, но `await Future.wait(...)` переключает контекст, и конкурентные `_logs.add()` технически безопасны, однако порядок логов непредсказуем. Более серьёзно: `context.state.addAll()` в параллельных ветках может создать race condition если контекст не клонируется правильно.

**Тестовый backdoor в production коде**

```dart
if (config.apiKey == 'test_api_key') {
  token = 'mock_token_for_tests';
}
```

Это должно быть убрано или вынесено в отдельный `TestGraphWorker`. В текущем виде — security issue.

**`print()` в production коде**

`graph_engine_client.dart` содержит:
```dart
print('🚀 Starting run: ${request.blueprintId}');
print('✅ Run started: ${result.runId}');
```

В production весь вывод должен идти через структурированный логгер, а не `print()`.

**InstructionRunner не защищён от циклов**

Документация обещает `maxSteps = 20`, но в реализации `InstructionRunner._processNode()` нет счётчика шагов. При циклическом графе — бесконечная рекурсия и stack overflow.

**`WorkflowEdge` в schema не имеет полей `priority`, `isExclusive`, `executionMode`**

Runner использует `edge.priority`, `edge.isExclusive`, `edge.executionMode`, но в `WorkflowEdge` из `workflow_graph.dart` этих полей нет (они, вероятно, в новой версии WorkflowEdge в `aq_schema` для новой архитектуры, но старый `WorkflowGraph` их не содержит). Это создаёт риск NullPointerException при работе с реальными графами из хранилища.

---

### 3.4. 📋 Незначительные замечания

- Нет rate limiting на HTTP endpoints воркера (`/run`, `/status`)
- Нет circuit breaker при недоступности data service
- Метрика `graph_queued_runs` объявлена, но нигде не обновляется
- `Future.delayed(const Duration(days: 365))` в `main()` — слишком грубый keep-alive (лучше использовать `Completer`)
- Отсутствуют unit тесты для runner, retry, graceful shutdown (Неделя 3 из плана)
- Нет dead letter queue для failed jobs в Redis

---

## 4. Сводная матрица готовности

| Компонент | Бизнес-логика | Код качество | Production-готовность |
|-----------|:---:|:---:|:---:|
| WorkflowGraph schema | ✅ Полная | ⚠️ Частично deprecated | ⚠️ Без новых полей edges |
| InstructionGraph | ✅ Полная | ✅ Хорошее | ⚠️ Нет защиты от цикла |
| PromptGraph | ✅ Полная | ✅ Хорошее | ✅ Готово |
| PolymorphicWorkflowRunner | ✅ Логика верна | ⚠️ Deprecated factory | 🚨 Conditional edge сломан |
| InstructionRunner | ✅ Логика верна | ✅ Хорошее | ⚠️ Нет maxSteps |
| GraphEngine (фасад) | ✅ | ✅ | ✅ |
| LocalEngineTransport | ✅ | ✅ | ✅ |
| GraphWorker (Redis consumer) | ✅ | ✅ | 🚨 Нет LLM/tools |
| Monitoring (Prometheus/Grafana) | ✅ | ✅ | ✅ Готово |
| Graceful Shutdown | ✅ | ✅ | ✅ Готово |
| Retry / Backoff | ✅ | ✅ | ✅ Готово |
| Auth / JWT | ✅ | ⚠️ Test backdoor | ⚠️ Token expiry risk |
| MCP Integration | ❌ Нет | ❌ | ❌ Не реализовано |
| LLM Hands | ❌ Нет | ❌ Стабы | ❌ Не реализовано |
| Тесты | ❌ Нет | — | ❌ Запланированы |

---

## 5. Приоритетный план до production

### 🔴 Приоритет 1 — Блокеры (до первого реального запуска)

1. **Реализовать `GenericLlmHand`** (Anthropic + OpenAI) и зарегистрировать в `worker_hands_registry.dart`
2. **Реализовать `FsReadHand` / `FsWriteHand`** с sandbox isolation
3. **Исправить `isSystemTool`** во всех hands (не выбрасывать UnimplementedError)
4. **Реализовать conditional edge evaluation** в PolymorphicWorkflowRunner
5. **Завершить миграцию WorkflowNodeFactory** — либо убрать `@Deprecated` и поддержать все типы, либо переключить runner на новую полиморфную систему

### 🟡 Приоритет 2 — Риски стабильности

6. **Token refresh** — добавить фоновый цикл обновления токена в GraphWorker
7. **maxSteps в InstructionRunner** — защита от бесконечных циклов
8. **Убрать тестовый backdoor** (`test_api_key`) из production кода
9. **Заменить `print()` на структурированный логгер** (пакет `logging`)
10. **Добавить поля `priority`, `isExclusive`, `executionMode` в WorkflowEdge** schema или проверить совместимость

### 🟢 Приоритет 3 — Качество и масштаб

11. **Unit + Integration тесты** (Неделя 3 по плану)
12. **MCP адаптер** — хотя бы базовый транспорт для подключения MCP серверов
13. **Dead letter queue** для failed jobs
14. **Метрика `graph_queued_runs`** — реальное заполнение из Redis
15. **Rate limiting** на worker HTTP endpoints

---

## 6. Заключение

**Архитектура системы хорошо спроектирована.** Принцип «Граф как Закон», три типа графов, полиморфные узлы, stateless worker, transport pattern — это грамотные решения, которые обеспечат долгосрочную расширяемость платформы.

**Инфраструктурный слой (мониторинг, shutdown, retry, auth, Redis) достаточно зрелый** для production при устранении нескольких рисков (token refresh, test backdoor).

**Бизнес-логика движка (пуск, suspend/resume, join, retry) реализована правильно** и покрывает основные use cases агентного workflow.

**Критический пробел — отсутствие реальных инструментов (LLM hands, FS hands, MCP).** Без них весь стек технически запускается, но агент ничего полезного сделать не может. Это главный барьер между текущим состоянием и первым production запуском.

Незавершённая миграция (deprecated WorkflowNodeFactory, conditional edges не работают) — второй по приоритету блокер. При правильной расстановке приоритетов система может выйти в production за 2–3 недели активной разработки.