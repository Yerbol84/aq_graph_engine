# NEXT_SESSION.md — Задание для следующей сессии

**Пакеты в работе:** `aq_schema` (только `lib/graph/`) + `aq_graph_engine` + `aq_graph_worker`  
**Правило:** одна сессия = один пакет (package_work_rules). Здесь исключение — три пакета связаны одной миграцией.

---

## Контекст: что уже сделано

Выполнена миграция `WorkflowGraph` → `TypedWorkflowGraph` (полиморфные узлы `IWorkflowNode`).

Созданы в `aq_schema`:
- `TypedInstructionGraph extends $Graph<IInstructionNode, InstructionEdge>` ✅
- `TypedPromptGraph extends $Graph<IPromptNode, PromptEdge>` ✅
- `IInstructionNode extends $Node` с `const IInstructionNode()` ✅
- `IPromptNode extends $Node` с `const IPromptNode()` ✅
- Все конкретные узлы (`ConditionNode`, `LlmQueryNode`, `ToolCallNode`, `TransformNode`, `TextBlockNode`, `ConditionalBlockNode`, `VariableInsertNode`) — `extends` (не `implements`) ✅

Стек чистый: `dart analyze` — 0 errors, `dart test` — 53/53, сценарии 01–05 ✅

---

## Задача сессии: завершить миграцию

Цель — убрать все старые data-class графы и фабрики. Оставить только Typed.

---

## Шаг 1: InstructionRunner → TypedInstructionGraph

**Файл:** `aq_graph_engine/lib/src/server/runners/instruction_runner.dart`

**Сейчас (проблема):**
```dart
// Загружает старый InstructionGraph
if (graph is! InstructionGraph) { ... }

// Конвертирует узел на каждом шаге — лишняя сериализация
final polymorphicNode = InstructionNodeFactory.fromJson(firstNode.toJson()); // строка 89
// ...
final nextNode = InstructionNodeFactory.fromJson(nextNodeData.toJson()); // строка 135
```

**Нужно:**
```dart
// Загружать TypedInstructionGraph
if (graph is! TypedInstructionGraph) { ... }

// Узлы уже полиморфные — вызывать напрямую
final node = graph.nodes[nodeId]!; // IInstructionNode
await node.execute(context);       // без конвертации
```

`NodeTypeRegistry` уже реализует `IInstructionNodeSerializer` — использовать его при загрузке графа.

**Что изменить в `DataLayerGraphRepository`** (шаг 3 ниже) — загружать `TypedInstructionGraph` вместо `InstructionGraph`.

---

## Шаг 2: PromptRunner → TypedPromptGraph

**Файл:** `aq_graph_engine/lib/src/server/runners/prompt_runner.dart`

**Сейчас (проблема):**
```dart
if (graph is! PromptGraph) { ... }
// ...
final promptNode = _createPromptNode(node); // строка 57 — конвертация на каждом узле
```

**Нужно:**
```dart
if (graph is! TypedPromptGraph) { ... }
// ...
final result = await node.compile(context); // IPromptNode — напрямую
```

Проверить что у `IPromptNode` есть метод `compile(RunContext) → String`.  
Если нет — добавить в `aq_schema/lib/graph/nodes/base/i_prompt_node.dart`.

---

## Шаг 3: DataLayerGraphRepository — загружать Typed-графы

**Файл:** `aq_graph_engine/lib/src/server/storage/data_layer_graph_repository.dart`

**Сейчас:**
```dart
VersionedRepository<InstructionGraph> get _instructions => ...  // старый тип
VersionedRepository<PromptGraph> get _prompts => ...            // старый тип
```

**Нужно:**
```dart
// TypedInstructionGraph через IInstructionNodeSerializer (NodeTypeRegistry)
VersionedRepository<TypedInstructionGraph> get _instructions =>
    IDataLayer.instance.versioned<TypedInstructionGraph>(
      collection: TypedInstructionGraph.kCollection,
      fromMap: (m) => TypedInstructionGraph.fromMap(m, _defaultRegistry),
    );

// TypedPromptGraph через IPromptNodeSerializer (NodeTypeRegistry)
VersionedRepository<TypedPromptGraph> get _prompts =>
    IDataLayer.instance.versioned<TypedPromptGraph>(
      collection: TypedPromptGraph.kCollection,
      fromMap: (m) => TypedPromptGraph.fromMap(m, _defaultRegistry),
    );
```

