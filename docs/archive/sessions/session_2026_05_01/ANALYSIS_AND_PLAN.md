# aq_graph_engine — Анализ и план устранения

**Дата:** 2026-05-01  
**Пакет:** `aq_graph_engine`  
**Задача пакета:** исполнять граф максимально эффективно  
**Scope:** только `aq_graph_engine`, без изменений `aq_schema` и других пакетов

---

## Часть 1. Прожарка — объективная критика

### 🔴 КРИТИЧЕСКИЕ

---

#### C1. `IRunRepository` и `IGraphRepository` живут в движке, а не в `aq_schema`

**Файлы:** `lib/src/interfaces/i_run_repository.dart`, `lib/src/interfaces/i_graph_repository.dart`

По правилу `aq_schema_architecture_rules`: интерфейс нужный двум и более пакетам живёт в `aq_schema`.  
`IRunRepository` используется в `aq_graph_engine` и в `aq_graph_worker`. Сейчас `aq_graph_worker` вынужден зависеть от `aq_graph_engine` чтобы получить этот интерфейс — нарушение `no_cross_package_deps`.

**Мировой опыт:** В Temporal, Cadence — все storage-контракты определены в core-пакете, реализации в отдельных пакетах.

---

#### C2. `WorkflowRunner` — God Object (400+ строк, 7 ответственностей)

**Файл:** `lib/src/server/runners/workflow_runner.dart`

Один класс делает:
1. Управление жизненным циклом run (start/complete/fail)
2. Обход графа (traversal)
3. Выполнение узлов (execution)
4. Retry логику
5. Suspend/Resume
6. Сериализацию/десериализацию контекста
7. Логирование + метрики

**Мировой опыт:** В Temporal — `WorkflowWorker` (lifecycle) + `WorkflowTaskHandler` (execution) + `ActivityWorker` (node execution) — разные классы. В Airflow — `TaskRunner` отдельно от `DagRun`.

---

#### C3. Управление потоком через статус в репозитории

**Файл:** `workflow_runner.dart`, строки ~285, ~178

```dart
final currentRun = await _repo.getRun(runId);
if (currentRun?['status'] == 'suspended' && !_isResuming) return;
```

Логика обхода графа зависит от I/O запроса к репозиторию на каждом шаге. Это:
- Coupling между traversal и persistence
- Лишний I/O на каждый узел
- Источник багов (флаг `_isResuming` — симптом)

**Мировой опыт:** В Temporal — state machine in-memory, персистентность через event sourcing отдельно. В Prefect — `FlowRun` state machine изолирована от storage.

---

#### C4. `Map<String, dynamic>` как API репозитория

**Файл:** `i_run_repository.dart`

```dart
Future<Map<String, dynamic>?> getRun(String runId);
Future<void> createRun({..., required Map<String, dynamic> graphSnapshot});
```

Строковые ключи `'status'`, `'contextJson'`, `'suspendedNodeId'` разбросаны по 3 файлам. `WorkflowRun` уже существует в `aq_schema` — репозиторий должен возвращать его.

---

#### C5. Нет защиты от циклов в графе

**Файл:** `workflow_runner.dart`, `instruction_runner.dart`

`WorkflowRunner` — рекурсивный обход без проверки посещённых узлов. Граф с циклом A→B→A вызовет stack overflow. `InstructionRunner` защищён `maxSteps`, но это не то же самое что детекция цикла.

**Мировой опыт:** Airflow, Prefect, Dagster — DAG валидируется на ациклизм при загрузке, не при выполнении.

---

### 🟠 СЕРЬЁЗНЫЕ

---

#### S1. Двойной формат `contextJson` — незавершённая миграция

**Файл:** `workflow_runner.dart`, строки ~97–115

```dart
if (parsedState.containsKey('user_context')) {
  // новый формат
} else {
  // старый формат
}
```

Два формата в одном коде — источник скрытых багов. Нужно выбрать один и мигрировать.

---

#### S2. `print()` вместо структурированного логгера

**Файлы:** `workflow_runner.dart`, `local_engine_transport.dart`, `http_engine_transport.dart`

`WorkflowRunner` использует `print()` напрямую. `PromptRunner` использует `graphEngineServerLogger` (правильно). Нет единого подхода. В продакшне `print()` нельзя отключить, нет уровней, нет структуры.

