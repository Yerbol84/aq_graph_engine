# ARCHITECTURE.md — Внутреннее устройство aq_graph_engine

**Последнее обновление:** 2026-05-02  
**Статус:** Актуально

---

## Пакеты

```
aq_schema/          — контракты, интерфейсы, модели данных
aq_graph_engine/    — реализация движка (runners, transport, storage)
aq_graph_worker/    — HTTP воркер (очередь + GraphEngine)
```

Правило: домены и интерфейсы — в `aq_schema`. Реализации — в целевом пакете.

---

## Структура aq_graph_engine/lib

```
aq_graph_engine.dart          — публичный API (клиентская часть)
server.dart                   — публичный API (серверная часть)

src/
  server/
    engine/
      graph_engine.dart        — единая точка входа, выбор транспорта
      engine_execution_context.dart
    runners/
      workflow_runner.dart     — оркестратор lifecycle (start/suspend/complete/fail)
      graph_traversal.dart     — алгоритм обхода графа (DAG traversal)
      node_executor.dart       — выполнение одного узла
      instruction_runner.dart  — выполнение InstructionGraph
      prompt_runner.dart       — компиляция PromptGraph → строка
    storage/
      data_layer_run_repository.dart   — IRunRepository через IDataLayer
      data_layer_graph_repository.dart — IGraphRepository через IDataLayer
    registry/
      node_type_registry.dart  — реестр типов узлов (замена фабрикам)
    factories/                 — DEPRECATED, удалить после миграции
      workflow_node_factory.dart
      instruction_node_factory.dart
      prompt_node_factory.dart
    monitoring/
      metrics.dart
  transport/
    local_engine_transport.dart  — выполнение в том же процессе
    http_engine_transport.dart   — выполнение на удалённом сервере (клиент)
    run_repo_event_bridge.dart   — декоратор: IRunRepository + Stream событий
  client/
    graph_engine_client.dart     — HTTP клиент для GraphEngine Server
    graph_run_stream.dart        — WebSocket stream событий
    models.dart / exceptions.dart
  shared/
    logger.dart                  — shortId(), логгеры
```

---

## Структура aq_schema/lib/graph

```
graph.dart                    — barrel export

core/
  graph_def.dart              — $Graph, $Node, $Edge базовые классы

graphs/
  typed_workflow_graph.dart   — TypedWorkflowGraph ✅ актуальный
  typed_instruction_graph.dart — TypedInstructionGraph ✅ создан, миграция в процессе
  typed_prompt_graph.dart     — TypedPromptGraph ✅ создан, миграция в процессе
  workflow_graph.dart         — @Deprecated → TypedWorkflowGraph
  instruction_graph.dart      — @Deprecated → TypedInstructionGraph
  prompt_graph.dart           — @Deprecated → TypedPromptGraph

nodes/
  base/
    i_workflow_node.dart      — IWorkflowNode extends $Node
    i_instruction_node.dart   — IInstructionNode extends $Node
    i_prompt_node.dart        — IPromptNode extends $Node
    automatic_node.dart       — AutomaticNode (workflow)
    interactive_node.dart     — InteractiveNode (workflow, suspend/resume)
    composite_node.dart       — CompositeNode (workflow, subgraph)
  workflow/
    automatic/  llm_action_node, file_read_node, file_write_node, git_commit_node
    interactive/ user_input_node, manual_review_node, file_upload_node, co_creation_chat_node
    composite/  sub_graph_node, run_instruction_node
  instruction/
    condition_node, llm_query_node, tool_call_node, transform_node
  prompt/
    text_block_node, variable_insert_node, conditional_block_node

engine/
  i_run_repository.dart       — lifecycle run (статус, логи, suspend/resume) → БД
  i_graph_repository.dart     — загрузка графов по ID
  i_run_state_manager.dart    — кэш RunContext между узлами → память
  run_context.dart            — контекст выполнения (переменные, логи)
  workflow_run.dart           — модель run в БД
  condition_evaluator.dart    — вычисление условий для рёбер
  state_strategies/           — InMemoryStateManager, IntervalStateManager, NoopStateManager

transport/
  interfaces/i_engine_transport.dart
  messages/  run_event, run_request, run_state, run_status, user_input_response
```

---

## Иерархия узлов (актуальная)

```
$Node
├── IWorkflowNode
│   ├── AutomaticNode
│   │   ├── LlmActionNode
│   │   ├── FileReadNode
│   │   ├── FileWriteNode
│   │   └── GitCommitNode
│   ├── InteractiveNode          ← suspend/resume
│   │   ├── UserInputNode
│   │   ├── ManualReviewNode
│   │   ├── FileUploadNode
│   │   └── CoCreationChatNode
│   └── CompositeNode
│       ├── SubGraphNode
│       └── RunInstructionNode
├── IInstructionNode
│   ├── ConditionNode
│   ├── LlmQueryNode
│   ├── ToolCallNode
│   └── TransformNode
└── IPromptNode
    ├── TextBlockNode
    ├── VariableInsertNode
    └── ConditionalBlockNode
```

