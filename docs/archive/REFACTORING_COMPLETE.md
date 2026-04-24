# Graph Engine Refactoring - Полиморфная архитектура узлов

## Выполненная работа

Успешно завершена трансформация Graph Engine от enum-based системы к полиморфной архитектуре на основе классов.

## Созданные компоненты

### 1. Иерархия узлов WorkflowGraph (10 типов)

**Базовые классы:**
- `IWorkflowNode` - базовый интерфейс
- `AutomaticNode` - автоматические узлы (выполняются сразу)
- `InteractiveNode` - интерактивные узлы (требуют ввода пользователя)
- `CompositeNode` - композитные узлы (содержат подграфы)

**Automatic узлы (4):**
- `LlmActionNode` - вызов LLM через Tool 'llm_ask'
- `FileReadNode` - чтение файла через Tool 'fs_read_file'
- `FileWriteNode` - запись файла через Tool 'fs_write_file'
- `GitCommitNode` - git commit через Tool 'git_commit'

**Interactive узлы (4):**
- `UserInputNode` - запрос текстового ввода от пользователя
- `ManualReviewNode` - ручная проверка и одобрение (approve/reject)
- `FileUploadNode` - загрузка файла пользователем
- `CoCreationChatNode` - интерактивный чат с пользователем

**Composite узлы (2):**
- `SubGraphNode` - выполнение вложенного WorkflowGraph
- `RunInstructionNode` - выполнение InstructionGraph как функции

### 2. Иерархия узлов InstructionGraph (4 типа)

**Базовый интерфейс:**
- `IInstructionNode` - базовый интерфейс для узлов инструкций

**Узлы (4):**
- `ToolCallNode` - вызов любого зарегистрированного Tool
- `LlmQueryNode` - запрос к LLM (с PromptGraph или прямым промптом)
- `ConditionNode` - условное ветвление (==, !=, >, <, contains, isEmpty)
- `TransformNode` - преобразование данных (extract, format, parse, concat, split, trim)

### 3. Иерархия узлов PromptGraph (3 типа)

**Базовый интерфейс:**
- `IPromptNode` - базовый интерфейс для узлов промптов

**Узлы (3):**
- `TextBlockNode` - статический текстовый блок с подстановкой переменных
- `VariableInsertNode` - вставка переменной с prefix/suffix
- `ConditionalBlockNode` - условный блок текста

### 4. Фабрики узлов (в aq_graph_engine)

- `WorkflowNodeFactory` - создание WorkflowGraph узлов из JSON
- `InstructionNodeFactory` - создание InstructionGraph узлов из JSON
- `PromptNodeFactory` - создание PromptGraph узлов из JSON

### 5. Обновлённые Runners

**PolymorphicWorkflowRunner:**
- Использует `node.execute()` вместо switch
- Обрабатывает `SuspendExecutionException` для интерактивных узлов
- Применяет output mapping для композитных узлов

**InstructionRunner:**
- Полностью переписан на полиморфизм
- Выполняет InstructionGraph как функцию без пауз
- Проверяет project isolation (graph.ownerId == context.projectId)

**PromptRunner:**
- Переписан на полиморфизм
- Компилирует промпт из узлов через `node.execute()`
- Возвращает готовый текст промпта

## Архитектурные принципы

### Разделение ответственности

**aq_schema (домены):**
- Все интерфейсы узлов (`IWorkflowNode`, `IInstructionNode`, `IPromptNode`)
- Все базовые классы (`AutomaticNode`, `InteractiveNode`, `CompositeNode`)
- Все конкретные узлы (17 типов)
- Метод `execute()` в каждом узле

**aq_graph_engine (логика):**
- Фабрики для создания узлов из JSON
- Runners для выполнения графов
- Интерфейсы репозиториев (`IRunRepository`, `IGraphRepository`)

### Полиморфизм вместо switch

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

### Изолированные контексты

**WorkflowGraph:**
- Основной контекст с возможностью suspend/resume
- Интерактивные узлы приостанавливают выполнение

**InstructionGraph:**
- Изолированный контекст (создаётся через `RunContext(...)`)
- Выполняется полностью без пауз
- Input/output mapping через `CompositeNode`