---

#### S3. `_logs: List<String>` — накопление в памяти + O(n) I/O

**Файл:** `workflow_runner.dart`

Все логи накапливаются в памяти и при каждом `updateRunLog` передаются целиком. При 1000 узлах — 1000 строк передаются 1000 раз = O(n²) данных. Нужен append-only подход.

---

#### S4. `buildDefaultRegistry()` — создаётся на каждый вызов

**Файл:** `local_engine_transport.dart`, строка ~90

```dart
final registry = buildDefaultRegistry(); // при каждой конвертации
```

Создаёт новый реестр с регистрацией всех типов при каждой конвертации deprecated `WorkflowGraph`. По правилам `dip_ports_rules` — синглтон через `INodeTypeRegistry.instance`.

---

#### S5. Конвертация `WorkflowGraph → TypedWorkflowGraph` в транспорте

**Файл:** `local_engine_transport.dart`, строки ~85–110

Транспорт не должен трансформировать модели. Это ответственность репозитория или фабрики. Транспорт — передача данных.

---

#### S6. `_graphRepo` и `_tools` — мёртвые поля

**Файл:** `workflow_runner.dart`

```dart
// ignore: unused_field
final IGraphRepository _graphRepo;
// ignore: unused_field
final IToolService _tools;
```

Принимаются в конструктор, не используются. Либо нужны — тогда использовать. Либо нет — убрать из конструктора.

---

#### S7. `_RunRepoWithEvents` — Decorator с 100 строк boilerplate

**Файл:** `local_engine_transport.dart`

Дублирует все методы `IRunRepository`. Должен быть отдельным файлом или реализован через callback injection.

---

#### S8. `nodeTimer` не останавливается при `SuspendExecutionException`

**Файл:** `workflow_runner.dart`, `_processNode`

При suspend — `nodeTimer.stop()` никогда не вызывается. Утечка таймера метрик.

---

#### S9. `getDLQJobs` и `cleanupDLQ` — заглушки в продакшне

**Файл:** `data_layer_run_repository.dart`

```dart
Future<List<Map<String, dynamic>>> getDLQJobs(...) async => []; // TODO
Future<int> cleanupDLQ(...) async => 0; // TODO
```

По правилам `agent_framework.xml` — незавершённая реализация недопустима.

---

### 🟡 АРХИТЕКТУРНЫЕ НЕСООТВЕТСТВИЯ

---

#### A1. `GraphEngine` сам создаёт транспорты — нарушение DIP

**Файл:** `graph_engine.dart`

По правилам `dip_ports_rules`: только приложение (точка сборки) создаёт реализации. `GraphEngine` сам создаёт `LocalEngineTransport`, `HttpEngineTransport`, `_AutoFallbackTransport`. Правильно — принимать `IEngineTransport` снаружи.

---

#### A2. `_AutoFallbackTransport` в файле `graph_engine.dart`

Приватный класс в том же файле что и `GraphEngine`. Нарушение принципа одного файла — одной ответственности.

---

#### A3. Импорты — нарушение barrel правил

**Файлы:** `workflow_runner.dart`, `local_engine_transport.dart`

```dart
import 'package:aq_schema/aq_schema.dart';           // полный barrel
import 'package:aq_schema/graph/nodes/base/...';     // прямой импорт
```

Смешаны barrel и прямые импорты. По правилам — минимально необходимый barrel (`graph.dart`), не `aq_schema.dart`.

---

#### A4. `ConditionEvaluator` живёт в движке, должен быть в `aq_schema`

**Файл:** `lib/src/server/engine/condition_evaluator.dart`

Чистая утилита без зависимостей на движок. По правилам — переиспользуемые утилиты в `aq_schema`. Сейчас недоступна другим пакетам.

---

#### A5. `IWorkflowNode` в `lib/src/server/nodes/` — дубль интерфейса из `aq_schema`

**Файл:** `lib/src/server/nodes/i_workflow_node.dart`

Этот файл объявляет `IWorkflowNode` с другой сигнатурой `execute()`:
```dart
// В движке:
Future<dynamic> execute(RunContext context, ToolRegistry tools, IGraphRepository graphRepo);
// В aq_schema:
Future<dynamic> execute(RunContext context);
```

