# Graph Engine - Полное руководство по полиморфной архитектуре

## Обзор

Graph Engine теперь использует полиморфную архитектуру на основе классов вместо enum-based системы. Это обеспечивает лучшую расширяемость, типобезопасность и читаемость кода.

## Архитектура

### Три типа графов

1. **WorkflowGraph** - основные рабочие процессы с поддержкой suspend/resume
2. **InstructionGraph** - граф-функции, выполняются полностью без пауз
3. **PromptGraph** - компиляция текста промпта из частей

### Иерархия узлов

```
$Node (базовый абстрактный класс)
├── IWorkflowNode (интерфейс для WorkflowGraph)
│   ├── AutomaticNode (автоматические узлы)
│   │   ├── LlmActionNode
│   │   ├── FileReadNode
│   │   ├── FileWriteNode
│   │   └── GitCommitNode
│   ├── InteractiveNode (интерактивные узлы)
│   │   ├── UserInputNode
│   │   ├── ManualReviewNode
│   │   ├── FileUploadNode
│   │   └── CoCreationChatNode
│   └── CompositeNode (композитные узлы)
│       ├── SubGraphNode
│       └── RunInstructionNode
├── IInstructionNode (интерфейс для InstructionGraph)
│   ├── ToolCallNode
│   ├── LlmQueryNode
│   ├── ConditionNode
│   └── TransformNode
└── IPromptNode (интерфейс для PromptGraph)
    ├── TextBlockNode
    ├── VariableInsertNode
    └── ConditionalBlockNode
```

## Использование

### Создание узлов

#### Из кода

```dart
// Automatic node
final llmNode = LlmActionNode(
  id: 'llm1',
  promptBlueprintId: 'prompt_123',
  outputVar: 'result',
  modelName: 'gpt-4',
);

// Interactive node
final inputNode = UserInputNode(
  id: 'input1',
  title: 'Enter name',
  message: 'Please enter your name',
  outputVar: 'user_name',
  inputType: 'text',
);

// Composite node
final subGraphNode = SubGraphNode(
  id: 'sub1',
  subGraphId: 'graph_456',
  inputMapping: {'input': 'data'},
  outputMapping: {'result': 'output'},
);
```

#### Из JSON

```dart
import 'package:aq_graph_engine/src/factories/workflow_node_factory.dart';

final json = {
  'id': 'llm1',
  'type': 'llmAction',
  'config': {
    'prompt_blueprint_id': 'prompt_123',
    'output_var': 'result',
  },
};

final node = WorkflowNodeFactory.fromJson(json);
```

### Выполнение узлов

```dart
// Создать контекст
final context = RunContext(
  runId: 'run_123',
  projectId: 'proj_456',
  projectPath: '/path/to/project',
  log: (msg, {type, depth, required branch, details}) {
    print('[$branch] $msg');
  },
);

// Создать реестр инструментов
final tools = ToolRegistry();

// Выполнить узел
final result = await node.execute(context, tools);
```

### Использование Runners

#### WorkflowRunner

```dart
import 'package:aq_graph_engine/src/runners/polymorphic_workflow_runner.dart';

final runner = PolymorphicWorkflowRunner(
  runId: 'run_123',
  projectId: 'proj_456',
  projectPath: '/path/to/project',
  graph: workflowGraph,
  repo: runRepository,
  graphRepo: graphRepository,
  tools: toolRegistry,
);

await runner.start();
```

#### InstructionRunner

```dart
import 'package:aq_graph_engine/src/runners/instruction_runner.dart';

final runner = InstructionRunner(
  graphRepo: graphRepository,
  tools: toolRegistry,
);

final context = RunContext(...);
final resultContext = await runner.execute('instruction_id', context);
```

#### PromptRunner

```dart
import 'package:aq_graph_engine/src/runners/prompt_runner.dart';

final runner = PromptRunner(
  graphRepo: graphRepository,
);

final context = RunContext(...);
context.setVar('name', 'Alice');

final compiledPrompt = await runner.run('prompt_id', context);
```

## Типы узлов

### WorkflowGraph узлы

#### Automatic узлы