---

## Поток выполнения WorkflowGraph

```
GraphEngine.run(request)
  └── LocalEngineTransport.run(request)
        ├── DataLayerGraphRepository.loadGraph(blueprintId)
        │     └── TypedWorkflowGraph (или конвертация из deprecated WorkflowGraph)
        ├── DataLayerRunRepository.createRun(...)
        └── WorkflowRunner.start(...)
              ├── RunContext (переменные, логи)
              ├── GraphTraversal.traverse(graph, startNode, onNodeExecuted)
              │     └── для каждого узла:
              │           ├── NodeExecutor.execute(node, context, tools)
              │           │     └── node.execute(context)  ← полиморфизм
              │           └── onNodeExecuted() → WorkflowRunner проверяет статус
              └── при suspend:
                    ├── IRunRepository.suspendRun(contextJson, nodeId)
                    └── IRunStateManager.checkpointForNode(runId, context)
```

---

## Разграничение IRunRepository vs IRunStateManager

| | IRunRepository | IRunStateManager |
|---|---|---|
| Что хранит | Статус, логи, snapshot | RunContext (переменные) |
| Где | БД (персистентно) | Память (кэш) |
| Когда пишет | При смене статуса | После каждого узла |
| Аналогия | Журнал событий | Буфер между узлами |

**Правило:** lifecycle (suspend/resume/complete) — только через `IRunRepository`.
`IRunStateManager` — только кэш для производительности.

---

## Регистрация узлов (NodeTypeRegistry)

Фабрики (`WorkflowNodeFactory` и др.) — deprecated. Правильный способ:

```dart
// node_type_registry.dart
NodeTypeRegistry buildDefaultRegistry() {
  final registry = NodeTypeRegistry();

  // Workflow
  registry.registerWorkflow('llmAction', (json) => LlmActionNode.fromJson(json));
  registry.registerWorkflow('fileRead',  (json) => FileReadNode.fromJson(json));
  // ...

  // Instruction
  registry.registerInstruction('condition', (json) => ConditionNode.fromJson(json));
  registry.registerInstruction('llmQuery',  (json) => LlmQueryNode.fromJson(json));
  // ...

  // Prompt
  registry.registerPrompt('textBlock',        (json) => TextBlockNode.fromJson(json));
  registry.registerPrompt('conditionalBlock', (json) => ConditionalBlockNode.fromJson(json));
  // ...

  return registry;
}
```

`NodeTypeRegistry` реализует `IWorkflowNodeSerializer`, `IInstructionNodeSerializer`,
`IPromptNodeSerializer` — используется при десериализации Typed-графов.

---

## Транспорты

### LocalEngineTransport

Выполняет граф в том же процессе. Используется в desktop приложении и тестах.

```
LocalEngineTransport
  ├── RunRepoEventBridge (декоратор над IRunRepository — добавляет Stream событий)
  ├── WorkflowRunner
  ├── InstructionRunner
  └── PromptRunner
```

**Tech Debt:** `projectPath` сохраняется в `graphSnapshot['_projectPath']` при создании run
и восстанавливается при resume. Будет убрано после добавления поля в `WorkflowRun`.

### HttpEngineTransport

Клиентская сторона. Отправляет запросы к GraphEngine Server по HTTP/SSE.
Включает circuit breaker и retry логику.

---

## Текущие ограничения (tech debt)

| ID | Проблема | Где | Условие удаления |
|----|----------|-----|-----------------|
| TD-1 | `projectPath` в `graphSnapshot` | `local_engine_transport.dart` | После `WorkflowRun.projectPath` в `aq_schema` |
| TD-2 | `tryAcquireLock → true` | `data_layer_run_repository.dart` | После advisory locks в `aq_data_layer` |
| TD-3 | `appendLog` no-op дефолт | `i_run_repository.dart` | После отдельной таблицы логов в `aq_data_layer` |

---

## Что нужно сделать (следующие сессии)

### Сессия: Миграция InstructionRunner и PromptRunner

1. `InstructionRunner` — принимать `TypedInstructionGraph`, убрать `InstructionNodeFactory`
2. `PromptRunner` — принимать `TypedPromptGraph`, убрать `_createPromptNode`
3. `DataLayerGraphRepository` — загружать `TypedInstructionGraph` и `TypedPromptGraph`
4. Удалить `InstructionNodeFactory`, `WorkflowNodeFactory`, `PromptNodeFactory`
5. `aq_graph_worker` тесты — заменить `WorkflowGraph` → `TypedWorkflowGraph`

### Сессия: TD-1 (projectPath)

Добавить `projectPath` в `WorkflowRun` в `aq_schema`.
Убрать костыль из `local_engine_transport.dart`.

### Сессия: TD-2 (distributed lock)

Реализовать advisory locks в `aq_data_layer`.
Обновить `DataLayerRunRepository.tryAcquireLock`.