Два несовместимых интерфейса с одним именем. Это критическая архитектурная проблема — какой из них реальный контракт?

---

#### A6. Параллельное выполнение — shared mutable state без синхронизации

**Файл:** `workflow_runner.dart`, `_executeEdges`

При `EdgeExecutionMode.parallel` несколько `_processNode` пишут в общий `_logs` и `_visitedEdges` одновременно. В Dart это безопасно только без `await` между операциями — но здесь `await` есть.

---

### 🔵 КАЧЕСТВО КОДА

---

#### Q1. Магические строки без констант

```dart
run['status'] == 'suspended'   // 6 раз
run['contextJson']              // 3 раза
run['suspendedNodeId']          // 2 раза
```

---

#### Q2. Усечение ID — дублирование логики

```dart
runId.length > 6 ? runId.substring(0, 6) : runId   // 4 раза
node.id.length > 4 ? node.id.substring(0, 4) : node.id  // 5 раз
```

Должна быть одна функция `_shortId(String id, [int len = 6])`.

---

#### Q3. Stack trace пишется дважды

```dart
_log('Stack trace: $stack');
print('Stack trace: $stack');
```

---

#### Q4. `PromptRunner._createPromptNode` возвращает только `TextBlockNode?`

**Файл:** `prompt_runner.dart`

Возвращаемый тип `TextBlockNode?` вместо `IPromptNode?`. Нарушение LSP — метод должен возвращать интерфейс.

---

#### Q5. `InstructionRunner` — конвертация через `InstructionNodeFactory` при каждом шаге

**Файл:** `instruction_runner.dart`

```dart
final polymorphicNode = InstructionNodeFactory.fromJson(firstNode.toJson());
```

Сериализация → десериализация на каждом узле. Если граф уже типизирован — это лишняя работа.

---

## Часть 2. О State Machine — нюансы

### Текущее состояние

Сейчас статус run (`running/suspended/completed/failed`) хранится в репозитории и проверяется через I/O в `_processNode`. Это не state machine — это опрос БД.

### Ты прав: state machine → отдельный сервис

По архитектуре платформы state machine жизненного цикла run должна быть в отдельном сервисе (назовём его `IRunLifecycleService` или `IRunStateService` в `aq_schema`). Движок делегирует ему все переходы состояний.

### Нюансы которые нужно учесть

**Нюанс 1: Stateless runner vs. stateful run**

Движок должен быть stateless — он берёт граф, контекст, выполняет, возвращает результат. Состояние run (статус, контекст, логи) — ответственность внешнего сервиса. Сейчас runner хранит `_logs`, `_visitedEdges`, `_arrivedEdges` — это state run'а, не runner'а.

**Нюанс 2: Suspend/Resume без state machine**

Текущий suspend/resume работает через сохранение JSON снапшота контекста. Это правильный подход для stateless runner'а — runner не помнит ничего между вызовами, всё восстанавливается из снапшота. Проблема не в подходе, а в том что снапшот смешан с логикой runner'а.

**Нюанс 3: `_isResuming` флаг — симптом отсутствия явных переходов**

Флаг появился потому что runner проверяет статус в репо для управления потоком. Если runner будет stateless и получать явный `RunMode` (new/resume) как параметр — флаг не нужен.

**Нюанс 4: Параллельные ветки и shared state**

При параллельном выполнении `_visitedEdges` и `_arrivedEdges` — shared mutable state. В stateless подходе это должно быть частью снапшота контекста, не полями runner'а.

**Нюанс 5: `waitAll` join strategy**

`_arrivedEdges` используется для `NodeJoinStrategy.waitAll`. В stateless runner'е это состояние должно персистироваться между вызовами — иначе при resume после suspend join не восстановится.

---

## Часть 3. План устранения

### Принципы плана

- Каждый этап — атомарный, проверяемый, не ломает существующие тесты
- После каждого этапа: `dart analyze` + `dart test` + запуск сценариев
- Пакет развивается независимо — примеры для отработки сценариев
- Без изменений `aq_schema` в рамках этих этапов (отдельная сессия)

---

### Этап 0: Baseline (уже готово)