**PromptGraph:**
- Использует контекст только для чтения переменных
- Не модифицирует контекст
- Возвращает строку

### Project Isolation

Все Runners проверяют:
```dart
if (graph.ownerId != context.projectId) {
  throw Exception('Graph does not belong to project');
}
```

## Структура файлов

### pkgs/aq_schema/lib/graph/nodes/

```
nodes/
├── base/
│   ├── $node.dart                    # Базовый абстрактный класс
│   ├── i_workflow_node.dart          # Интерфейс WorkflowGraph узлов
│   ├── i_instruction_node.dart       # Интерфейс InstructionGraph узлов
│   ├── i_prompt_node.dart            # Интерфейс PromptGraph узлов
│   ├── automatic_node.dart           # Базовый класс автоматических узлов
│   ├── interactive_node.dart         # Базовый класс интерактивных узлов
│   └── composite_node.dart           # Базовый класс композитных узлов
├── workflow/
│   ├── automatic/
│   │   ├── llm_action_node.dart
│   │   ├── file_read_node.dart
│   │   ├── file_write_node.dart
│   │   └── git_commit_node.dart
│   ├── interactive/
│   │   ├── user_input_node.dart
│   │   ├── manual_review_node.dart
│   │   ├── file_upload_node.dart
│   │   └── co_creation_chat_node.dart
│   └── composite/
│       ├── sub_graph_node.dart
│       └── run_instruction_node.dart
├── instruction/
│   ├── tool_call_node.dart
│   ├── llm_query_node.dart
│   ├── condition_node.dart
│   └── transform_node.dart
├── prompt/
│   ├── text_block_node.dart
│   ├── variable_insert_node.dart
│   └── conditional_block_node.dart
└── nodes.dart                        # Экспорт всех узлов
```

### pkgs/aq_graph_engine/lib/src/

```
src/
├── factories/
│   ├── workflow_node_factory.dart
│   ├── instruction_node_factory.dart
│   ├── prompt_node_factory.dart
│   └── factories.dart                # Экспорт фабрик
└── runners/
    ├── polymorphic_workflow_runner.dart
    ├── instruction_runner.dart
    ├── prompt_runner.dart
    ├── workflow_runner.dart          # Старый runner (deprecated)
    └── runners.dart                  # Экспорт runners
```

## Что дальше

### Phase 6: Тесты (TODO)

Необходимо создать тесты для:
1. Всех узлов (unit tests)
2. Фабрик (fromJson/toJson)
3. Runners (integration tests)
4. Edge cases (suspend/resume, errors, isolation)

### Phase 7: Документация (TODO)

Обновить документацию:
1. `GRAPH_ENGINE_FINAL_PLAN.md` - отметить выполненные фазы
2. Создать примеры использования для каждого типа узлов
3. Документировать API фабрик и runners
4. Добавить диаграммы архитектуры

### Удаление старого кода (TODO)

После тестирования удалить:
1. Enum типы: `WorkflowNodeType`, `InstructionNodeType`, `PromptNodeType`
2. Старые enum-based узлы в graph models
3. Старый `workflow_runner.dart` (если не используется)
4. Старые пути импортов в `src/nodes/` (если остались)

## Преимущества новой архитектуры

1. **Расширяемость**: Добавление нового типа узла = создание одного класса
2. **Читаемость**: Логика узла инкапсулирована в его классе
3. **Тестируемость**: Каждый узел тестируется независимо
4. **Типобезопасность**: Компилятор проверяет корректность вызовов
5. **Модульность**: Узлы в aq_schema, логика в aq_graph_engine
6. **Изоляция**: Чёткое разделение контекстов для разных типов графов

## Статистика

- **Создано файлов**: 30+
- **Типов узлов**: 17 (10 Workflow + 4 Instruction + 3 Prompt)
- **Базовых классов**: 6 (IWorkflowNode, IInstructionNode, IPromptNode, AutomaticNode, InteractiveNode, CompositeNode)
- **Фабрик**: 3
- **Обновлённых Runners**: 3
- **Строк кода**: ~3000+

## Заключение

Рефакторинг завершён успешно. Система готова к добавлению новых типов узлов и расширению функциональности. Следующий шаг - написание тестов и обновление документации.
