# Graph Engine - Боевой план реализации

**Дата:** 2026-04-08
**Статус:** READY TO IMPLEMENT

## Архитектура (КРИТИЧНО!)

### Правильная концепция:

```
┌─────────────────────────────────────────────────────────────┐
│ WorkflowGraph (основной сценарий)                           │
│                                                              │
│  [Node 1] → [Node 2] → [Node 3]                            │
│     ↓          ↓          ↓                                 │
│  Instruction Instruction Instruction                        │
└─────────────────────────────────────────────────────────────┘

Каждый узел:
1. Собирает входные данные из WorkflowContext
2. Настраивает InstructionGraph (маппинг переменных)
3. Запускает InstructionRunner (изолированная песочница)
4. Получает результат
5. Сохраняет в WorkflowContext
6. Передаёт управление следующему узлу
```

### Роли компонентов:

#### 1. WorkflowNode (Конфигуратор)
**Ответственность:**
- Собрать входные данные из WorkflowContext
- Настроить InstructionGraph (input_mapping)
- Запустить InstructionRunner
- Получить результат
- Сохранить в WorkflowContext (output_mapping)

**НЕ делает:**
- ❌ Не выполняет бизнес-логику
- ❌ Не обращается к Tools напрямую
- ❌ Не сохраняет в БД

#### 2. InstructionGraph (Функция)
**Ответственность:**
- Принять входные данные (контракт)
- Выполнить бизнес-логику (узлы инструкции)
- Вернуть результат (контракт)

**НЕ делает:**
- ❌ Не знает о WorkflowGraph
- ❌ Не сохраняет в БД (только читает!)
- ❌ Не знает о других инструкциях

#### 3. InstructionRunner (Песочница)
**Ответственность:**
- Создать изолированный контекст
- Выполнить граф инструкции
- Использовать Tools (LLM, DB queries, file ops)
- Вернуть результат

**НЕ делает:**
- ❌ Не сохраняет состояние в БД
- ❌ Не знает о WorkflowGraph
- ❌ Не модифицирует WorkflowContext

#### 4. PromptGraph (Шаблон)
**Ответственность:**
- Хранить шаблон промпта
- Подставлять переменные
- Вернуть скомпилированный промпт

**НЕ делает:**
- ❌ Не вызывает LLM
- ❌ Не сохраняет результаты

## Реализация

### Phase 1: Исправить текущую архитектуру (КРИТИЧНО!)

#### 1.1 Переделать WorkflowNode

**Файл:** `pkgs/aq_graph_engine/lib/src/nodes/workflow/run_instruction_node.dart`

**Было (НЕПРАВИЛЬНО):**
```dart
class LlmActionNode {
  Future<dynamic> execute() {
    // Узел сам вызывает LLM - НЕПРАВИЛЬНО!
    final result = await tools.getHand('llm_action').execute(...);
  }
}
```

**Стало (ПРАВИЛЬНО):**
```dart
class RunInstructionNode extends WorkflowNode {
  final String instructionBlueprintId;
  final Map<String, String> inputMapping;   // {"source_code": "code"}
  final Map<String, String> outputMapping;  // {"result": "analysis"}

  @override
  Future<dynamic> execute(
    RunContext workflowContext,
    ToolRegistry tools,
    IGraphRepository graphRepo,
    IRunRepository runRepo,
  ) async {
    // 1. Загрузить InstructionGraph
    final instructionGraph = await graphRepo.loadGraph(instructionBlueprintId);

    // 2. Создать изолированный контекст для инструкции
    final instructionContext = RunContext(
      runId: '${workflowContext.runId}_instruction_${uuid()}',
      projectId: workflowContext.projectId,
      projectPath: workflowContext.projectPath,
      log: workflowContext.log,
      currentBranch: 'instruction',
    );

    // 3. Скопировать входные данные согласно inputMapping
    for (final entry in inputMapping.entries) {
      final instructionVar = entry.key;    // "source_code"
      final workflowVar = entry.value;     // "code"
      final value = workflowContext.getVar(workflowVar);
      instructionContext.setVar(instructionVar, value);
    }

    // 4. Запустить InstructionRunner (песочница!)
    final runner = InstructionRunner(
      graph: instructionGraph,
      context: instructionContext,
      tools: tools,
      graphRepo: graphRepo,
      runRepo: runRepo,
    );

    await runner.run();

    // 5. Скопировать выходные данные согласно outputMapping
    for (final entry in outputMapping.entries) {
      final instructionVar = entry.key;    // "result"
      final workflowVar = entry.value;     // "analysis"
      final value = instructionContext.getVar(instructionVar);
      workflowContext.setVar(workflowVar, value);
    }

    // 6. Вернуть результат (опционально)
    return instructionContext.state;
  }
}
```

