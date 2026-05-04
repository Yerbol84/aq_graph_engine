# Refactoring Plan — aq_graph_engine

Статус: 📋 ПЛАН  
Дата: 2026-05-04

---

## Цель

Стабильный движок с чистой архитектурой:
- Движок исполняет граф, не знает о деталях инструментов
- Инструменты — внешний сервис через порт `IToolEngineProtocol`
- Три типа графов на одном механизме обхода
- Узел = поведение в графе, не тип действия

---

## RF-1: IToolService → IToolEngineProtocol

**Приоритет:** HIGH  
**Риск:** Средний — меняется сигнатура GraphEngine  
**Зависимость:** нет

**Почему:**  
`IToolService` — legacy DI через конструктор. `IToolEngineProtocol` — архитектурный порт-синглтон.
Движок не должен принимать tools в конструктор — как `IDataLayer`, сервис инициализируется снаружи.
`IToolEngineProtocol` добавляет: async `hasTool`, streaming, lifecycle events, namespace, метаданные результата.

**Что меняется:**

```
// БЫЛО
GraphEngine(tools: myToolService, runRepo: ..., graphRepo: ...)

// СТАНЕТ
IToolEngineProtocol.initialize(myToolProtocol); // в main()
GraphEngine(runRepo: ..., graphRepo: ...)        // tools больше не параметр
```

**Файлы:**
- `aq_graph_engine/lib/src/server/engine/graph_engine.dart` — убрать `tools` поле и параметр
- `aq_graph_engine/lib/src/transport/local_engine_transport.dart` — убрать `tools` поле
- `aq_schema/lib/graph/nodes/instruction/tool_call_node.dart` — раскомментировать execute через `IToolEngineProtocol.instance`
- `aq_schema/lib/graph/nodes/workflow/automatic/llm_action_node.dart` — аналогично
- `aq_schema/lib/graph/nodes/instruction/llm_query_node.dart` — аналогично
- `aq_graph_worker/examples/scenarios/shared/lib/helpers.dart` — убрать `EmptyTools`, добавить `NoopToolProtocol`
- `aq_graph_worker/bin/main.dart` — инициализировать `IToolEngineProtocol` перед `GraphEngine`

**Шаги:**
1. Создать `NoopToolProtocol implements IToolEngineProtocol` в тестовых helpers (заглушка для тестов)
2. Убрать `tools` из `GraphEngine` конструктора и `LocalEngineTransport`
3. Раскомментировать `ToolCallNode.execute()` — использует `IToolEngineProtocol.instance`
4. Раскомментировать `LlmActionNode.execute()` и `LlmQueryNode.execute()`
5. Обновить примеры и тесты
6. Запустить все тесты

---

## RF-2: Унификация механизма обхода трёх типов графов

**Приоритет:** MEDIUM  
**Риск:** Средний — затрагивает runners  
**Зависимость:** RF-1

**Почему:**  
`WorkflowRunner`, `InstructionRunner`, `PromptRunner` дублируют логику обхода.
`GraphTraversal` уже изолирован — нужно сделать его общим для всех трёх.

**Концепция:**

```
GraphTraversal (общий обход)
    ↓ стратегия выполнения узла
WorkflowNodeExecutor   — execute + suspend + checkpoint
InstructionNodeExecutor — execute + валидация результата через контракт
PromptNodeExecutor     — execute → String, аккумулирует в буфер
```

**Разница между типами графов:**

| | Workflow | Instruction | Prompt |
|---|---|---|---|
| Suspend | ✅ | ❌ | ❌ |
| Результат | side effects | валидируемый Map | String |
| Валидация выхода | нет | JSON Schema | нет |
| Checkpoint | ✅ IStatefulNode | нет | нет |
| Инструменты | через IToolEngineProtocol | через IToolEngineProtocol | нет |

**Что меняется:**
- `GraphTraversal` получает `NodeExecutionStrategy` как параметр
- `WorkflowRunner` передаёт `WorkflowExecutionStrategy`
- `InstructionRunner` передаёт `InstructionExecutionStrategy`
- `PromptRunner` передаёт `PromptExecutionStrategy`
- Логика обхода (рёбра, join, parallel, cycle detection) — один раз в `GraphTraversal`

**Файлы:**
- `aq_graph_engine/lib/src/server/runners/graph_traversal.dart` — добавить `NodeExecutionStrategy`
- `aq_graph_engine/lib/src/server/runners/node_executor.dart` — стать стратегией
- `aq_graph_engine/lib/src/server/runners/instruction_runner.dart` — использовать GraphTraversal
- `aq_graph_engine/lib/src/server/runners/prompt_runner.dart` — использовать GraphTraversal

**Шаги:**
1. Выделить `NodeExecutionStrategy` интерфейс
2. `NodeExecutor` → `WorkflowNodeExecutor implements NodeExecutionStrategy`
3. Создать `InstructionNodeExecutor` с валидацией контракта
4. Создать `PromptNodeExecutor` с аккумулятором строк
5. Обновить `InstructionRunner` и `PromptRunner` — использовать `GraphTraversal`
6. Убедиться что тесты зелёные

---

## RF-3: Упрощение типов узлов WorkflowGraph

**Приоритет:** LOW  
**Риск:** Высокий — меняется публичный API узлов  
**Зависимость:** RF-1, RF-2

**Почему:**  
`LlmActionNode`, `FileReadNode`, `FileWriteNode`, `GitCommitNode` — узлы знают **что** делают.
После RF-1 они все просто вызывают `IToolEngineProtocol.instance.callTool(toolName, args, ctx)`.
Разница между ними — только `toolName`. Типизация по действию теряет смысл.

**Концепция:**  
Узлы типизируются по **поведению в графе**, не по действию:
- `AutomaticWorkflowNode` — выполняет инструмент, не suspend
- `InteractiveWorkflowNode` — может suspend (userInput, manualReview, fileUpload)
- `CompositeWorkflowNode` — вызывает вложенный граф

`LlmActionNode` = `AutomaticWorkflowNode(toolName: 'llm_complete', ...)`  
`FileReadNode` = `AutomaticWorkflowNode(toolName: 'fs_read', ...)`

**Важно:** это изменение в `aq_schema` — отдельная сессия.

**Шаги:**
1. Обсудить и утвердить новую схему узлов
2. Создать `AutomaticWorkflowNode` как универсальный узел
3. Пометить `LlmActionNode`, `FileReadNode` и т.д. как `@Deprecated`
4. Мигрировать существующие графы
5. Удалить deprecated узлы

---

## Порядок исполнения

```
RF-1 (IToolEngineProtocol)
  ↓
TD-1 (projectPath)  ←→  TD-2 (deprecated v1)  ←→  TD-3 (GraphValidator)
  ↓
RF-2 (унификация обхода)
  ↓
RF-3 (упрощение узлов) + TD-5 (fileContext)
  ↓
TD-4 (distributed lock) — когда data layer готов
```

---

## Отчёт об исполнении

| ID | Задача | Статус | Дата |
|----|--------|--------|------|
| RF-1 | IToolService → IToolEngineProtocol | ⏳ | — |
| RF-2 | Унификация обхода трёх графов | ⏳ | — |
| RF-3 | Упрощение типов узлов | ⏳ | — |
