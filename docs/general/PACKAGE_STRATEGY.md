# AQ Graph Engine — Стратегия пакета

> Агрегированный документ, объединяющий всю документацию пакета
> Дата создания: 2026-04-10
> Версия: 1.0

---

## Оглавление

1. [Философия и концепция](#1-философия-и-концепция)
2. [Архитектура системы](#2-архитектура-системы)
3. [Три типа графов](#3-три-типа-графов)
4. [Иерархия узлов](#4-иерархия-узлов)
5. [Режимы работы (Client/Server)](#5-режимы-работы-clientserver)
6. [Авторизация и безопасность](#6-авторизация-и-безопасность)
7. [Абстракция инструментов (AQToolService)](#7-абстракция-инструментов-aqtoolservice)
8. [Жизненный цикл выполнения](#8-жизненный-цикл-выполнения)
9. [Production-готовность](#9-production-готовность)
10. [План развития](#10-план-развития)
11. [Использование клиента](#11-использование-клиента)

---

## 1. Философия и концепция

### 1.1. Принцип "Граф как Закон"

**Ключевая идея:** В AQ Studio любая активность — это выполнение графа.

Это фундаментальный архитектурный принцип, который определяет всю систему:

- Написание кода агентом → WorkflowGraph
- Создание спецификации → WorkflowGraph
- Генерация промпта → PromptGraph
- Анализ кода → InstructionGraph
- Любая бизнес-логика → граф

### 1.2. Преимущества подхода

**Унификация** — один механизм для всех процессов:
- Не нужно создавать отдельные системы для разных типов задач
- Единый runtime для всего
- Общие инструменты разработки и отладки

**Версионирование** — каждый граф автоматически версионируется:
- История изменений из коробки
- Откат к предыдущим версиям
- Сравнение версий
- Аудит изменений

**Визуализация** — логика видна визуально:
- Не нужно читать код для понимания процесса
- Граф можно редактировать визуально
- Отладка через визуальный дебаггер
- Понятно даже не-программистам

**Переносимость** — экспорт/импорт через JSON:
- Графы можно делиться между проектами
- Импорт готовых решений из библиотеки
- Экспорт для резервного копирования
- Миграция между окружениями

**Композиция** — графы вызывают другие графы:
- Модульная архитектура
- Переиспользование логики
- Иерархическая структура
- Инкапсуляция сложности

**Приостановка** — можно остановить и продолжить позже:
- Интерактивное взаимодействие с пользователем
- Долгоживущие процессы
- Сохранение состояния в БД
- Возобновление после перезапуска

### 1.3. Бизнес-ценность для AQ Studio

Для платформы AI-агентов (AQ Studio) это правильное стратегическое решение:

**Прозрачность для пользователя:**
- Пользователь видит поведение агента как граф, а не как чёрный ящик
- Можно редактировать логику агента визуально
- Понятно что делает агент на каждом шаге

**Контроль и безопасность:**
- Пользователь может остановить выполнение в любой момент
- Можно проверить каждый шаг перед выполнением
- Аудит всех действий агента

**Гибкость и расширяемость:**
- Пользователь может создавать свои графы
- Можно комбинировать готовые блоки
- Marketplace графов и инструкций

---

## 2. Архитектура системы

### 2.1. Общая схема

```
┌─────────────────────────────────────────────────────────────┐
│                    AQ Studio (Flutter UI)                   │
│              (UI + вызовы готовых сервисов)                 │
│                   НИКАКОЙ БИЗНЕС-ЛОГИКИ!                    │
└─────────────────────────┬───────────────────────────────────┘
                          │ HTTP/WebSocket
                          ↓
┌─────────────────────────────────────────────────────────────┐
│              graph_engine_server (Shelf HTTP)               │
│  ┌──────────────────────────────────────────────────────┐   │
│  │              GraphEngine (фасад)                     │   │
│  │  ┌────────────────────────────────────────────────┐ │   │
│  │  │         IEngineTransport                       │ │   │
│  │  │  ┌──────────────────────────────────────────┐ │ │   │
│  │  │  │    LocalEngineTransport                  │ │ │   │
│  │  │  │      ├─ PolymorphicWorkflowRunner        │ │ │   │
│  │  │  │      ├─ InstructionRunner                │ │ │   │
│  │  │  │      └─ PromptRunner                     │ │ │   │
│  │  │  └──────────────────────────────────────────┘ │ │   │
│  │  └────────────────────────────────────────────────┘ │   │
│  │  ┌────────────────────────────────────────────────┐ │   │
│  │  │  IRunRepository  IGraphRepository             │ │   │
│  │  │  (абстракции — dart_vault адаптеры)           │ │   │
│  │  └────────────────────────────────────────────────┘ │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────┬───────────────────────────────────┘
                          │ Redis Queue
                          ↓
┌─────────────────────────────────────────────────────────────┐
│            aq_graph_worker (Background Worker)              │
│  Redis BRPOP → GraphWorker → GraphEngine                    │
│  concurrency=N параллельных потребителей                     │
│  Stateless (12-factor) — состояние в IRunRepository         │
└─────────────────────────────────────────────────────────────┘
```

### 2.2. Принцип "Тонкого клиента"

**КРИТИЧЕСКИ ВАЖНО:** Клиент НЕ реализует бизнес-логику сервиса.

**Клиент (Flutter приложение):**
- ✅ Отображает UI
- ✅ Вызывает готовые сервисы
- ✅ Обрабатывает события
- ✅ Показывает формы для ввода
- ❌ НЕ реализует логику выполнения графов
- ❌ НЕ реализует логику хранения данных
- ❌ НЕ дублирует серверную логику

**Сервер (Graph Engine):**
- ✅ Выполняет графы
- ✅ Управляет жизненным циклом
- ✅ Сохраняет состояние
- ✅ Обрабатывает ошибки
- ✅ Использует готовые репозитории от Data Layer

**Золотое правило:** Если клиенту чего-то не хватает — это задача для сервиса, а не для клиента.

### 2.3. Слои абстракции

**Уровень 1: GraphEngine (фасад)**
- Единая точка входа для выполнения любых графов
- Скрывает детали реализации
- Управляет зависимостями (tools, repos, transport)

**Уровень 2: IEngineTransport (абстракция транспорта)**
- LocalEngineTransport — локальное выполнение (desktop)
- HttpEngineTransport — удалённое выполнение (клиент → сервер)
- CustomTransport — любая кастомная реализация

**Уровень 3: Runners (исполнители)**
- PolymorphicWorkflowRunner — выполняет WorkflowGraph
- InstructionRunner — выполняет InstructionGraph
- PromptRunner — компилирует PromptGraph

**Уровень 4: Repositories (абстракция хранилища)**
- IRunRepository — хранилище запусков
- IGraphRepository — хранилище графов
- Реализации через dart_vault (не знают о БД)

### 2.4. Качество архитектуры

**Чистые абстракции:**
- `IRunRepository` и `IGraphRepository` — правильные порты
- Движок не знает о Drift, PostgreSQL или HTTP
- Работает только с интерфейсами
- Тестируемость и переносимость

**Stateless Worker (12-factor):**
- `GraphWorker` не хранит состояние выполнения
- Состояние живёт в `IRunRepository`
- Можно поднять N воркеров горизонтально
- Без изменения кода

**Полиморфизм вместо switch:**
- Было: `switch(nodeType) { case llmAction: ... }`
- Стало: `node.execute(context, tools)`
- Добавление нового типа узла не требует правки runner
- Каждый узел инкапсулирует свою логику

**Transport pattern:**
- `IEngineTransport` позволяет одному движку работать везде
- Локально (десктоп)
- Через HTTP (сервер)
- Через любой кастомный транспорт

---

## 3. Три типа графов

### 3.1. Сравнительная таблица

| Критерий | WorkflowGraph | InstructionGraph | PromptGraph |
|----------|---------------|------------------|-------------|
| **Назначение** | Полный сценарий агента | Переиспользуемая функция | Компилятор промптов |
| **Suspend/Resume** | ✅ Да | ❌ Нет | ❌ Нет |
| **Циклы** | ❌ Нет (DAG) | ✅ Да (maxSteps=20) | ❌ Нет |
| **UI узлы** | ✅ Да | ❌ Нет | ❌ Нет |
| **Параллельное выполнение** | ✅ Да (branches) | ❌ Нет | ❌ Нет |
| **Контракт входов/выходов** | ❌ Нет | ✅ Обязателен | ❌ Нет |
| **Вызов из другого графа** | ❌ Нет | ✅ Да (runInstruction) | ✅ Да (в LLM узлах) |
| **Версионирование** | ✅ Да | ✅ Да | ✅ Да |
| **Изоляция контекста** | ❌ Общий | ✅ Изолированный | ✅ Только чтение |

### 3.2. WorkflowGraph — Основной сценарий

**Суть:** Главный pipeline агента — полный сценарий работы от начала до конца.

**Когда использовать:**
- ✅ Автоматизация процесса разработки (анализ → генерация → тестирование)
- ✅ Интерактивные мастера с UI формами
- ✅ Code Review процессы
- ✅ Создание документации
- ✅ Процессы с параллельным выполнением

**Ключевые возможности:**

**Параллельное выполнение:**
```
        ┌─→ [analyze-security] ─┐
[start] ┤─→ [analyze-performance] ├─→ [merge]
        └─→ [analyze-style] ─────┘
```
- Один узел запускает несколько веток
- Join strategies: waitAll, firstCome, waitPriority
- Отслеживание прибытия рёбер

**Приостановка для UI:**
- Граф останавливается в узле userInput/manualReview
- Состояние сохраняется в БД
- UI показывает форму
- Пользователь вводит данные
- Граф возобновляется с того же места

**Интерактивные узлы:**
- `userInput` — запрос данных (с Dynamic UI)
- `manualReview` — ожидание подтверждения
- `fileUpload` — загрузка файла
- `coCreationChat` — интерактивный чат с AI

**Композиция:**
- `runInstruction` — вызов InstructionGraph как функции
- `subGraph` — вызов другого WorkflowGraph
- Input/output mapping для передачи данных

**Обработка ошибок:**
- Рёбра `onError` для альтернативных путей
- Retry с экспоненциальным backoff
- Фильтрация по типу ошибки

**Основные узлы:**
- `llmAction` — запрос к LLM
- `fileRead` / `fileWrite` — работа с файлами
- `userInput` — запрос данных у пользователя
- `manualReview` — ожидание подтверждения
- `runInstruction` — вызов Instruction графа
- `gitCommit` — коммит в Git

**Ограничения:**
- ❌ Нет циклов (должен быть DAG)
- ❌ Условия (conditional edges) в процессе реализации
- ❌ Нет timeout на уровне узла (планируется)

### 3.3. InstructionGraph — Переиспользуемая инструкция

**Суть:** Атомарная бизнес-логика с контрактом — как функция, но в виде графа.

**Когда использовать:**
- ✅ Переиспользуемая логика (анализ кода, генерация тестов)
- ✅ Композиция Skills в бизнес-процесс
- ✅ Версионирование бизнес-логики
- ✅ Сложные ветвления и проверки
- ✅ Циклические процессы (с защитой)

**Ключевые возможности:**

**Контракт входов/выходов:**
```json
{
  "inputs": [
    {"name": "source_code", "type": "string", "required": true}
  ],
  "outputs": [
    {"name": "analysis", "type": "string"}
  ]
}
```
- Чёткий интерфейс
- Валидация через JSON Schema
- Проверка перед выполнением

**Циклы разрешены:**
```
[LLM] → [Результат не пустой?]
          ├─ true → [Успех]
          └─ false → [Счётчик++] → [Счётчик < 3?]
                                      ├─ true → [LLM] (retry)
                                      └─ false → [Ошибка]
```
- Защита: maxSteps = 20
- Kill switch через статус в БД
- Подходит для retry логики

**Изолированный контекст:**
- Создаётся через `RunContext(...)`
- Выполняется полностью без пауз
- Input/output mapping через `CompositeNode`
- Не влияет на родительский контекст

**Основные узлы:**
- `systemAction` / `toolCall` — вызов Skill (LLM, файлы, векторный поиск)
- `validationCheck` / `condition` — проверка условия (ветвление)
- `stepDescription` — описательный шаг
- `transform` — преобразование данных

**Операторы условий:**
- `==`, `!=` — равенство
- `>`, `<`, `>=`, `<=` — сравнение чисел
- `contains` — содержит подстроку
- `isEmpty`, `isNotEmpty` — проверка пустоты
- `exists`, `notExists` — проверка существования

**Ограничения:**
- ❌ Максимум 20 шагов (защита от бесконечных циклов)
- ❌ Нет UI узлов (нельзя запросить ввод у пользователя)
- ❌ Нет параллельного выполнения

**Вызов из Workflow:**
```json
{
  "type": "runInstruction",
  "config": {
    "instruction_blueprint_id": "uuid-инструкции",
    "input_mapping": {
      "source_code": "file_content"
    },
    "output_mapping": {
      "analysis_result": "llm_result"
    }
  }
}
```

### 3.4. PromptGraph — Шаблон промпта

**Суть:** Конструктор промптов с переменными — промпты тоже графы!

**Когда использовать:**
- ✅ Промпты, которые используются в разных местах
- ✅ Промпты, которые часто меняются
- ✅ Промпты с переменными
- ✅ A/B тестирование промптов
- ✅ Версионирование промптов

**Ключевые возможности:**

**Переменные:**
```
Граф: [textBlock: "Проанализируй: {{source_code}}"]
Контекст: {source_code: "function main() {}"}
Результат: "Проанализируй: function main() {}"
```

**Версионирование:**
- Каждое изменение = новая версия
- Откат к предыдущей версии
- История изменений

**Композиция:**
- Промпт из нескольких блоков
- Условные блоки
- Вставка переменных с форматированием

**Основные узлы:**
- `textBlock` — блок текста с переменными `{{var}}`
- `variableInsert` — вставка переменной с prefix/suffix
- `conditionalBlock` — условный блок текста

**Компиляция:**
- Происходит ДО вызова LLM
- Возвращает готовую строку
- Использует контекст только для чтения

**Ограничения:**
- ❌ Нет сложной условной логики (if/else с вложенностью)
- ❌ Нет циклов
- ❌ Нет вложенных промптов

### 3.5. Как они работают вместе

**Архитектура композиции:**
```
WorkflowGraph (главный агент)
  ├─ Узел: llmAction
  │    └─ Использует: PromptGraph "Analyze Code"
  │
  ├─ Узел: runInstruction
  │    └─ Вызывает: InstructionGraph "Code Analyzer"
  │         ├─ Узел: systemAction (tool_id: llm_ask)
  │         │    └─ Использует: PromptGraph "Detailed Analysis"
  │         └─ Узел: validationCheck
  │
  └─ Узел: userInput (с Dynamic UI)
```

**Пример реального сценария:**

Задача: Проанализировать код, запросить подтверждение, создать отчёт.

```
1. [fileRead] — читаем main.dart
2. [runInstruction: "Code Analyzer"] — анализируем
   └─ Instruction внутри:
      - [systemAction: llm_ask с PromptGraph "Analysis"]
      - [validationCheck: результат не пустой?]
3. [userInput] — показываем результат, запрашиваем подтверждение
4. [fileWrite] — сохраняем отчёт
5. [gitCommit] — коммитим
```

---

## 4. Иерархия узлов

### 4.1. Полиморфная архитектура

**Принцип:** Каждый узел — это класс с методом `execute()`. Никаких switch/case.

**Было (enum-based):**
```dart
switch (node.type) {
  case WorkflowNodeType.llmAction:
    // 50 строк кода
    break;
  case WorkflowNodeType.fileRead:
    // 30 строк кода
    break;
  // ... ещё 8 case
}
```

**Стало (полиморфизм):**
```dart
await node.execute(context, tools);
```

**Преимущества:**
- Добавление нового типа узла = создание одного класса
- Логика узла инкапсулирована в его классе
- Каждый узел тестируется независимо
- Компилятор проверяет корректность вызовов

### 4.2. Базовая иерархия

```
$Node (базовый абстрактный класс)
├── IWorkflowNode (интерфейс для WorkflowGraph)
│   ├── AutomaticNode (автоматические узлы)
│   ├── InteractiveNode (интерактивные узлы)
│   └── CompositeNode (композитные узлы)
├── IInstructionNode (интерфейс для InstructionGraph)
└── IPromptNode (интерфейс для PromptGraph)
```

### 4.3. WorkflowGraph узлы (10 типов)

**AutomaticNode (4 типа)** — выполняются сразу:
- `LlmActionNode` — вызов LLM через Tool 'llm_ask'
- `FileReadNode` — чтение файла через Tool 'fs_read_file'
- `FileWriteNode` — запись файла через Tool 'fs_write_file'
- `GitCommitNode` — git commit через Tool 'git_commit'

**InteractiveNode (4 типа)** — требуют ввода пользователя:
- `UserInputNode` — запрос текстового ввода
- `ManualReviewNode` — ручная проверка и одобрение (approve/reject)
- `FileUploadNode` — загрузка файла пользователем
- `CoCreationChatNode` — интерактивный чат с пользователем

**CompositeNode (2 типа)** — содержат подграфы:
- `SubGraphNode` — выполнение вложенного WorkflowGraph
- `RunInstructionNode` — выполнение InstructionGraph как функции

### 4.4. InstructionGraph узлы (4 типа)

- `ToolCallNode` — вызов любого зарегистрированного Tool
- `LlmQueryNode` — запрос к LLM (с PromptGraph или прямым промптом)
- `ConditionNode` — условное ветвление
- `TransformNode` — преобразование данных (extract, format, parse, concat, split, trim)

### 4.5. PromptGraph узлы (3 типа)

- `TextBlockNode` — статический текстовый блок с подстановкой переменных
- `VariableInsertNode` — вставка переменной с prefix/suffix
- `ConditionalBlockNode` — условный блок текста

### 4.6. Регистрация узлов (NodeTypeRegistry)

**Проблема старого подхода:**
- `WorkflowNodeFactory` — статический switch
- Добавление нового типа требует правки фабрики
- Помечен как `@Deprecated`

**Новый подход (планируется):**
```dart
class NodeTypeRegistry {
  final _workflow = <String, IWorkflowNode Function(Map<String, dynamic>)>{};

  void registerWorkflow<T extends IWorkflowNode>(
    String typeKey,
    T Function(Map<String, dynamic>) fromJson,
  ) => _workflow[typeKey] = fromJson;

  IWorkflowNode workflowFromJson(Map<String, dynamic> json) {
    final type = json['type'] as String;
    final factory = _workflow[type];
    if (factory == null) throw UnknownNodeTypeException(type, 'workflow');
    return factory(json);
  }
}
```

**Регистрация:**
```dart
final registry = NodeTypeRegistry();
registry.registerWorkflow('llmAction', LlmActionNode.fromJson);
registry.registerWorkflow('fileRead', FileReadNode.fromJson);
// ... и так далее
```

**Преимущества:**
- Добавление нового типа — одна строка регистрации
- Никаких правок в runner
- Расширяемость без изменения кода движка

### 4.7. Conditional Edges — механизм выбора ветки

**Два уровня выбора:**

**Уровень 1: node.selectBranch(edges, result)**
- Узел может сам выбрать ветку по результату выполнения
- Возвращает branchName ребра
- Возвращает null — runner сам выбирает

**Уровень 2: runner выбирает по приоритету**
- Фильтр по onSuccess / onError
- Фильтр по conditionExpression (evaluator)
- Сортировка по priority (DESC)
- Если isExclusive — берём только первое

**Метод selectBranch в базовом классе:**
```dart
abstract interface class IWorkflowNode {
  String? selectBranch(List<WorkflowEdge> outgoingEdges, dynamic result) => null;
}
```

**Пример кастомной логики:**
```dart
class ConditionBranchNode extends AutomaticNode {
  @override
  String? selectBranch(List<WorkflowEdge> edges, dynamic result) {
    final passed = result as bool;
    final branchKey = passed ? 'true' : 'false';
    final edge = edges.firstWhereOrNull((e) => e.branchName == branchKey);
    return edge?.branchName;
  }
}
```

  }
}
```

---

## 5. Режимы работы (Client/Server)

### 5.1. Два режима — один пакет

Пакет `aq_graph_engine` должен уметь работать в двух режимах:

```
┌────────────────────────────────────────────────────────────────────┐
│                    aq_graph_engine                                  │
│                                                                     │
│  GraphEngineService.local(...)   GraphEngineService.remote(...)     │
│         │                                   │                       │
│   LocalEngineTransport              HttpEngineTransport             │
│   (выполняет граф здесь же)         (делегирует на сервер)          │
│         │                                   │                       │
│   PolymorphicWorkflowRunner         GraphEngineClient               │
│   InstructionRunner                 (SSE / HTTP polling)            │
│   PromptRunner                                                      │
└────────────────────────────────────────────────────────────────────┘
```

**Local mode** — движок работает в том же процессе (десктоп-приложение, CLI, тест).
**Remote mode** — движок работает на сервере, клиент получает только `GraphEngineService` с теми же методами и стримами событий.

### 5.2. Публичный API одинаков в обоих режимах

```dart
// Инициализация — выбор режима один раз при старте приложения
final engine = GraphEngineService.local(
  tools: myToolService,       // AQToolService
  runRepo: myRunRepo,
  graphRepo: myGraphRepo,
  auth: myAuthClient,         // AQAuthClient
);

// — или —

final engine = GraphEngineService.remote(
  baseUrl: 'https://engine.aq.io',
  auth: myAuthClient,
);

// Использование — одинаково в обоих режимах
final stream = engine.run(GraphRunRequest(...));
await engine.resume(runId, userInput);
await engine.cancel(runId);
```

**Ключевой принцип:** Клиентская часть приложения работает **только** через `GraphEngineService` — она не знает, где физически выполняется граф.

### 5.3. Структура пакета

```
aq_graph_engine/
├── lib/
│   ├── aq_graph_engine.dart          # Публичный API (ТОЛЬКО клиент)
│   ├── server.dart                   # Серверный экспорт (КРИТИЧНО!)
│   │
│   └── src/
│       ├── client/                   # Клиентская часть
│       │   ├── graph_engine_client.dart
│       │   ├── graph_run_stream.dart
│       │   └── models.dart
│       │
│       ├── server/                   # Серверная часть
│       │   ├── engine/
│       │   │   ├── graph_engine.dart
│       │   │   └── engine_execution_context.dart
│       │   ├── runners/
│       │   ├── monitoring/
│       │   └── registry/
│       │
│       ├── interfaces/               # Интерфейсы (доступны всем)
│       │   ├── i_run_repository.dart
│       │   └── i_graph_repository.dart
│       │
│       └── transport/                # Транспорт (смешанный)
│           ├── http_engine_transport.dart    (клиент)
│           └── local_engine_transport.dart   (сервер)
```

**КРИТИЧЕСКОЕ ТРЕБОВАНИЕ:**
- `lib/aq_graph_engine.dart` — экспортирует ТОЛЬКО клиентскую часть
- `lib/server.dart` — экспортирует серверную часть + клиент
- Клиент НЕ должен иметь доступ к `GraphEngine`, `EngineExecutionContext`, `NodeTypeRegistry`

### 5.4. Использование

**Клиентское приложение (Flutter):**
```dart
import 'package:aq_graph_engine/aq_graph_engine.dart';

final client = GraphEngineClient(
  transport: HttpEngineTransport(endpoint: 'http://localhost:8765'),
);

final stream = client.run(GraphRunRequest(...));
```

**Серверное приложение (Worker):**
```dart
import 'package:aq_graph_engine/server.dart';  // ← Отдельный импорт!

final engine = GraphEngine(
  tools: toolRegistry,
  runRepo: runRepository,
  graphRepo: graphRepository,
  nodeRegistry: NodeTypeRegistry(),
);

final transport = LocalEngineTransport(engine: engine);
await transport.run(request);
```

---

## 6. Авторизация и безопасность

### 6.1. Два типа учётных данных

| Тип | Кто использует | Что содержит | Как валидируется |
|-----|----------------|--------------|-----------------|
| **JWT-токен** | Команды от клиента → сервер | userId, projectId, роли, exp | Сервером по подписи |
| **API-ключ** | Движок → внешние ресурсы | scope (llm/fs/mcp), projectId, rateLimit | Самим ресурсом по хешу |

### 6.2. API-ключ несёт в себе права

**Важно:** API-ключ — это не просто строка. В него зашито:
- Что ключ может делать (`scope`)
- К какому проекту он привязан
- Кто его выдал и когда
- Rate limits

**Структура AQApiKeyClaims:**
```dart
class AQApiKeyClaims {
  final String projectId;
  final String keyId;
  final List<String> scope;       // ['llm', 'fs:read', 'vault:write', 'mcp:*']
  final String issuedBy;          // auth service instance
  final DateTime issuedAt;
  final DateTime? expiresAt;
  final Map<String, dynamic> rateLimit;   // { 'llm_rpm': 60, 'fs_ops': 1000 }

  bool allows(String permission) => scope.any((s) =>
    s == permission || s == '${permission.split(':').first}:*' || s == '*');
}
```

### 6.3. Жизненный цикл токена в движке

```
[Клиент] ──JWT──► [GraphEngineServer] ──валидирует JWT──► [запускает граф]
                                              │
                             граф получает API-ключ из JWT claims
                                              │
                   [Узел в графе] ──API-key──► [AQToolService / AQVault]
```

**Процесс:**
1. Клиент отправляет JWT токен
2. Сервер валидирует JWT
3. Извлекает `apiKeyRef` из JWT claims
4. Загружает API-ключ с правами
5. Передаёт в `RunContext`
6. Каждый инструмент получает API-ключ через контекст

### 6.4. Публичный API модуля aq_auth

```dart
abstract interface class AQAuthClient {
  /// Аутентификация по логину/паролю → JWT токен
  Future<AQToken> loginWithCredentials(String email, String password);

  /// Аутентификация воркера по API-ключу → service JWT
  Future<AQToken> loginWithApiKey(String apiKey);

  /// Текущий действующий токен (автоматически обновляется)
  Future<AQToken> get currentToken;

  /// Проверить токен локально (без сети, по jwtSecret)
  AQTokenClaims? validateLocally(String rawToken);

  /// Получить / создать API-ключ для проекта
  Future<AQApiKey> getProjectApiKey(String projectId, {List<String> scope});

  /// Выйти
  Future<void> logout();

  /// Стрим событий (tokenRefreshed, expired, loggedOut)
  Stream<AQAuthEvent> get events;
}
```

### 6.5. Двойная авторизация в AuthMiddleware

**JWT токены** (для пользователей):
```bash
Authorization: Bearer <token>
```

**API ключи** (для воркеров):
```bash
X-API-Key: aq_<type>_<random>
```

**Приоритет:** API ключ проверяется первым. Если присутствует валидный API ключ, JWT токен игнорируется.

**Context для handlers:**

JWT:
```dart
{
  'authType': 'jwt',
  'userId': 'user-123',
  'serviceId': null
}
```

API Key:
```dart
{
  'authType': 'api_key',
  'userId': null,
  'serviceId': 'service-worke'
}
```

### 6.6. Формат API ключей

API ключи должны иметь префикс `aq_`:

```
aq_worker_<random>     - для воркеров
aq_service_<random>    - для сервисов
aq_integration_<random> - для интеграций
```

---

## 7. Абстракция инструментов (AQToolService)

### 7.1. Философия: движок — это "пользователь" сервисов

Граф организует логику. Узлы исполняют команды. Но узел **не знает**, как именно выполнена команда — локально, через HTTP, через MCP, через subprocess. Это задача `AQToolService`.

```
[WorkflowRunner]
      │
      ▼
[LlmActionNode].execute(context, toolService)
      │
      ▼
toolService.llm.complete(messages, model: 'claude-3-5')
      │
      ├─ если local: прямой HTTP в Anthropic API
      ├─ если remote MCP: MCP transport → Anthropic
      └─ если mock (тест): возвращает заглушку
```

### 7.2. Интерфейс AQToolService (в aq_schema)

```dart
/// Главный фасад для доступа к инструментам из узлов графа.
/// Движок получает его при инициализации — не знает о реализации.
abstract interface class AQToolService {

  /// LLM-интерфейс
  IAQLlmService get llm;

  /// Файловая система / хранилище артефактов
  IAQVaultService get vault;

  /// Произвольный инструмент по имени (для ToolCallNode)
  Future<dynamic> callTool(String toolName, Map<String, dynamic> args, RunContext ctx);

  /// Проверить доступность инструмента
  bool hasTool(String toolName);

  /// Список всех зарегистрированных инструментов
  List<AQToolDescriptor> get availableTools;
}
```

### 7.3. LLM интерфейс

```dart
abstract interface class IAQLlmService {
  /// Запрос к LLM. Узел не знает: это Claude, GPT или локальная модель.
  Future<AQLlmResponse> complete({
    required List<AQLlmMessage> messages,
    String? model,
    double? temperature,
    int? maxTokens,
    List<AQToolDescriptor>? tools,   // для tool-use (function calling)
  });

  /// Стриминг ответа
  Stream<AQLlmChunk> stream({
    required List<AQLlmMessage> messages,
    String? model,
  });
}
```

### 7.4. Vault интерфейс

```dart
abstract interface class IAQVaultService {
  /// Прочитать артефакт / файл
  Future<AQVaultItem?> read(String path, RunContext ctx);

  /// Записать артефакт
  Future<void> write(String path, dynamic content, RunContext ctx);

  /// Найти артефакты по запросу
  Future<List<AQVaultItem>> query(AQVaultQuery q, RunContext ctx);

  /// Удалить
  Future<void> delete(String path, RunContext ctx);
}
```

### 7.5. Использование в узлах

```dart
// В LlmActionNode.execute():
@override
Future<dynamic> execute(RunContext context, AQToolService tools) async {
  final prompt = context.getVar(promptVar) as String;

  final response = await tools.llm.complete(
    messages: [
      AQLlmMessage(role: 'system', content: systemPrompt),
      AQLlmMessage(role: 'user', content: prompt),
    ],
    model: modelName,
  );

  context.setVar(outputVar, response.text);
  return response.text;
}

// В FileReadNode.execute():
@override
Future<dynamic> execute(RunContext context, AQToolService tools) async {
  final path = substituteVariables(filePath, context);
  final item = await tools.vault.read(path, context);
  context.setVar(outputVar, item?.content);
  return item?.content;
}
```

**Ключевое решение:** `IWorkflowNode.execute()` принимает `AQToolService`, а не `ToolRegistry`. `ToolRegistry` — внутренняя деталь реализации `AQToolService`, снаружи невидима.

### 7.6. Организация пакета aq_tool_service

```
pkgs/aq_tool_service/
├── lib/
│   ├── aq_tool_service.dart          # публичный экспорт
│   ├── src/
│   │   ├── service/
│   │   │   ├── tool_service_impl.dart    # конкретная реализация AQToolService
│   │   │   └── tool_service_builder.dart # builder pattern для конфигурации
│   │   ├── llm/
│   │   │   ├── anthropic_llm.dart        # Anthropic API
│   │   │   ├── openai_llm.dart           # OpenAI API
│   │   │   └── mcp_llm_proxy.dart        # LLM через MCP транспорт
│   │   ├── vault/
│   │   │   ├── remote_vault.dart         # через dart_vault (HTTP)
│   │   │   └── local_vault.dart          # локальная FS (десктоп)
│   │   ├── mcp/
│   │   │   ├── mcp_transport.dart        # MCP JSON-RPC транспорт
│   │   │   ├── mcp_tool_adapter.dart     # MCP tool → AQToolDescriptor
│   │   │   └── mcp_server_registry.dart  # список подключённых MCP серверов
│   │   └── tools/
│   │       ├── git_tool.dart
│   │       ├── code_exec_tool.dart
│   │       └── web_search_tool.dart
```

### 7.7. Builder для конфигурации

```dart
final toolService = AQToolServiceBuilder()
  .withLlm(AnthropicLlmService(apiKey: key))
  .withVault(RemoteVaultService(endpoint: vaultUrl, auth: auth))
  .withMcpServer('filesystem', 'stdio', 'npx @modelcontextprotocol/server-filesystem /data')
  .withMcpServer('github', 'http', 'https://github.mcp.example.com')
  .withTool('git_commit', GitCommitTool(workDir: projectPath))
  .build();

// Передаём в движок
final engine = GraphEngineService.local(
  tools: toolService,
  ...
);
```

**Ключевой принцип:** `aq_tool_service` **реализует** интерфейсы из `aq_schema`. Движок `aq_graph_engine` зависит только от `aq_schema`. Так движок никогда не узнает о конкретных реализациях:

```
aq_graph_engine  →  aq_schema (interfaces)  ←  aq_tool_service (implementations)
```

---

## 8. Жизненный цикл выполнения

### 8.1. Создание и запуск

**Шаг 1: Создание запроса**
```dart
final request = GraphRunRequest(
  runId: uuid,
  blueprintId: workflowId,
  projectId: projectId,
  projectPath: '/path/to/project',
  initialVariables: {'key': 'value'},
);
```

**Шаг 2: Запуск через движок**
```dart
final engine = GraphEngine(
  tools: toolRegistry,
  runRepo: runRepository,
  graphRepo: graphRepository,
);

Stream<GraphRunEvent> events = engine.run(request);
```

**Шаг 3: Обработка событий**
```dart
await for (final event in events) {
  switch (event.type) {
    case GraphRunEventType.log:
      print(event.message);
    case GraphRunEventType.statusChanged:
      print('Status: ${event.newStatus}');
    case GraphRunEventType.userInputRequired:
      final input = await showDialog(...);
      await engine.resumeWithInput(UserInputResponse(
        runId: event.runId,
        data: input,
      ));
    case GraphRunEventType.completed:
      print('Done!');
    case GraphRunEventType.error:
      print('Error: ${event.errorMessage}');
  }
}
```

### 8.2. Статусы выполнения

```
pending → running → suspended → running → completed
                 ↘ failed
```

- `pending` — в очереди
- `running` — выполняется
- `suspended` — ждёт ввода пользователя
- `completed` — успешно завершён
- `failed` — ошибка

### 8.3. Механизм Suspend/Resume

**Приостановка:**
```dart
// WorkflowRunner
await _repo.suspendRun(
  runId: runId,
  contextJson: jsonEncode({
    'user_context': context.toJson(),
    'engine_state': {
      'visited_edges': _visitedEdges.toList(),
      'ui_action': 'user_input',
      'target_var': 'user_answer',
      'ui_config': {...}
    }
  }),
  nodeId: node.id,
  logs: _logs,
);
```

**Сохранение в БД:**
```sql
UPDATE runs SET
  status = 'suspended',
  context_json = '...',
  node_id = 'node-001',
  logs_json = '[...]'
WHERE run_id = 'uuid';
```

**Возобновление:**
```dart
// Клиент
await engine.resumeWithInput(UserInputResponse(
  runId: runId,
  data: {'user_answer': 'My Project'},
));

// WorkflowRunner
final savedRun = await _repo.getRun(runId);
final contextJson = savedRun['context_json'];
final parsedState = jsonDecode(contextJson);

// Восстанавливаем контекст
final context = RunContext.fromJson(
  parsedState['user_context'],
  _log,
);

// Добавляем новые данные
context.state.addAll(injectedVariables);

// Продолжаем с сохранённого узла
await _processNode(startNode, 0, context);
```

### 8.4. Параллельное выполнение (Join Strategies)

**waitAll** — ждать все ветки:
```dart
if (node.joinStrategy == JoinStrategy.waitAll) {
  final allArrived = incomingEdges.every((e) => _arrivedEdges.contains(e.id));
  if (!allArrived) {
    return; // Пропускаем узел, ждём остальные ветки
  }
}
```

**firstCome** — первая пришедшая ветка:
```dart
if (node.joinStrategy == JoinStrategy.firstCome) {
  if (_arrivedEdges.any((id) => incomingEdges.any((e) => e.id == id))) {
    // Выполняем сразу
  }
}
```

**waitPriority** — ждать ветку с наивысшим приоритетом:
```dart
if (node.joinStrategy == JoinStrategy.waitPriority) {
  final highestPriority = incomingEdges.map((e) => e.priority).reduce(max);
  final arrived = _arrivedEdges.any((id) =>
    incomingEdges.any((e) => e.id == id && e.priority == highestPriority)
  );
  if (!arrived) return;
}
```

### 8.5. Retry с экспоненциальным backoff

```dart
int retryCount = 0;
while (retryCount <= node.maxRetries) {
  try {
    final result = await node.execute(context, tools);
    return result;
  } catch (e) {
    if (!_isRetryable(e, node.retryableExceptions)) {
      rethrow;
    }

    retryCount++;
    if (retryCount > node.maxRetries) {
      rethrow;
    }

    final delay = node.useExponentialBackoff
        ? node.retryDelayMs * pow(2, retryCount - 1)
        : node.retryDelayMs;

    await Future.delayed(Duration(milliseconds: delay));
    metrics.nodeRetries.inc();
  }
}
```

---

## 9. Production-готовность

### 9.1. ✅ Что уже готово к production

**Prometheus + Grafana мониторинг:**
- 8 метрик: счётчики запусков (started/completed/failed/suspended)
- Счётчик node executions
- Retry счётчик
- Гистограммы длительности
- Gauges активных и очередных запусков
- Docker Compose стек с Prometheus scraping каждые 10s
- Prebuilt Grafana dashboard
- Endpoint `/metrics` работает

**Graceful Shutdown:**
- SIGINT/SIGTERM перехватываются
- Воркер дожидается завершения активных jobs до 30 секунд
- HTTP сервер возвращает 503 новым запросам во время остановки
- Корректное завершение всех соединений

**Retry с экспоненциальным backoff:**
- `maxRetries`, `retryDelayMs`, `useExponentialBackoff` настраиваются на уровне каждого узла
- Фильтрация по типу ошибки через `retryableExceptions`
- Метрика `graph_node_retries_total` пишется

**Redis Job Queue:**
- BRPOP-based consumer с timeout polling
- `JobStatus` enum: pending → running → done/failed/timeout
- `setStatus`, `setResult` — контракт между адаптером и воркером чёткий
- Горизонтальное масштабирование воркеров

**Join Strategies:**
- `waitAll`, `firstCome`, `waitPriority` реализованы в runner
- Отслеживание прибытия рёбер через `_arrivedEdges`

**Auth:**
- JWT + offline validation через `jwtSecret`
- API key → access token flow через `AQSecurityClient`
- Двойная авторизация (JWT + API keys)

**Полиморфная архитектура узлов:**
- 17 типов узлов (10 Workflow + 4 Instruction + 3 Prompt)
- Расширяемость без изменения кода движка
- Каждый узел тестируется независимо

### 9.2. 🚨 Критические блокеры перед production

**БЛОКЕР 1: `isSystemTool` бросает `UnimplementedError` в воркере**

Все три hands в `worker_hands_registry.dart` содержат:
```dart
@override
bool get isSystemTool => throw UnimplementedError();
```

Это не заглушка — это падение в рантайме при первом обращении к этому свойству.

**Решение:** Реализовать `isSystemTool` во всех hands (вернуть `true` или `false`).

---

**БЛОКЕР 2: Нет реальных LLM и инструментов**

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

Без `GenericLlmHand` `LlmActionNode` и `LlmQueryNode` не могут выполниться.

**Решение:** Реализовать `GenericLlmHand` (Anthropic + OpenAI) и `FsReadHand` / `FsWriteHand`.

---

**БЛОКЕР 3: MCP — нет ни одной реализации**

В документации упоминается MCP (Model Context Protocol) как способ подключения внешних сервисов. В коде нет ни одного MCP-адаптера, ни транспорта, ни регистрации инструментов через MCP.

**Решение:** Реализовать базовый MCP транспорт и адаптер.

---

**БЛОКЕР 4: `WorkflowNodeFactory` помечен `@Deprecated` но используется везде**

`PolymorphicWorkflowRunner` использует `WorkflowNodeFactory.fromJson()` в 4 местах. Сама фабрика помечена `@Deprecated('РУДИМЕНТ!')` с комментарием «Удалить после миграции».

**Решение:** Завершить миграцию на `NodeTypeRegistry` или убрать `@Deprecated`.

---

**БЛОКЕР 5: Conditional edges не реализованы**

В `PolymorphicWorkflowRunner._processNode()`:
```dart
case WorkflowEdgeType.conditional:
  // TODO: Реализовать оценку conditionExpression
  return true;
```

Любое условное ребро всегда возвращает `true`.

**Решение:** Реализовать `ConditionEvaluator` и интегрировать в runner.

---

**БЛОКЕР 6: Отсутствует `lib/server.dart`**

Серверные компоненты экспортируются в клиентский файл `lib/aq_graph_engine.dart`. Это нарушает принцип "тонкого клиента".

**Решение:** Создать `lib/server.dart` и разделить client/server экспорты.

### 9.3. ⚠️ Серьёзные риски

**Истечение access token при долгих графах:**

Комментарий в коде:
```dart
// Access token живёт 15 минут — достаточно для одного job.
```

Граф с интерактивными узлами может длиться часы или дни. После 15 минут токен истечёт.

**Решение:** Механизм refresh токена или использование долгоживущего service account токена.

---

**Состояние гонки в параллельных ветках:**

При параллельном выполнении рёбер несколько потоков пишут в `_logs` и `_visitedEdges` без синхронизации.

**Решение:** Использовать `SynchronizedList` или mutex для защиты общих структур данных.

---

**Тестовый backdoor в production коде:**

```dart
if (config.apiKey == 'test_api_key') {
  token = 'mock_token_for_tests';
}
```

**Решение:** Убрать или вынести в отдельный `TestGraphWorker`.

---

**`print()` в production коде:**

`graph_engine_client.dart` содержит:
```dart
print('🚀 Starting run: ${request.blueprintId}');
```

**Решение:** Заменить на структурированный логгер (пакет `logging`).

---

**InstructionRunner не защищён от циклов:**

Документация обещает `maxSteps = 20`, но в реализации нет счётчика шагов.

**Решение:** Добавить счётчик шагов и проверку `if (stepCount > maxSteps) break;`.

### 9.4. 📋 Незначительные замечания

- Нет rate limiting на HTTP endpoints воркера
- Нет circuit breaker при недоступности data service
- Метрика `graph_queued_runs` объявлена, но нигде не обновляется
- Отсутствуют unit тесты для runner, retry, graceful shutdown
- Нет dead letter queue для failed jobs в Redis

### 9.5. Сводная матрица готовности

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
| Client/Server разделение | ❌ Нет | ❌ | 🚨 Критично |
| Тесты | ❌ Нет | — | ❌ Запланированы |

---

## 10. План развития

### 10.1. 🔴 Приоритет 1 — Блокеры (до первого реального запуска)

**Неделя 1-2:**

1. **Создать `lib/server.dart`** и разделить client/server экспорты
2. **Реорганизовать `src/`** на client/server/shared
3. **Реализовать `GenericLlmHand`** (Anthropic + OpenAI)
4. **Реализовать `FsReadHand` / `FsWriteHand`** с sandbox isolation
5. **Исправить `isSystemTool`** во всех hands
6. **Реализовать conditional edge evaluation** в PolymorphicWorkflowRunner
7. **Завершить миграцию `WorkflowNodeFactory`** на `NodeTypeRegistry`

### 10.2. 🟡 Приоритет 2 — Риски стабильности

**Неделя 3-4:**

8. **Token refresh** — добавить фоновый цикл обновления токена в GraphWorker
9. **maxSteps в InstructionRunner** — защита от бесконечных циклов
10. **Убрать тестовый backdoor** (`test_api_key`) из production кода
11. **Заменить `print()` на структурированный логгер**
12. **Добавить поля `priority`, `isExclusive`, `executionMode` в WorkflowEdge** schema
13. **Защита от race conditions** в параллельных ветках

### 10.3. 🟢 Приоритет 3 — Качество и масштаб

**Неделя 5-7:**

14. **Unit + Integration тесты** (Неделя 3 по плану)
15. **MCP адаптер** — хотя бы базовый транспорт
16. **Dead letter queue** для failed jobs
17. **Метрика `graph_queued_runs`** — реальное заполнение из Redis
18. **Rate limiting** на worker HTTP endpoints
19. **Circuit breaker** для data service
20. **Типизированные клиенты** через `IAQGraphEngineClient`
21. **Интеграционные тесты** client + server

### 10.4. Фазированный план (из документа production-готовности)

**Фаза 0: Фундаментные исправления (1 неделя)**
- Очистка иерархии узлов
- Conditional edges
- Базовый тест всего стека

**Фаза 1: Интерфейс инструментов (1.5 недели)**
- AQToolService интерфейс
- MockToolService для тестов
- API ключ в RunContext

**Фаза 2: Auth-модуль (1 неделя)**
- Пакет aq_auth
- Интеграция в движок
- API-ключ → RunContext

**Фаза 3: Два режима Client/Server (1.5 недели)**
- GraphEngineService фасад
- Remote mode (HttpEngineTransport)
- Тесты integration

**Фаза 4: Production hardening (1 неделя)**
- Параллельность и race conditions
- Token и session lifecycle
- Метрики и алертинг

**Фаза 5: Тестирование (1 неделя)**
- Unit тесты
- Integration тесты
- E2E тест

**Итого: 7 недель до полной production-готовности.**

---

## 11. Использование клиента

### 11.1. Быстрый старт

```dart
import 'package:aq_graph_engine/aq_graph_engine.dart';

// Создать клиент
final client = GraphEngineClient(
  baseUrl: 'http://localhost:8080',
  defaultHeaders: {
    'X-API-Key': 'aq_your_api_key',
  },
);

// Запустить граф
final response = await client.startRun(GraphRunRequest(
  runId: 'run-123',
  blueprintId: 'bp-1',
  projectId: 'proj-1',
  projectPath: '/path/to/project',
));

print('Run started: ${response.runId}');

// Подключиться к событиям
final stream = client.connectToRun(response.runId, apiKey: 'aq_your_api_key');

await for (final event in stream.events) {
  print('Event: ${event.type} - ${event.message}');

  if (event.type == GraphRunEventType.completed) {
    break;
  }
}

await stream.disconnect();
client.close();
```

### 11.2. Обработка событий

```dart
await for (final event in stream.events) {
  switch (event.type) {
    case GraphRunEventType.log:
      print('📝 ${event.message}');
      break;

    case GraphRunEventType.statusChanged:
      print('🔄 Status changed to: ${event.newStatus}');
      break;

    case GraphRunEventType.completed:
      print('✅ Run completed successfully');
      break;

    case GraphRunEventType.error:
      print('❌ Error: ${event.errorMessage}');
      break;

    case GraphRunEventType.userInputRequired:
      print('⏸️  User input required');
      final input = await showDialog(...);
      await client.resumeRun(response.runId, {'userInput': input});
      break;
  }
}
```

### 11.3. Error Handling

```dart
try {
  final response = await client.startRun(request);
  print('Success: ${response.runId}');
} on GraphEngineValidationException catch (e) {
  print('Validation error: ${e.message}');
} on GraphEngineUnauthorizedException catch (e) {
  print('Auth required: ${e.message}');
} on GraphEngineConnectionException catch (e) {
  print('Connection failed: ${e.message}');
} on GraphEngineException catch (e) {
  print('Error: ${e.message} (HTTP ${e.statusCode})');
}
```

### 11.4. Best Practices

**1. Всегда закрывайте клиент:**
```dart
final client = GraphEngineClient(baseUrl: 'http://localhost:8080');
try {
  // Используйте клиент
} finally {
  client.close(); // Освобождает ресурсы
}
```

**2. Обрабатывайте disconnect:**
```dart
final stream = client.connectToRun('run-123');
try {
  await for (final event in stream.events) {
    print('Event: ${event.type}');
  }
} finally {
  await stream.disconnect();
}
```

**3. Используйте timeout:**
```dart
final client = GraphEngineClient(
  baseUrl: 'http://localhost:8080',
  timeout: const Duration(seconds: 60), // Для долгих операций
);
```

**4. Keep-alive для долгих соединений:**
```dart
final stream = GraphRunStream(
  runId: 'run-123',
  wsUrl: 'ws://localhost:8080/api/v1/runs/run-123/ws',
  enableKeepAlive: true,
  keepAliveInterval: const Duration(seconds: 30),
);
```

---

## 12. Заключение

### 12.1. Сильные стороны архитектуры

**Философия "Граф как Закон" — правильное решение:**
- Унификация всех процессов через графы
- Версионирование из коробки
- Визуализация логики
- Композиция и переиспользование
- Приостановка и возобновление

**Чистая архитектура:**
- Слои абстракции (GraphEngine → Transport → Runners → Repositories)
- Полиморфизм вместо switch
- Stateless Worker (12-factor)
- Transport pattern для разных режимов работы

**Production-ready инфраструктура:**
- Prometheus + Grafana мониторинг
- Graceful Shutdown
- Retry с экспоненциальным backoff
- Redis Job Queue
- JWT + API keys авторизация

### 12.2. Что нужно доработать

**Критические блокеры:**
1. Создать `lib/server.dart` и разделить client/server
2. Реализовать реальные LLM и FS hands
3. Завершить миграцию на `NodeTypeRegistry`
4. Реализовать conditional edges
5. Исправить `isSystemTool` в hands

**Серьёзные риски:**
1. Token refresh для долгих графов
2. Защита от race conditions в параллельных ветках
3. maxSteps в InstructionRunner
4. Убрать тестовый backdoor
5. Заменить print() на логгер

**Качество и масштаб:**
1. Unit + Integration тесты
2. MCP адаптер
3. Dead letter queue
4. Rate limiting
5. Circuit breaker

### 12.3. Оценка готовности

**Архитектура:** 9/10 — отличная, но нужно разделить client/server

**Бизнес-логика:** 8/10 — основные сценарии покрыты, нужны инструменты

**Инфраструктура:** 8/10 — мониторинг и shutdown готовы, нужны тесты

**Production-готовность:** 4/10 — критические блокеры мешают запуску

### 12.4. Временная оценка

**До первого реального запуска:** 2-3 недели
- Устранение критических блокеров
- Реализация LLM и FS hands
- Базовое тестирование

**До полной production-готовности:** 7 недель
- Все фазы из плана
- Полное тестирование
- MCP интеграция
- Типизированные клиенты

### 12.5. Рекомендации

**Немедленно:**
1. Создать `lib/server.dart` — это критично для архитектуры
2. Реализовать `GenericLlmHand` — без этого агент не работает
3. Исправить `isSystemTool` — это runtime crash

**В ближайшее время:**
1. Завершить миграцию на `NodeTypeRegistry`
2. Реализовать conditional edges
3. Добавить token refresh
4. Написать базовые тесты

**Для production:**
1. Полное тестирование (unit + integration + e2e)
2. MCP адаптер для расширяемости
3. Dead letter queue для надёжности
4. Rate limiting и circuit breaker для стабильности

### 12.6. Итоговый вердикт

**Архитектура системы хорошо спроектирована.** Принцип «Граф как Закон», три типа графов, полиморфные узлы, stateless worker, transport pattern — это грамотные решения, которые обеспечат долгосрочную расширяемость платформы.

**Инфраструктурный слой достаточно зрелый** для production при устранении нескольких рисков (token refresh, test backdoor, race conditions).

**Бизнес-логика движка реализована правильно** и покрывает основные use cases агентного workflow.

**Критический пробел — отсутствие реальных инструментов (LLM hands, FS hands, MCP) и разделения client/server.** Без них весь стек технически запускается, но агент ничего полезного сделать не может, а клиент имеет доступ к серверным компонентам.

При правильной расстановке приоритетов система может выйти в production за 2–3 недели активной разработки (для первого запуска) или за 7 недель (для полной production-готовности).

---

## Приложения

### A. Ссылки на документацию

**Основные документы:**
- `OVERVIEW.md` — общий обзор системы
- `WORKFLOW_GRAPH.md` — WorkflowGraph в деталях
- `INSTRUCTION_GRAPH.md` — InstructionGraph в деталях
- `CLIENT_SERVER_ARCHITECTURE.md` — архитектура клиент-сервер
- `AQ Graph Engine — План полной production-готовности.md` — детальный план

**Технические документы:**
- `GRAPH_ENGINE_GUIDE.md` — руководство по полиморфной архитектуре
- `CLIENT_USAGE.md` — руководство по использованию клиента
- `API_KEYS.md` — документация по авторизации
- `REFACTORING_COMPLETE.md` — отчёт о рефакторинге
- `COMPLIANCE_REPORT.md` — отчёт о соответствии архитектурным принципам

### B. Глоссарий

**WorkflowGraph** — основной тип графа, описывает полный сценарий работы агента с поддержкой suspend/resume и интерактивных узлов.

**InstructionGraph** — переиспользуемая атомарная бизнес-логика с контрактом входов/выходов, может содержать циклы.

**PromptGraph** — шаблон промпта для LLM с переменными, компилируется в строку перед вызовом LLM.

**AQToolService** — абстракция инструментов, предоставляет узлам доступ к LLM, файловой системе и другим сервисам.

**RunContext** — контекст выполнения графа, содержит переменные, логи и метаданные.

**IEngineTransport** — абстракция транспорта, позволяет движку работать локально или удалённо.

**NodeTypeRegistry** — реестр типов узлов, позволяет регистрировать новые типы без изменения кода движка.

**Suspend/Resume** — механизм приостановки и возобновления выполнения графа для интерактивного взаимодействия с пользователем.

**Join Strategy** — стратегия синхронизации параллельных веток (waitAll, firstCome, waitPriority).

**Conditional Edge** — условное ребро графа, выбирается на основе результата выполнения узла или выражения.

---

**Документ создан:** 2026-04-10
**Версия:** 1.0
**Статус:** Актуален