```
✅ dart analyze — 0 errors
✅ dart test test/unit/ — 52/52
✅ Сценарии 01, 02, 03, 05 — УСПЕХ
```

---

### Этап 1: Быстрые wins — качество кода

**Цель:** убрать мусор без изменения архитектуры.

**Задачи:**

1.1. Добавить `_shortId(String id, [int len = 6])` — убрать 9 дублирований  
1.2. Убрать дублирование `print('Stack trace: $stack')` + `_log(...)`  
1.3. Убрать `_graphRepo` и `_tools` из конструктора `WorkflowRunner` (unused)  
1.4. Остановить `nodeTimer` при `SuspendExecutionException`  
1.5. Исправить возвращаемый тип `_createPromptNode` → `IPromptNode?`  

**Проверка:**
```bash
dart analyze
dart test test/unit/
dart run bin/main.dart  # сценарии 01-05
```

---

### Этап 2: Типобезопасность репозитория

**Цель:** убрать `Map<String, dynamic>` из API `IRunRepository`.

**Задачи:**

2.1. Изменить `IRunRepository.getRun()` → возвращает `WorkflowRun?` (из `aq_schema`)  
2.2. Изменить `IRunRepository.createRun()` → принимает `WorkflowRun` вместо Map  
2.3. Обновить `DataLayerRunRepository` — убрать `toMap()` в `getRun`  
2.4. Обновить `WorkflowRunner` — работать с `WorkflowRun` напрямую  
2.5. Обновить `LocalEngineTransport` — убрать строковые ключи  
2.6. Обновить `InMemoryRunRepo` в `shared/helpers.dart` (примеры)  

**Проверка:**
```bash
dart analyze  # 0 errors
dart test test/unit/
dart run  # сценарии 01-05
```

---

### Этап 3: Явный `RunMode` — убрать `_isResuming` флаг

**Цель:** runner получает явный режим запуска, не угадывает его по флагам.

**Задачи:**

3.1. Добавить `enum RunMode { fresh, resume }` в `EngineExecutionContext`  
3.2. Передавать `RunMode` в `WorkflowRunner.start()` явным параметром  
3.3. Убрать `_isResuming` поле — заменить на локальный параметр  
3.4. Убрать проверку `currentRun?['status'] == 'suspended'` из `_processNode` — заменить на `RunMode`  

**Проверка:**
```bash
dart analyze
dart test test/unit/
dart run  # сценарии 01-05, особенно 05 (suspend/resume)
```

---

### Этап 4: Единый формат `contextJson`

**Цель:** убрать двойной формат снапшота.

**Задачи:**

4.1. Зафиксировать формат: `{ user_context: {...}, engine_state: { visited_edges: [...] } }`  
4.2. Убрать ветку `else` (старый формат) из `WorkflowRunner.start()`  
4.3. Убедиться что `suspendRun` всегда пишет новый формат  
4.4. Добавить `RunSnapshot` value object для типобезопасной работы со снапшотом  

**Проверка:**
```bash
dart analyze
dart test test/unit/
dart run  # сценарии 01-05
```

---

### Этап 5: Защита от циклов

**Цель:** граф с циклом не вызывает stack overflow.

**Задачи:**

5.1. Добавить `_executedNodes: Set<String>` в `WorkflowRunner`  
5.2. В `_processNode` — проверять `_executedNodes` перед выполнением  
5.3. При обнаружении цикла — логировать и прерывать ветку (не весь run)  
5.4. Добавить тест: граф с циклом завершается с ошибкой, не зависает  
5.5. `InstructionRunner` — заменить `maxSteps` на детекцию цикла через `visited`  

**Проверка:**
```bash
dart test test/unit/  # новый тест на цикл
dart run  # сценарии 01-05
```

---

### Этап 6: Разбиение `WorkflowRunner`

**Цель:** SRP — каждый класс делает одно.

**Задачи:**

6.1. Выделить `GraphTraversal` — обход графа (edges, join strategy, parallel)  
6.2. Выделить `NodeExecutor` — выполнение узла с retry  
6.3. `WorkflowRunner` становится тонким оркестратором: создаёт `GraphTraversal` и `NodeExecutor`, управляет lifecycle  
6.4. `_RunRepoWithEvents` → отдельный файл `run_repo_event_bridge.dart`  