#### 1.2 Убрать прямые вызовы Tools из узлов

**Удалить:**
- `LlmActionNode` - заменить на `RunInstructionNode` с инструкцией "llm_ask"
- `FileReadNode` - заменить на `RunInstructionNode` с инструкцией "file_read"
- `FileWriteNode` - заменить на `RunInstructionNode` с инструкцией "file_write"

**Оставить только:**
- `RunInstructionNode` - универсальный узел для запуска инструкций
- `UserInputNode` - интерактивный узел (suspend/resume)
- `ManualReviewNode` - интерактивный узел
- `SubGraphNode` - композитный узел (запуск вложенного Workflow)

#### 1.3 Создать базовые инструкции

**Файлы:** `pkgs/aq_schema/lib/graph/instructions/`

**Инструкции:**

1. **llm_ask.json** - запрос к LLM
```json
{
  "id": "instruction_llm_ask",
  "name": "LLM Ask",
  "contract": {
    "input": {
      "type": "object",
      "properties": {
        "prompt": {"type": "string"},
        "model": {"type": "string", "default": "gpt-4"}
      },
      "required": ["prompt"]
    },
    "output": {
      "type": "object",
      "properties": {
        "result": {"type": "string"}
      }
    }
  },
  "nodes": [
    {
      "id": "node1",
      "type": "systemAction",
      "payload": {
        "tool_id": "llm_action",
        "tool_args_variables": {"prompt": "prompt"},
        "output_var": "result"
      }
    }
  ]
}
```

2. **file_read.json** - чтение файла
```json
{
  "id": "instruction_file_read",
  "name": "File Read",
  "contract": {
    "input": {
      "properties": {
        "file_path": {"type": "string"}
      },
      "required": ["file_path"]
    },
    "output": {
      "properties": {
        "content": {"type": "string"}
      }
    }
  },
  "nodes": [
    {
      "id": "node1",
      "type": "systemAction",
      "payload": {
        "tool_id": "fs_read_file",
        "tool_args_variables": {"file_path": "file_path"},
        "output_var": "content"
      }
    }
  ]
}
```

3. **file_write.json** - запись файла
```json
{
  "id": "instruction_file_write",
  "name": "File Write",
  "contract": {
    "input": {
      "properties": {
        "file_path": {"type": "string"},
        "content": {"type": "string"}
      },
      "required": ["file_path", "content"]
    }
  },
  "nodes": [
    {
      "id": "node1",
      "type": "systemAction",
      "payload": {
        "tool_id": "fs_write_file",
        "tool_args_variables": {
          "file_path": "file_path",
          "content": "content"
        }
      }
    }
  ]
}
```

4. **code_analyzer.json** - анализ кода (сложная инструкция)
```json
{
  "id": "instruction_code_analyzer",
  "name": "Code Analyzer",
  "contract": {
    "input": {
      "properties": {
        "source_code": {"type": "string"},
        "analysis_type": {"type": "string", "enum": ["security", "performance", "style"]}
      },
      "required": ["source_code"]
    },
    "output": {
      "properties": {
        "analysis": {"type": "string"},
        "issues": {"type": "array"},
        "score": {"type": "number"}
      }
    }
  },
  "nodes": [
    {
      "id": "analyze",
      "type": "systemAction",
      "payload": {
        "tool_id": "llm_action",
        "prompt_blueprint_id": "prompt_code_analysis",
        "tool_args_variables": {"prompt": "compiled_prompt"},
        "output_var": "raw_analysis"
      }
    },
    {
      "id": "parse",
      "type": "systemAction",
      "payload": {
        "tool_id": "parse_json",
        "tool_args_variables": {"input": "raw_analysis"},
        "output_var": "parsed"
      }
    },
    {
      "id": "validate",
      "type": "validationCheck",
      "payload": {
        "check_var": "parsed",
        "operator": "!=",
        "target_value": "null"
      }
    }
  ],
  "edges": [
    {"sourceId": "analyze", "targetId": "parse"},
    {"sourceId": "parse", "targetId": "validate"},
    {"sourceId": "validate", "targetId": "end", "trigger": "true"}
  ]
}
```

### Phase 2: Реализовать недостающие узлы

#### 2.1 UserInputNode (интерактивный)

**Файл:** `pkgs/aq_graph_engine/lib/src/nodes/interactive/user_input_node.dart`

