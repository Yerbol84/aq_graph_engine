# ОТЧЁТ О ПРОГРЕССЕ: Миграция графов

**Дата:** 2026-05-02  
**Сессия:** session_graph_migration

---

## Статус по плану

| Шаг | Задача | Статус |
|-----|--------|--------|
| 1 | TypedInstructionGraph в aq_schema | ✅ Выполнено |
| 2 | TypedPromptGraph в aq_schema | ✅ Выполнено |
| 3 | InstructionRunner — убрать InstructionNodeFactory | 🔄 В процессе |
| 4 | PromptRunner — убрать _createPromptNode | ⏳ Ожидает |
| 5 | DataLayerGraphRepository — загрузка Typedграфов | ⏳ Ожидает |
| 6 | Удалить старые фабрики и конвертацию | ⏳ Ожидает |
| 7 | aq_graph_worker — WorkflowGraph → TypedWorkflowGraph в тестах | ⏳ Ожидает |
| 8 | Проверка + финальный отчёт | ⏳ Ожидает |

---

## Что сделано (Шаги 1–2)

### TypedInstructionGraph (`aq_schema/lib/graph/graphs/typed_instruction_graph.dart`)

Создан по образцу `TypedWorkflowGraph`:
- `extends $Graph<IInstructionNode, InstructionEdge>` — типизированные узлы
- `kCollection = 'instruction_graphs'` — та же коллекция в БД
- `fromMap(m, IInstructionNodeSerializer)` — десериализация через serializer
- `IInstructionNodeSerializer` — интерфейс для движка (аналог `IWorkflowNodeSerializer`)

### TypedPromptGraph (`aq_schema/lib/graph/graphs/typed_prompt_graph.dart`)

Аналогично:
- `extends $Graph<IPromptNode, PromptEdge>`
- `kCollection = 'prompt_graphs'`
- `IPromptNodeSerializer`

### IInstructionNode и IPromptNode — обновлены

Оба интерфейса теперь `extends $Node`:
- Добавлен `const Constructor()`
- Добавлен `@override copyWith()`
- Все конкретные узлы переведены с `implements` на `extends`

### Экспорт

Оба новых класса экспортированы из `aq_schema/lib/graph/graph.dart`.

---

## Проверка стека

| Компонент | Результат |
|-----------|-----------|
| `dart analyze aq_schema` | 0 errors ✅ (90 info/warning) |
| `dart analyze aq_graph_engine` | 0 errors ✅ (18 info/warning) |
| `dart analyze aq_graph_worker` | 0 issues ✅ |
| `dart test aq_graph_engine` | 53/53 ✅ |
| Сценарий 01 hello_world | ✅ УСПЕХ |
| Сценарий 02 chain | ✅ УСПЕХ |
| Сценарий 03 conditional | ✅ УСПЕХ |
| Сценарий 05 suspend/resume | ✅ УСПЕХ |

---

## Что осталось

### Шаг 3: InstructionRunner

Сейчас:
```dart
// InstructionRunner принимает InstructionGraph (старый)
// и конвертирует каждый узел:
final polymorphicNode = InstructionNodeFactory.fromJson(firstNode.toJson());
```

Нужно:
```dart
// InstructionRunner принимает TypedInstructionGraph
// и вызывает напрямую:
await node.execute(context);
```

`NodeTypeRegistry` уже имеет `instructionFromJson` — нужно реализовать
`IInstructionNodeSerializer` через него.

### Шаг 4: PromptRunner

Аналогично — убрать `_createPromptNode(node)`, принимать `TypedPromptGraph`.

### Шаг 5: DataLayerGraphRepository

Добавить загрузку `TypedInstructionGraph` и `TypedPromptGraph`.
Убрать конвертацию deprecated `WorkflowGraph`.

### Шаг 6: Удалить

- `InstructionNodeFactory`
- `WorkflowNodeFactory`  
- `PromptNodeFactory`
- Конвертацию `WorkflowGraph → TypedWorkflowGraph` из репозитория

### Шаг 7: aq_graph_worker тесты

~200 вхождений `WorkflowGraph` в 15 интеграционных тестах.
Заменить на `TypedWorkflowGraph`.