Убрать конвертацию `WorkflowGraph → TypedWorkflowGraph` (`_convertToTyped`).  
`WorkflowGraph` deprecated — данные в БД уже в формате `TypedWorkflowGraph`.

---

## Шаг 4: Удалить старые фабрики

После шагов 1–3 фабрики больше не используются.

**Удалить файлы:**
- `aq_graph_engine/lib/src/server/factories/instruction_node_factory.dart`
- `aq_graph_engine/lib/src/server/factories/workflow_node_factory.dart`
- `aq_graph_engine/lib/src/server/factories/prompt_node_factory.dart`
- `aq_graph_engine/lib/src/server/factories/factories.dart`

Убрать папку `factories/` целиком.  
Убрать экспорт из `server.dart` если есть.

---

## Шаг 5: aq_graph_worker — тесты

**336 вхождений `WorkflowGraph`** в тестах. Заменить на `TypedWorkflowGraph`.

```bash
grep -rn "WorkflowGraph\b" /my_dir/ai_work/dev/aq_graph_worker/test/ | wc -l  # 336
```

Файлы в `test/integration/` — построены на `WorkflowGraph` (deprecated).  
Заменить конструкторы и импорты. `TypedWorkflowGraph` принимает `IWorkflowNode` узлы.

Образец замены:
```dart
// Было:
WorkflowGraph(id: ..., nodes: {'n1': WorkflowNode(type: WorkflowNodeType.llmAction, ...)})

// Стало:
TypedWorkflowGraph(id: ..., nodes: {'n1': LlmActionNode(id: 'n1', ...)})
```

---

## Шаг 6: Проверка

```bash
dart analyze lib/  # aq_schema — 0 errors
dart analyze lib/  # aq_graph_engine — 0 errors
dart analyze lib/  # aq_graph_worker — 0 errors
dart test test/unit/  # aq_graph_engine — все зелёные
dart test test/       # aq_graph_worker — все зелёные
# Сценарии 01–05 — все УСПЕХ
```

---

## После завершения этой сессии

Пометить для удаления в `aq_schema` (отдельная сессия):
- `graphs/workflow_graph.dart` — `@Deprecated`
- `graphs/instruction_graph.dart` — удалить
- `graphs/prompt_graph.dart` — удалить

---

## Tech Debt (не трогать в этой сессии)

| ID | Что | Где |
|----|-----|-----|
| TD-1 | `projectPath` в `graphSnapshot` | `local_engine_transport.dart` — ждёт `WorkflowRun.projectPath` в `aq_schema` |
| TD-2 | `tryAcquireLock → true` | `data_layer_run_repository.dart` — ждёт advisory locks в `aq_data_layer` |
| TD-3 | `appendLog` no-op | `i_run_repository.dart` — ждёт отдельной таблицы логов в `aq_data_layer` |

---

## Ключевые файлы для чтения перед началом

```
aq_schema/lib/graph/graphs/typed_instruction_graph.dart   — интерфейс IInstructionNodeSerializer
aq_schema/lib/graph/graphs/typed_prompt_graph.dart        — интерфейс IPromptNodeSerializer
aq_schema/lib/graph/nodes/base/i_instruction_node.dart    — что умеет IInstructionNode
aq_schema/lib/graph/nodes/base/i_prompt_node.dart         — что умеет IPromptNode
aq_graph_engine/lib/src/server/registry/node_type_registry.dart — buildDefaultRegistry()
aq_graph_engine/lib/src/server/runners/instruction_runner.dart  — что менять
aq_graph_engine/lib/src/server/runners/prompt_runner.dart       — что менять
aq_graph_engine/lib/src/server/storage/data_layer_graph_repository.dart — что менять
```