**LlmActionNode** - вызов LLM
```dart
LlmActionNode(
  id: 'llm1',
  promptBlueprintId: 'prompt_123',  // ID PromptGraph
  outputVar: 'result',              // Переменная для результата
  modelName: 'gpt-4',               // Опционально
)
```

**FileReadNode** - чтение файла
```dart
FileReadNode(
  id: 'read1',
  filePath: '/path/to/{{filename}}',  // Поддержка {{variables}}
  outputVar: 'content',
)
```

**FileWriteNode** - запись файла
```dart
FileWriteNode(
  id: 'write1',
  filePath: '/path/to/output.txt',
  inputVar: 'data',  // Переменная с содержимым
)
```

**GitCommitNode** - git commit
```dart
GitCommitNode(
  id: 'commit1',
  message: 'Fix {{issue_id}}',  // Поддержка {{variables}}
  filesVar: 'changed_files',    // Опционально
)
```

#### Interactive узлы

**UserInputNode** - запрос ввода
```dart
UserInputNode(
  id: 'input1',
  title: 'Enter name',
  message: 'Please enter your name',
  outputVar: 'user_name',
  inputType: 'text',  // text, number, multiline
)
```

**ManualReviewNode** - ручная проверка
```dart
ManualReviewNode(
  id: 'review1',
  title: 'Review code',
  message: 'Please review the generated code',
  reviewVar: 'generated_code',
  outputVar: 'review_decision',  // approved/rejected
)
```

**FileUploadNode** - загрузка файла
```dart
FileUploadNode(
  id: 'upload1',
  title: 'Upload document',
  message: 'Please upload a PDF',
  outputVar: 'uploaded_file',
  allowedExtensions: ['.pdf', '.doc'],
)
```

**CoCreationChatNode** - интерактивный чат
```dart
CoCreationChatNode(
  id: 'chat1',
  title: 'Discuss requirements',
  initialMessage: 'What features do you need?',
  chatHistoryVar: 'chat_history',
  outputVar: 'user_message',
)
```

#### Composite узлы

**SubGraphNode** - выполнение подграфа
```dart
SubGraphNode(
  id: 'sub1',
  subGraphId: 'graph_456',
  inputMapping: {
    'subVar': 'parentVar',  // Передать переменные в подграф
  },
  outputMapping: {
    'parentVar': 'subVar',  // Получить результаты из подграфа
  },
)
```

**RunInstructionNode** - выполнение инструкции
```dart
RunInstructionNode(
  id: 'instr1',
  subGraphId: 'instruction_789',
  inputMapping: {'input': 'data'},
  outputMapping: {'result': 'output'},
)
```

### InstructionGraph узлы

**ToolCallNode** - вызов инструмента
```dart
ToolCallNode(
  id: 'tool1',
  toolName: 'test_tool',
  params: {
    'param1': 'value1',
    'param2': '{{variable}}',  // Поддержка {{variables}}
  },
  outputVar: 'result',
)
```

**LlmQueryNode** - запрос к LLM
```dart
LlmQueryNode(
  id: 'llm1',
  promptBlueprintId: 'prompt_123',  // Или directPrompt
  directPrompt: 'Analyze: {{code}}',
  outputVar: 'analysis',
  modelName: 'gpt-4',
)
```

**ConditionNode** - условие
```dart
ConditionNode(
  id: 'cond1',
  checkVar: 'status',
  operator: '==',  // ==, !=, >, <, >=, <=, contains, isEmpty
  compareValue: 'success',
  outputVar: 'is_success',
)
```

**TransformNode** - преобразование данных
```dart
TransformNode(
  id: 'trans1',
  inputVar: 'text',
  transformType: 'extract',  // extract, format, parse, concat, split, trim
  params: {'pattern': r'(\d+)', 'group': 1},
  outputVar: 'number',
)
```

### PromptGraph узлы

**TextBlockNode** - текстовый блок
```dart
TextBlockNode(
  id: 'text1',
  text: 'Hello {{name}}, welcome to {{app}}!',
)
```