```dart
class UserInputNode extends InteractiveNode {
  final String outputVar;
  final String? uiTitle;
  final String? uiMessage;
  final String? uiBlueprintId;

  @override
  Future<dynamic> execute(
    RunContext context,
    ToolRegistry tools,
    IGraphRepository graphRepo,
    IRunRepository runRepo,
  ) async {
    // Приостановить выполнение
    await runRepo.suspendRun(
      runId: context.runId,
      contextJson: jsonEncode({
        'user_context': context.toJson(),
        'engine_state': {
          'ui_action': 'user_input',
          'target_var': outputVar,
          'ui_config': {
            'title': uiTitle,
            'message': uiMessage,
            'blueprint_id': uiBlueprintId,
          },
        },
      }),
      nodeId: id,
      logs: context.logs,
    );

    // Выбросить исключение для остановки runner
    throw SuspendExecutionException(
      nodeId: id,
      reason: 'Waiting for user input',
    );
  }
}
```

#### 2.2 SubGraphNode (композитный)

**Файл:** `pkgs/aq_graph_engine/lib/src/nodes/composite/subgraph_node.dart`

```dart
class SubGraphNode extends CompositeNode {
  final String workflowBlueprintId;
  final Map<String, String> inputMapping;
  final Map<String, String> outputMapping;

  @override
  Future<dynamic> execute(
    RunContext context,
    ToolRegistry tools,
    IGraphRepository graphRepo,
    IRunRepository runRepo,
  ) async {
    // 1. Загрузить вложенный WorkflowGraph
    final subWorkflow = await graphRepo.loadGraph(workflowBlueprintId);

    // 2. Создать изолированный контекст
    final subContext = RunContext(
      runId: '${context.runId}_subgraph_${uuid()}',
      projectId: context.projectId,
      projectPath: context.projectPath,
      log: context.log,
      currentBranch: 'subgraph',
    );

    // 3. Маппинг входов
    for (final entry in inputMapping.entries) {
      subContext.setVar(entry.key, context.getVar(entry.value));
    }

    // 4. Запустить вложенный Workflow
    final runner = PolymorphicWorkflowRunner(
      runId: subContext.runId,
      projectId: subContext.projectId,
      projectPath: subContext.projectPath,
      graph: subWorkflow,
      repo: runRepo,
      graphRepo: graphRepo,
      tools: tools,
    );

    await runner.start(injectedVariables: subContext.state);

    // 5. Маппинг выходов
    for (final entry in outputMapping.entries) {
      context.setVar(entry.value, subContext.getVar(entry.key));
    }
  }
}
```

### Phase 3: Улучшить InstructionRunner

#### 3.1 Добавить изоляцию

**Файл:** `pkgs/aq_graph_engine/lib/src/runners/instruction_runner.dart`

**Изменения:**
```dart
class InstructionRunner {
  final InstructionGraph graph;
  final RunContext context;  // ИЗОЛИРОВАННЫЙ контекст!
  final ToolRegistry tools;
  final IGraphRepository graphRepo;
  final IRunRepository runRepo;

  InstructionRunner({
    required this.graph,
    required this.context,
    required this.tools,
    required this.graphRepo,
    required this.runRepo,
  });

  Future<void> run() async {
    // КРИТИЧНО: Инструкция НЕ сохраняет в БД!
    // Она только читает данные и возвращает результат

    context.log('⚙️ Starting Instruction: ${graph.name}');

    // Валидация контракта
    await _validateContract();

    // Выполнение узлов
    InstructionNode? currentNode = _findStartNode();
    int stepCount = 0;
    const int maxSteps = 20;

    while (currentNode != null && stepCount < maxSteps) {
      stepCount++;

      // Kill switch (проверка статуса родительского run)
      final parentRunId = context.runId.split('_instruction_').first;
      final parentRun = await runRepo.getRun(parentRunId);
      if (parentRun?['status'] == 'cancelled') {
        throw ExecutionCancelledException('Parent run cancelled');
      }

      // Выполнить узел
      await _executeNode(currentNode);

      // Следующий узел
      currentNode = _getNextNode(currentNode);
    }

    context.log('🏁 Instruction completed: ${graph.name}');
  }

  Future<void> _executeNode(InstructionNode node) async {
    if (node.type == InstructionNodeType.systemAction) {
      final toolId = node.payload['tool_id'] as String;
      final hand = tools.getHand(toolId);

      if (hand == null) {
        throw Exception('Tool not found: $toolId');
      }

      // Собрать аргументы
      final args = _buildToolArgs(node);

      // Выполнить
      final result = await hand.execute(args, context);

      // Сохранить результат в контекст инструкции
      final outputVar = node.payload['output_var'] as String?;
      if (outputVar != null) {
        context.setVar(outputVar, result);
      }
    }
  }
}
```

