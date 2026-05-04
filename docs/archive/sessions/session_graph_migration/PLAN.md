# ПЛАН МИГРАЦИИ: Все три графа на типизированную архитектуру

**Цель:** Удалить все старые data-class графы. Оставить только типизированные.

## Текущее состояние

| Граф | Тип узлов | Статус |
|------|-----------|--------|
| `TypedWorkflowGraph` | `IWorkflowNode` (полиморфный) | ✅ Готово |
| `InstructionGraph` | `InstructionNode` (data-class + enum) | ❌ Старый |
| `PromptGraph` | `PromptNode` (data-class + enum) | ❌ Старый |
| `WorkflowGraph` | `WorkflowNode` (deprecated) | ❌ Удалить |

## Проблема старых графов

`InstructionGraph` и `PromptGraph` хранят узлы как data-классы с `enum type + Map payload`.
Чтобы выполнить узел нужна конвертация: `node.toJson()` → `Factory.fromJson()` → `INode`.
Это лишняя сериализация на каждом шаге.

## Целевое состояние

```
$Graph<N extends $Node, E extends $Edge>
  ├── TypedWorkflowGraph    extends $Graph<IWorkflowNode,    WorkflowEdge>    ✅
  ├── TypedInstructionGraph extends $Graph<IInstructionNode, InstructionEdge> ← создать
  └── TypedPromptGraph      extends $Graph<IPromptNode,      PromptEdge>      ← создать
```

## Шаги

### Шаг 1: aq_schema — TypedInstructionGraph
- Создать `lib/graph/graphs/typed_instruction_graph.dart`
- Экспортировать из `graph.dart`

### Шаг 2: aq_schema — TypedPromptGraph
- Создать `lib/graph/graphs/typed_prompt_graph.dart`
- Экспортировать из `graph.dart`

### Шаг 3: aq_graph_engine — InstructionRunner
- Принимать `TypedInstructionGraph` вместо `InstructionGraph`
- Убрать `InstructionNodeFactory.fromJson` — вызывать `node.execute()` напрямую

### Шаг 4: aq_graph_engine — PromptRunner
- Принимать `TypedPromptGraph` вместо `PromptGraph`
- Убрать `_createPromptNode` — вызывать `node.execute()` напрямую

### Шаг 5: aq_graph_engine — DataLayerGraphRepository
- Загружать `TypedInstructionGraph` и `TypedPromptGraph`
- Убрать конвертацию deprecated `WorkflowGraph`

### Шаг 6: aq_graph_engine — Удалить старое
- Удалить `InstructionNodeFactory`
- Удалить `WorkflowNodeFactory`
- Удалить `PromptNodeFactory`
- Удалить конвертацию `WorkflowGraph → TypedWorkflowGraph`

### Шаг 7: aq_graph_worker — тесты
- Заменить `WorkflowGraph` на `TypedWorkflowGraph` во всех интеграционных тестах

### Шаг 8: Проверка
- `dart analyze` — 0 errors
- `dart test` — все тесты
- Сценарии 01–05

## После завершения
- `WorkflowGraph` (deprecated) — помечен для удаления из `aq_schema` (отдельная сессия)
- `InstructionGraph`, `PromptGraph` — помечены для удаления из `aq_schema`