**Структура после:**
```
lib/src/server/runners/
  workflow_runner.dart        # оркестратор ~80 строк
  graph_traversal.dart        # обход графа ~150 строк
  node_executor.dart          # выполнение узла + retry ~80 строк
  run_repo_event_bridge.dart  # decorator репозитория ~100 строк
```

**Проверка:**
```bash
dart analyze
dart test  # все тесты
dart run  # все сценарии
```

---

### Этап 7: Логирование

**Цель:** единый структурированный логгер вместо `print()`.

**Задачи:**

7.1. Создать `lib/src/shared/logger.dart` (уже есть в `PromptRunner` — расширить)  
7.2. Заменить все `print()` в `WorkflowRunner` на `graphEngineLogger`  
7.3. Заменить все `print()` в `LocalEngineTransport` на `graphEngineLogger`  
7.4. Заменить все `print()` в `HttpEngineTransport` на `graphEngineLogger`  

**Проверка:**
```bash
dart analyze
dart test
```

---

### Этап 8: Append-only логи

**Цель:** убрать O(n²) передачу логов.

**Задачи:**

8.1. Добавить `appendLog(String runId, String entry)` в `IRunRepository`  
8.2. `WorkflowRunner` вызывает `appendLog` вместо `updateRunLog(runId, _logs)`  
8.3. Убрать накопление `_logs: List<String>` из runner'а  
8.4. Обновить реализации репозитория  

**Проверка:**
```bash
dart analyze
dart test
dart run  # все сценарии
```

---

### Этап 9: Stateless runner (финальный)

**Цель:** runner не хранит состояние между вызовами.

**Задачи:**

9.1. Перенести `_visitedEdges` и `_arrivedEdges` в `RunSnapshot` (персистируется)  
9.2. Runner восстанавливает их из снапшота при resume  
9.3. Runner не хранит `_logs` — только пишет через `appendLog`  
9.4. `WorkflowRunner` становится stateless — можно создавать на каждый вызов без потери данных  

**Проверка:**
```bash
dart analyze
dart test
dart run  # все сценарии, особенно 05
```

---

## Часть 4. Что НЕ входит в план этого пакета

Следующие задачи требуют отдельных сессий:

| Задача | Пакет | Причина |
|--------|-------|---------|
| `IRunRepository` → `aq_schema` | `aq_schema` | изменение общего контракта |
| `IGraphRepository` → `aq_schema` | `aq_schema` | изменение общего контракта |
| `ConditionEvaluator` → `aq_schema` | `aq_schema` | переиспользуемая утилита |
| `IRunLifecycleService` (state machine) | `aq_schema` + новый пакет | отдельный сервис |
| `getDLQJobs` / `cleanupDLQ` реализация | `aq_data_layer` | Vault query API |

---

## Часть 5. Сравнение с мировым опытом

| Аспект | aq_graph_engine сейчас | Temporal | Airflow | Prefect |
|--------|----------------------|----------|---------|---------|
| Runner size | 400+ строк, God Object | ~80 строк оркестратор | TaskRunner отдельно | FlowRunner отдельно |
| State management | флаги + I/O в traversal | event sourcing, in-memory FSM | DB отдельно от executor | DB отдельно |
| Cycle detection | нет (stack overflow) | DAG validation при регистрации | DAG validation | DAG validation |
| Logging | print() | structured + streaming | structured | structured |
| Parallelism | shared mutable state | immutable events | task isolation | task isolation |
| Type safety | Map<String, dynamic> | typed models | typed models | typed models |
| Suspend/Resume | JSON snapshot ✅ | event replay | checkpoint | checkpoint |
| Retry | в runner | декларативно в workflow definition | декларативно | декларативно |
| Circuit breaker | в HttpTransport ✅ | встроен | нет | нет |

**Что уже хорошо:**
- Suspend/Resume через JSON snapshot — правильный подход для stateless
- Circuit breaker в HttpTransport
- Метрики через `IMetricsService`
- `NodeTypeRegistry` — расширяемая система
- Разделение client/server barrel

**Что отстаёт:**
- God Object runner
- Нет cycle detection
- `print()` вместо логгера
- `Map<String, dynamic>` API