### Phase 4: Создать примеры Workflow

#### 4.1 Простой Workflow

**Файл:** `examples/simple_workflow.json`

```json
{
  "name": "Simple Code Analyzer",
  "nodes": [
    {
      "id": "read_file",
      "type": "runInstruction",
      "config": {
        "instruction_blueprint_id": "instruction_file_read",
        "input_mapping": {
          "file_path": "target_file"
        },
        "output_mapping": {
          "content": "source_code"
        }
      }
    },
    {
      "id": "analyze",
      "type": "runInstruction",
      "config": {
        "instruction_blueprint_id": "instruction_code_analyzer",
        "input_mapping": {
          "source_code": "source_code",
          "analysis_type": "security"
        },
        "output_mapping": {
          "analysis": "analysis_result",
          "score": "quality_score"
        }
      }
    },
    {
      "id": "write_report",
      "type": "runInstruction",
      "config": {
        "instruction_blueprint_id": "instruction_file_write",
        "input_mapping": {
          "file_path": "report_path",
          "content": "analysis_result"
        }
      }
    }
  ],
  "edges": [
    {"sourceId": "read_file", "targetId": "analyze"},
    {"sourceId": "analyze", "targetId": "write_report"}
  ]
}
```

#### 4.2 Интерактивный Workflow

**Файл:** `examples/interactive_workflow.json`

```json
{
  "name": "Interactive Code Review",
  "nodes": [
    {
      "id": "ask_file",
      "type": "userInput",
      "config": {
        "output_var": "target_file",
        "ui_title": "Выберите файл для анализа"
      }
    },
    {
      "id": "read_file",
      "type": "runInstruction",
      "config": {
        "instruction_blueprint_id": "instruction_file_read",
        "input_mapping": {"file_path": "target_file"},
        "output_mapping": {"content": "source_code"}
      }
    },
    {
      "id": "analyze",
      "type": "runInstruction",
      "config": {
        "instruction_blueprint_id": "instruction_code_analyzer",
        "input_mapping": {"source_code": "source_code"},
        "output_mapping": {"analysis": "analysis_result"}
      }
    },
    {
      "id": "review",
      "type": "manualReview",
      "config": {
        "ui_title": "Подтвердите анализ",
        "data_var": "analysis_result"
      }
    },
    {
      "id": "write_report",
      "type": "runInstruction",
      "config": {
        "instruction_blueprint_id": "instruction_file_write",
        "input_mapping": {
          "file_path": "report.md",
          "content": "analysis_result"
        }
      }
    }
  ],
  "edges": [
    {"sourceId": "ask_file", "targetId": "read_file"},
    {"sourceId": "read_file", "targetId": "analyze"},
    {"sourceId": "analyze", "targetId": "review"},
    {"sourceId": "review", "targetId": "write_report"}
  ]
}
```

## Порядок реализации (БОЕВОЙ!)

### День 1: Исправить архитектуру ✅ ЗАВЕРШЕНО
- [x] Создать `RunInstructionNode`
- [x] Удалить `LlmActionNode`, `FileReadNode`, `FileWriteNode`
- [x] Обновить `NodeFactory`
- [x] Создать базовые инструкции (llm_ask, file_read, file_write)
- [x] Создать пример простого Workflow
- [x] Unit тесты для `RunInstructionNode` (5/5 passed)

### День 2: Интерактивные узлы
- [ ] Реализовать `UserInputNode`
- [ ] Реализовать `ManualReviewNode`
- [ ] Добавить suspend/resume в `PolymorphicWorkflowRunner`

### День 3: Композитные узлы
- [ ] Реализовать `SubGraphNode`
- [ ] Улучшить изоляцию в `InstructionRunner`

### День 4: Примеры и тесты
- [ ] Создать примеры Workflow
- [ ] Unit tests для узлов
- [ ] Integration tests для полного flow

### День 5: Документация
- [ ] Обновить README
- [ ] Обновить WORKFLOW_GRAPH.md
- [ ] Создать ARCHITECTURE.md

## Критерии готовности

- [ ] `RunInstructionNode` работает
- [ ] Инструкции выполняются в изоляции
- [ ] Suspend/Resume работает
- [ ] SubGraph работает
- [ ] Примеры запускаются
- [ ] Тесты зелёные
- [ ] Документация обновлена

## Начинаем!

Первая задача: **Создать RunInstructionNode и удалить старые узлы**
