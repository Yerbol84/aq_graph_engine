# AQ Graph Engine — Обзор

**Последнее обновление:** 2026-05-02

---

## Что это

`aq_graph_engine` — Dart runtime для выполнения графов трёх типов:

- **WorkflowGraph** — сценарий выполнения агента (pipeline)
- **InstructionGraph** — переиспользуемая логика с контрактом входов/выходов
- **PromptGraph** — шаблон промпта для LLM с подстановкой переменных

Движок работает:
- **Локально** (desktop) — через `LocalEngineTransport`
- **Удалённо** (web service) — через `HttpEngineTransport`
- **В воркере** (background job) — через `GraphWorker` в `aq_graph_worker`

---

## Три типа графов

### TypedWorkflowGraph ✅ Актуальный

Основной сценарий. Узлы — полиморфные `IWorkflowNode`.

**Узлы:**
- `llmAction` — запрос к LLM
- `fileRead` / `fileWrite` — файловая система
- `userInput` / `manualReview` / `fileUpload` / `coCreationChat` — интерактивные (suspend/resume)
- `runInstruction` — вызов InstructionGraph
- `subGraph` — вложенный Workflow
- `gitCommit` — коммит в Git

**Рёбра:** `onSuccess`, `onError`, `conditional`

**Особенности:** параллельные ветки, suspend/resume, сохранение состояния в БД.

---

### TypedInstructionGraph 🔄 В процессе миграции

Атомарная бизнес-логика. Узлы — полиморфные `IInstructionNode`.

**Узлы:**
- `condition` — ветвление по условию
- `llmQuery` — запрос к LLM
- `toolCall` — вызов инструмента из ToolRegistry
- `transform` — преобразование данных

**Особенности:** циклы разрешены (защита: maxSteps=50), нет UI узлов, контракт входов/выходов.

> **Статус:** `TypedInstructionGraph` создан в `aq_schema`. `InstructionRunner` пока работает
> со старым `InstructionGraph` (deprecated) — миграция в следующей сессии.

---

### TypedPromptGraph 🔄 В процессе миграции

Шаблон промпта. Узлы — полиморфные `IPromptNode`.

**Узлы:**
- `textBlock` — текст с `{{переменными}}`
- `variableInsert` — вставка переменной с prefix/suffix
- `conditionalBlock` — условный блок текста

**Особенности:** компилируется в строку, переменные из RunContext.

> **Статус:** `TypedPromptGraph` создан в `aq_schema`. `PromptRunner` пока работает
> со старым `PromptGraph` (deprecated) — миграция в следующей сессии.

---

## Жизненный цикл run

```
pending → running → completed
                 ↘ failed
                 ↘ suspended → running → ...
```

- `pending` — создан, ещё не запущен
- `running` — выполняется
- `suspended` — ждёт ввода пользователя (только WorkflowGraph)
- `completed` — успешно завершён
- `failed` — ошибка

---

## Как запустить

### Локально (desktop)

```dart
import 'package:aq_graph_engine/server.dart';

final engine = GraphEngine(
  tools: buildToolRegistry(),
  runRepo: myRunRepository,    // implements IRunRepository
  graphRepo: myGraphRepository, // implements IGraphRepository
);

final events = engine.run(GraphRunRequest(
  runId: uuid,
  blueprintId: workflowId,
  projectId: projectId,
  projectPath: '/path/to/project',
));

await for (final event in events) {
  // GraphRunEvent: log, statusChanged, completed, error, userInputRequired
}
```

### Через HTTP клиент

```dart
import 'package:aq_graph_engine/aq_graph_engine.dart';

final client = GraphEngineClient(baseUrl: 'http://localhost:8080');
final response = await client.startRun(request);
final stream = client.connectToRun(response.runId);
```

---

## Ключевые контракты (в aq_schema)

| Интерфейс | Ответственность |
|-----------|----------------|
| `IRunRepository` | Lifecycle run: статус, логи, suspend/resume → БД |
| `IGraphRepository` | Загрузка графов по ID |
| `IRunStateManager` | Кэш RunContext между узлами → память |
| `IEngineTransport` | Абстракция транспорта (local/http) |

---

## Что сейчас работает

- ✅ `TypedWorkflowGraph` — полная поддержка
- ✅ Параллельные ветки + join стратегии
- ✅ Suspend/resume для интерактивных узлов
- ✅ `InstructionRunner` — работает (через старый `InstructionGraph`)
- ✅ `PromptRunner` — работает (через старый `PromptGraph`)
- ✅ `LocalEngineTransport` — локальное выполнение
- ✅ `HttpEngineTransport` — удалённое выполнение (клиентская сторона)
- ✅ `GraphEngineClient` — HTTP клиент
- ✅ DLQ (Dead Letter Queue) для failed runs
- ✅ Защита от циклов (счётчик итераций)

## Что в процессе

- 🔄 Миграция `InstructionRunner` на `TypedInstructionGraph`
- 🔄 Миграция `PromptRunner` на `TypedPromptGraph`
- 🔄 Удаление старых фабрик (`InstructionNodeFactory`, `PromptNodeFactory`, `WorkflowNodeFactory`)

## Что не реализовано (tech debt)

- ❌ `projectPath` в `WorkflowRun` — временный костыль через `graphSnapshot`
- ❌ Distributed lock (`tryAcquireLock` всегда `true`) — single-worker only
- ❌ True append-only логи — сейчас read-modify-write

---

## Подробнее

- [ARCHITECTURE.md](ARCHITECTURE.md) — внутреннее устройство движка
- [CLIENT_USAGE.md](CLIENT_USAGE.md) — API клиента
- [CLIENT_SERVER_ARCHITECTURE.md](CLIENT_SERVER_ARCHITECTURE.md) — принцип тонкого клиента
- [API_KEYS.md](API_KEYS.md) — авторизация
- [audit_2026_05_02/STATUS.md](audit_2026_05_02/STATUS.md) — статус аудита и tech debt