**VariableInsertNode** - вставка переменной
```dart
VariableInsertNode(
  id: 'var1',
  varName: 'code',
  prefix: '```javascript\n',
  suffix: '\n```',
  defaultValue: 'No code provided',
)
```

**ConditionalBlockNode** - условный блок
```dart
ConditionalBlockNode(
  id: 'cond1',
  checkVar: 'has_error',
  operator: 'exists',  // ==, !=, isEmpty, isNotEmpty, exists, notExists
  compareValue: true,
  textIfTrue: 'Error: {{error_message}}',
  textIfFalse: 'All good',
)
```

## Расширение системы

### Добавление нового типа узла

1. Создать класс узла в `pkgs/aq_schema/lib/graph/nodes/`:

```dart
import 'package:aq_schema/graph/nodes/base/automatic_node.dart';

class MyCustomNode extends AutomaticNode {
  @override
  final String id;

  @override
  final String nodeType = 'myCustom';

  final String myParam;

  MyCustomNode({
    required this.id,
    required this.myParam,
  });

  @override
  Future<dynamic> execute(RunContext context, ToolRegistry tools) async {
    // Ваша логика
    return result;
  }

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': nodeType,
    'config': {'my_param': myParam},
  };

  factory MyCustomNode.fromJson(Map<String, dynamic> json) {
    final config = json['config'] as Map<String, dynamic>? ?? {};
    return MyCustomNode(
      id: json['id'] as String,
      myParam: config['my_param'] as String? ?? '',
    );
  }

  @override
  IWorkflowNode copyWith({String? id, String? myParam}) {
    return MyCustomNode(
      id: id ?? this.id,
      myParam: myParam ?? this.myParam,
    );
  }
}
```

2. Добавить в фабрику в `pkgs/aq_graph_engine/lib/src/factories/`:

```dart
case 'myCustom':
  return MyCustomNode.fromJson(json);
```

3. Добавить в список поддерживаемых типов:

```dart
static List<String> getSupportedTypes() => [
  // ... существующие типы
  'myCustom',
];
```

## Тестирование

Запуск тестов:

```bash
# Все тесты в aq_schema
cd pkgs/aq_schema && dart test

# Все тесты в aq_graph_engine
cd pkgs/aq_graph_engine && dart test

# Конкретный файл
dart test test/graph/nodes/workflow_automatic_nodes_test.dart
```

## Миграция со старой системы

### Было (enum-based):

```dart
switch (node.type) {
  case WorkflowNodeType.llmAction:
    // 50 строк кода
    break;
  case WorkflowNodeType.fileRead:
    // 30 строк кода
    break;
}
```

### Стало (полиморфизм):

```dart
await node.execute(context, tools);
```

### Миграция JSON:

Формат JSON остался совместимым:

```json
{
  "id": "node1",
  "type": "llmAction",
  "config": {
    "prompt_blueprint_id": "prompt_123",
    "output_var": "result"
  }
}
```

## Best Practices

1. **Используйте фабрики** для создания узлов из JSON
2. **Проверяйте project isolation** в Runners (graph.ownerId == context.projectId)
3. **Используйте изолированные контексты** для InstructionGraph и SubGraph
4. **Обрабатывайте SuspendExecutionException** для интерактивных узлов
5. **Применяйте input/output mapping** для композитных узлов
6. **Подставляйте переменные** через {{variable}} синтаксис
7. **Логируйте действия** через context.log()

## Troubleshooting

### Узел не выполняется

Проверьте:
- Зарегистрирован ли Tool в ToolRegistry
- Есть ли все необходимые переменные в контексте
- Правильно ли указан тип узла в JSON

### SuspendExecutionException не ловится

Убедитесь что:
- Runner обрабатывает это исключение
- Узел наследует InteractiveNode
- Проверка hasUserResponse() выполняется перед suspend

### Переменные не подставляются

Проверьте:
- Используется ли метод substituteVariables()
- Правильный ли синтаксис {{varName}}
- Установлена ли переменная в контексте

## Дополнительные ресурсы

- `REFACTORING_COMPLETE.md` - детальный отчёт о рефакторинге
- `GRAPH_ENGINE_FINAL_PLAN.md` - план реализации
- `pkgs/aq_schema/lib/graph/nodes/` - исходный код узлов
- `pkgs/aq_graph_engine/lib/src/` - фабрики и runners
- `test/` - примеры тестов
