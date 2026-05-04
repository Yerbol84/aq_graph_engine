# InstructionGraph — Переиспользуемая инструкция

## 📋 Содержание

1. [Назначение](#назначение)
2. [Структура графа](#структура-графа)
3. [Контракт (Contract)](#контракт-contract)
4. [Типы узлов](#типы-узлов)
5. [Валидация](#валидация)
6. [Циклы и ветвления](#циклы-и-ветвления)
7. [Вызов из Workflow](#вызов-из-workflow)
8. [Примеры использования](#примеры-использования)

---

## Назначение

**InstructionGraph** — это **атомарная единица бизнес-логики** с чётким контрактом входов и выходов. Это как функция в программировании, но в виде графа.

### Когда использовать

- ✅ Переиспользуемая логика (анализ кода, генерация тестов)
- ✅ Сложные ветвления и проверки
- ✅ Циклические процессы (с защитой от бесконечности)
- ✅ Композиция Skills в бизнес-процесс
- ✅ Версионирование бизнес-логики

### Отличия от WorkflowGraph

| Критерий | WorkflowGraph | InstructionGraph |
|----------|---------------|------------------|
| Назначение | Полный сценарий | Атомарная функция |
| Контракт | Нет | Обязателен |
| Циклы | Запрещены | Разрешены |
| UI узлы | Есть | Нет |
| Вызов из другого графа | Нет | Да (через `runInstruction`) |
| Версионирование | Да | Да |

---

## Структура графа

### JSON формат

```json
{
  "id": "uuid",
  "tenantId": "tenant-id",
  "ownerId": "project-id",
  "name": "Code Analyzer",
  "nodes": [
    {
      "id": "step-001",
      "type": "systemAction",
      "payload": {
        "is_root": true,
        "tool_id": "llm_ask",
        "output_var": "analysis",
        "prompt_blueprint_id": "prompt-uuid",
        "comment": "Анализирует код через LLM"
      }
    },
    {
      "id": "step-002",
      "type": "validationCheck",
      "payload": {
        "check_var": "analysis",
        "operator": "!=",
        "target_value": "",
        "comment": "Проверяем что результат не пустой"
      }
    }
  ],
  "edges": [
    {
      "id": "edge-001",
      "sourceId": "step-001",
      "targetId": "step-002",
      "trigger": "completed",
      "branchName": "main"
    }
  ],
  "contract": {
    "inputs": [
      {
        "name": "source_code",
        "type": "string",
        "description": "Код для анализа",
        "required": true
      }
    ],
    "outputs": [
      {
        "name": "analysis",
        "type": "string",
        "description": "Результат анализа"
      }
    ]
  },
  "tests": []
}
```

### Dart модель

```dart
class InstructionGraph extends $Graph<InstructionNode, InstructionEdge>
    implements VersionedStorable {
  final String id;
  final String tenantId;
  final String ownerId; // projectId
  final String name;
  final Map<String, InstructionNode> nodes;
  final Map<String, InstructionEdge> edges;
  final Map<String, dynamic> contract;
  final List<Map<String, dynamic>> tests;
}
```

---

## Контракт (Contract)

### Зачем нужен

Контракт определяет **интерфейс инструкции**:
- Какие данные нужны на входе
- Какие данные вернутся на выходе
- Типы данных
- Обязательность параметров

Это делает инструкцию **надёжной и переиспользуемой**.

### Структура

```json
{
  "inputs": [
    {
      "name": "source_code",
      "type": "string",
      "description": "Исходный код для анализа",
      "required": true
    },
    {
      "name": "language",
      "type": "string",
      "description": "Язык программирования",
      "required": false
    }
  ],
  "outputs": [
    {
      "name": "analysis",
      "type": "string",
      "description": "Результат анализа"
    },
    {
      "name": "issues_count",
      "type": "number",
      "description": "Количество найденных проблем"
    }
  ]
}
```

### Типы данных

- `string` — строка
- `number` — число (int или double)
- `boolean` — булево значение
- `object` — JSON объект
- `array` — массив

### Валидация контракта

Перед выполнением InstructionRunner **валидирует контракт** через JSON Schema:

```dart
final validator = GraphContractValidator();
final errors = await validator.validateInstructionContract(
  contract: graph.contract,
);

if (errors.isNotEmpty) {
  throw ContractValidationException('Контракт невалиден');
}
```

**Что проверяется:**
- Все поля `inputs` и `outputs` имеют `name` и `type`
- Типы данных корректны
- Нет дублирующихся имён

---

## Типы узлов

### 1. `systemAction` — Вызов инструмента

**Назначение:** Выполнить Skill (LLM, файлы, векторный поиск).

**Конфигурация:**
```json
{
  "id": "step-001",
  "type": "systemAction",
  "payload": {
    "is_root": true,
    "tool_id": "llm_ask",
    "output_var": "analysis",
    "model_name": "claude-opus-4",
    "prompt_blueprint_id": "prompt-uuid",
    "tool_args_variables": {
      "query": "search_query"
    },
    "tool_args_defaults": {
      "max_results": 10
    },
    "comment": "Анализирует данные через LLM"
  }
}
```

**Поля:**
- `is_root` — стартовый узел (должен быть ровно один)
- `tool_id` — ID Skill из ToolRegistry
- `output_var` — переменная для результата
- `prompt_blueprint_id` — для LLM узлов
- `tool_args_variables` — маппинг параметров из RunContext
- `tool_args_defaults` — значения по умолчанию

**Доступные tool_id:**
- `llm_ask` / `llm_action` — запрос к LLM
- `fs_read_file` — чтение файла
- `fs_write_file` — запись файла
- `vector_search` — поиск в векторной БД
- `parse_markdown_code` — парсинг кода из markdown
- `local_pdf_read` — чтение PDF

**Выполнение:**
1. Получает Skill из ToolRegistry
2. Собирает аргументы из `tool_args_variables` и `tool_args_defaults`
3. Для LLM: компилирует промпт из PromptGraph
4. Вызывает `hand.execute(args, context)`
5. Сохраняет результат в `RunContext.state[output_var]`

---

### 2. `validationCheck` — Проверка условия

**Назначение:** Ветвление по результату проверки.

**Конфигурация:**
```json
{
  "id": "step-002",
  "type": "validationCheck",
  "payload": {
    "check_var": "analysis",
    "operator": "!=",
    "target_value": "",
    "comment": "Проверяем что результат не пустой"
  }
}
```

**Операторы:**
- `==` — равно
- `!=` — не равно
- `contains` — содержит подстроку
- `>` — больше (для чисел)
- `<` — меньше (для чисел)
- `>=` — больше или равно
- `<=` — меньше или равно

**Рёбра:**
```json
{
  "edges": [
    {
      "sourceId": "step-002",
      "targetId": "step-success",
      "trigger": "true"
    },
    {
      "sourceId": "step-002",
      "targetId": "step-error",
      "trigger": "false"
    }
  ]
}
```

**Выполнение:**
1. Берёт значение из `RunContext.state[check_var]`
2. Сравнивает с `target_value` через `operator`
3. Результат: `true` или `false`
4. Выбирает ребро с соответствующим `trigger`

---

### 3. `stepDescription` — Описательный шаг

**Назначение:** Документация, комментарий в графе.

**Конфигурация:**
```json
{
  "id": "step-003",
  "type": "stepDescription",
  "payload": {
    "message": "Этот шаг анализирует код и находит проблемы",
    "comment": "Показывается пользователю"
  }
}
```

**Выполнение:**
- Логирует сообщение
- Не выполняет никаких действий
- Используется для визуальной документации

---

### 4. `userInputRequest` — Запрос ввода

**Назначение:** Запросить данные у пользователя (упрощённая версия).

**Конфигурация:**
```json
{
  "id": "step-004",
  "type": "userInputRequest",
  "payload": {
    "message": "Введите название проекта"
  }
}
```

**Примечание:** В текущей реализации не приостанавливает выполнение. Планируется доработка.

---

## Валидация

### Валидация контракта

**Когда:** Перед выполнением InstructionRunner.

**Что проверяется:**
```dart
final validator = GraphContractValidator();
final errors = await validator.validateInstructionContract(
  contract: graph.contract,
);
```

**Ошибки:**
- Отсутствует поле `inputs` или `outputs`
- Параметр без `name` или `type`
- Неизвестный тип данных
- Дублирующиеся имена

**Поведение при ошибке:**
```dart
if (errors.isNotEmpty) {
  context.log('❌ Ошибка валидации контракта', type: 'error');
  context.log('⚠️ Выполнение продолжается несмотря на ошибку', type: 'warning');
}
```

Граф **продолжает выполнение** даже при ошибках валидации (для обратной совместимости).

---

### Валидация входных данных

**Когда:** При вызове из Workflow через `runInstruction`.

**Что проверяется:**
- Все `required: true` параметры присутствуют
- Типы данных соответствуют контракту

**Пример:**
```dart
// Workflow передаёт
input_mapping: {
  "source_code": "file_content"
}

// Instruction ожидает
contract.inputs: [
  {"name": "source_code", "type": "string", "required": true}
]

// Проверка
if (!context.state.containsKey("source_code")) {
  throw Exception("Missing required parameter: source_code");
}
```

---

## Циклы и ветвления

### Циклы разрешены

В отличие от WorkflowGraph, InstructionGraph **может содержать циклы**.

**Пример:**
```json
{
  "nodes": [
    {"id": "step-001", "type": "systemAction"},
    {"id": "step-002", "type": "validationCheck"},
    {"id": "step-003", "type": "systemAction"}
  ],
  "edges": [
    {"sourceId": "step-001", "targetId": "step-002"},
    {"sourceId": "step-002", "targetId": "step-003", "trigger": "true"},
    {"sourceId": "step-002", "targetId": "step-001", "trigger": "false"}
  ]
}
```

**Выполнение:**
```
[step-001] → [step-002] ─true→ [step-003]
                │
                └─false→ [step-001] (цикл!)
```

---

### Защита от бесконечных циклов

```dart
int stepCount = 0;
const int maxSteps = 20;

while (currentNode != null) {
  stepCount++;
  if (stepCount > maxSteps) {
    context.log('🛑 FATAL: Max steps ($maxSteps) reached. Stopping.',
        type: 'error');
    break;
  }

  await _executeNode(currentNode);
  currentNode = getNextNode();
}
```

**Ограничение:** Максимум 20 шагов.

**Рекомендация:** Для сложных циклов используйте Skills вместо InstructionGraph.

---

### Kill Switch

Перед каждым шагом проверяется статус запуска:

```dart
final currentRun = await runRepo.getRun(context.runId);
if (currentRun != null) {
  final status = currentRun['status'] as String?;
  if (status == 'failed' || status == 'cancelled') {
    context.log('🛑 ИСПОЛНЕНИЕ ПРЕРВАНО!', type: 'error');
    break;
  }
}
```

Это позволяет **остановить выполнение извне**.

---

## Вызов из Workflow

### Узел `runInstruction`

```json
{
  "type": "runInstruction",
  "config": {
    "instruction_blueprint_id": "uuid-инструкции",
    "instruction_name": "Code Analyzer",
    "input_mapping": {
      "source_code": "file_content"
    },
    "output_mapping": {
      "analysis_result": "llm_result"
    }
  }
}
```

### Маппинг переменных

**input_mapping:**
```
Workflow.state["file_content"] → Instruction.state["source_code"]
```

**output_mapping:**
```
Instruction.state["llm_result"] → Workflow.state["analysis_result"]
```

### Выполнение

```dart
// 1. Загрузить граф
final instructionGraph = await graphRepo.loadGraph(instructionId);

// 2. Создать новый контекст (клон)
final subContext = context.cloneForBranch(context.currentBranch);

// 3. Скопировать входные данные
for (final entry in inputMapping.entries) {
  subContext.setVar(entry.key, context.getVar(entry.value));
}

// 4. Запустить InstructionRunner
final runner = InstructionRunner(
  graph: instructionGraph,
  context: subContext,
  tools: tools,
  graphRepo: graphRepo,
  runRepo: runRepo,
);
await runner.run();

// 5. Скопировать выходные данные
for (final entry in outputMapping.entries) {
  context.setVar(entry.value, subContext.getVar(entry.key));
}
```

---

## Примеры использования

### Пример 1: Простой анализ

```json
{
  "name": "Code Analyzer",
  "nodes": [
    {
      "id": "step-001",
      "type": "systemAction",
      "payload": {
        "is_root": true,
        "tool_id": "llm_ask",
        "output_var": "analysis",
        "prompt_blueprint_id": "analyze-prompt-uuid"
      }
    }
  ],
  "edges": [],
  "contract": {
    "inputs": [
      {"name": "source_code", "type": "string", "required": true}
    ],
    "outputs": [
      {"name": "analysis", "type": "string"}
    ]
  }
}
```

---

### Пример 2: С валидацией

```json
{
  "name": "Code Analyzer with Validation",
  "nodes": [
    {
      "id": "step-001",
      "type": "systemAction",
      "payload": {
        "is_root": true,
        "tool_id": "llm_ask",
        "output_var": "analysis",
        "prompt_blueprint_id": "analyze-prompt-uuid"
      }
    },
    {
      "id": "step-002",
      "type": "validationCheck",
      "payload": {
        "check_var": "analysis",
        "operator": "!=",
        "target_value": ""
      }
    },
    {
      "id": "step-success",
      "type": "stepDescription",
      "payload": {
        "message": "Анализ успешен"
      }
    },
    {
      "id": "step-error",
      "type": "stepDescription",
      "payload": {
        "message": "Анализ вернул пустой результат"
      }
    }
  ],
  "edges": [
    {"sourceId": "step-001", "targetId": "step-002", "trigger": "completed"},
    {"sourceId": "step-002", "targetId": "step-success", "trigger": "true"},
    {"sourceId": "step-002", "targetId": "step-error", "trigger": "false"}
  ],
  "contract": {
    "inputs": [
      {"name": "source_code", "type": "string", "required": true}
    ],
    "outputs": [
      {"name": "analysis", "type": "string"}
    ]
  }
}
```

---

### Пример 3: С циклом (retry)

```json
{
  "name": "LLM with Retry",
  "nodes": [
    {
      "id": "step-001",
      "type": "systemAction",
      "payload": {
        "is_root": true,
        "tool_id": "llm_ask",
        "output_var": "result"
      }
    },
    {
      "id": "step-002",
      "type": "validationCheck",
      "payload": {
        "check_var": "result",
        "operator": "!=",
        "target_value": ""
      }
    },
    {
      "id": "step-003",
      "type": "systemAction",
      "payload": {
        "tool_id": "increment_counter",
        "output_var": "retry_count"
      }
    },
    {
      "id": "step-004",
      "type": "validationCheck",
      "payload": {
        "check_var": "retry_count",
        "operator": "<",
        "target_value": "3"
      }
    }
  ],
  "edges": [
    {"sourceId": "step-001", "targetId": "step-002"},
    {"sourceId": "step-002", "targetId": "step-success", "trigger": "true"},
    {"sourceId": "step-002", "targetId": "step-003", "trigger": "false"},
    {"sourceId": "step-003", "targetId": "step-004"},
    {"sourceId": "step-004", "targetId": "step-001", "trigger": "true"},
    {"sourceId": "step-004", "targetId": "step-error", "trigger": "false"}
  ]
}
```

**Логика:**
```
[LLM] → [Результат не пустой?]
          ├─ true → [Успех]
          └─ false → [Счётчик++] → [Счётчик < 3?]
                                      ├─ true → [LLM] (retry)
                                      └─ false → [Ошибка]
```

---

## Ограничения и рекомендации

### Ограничения

1. **maxSteps = 20** — максимум 20 шагов выполнения
2. **Нет UI узлов** — нельзя запросить ввод у пользователя
3. **Нет параллельного выполнения** — только последовательное
4. **Нет timeout** — узел может выполняться бесконечно

### Рекомендации

1. **Используйте для атомарной логики** — одна чёткая задача
2. **Определяйте контракт** — это делает инструкцию надёжной
3. **Добавляйте валидацию** — используйте `validationCheck`
4. **Ограничивайте циклы** — не более 3-5 итераций
5. **Тестируйте отдельно** — перед использованием в Workflow
6. **Версионируйте** — при изменении логики создавайте новую версию

---

## Тестирование

### Поле `tests`

```json
{
  "tests": [
    {
      "name": "Test with valid code",
      "inputs": {
        "source_code": "function main() { return 42; }"
      },
      "expected_outputs": {
        "analysis": "Code is valid"
      }
    },
    {
      "name": "Test with empty code",
      "inputs": {
        "source_code": ""
      },
      "expected_error": true
    }
  ]
}
```

**Примечание:** Test Runner пока не реализован. Планируется в будущих версиях.

---

## Следующие шаги

- [PromptGraph](./PROMPT_GRAPH.md) — шаблоны промптов
- [WorkflowGraph](./WORKFLOW_GRAPH.md) — основные сценарии
- [Архитектура движка](./ARCHITECTURE.md) — как это работает внутри
