# WorkflowGraph — Основной сценарий выполнения

## 📋 Содержание

1. [Назначение](#назначение)
2. [Структура графа](#структура-графа)
3. [Типы узлов](#типы-узлов)
4. [Типы рёбер](#типы-рёбер)
5. [Параллельное выполнение](#параллельное-выполнение)
6. [Интерактивные узлы](#интерактивные-узлы)
7. [Приостановка и возобновление](#приостановка-и-возобновление)
8. [Примеры использования](#примеры-использования)

---

## Назначение

**WorkflowGraph** — это главный тип графа в AQ Studio. Он описывает **полный сценарий работы агента** от начала до конца.

### Когда использовать

- ✅ Автоматизация процесса разработки (анализ → генерация → тестирование)
- ✅ Создание документации (чтение кода → LLM обработка → запись файлов)
- ✅ Code Review процесс (анализ → запрос подтверждения → коммит)
- ✅ Интерактивные мастера (запрос данных → обработка → результат)

### Ключевые особенности

1. **Параллельное выполнение** — один узел может запустить несколько веток
2. **Приостановка для UI** — граф останавливается, ждёт ввода пользователя, продолжает
3. **Композиция** — может вызывать InstructionGraph как подграф
4. **Обработка ошибок** — рёбра `onError` для альтернативных путей
5. **Сохранение состояния** — после каждого шага состояние пишется в БД

---

## Структура графа

### JSON формат

```json
{
  "id": "uuid",
  "tenantId": "tenant-id",
  "ownerId": "project-id",
  "name": "Code Review Workflow",
  "nodes": [
    {
      "id": "node-001",
      "type": "fileRead",
      "config": {
        "label": "Читаем файл",
        "file_path": "/path/to/file.dart",
        "output_var": "source_code"
      }
    },
    {
      "id": "node-002",
      "type": "llmAction",
      "config": {
        "label": "Анализируем код",
        "prompt_blueprint_id": "prompt-uuid",
        "output_var": "analysis"
      }
    }
  ],
  "edges": [
    {
      "id": "edge-001",
      "sourceId": "node-001",
      "targetId": "node-002",
      "branchName": "main",
      "type": "onSuccess"
    }
  ]
}
```

### Dart модель

```dart
class WorkflowGraph extends $Graph<WorkflowNode, WorkflowEdge>
    implements VersionedStorable {
  final String id;
  final String tenantId;
  final String ownerId; // projectId
  final String name;
  final Map<String, WorkflowNode> nodes;
  final Map<String, WorkflowEdge> edges;
}
```

---

## Типы узлов

### 1. `llmAction` — Запрос к LLM

**Назначение:** Отправить промпт в LLM и получить ответ.

**Конфигурация:**
```json
{
  "type": "llmAction",
  "config": {
    "label": "Анализ кода",
    "comment": "Описание для разработчиков",
    "prompt_blueprint_id": "uuid-промпта",
    "output_var": "llm_result"
  }
}
```

**Поля:**
- `prompt_blueprint_id` — ID PromptGraph для компиляции промпта
- `output_var` — имя переменной для сохранения результата

**Выполнение:**
1. Загружает PromptGraph по ID
2. Компилирует промпт (подставляет переменные)
3. Вызывает Skill `llm_action`
4. Сохраняет результат в `RunContext.state[output_var]`

---

### 2. `fileRead` — Чтение файла

**Назначение:** Прочитать содержимое файла.

**Конфигурация:**
```json
{
  "type": "fileRead",
  "config": {
    "label": "Читаем main.dart",
    "file_path": "/Users/user/project/main.dart",
    "output_var": "source_code"
  }
}
```

**Выполнение:**
1. Вызывает Skill `fs_read_file`
2. Сохраняет содержимое в `RunContext.state[output_var]`
3. Также сохраняет путь в `current_file_path`

---

### 3. `fileWrite` — Запись файла

**Назначение:** Записать данные в файл.

**Конфигурация:**
```json
{
  "type": "fileWrite",
  "config": {
    "label": "Сохраняем результат",
    "file_path": "/Users/user/project/output.md",
    "input_var": "llm_result"
  }
}
```

**Выполнение:**
1. Берёт данные из `RunContext.state[input_var]`
2. Вызывает Skill `fs_write_file`
3. Записывает в указанный файл

---

### 4. `userInput` — Запрос данных у пользователя

**Назначение:** Приостановить выполнение и запросить ввод.

**Конфигурация:**
```json
{
  "type": "userInput",
  "config": {
    "label": "Получить данные",
    "output_var": "user_answer",
    "ui_title": "Введите название проекта",
    "ui_message": "Это будет использовано для генерации кода",
    "ui_blueprint_id": null
  }
}
```

**Поля:**
- `ui_blueprint_id` — если `null`, показывается простой TextField
- `ui_blueprint_id` — если UUID, показывается Dynamic UI форма

**Выполнение:**
1. Граф переходит в статус `suspended`
2. Сохраняет состояние в БД
3. UI показывает форму
4. Пользователь вводит данные и нажимает Submit
5. Данные записываются в `RunContext.state[output_var]`
6. Граф возобновляется с того же узла

---

### 5. `manualReview` — Ожидание подтверждения

**Назначение:** Показать данные пользователю и дождаться подтверждения.

**Конфигурация:**
```json
{
  "type": "manualReview",
  "config": {
    "label": "Проверить документ",
    "ui_title": "Требуется одобрение",
    "ui_message": "Проверьте сгенерированный код",
    "ui_blueprint_id": null
  }
}
```

**Выполнение:**
1. Граф приостанавливается
2. UI показывает данные и кнопки "Approve" / "Reject"
3. Результат сохраняется в `user_approved` (true/false)
4. Граф продолжается

---

### 6. `fileUpload` — Загрузка файла

**Назначение:** Дождаться загрузки файла от пользователя.

**Конфигурация:**
```json
{
  "type": "fileUpload",
  "config": {
    "label": "Загрузить PDF",
    "output_var": "uploaded_file_path",
    "ui_title": "Загрузите файл",
    "ui_message": "Выберите PDF для обработки"
  }
}
```

**Выполнение:**
1. Граф приостанавливается
2. UI показывает file picker
3. Файл сохраняется на диск
4. Путь записывается в `RunContext.state[output_var]`

---

### 7. `coCreationChat` — Совместное создание

**Назначение:** Интерактивный чат с AI для создания документа.

**Конфигурация:**
```json
{
  "type": "coCreationChat",
  "config": {
    "label": "Создать README",
    "output_var": "readme_content",
    "system_prompt_id": "uuid-системного-промпта",
    "initial_prompt_id": "uuid-начального-промпта",
    "validation_prompt_id": "uuid-валидации"
  }
}
```

**Выполнение:**
1. Компилирует все промпты (подставляет переменные!)
2. Граф приостанавливается
3. UI показывает чат интерфейс
4. Пользователь общается с AI
5. Финальный результат сохраняется в `output_var`

---

### 8. `runInstruction` — Вызов Instruction графа

**Назначение:** Выполнить InstructionGraph как подграф.

**Конфигурация:**
```json
{
  "type": "runInstruction",
  "config": {
    "label": "Анализ кода",
    "instruction_blueprint_id": "uuid-инструкции",
    "instruction_name": "Code Analyzer",
    "input_mapping": {
      "source_code": "source_code"
    },
    "output_mapping": {
      "analysis_result": "llm_result"
    }
  }
}
```

**Маппинг:**
- `input_mapping` — какие переменные передать в Instruction
- `output_mapping` — какие переменные забрать из Instruction

**Выполнение:**
1. Загружает InstructionGraph по ID
2. Создаёт новый RunContext (клон текущего)
3. Копирует переменные согласно `input_mapping`
4. Запускает InstructionRunner
5. Копирует результаты согласно `output_mapping`

---

### 9. `gitCommit` — Коммит в Git

**Назначение:** Создать Git коммит.

**Конфигурация:**
```json
{
  "type": "gitCommit",
  "config": {
    "label": "Коммит изменений",
    "message": "Generated by AI",
    "files": ["*.dart"]
  }
}
```

---

### 10. `subGraph` — Вложенный Workflow

**Назначение:** Выполнить другой WorkflowGraph как подграф.

**Конфигурация:**
```json
{
  "type": "subGraph",
  "config": {
    "label": "Запустить подпроцесс",
    "workflow_blueprint_id": "uuid-workflow"
  }
}
```

---

## Типы рёбер

### 1. `onSuccess` — Переход при успехе

Выполняется если узел завершился без ошибок.

```json
{
  "id": "edge-001",
  "sourceId": "node-001",
  "targetId": "node-002",
  "branchName": "main",
  "type": "onSuccess"
}
```

---

### 2. `onError` — Переход при ошибке

Выполняется если узел выбросил исключение.

```json
{
  "id": "edge-002",
  "sourceId": "node-001",
  "targetId": "node-error",
  "branchName": "error-handler",
  "type": "onError"
}
```

**Пример:**
```
[fileRead] ─onSuccess→ [llmAction]
     │
     └─onError→ [Показать ошибку]
```

---

### 3. `conditional` — Условный переход

Выполняется если условие истинно.

```json
{
  "id": "edge-003",
  "sourceId": "node-001",
  "targetId": "node-002",
  "branchName": "main",
  "type": "conditional",
  "conditionExpression": "user_approved == true"
}
```

**Примечание:** Условия пока не реализованы полностью. Планируется поддержка выражений.

---

## Параллельное выполнение

### Концепция веток (branches)

Один узел может иметь **несколько исходящих рёбер** с разными `branchName`. Это запускает параллельное выполнение.

### Пример

```json
{
  "nodes": [
    {"id": "start", "type": "fileRead"},
    {"id": "analyze-1", "type": "llmAction"},
    {"id": "analyze-2", "type": "llmAction"},
    {"id": "merge", "type": "llmAction"}
  ],
  "edges": [
    {
      "sourceId": "start",
      "targetId": "analyze-1",
      "branchName": "branch-1"
    },
    {
      "sourceId": "start",
      "targetId": "analyze-2",
      "branchName": "branch-2"
    },
    {
      "sourceId": "analyze-1",
      "targetId": "merge",
      "branchName": "branch-1"
    },
    {
      "sourceId": "analyze-2",
      "targetId": "merge",
      "branchName": "branch-2"
    }
  ]
}
```

**Выполнение:**
```
        ┌─→ [analyze-1] ─┐
[start] ┤                ├─→ [merge]
        └─→ [analyze-2] ─┘
```

### Синхронизация

Узел `merge` **ждёт завершения всех входящих веток** перед выполнением.

**Механизм:**
- WorkflowRunner отслеживает посещённые рёбра в `_visitedEdges`
- Перед выполнением узла проверяет: все ли входящие рёбра посещены?
- Если нет — узел пропускается (ждёт)
- Если да — узел выполняется

---

## Интерактивные узлы

### Dynamic UI Blueprint

Узлы `userInput`, `manualReview`, `fileUpload`, `coCreationChat` могут иметь **кастомную UI форму**.

### Привязка формы

```json
{
  "type": "userInput",
  "config": {
    "ui_blueprint_id": "uuid-формы",
    "anchor_binding_mapping": {
      "name_input.value": "project_name",
      "type_select.value": "project_type"
    },
    "anchor_action_mapping": {
      "submit_btn.onPressed": "submit"
    }
  }
}
```

### Механизм

1. **Граф приостанавливается** (`suspended`)
2. **Сохраняется состояние:**
   ```json
   {
     "user_context": {...},
     "engine_state": {
       "ui_action": "dynamic_ui",
       "target_var": "project_name",
       "ui_config": {
         "ui_blueprint_id": "uuid",
         "anchor_binding_mapping": {...}
       }
     }
   }
   ```
3. **UI загружает форму** из `ui_blueprint_id`
4. **Пользователь заполняет** и нажимает Submit
5. **Данные записываются** в `RunContext.state`
6. **Граф возобновляется** через `engine.resumeWithInput()`

---

## Приостановка и возобновление

### Зачем нужно

- Запросить данные у пользователя
- Дождаться подтверждения
- Загрузить файл
- Интерактивный чат с AI

### Механизм

#### 1. Приостановка

```dart
// WorkflowRunner
await _repo.suspendRun(
  runId: runId,
  contextJson: jsonEncode({
    'user_context': context.toJson(),
    'engine_state': {
      'visited_edges': _visitedEdges.toList(),
      'ui_action': 'user_input',
      'target_var': 'user_answer',
      'ui_config': {...}
    }
  }),
  nodeId: node.id,
  logs: _logs,
);
```

#### 2. Сохранение в БД

```sql
UPDATE runs SET
  status = 'suspended',
  context_json = '...',
  node_id = 'node-001',
  logs_json = '[...]'
WHERE run_id = 'uuid';
```

#### 3. Возобновление

```dart
// Клиент
await engine.resumeWithInput(UserInputResponse(
  runId: runId,
  data: {'user_answer': 'My Project'},
));

// WorkflowRunner
final savedRun = await _repo.getRun(runId);
final contextJson = savedRun['context_json'];
final parsedState = jsonDecode(contextJson);

// Восстанавливаем контекст
final context = RunContext.fromJson(
  parsedState['user_context'],
  _log,
);

// Добавляем новые данные
context.state.addAll(injectedVariables);

// Продолжаем с сохранённого узла
await _processNode(startNode, 0, context);
```

---

## Примеры использования

### Пример 1: Простой анализ кода

```json
{
  "name": "Code Analyzer",
  "nodes": [
    {
      "id": "read-file",
      "type": "fileRead",
      "config": {
        "file_path": "/path/to/main.dart",
        "output_var": "source_code"
      }
    },
    {
      "id": "analyze",
      "type": "llmAction",
      "config": {
        "prompt_blueprint_id": "analyze-prompt-uuid",
        "output_var": "analysis"
      }
    },
    {
      "id": "write-report",
      "type": "fileWrite",
      "config": {
        "file_path": "/path/to/report.md",
        "input_var": "analysis"
      }
    }
  ],
  "edges": [
    {"sourceId": "read-file", "targetId": "analyze"},
    {"sourceId": "analyze", "targetId": "write-report"}
  ]
}
```

---

### Пример 2: Интерактивный мастер

```json
{
  "name": "Project Setup Wizard",
  "nodes": [
    {
      "id": "ask-name",
      "type": "userInput",
      "config": {
        "ui_title": "Название проекта",
        "output_var": "project_name"
      }
    },
    {
      "id": "ask-type",
      "type": "userInput",
      "config": {
        "ui_title": "Тип проекта",
        "ui_blueprint_id": "dropdown-form-uuid",
        "output_var": "project_type"
      }
    },
    {
      "id": "generate",
      "type": "llmAction",
      "config": {
        "prompt_blueprint_id": "generate-structure-uuid",
        "output_var": "project_structure"
      }
    },
    {
      "id": "confirm",
      "type": "manualReview",
      "config": {
        "ui_title": "Подтвердите структуру"
      }
    },
    {
      "id": "create-files",
      "type": "runInstruction",
      "config": {
        "instruction_blueprint_id": "file-creator-uuid"
      }
    }
  ],
  "edges": [
    {"sourceId": "ask-name", "targetId": "ask-type"},
    {"sourceId": "ask-type", "targetId": "generate"},
    {"sourceId": "generate", "targetId": "confirm"},
    {"sourceId": "confirm", "targetId": "create-files"}
  ]
}
```

---

### Пример 3: Параллельная обработка

```json
{
  "name": "Multi-File Analyzer",
  "nodes": [
    {"id": "start", "type": "fileRead"},
    {"id": "analyze-security", "type": "runInstruction"},
    {"id": "analyze-performance", "type": "runInstruction"},
    {"id": "analyze-style", "type": "runInstruction"},
    {"id": "merge-reports", "type": "llmAction"},
    {"id": "write-final", "type": "fileWrite"}
  ],
  "edges": [
    {"sourceId": "start", "targetId": "analyze-security", "branchName": "security"},
    {"sourceId": "start", "targetId": "analyze-performance", "branchName": "performance"},
    {"sourceId": "start", "targetId": "analyze-style", "branchName": "style"},
    {"sourceId": "analyze-security", "targetId": "merge-reports", "branchName": "security"},
    {"sourceId": "analyze-performance", "targetId": "merge-reports", "branchName": "performance"},
    {"sourceId": "analyze-style", "targetId": "merge-reports", "branchName": "style"},
    {"sourceId": "merge-reports", "targetId": "write-final"}
  ]
}
```

**Выполнение:**
```
                ┌─→ [Security] ─┐
[Start] ─┬─→ [Performance] ─┼─→ [Merge] → [Write]
         └─→ [Style] ───────┘
```

---

## Ограничения и рекомендации

### Ограничения

1. **Нет циклов** — WorkflowGraph должен быть DAG (направленный ациклический граф)
2. **Условия не реализованы** — `conditional` рёбра пока не работают
3. **Нет timeout** — узел может выполняться бесконечно
4. **Нет retry** — если узел упал, граф останавливается

### Рекомендации

1. **Используйте InstructionGraph для сложной логики** — там можно циклы и ветвления
2. **Разбивайте большие Workflow** — используйте `subGraph` и `runInstruction`
3. **Добавляйте `onError` рёбра** — для обработки ошибок
4. **Логируйте промежуточные результаты** — используйте `comment` в узлах
5. **Тестируйте на маленьких данных** — перед запуском на больших файлах

---

## Следующие шаги

- [InstructionGraph](./INSTRUCTION_GRAPH.md) — переиспользуемые инструкции
- [PromptGraph](./PROMPT_GRAPH.md) — шаблоны промптов
- [Архитектура движка](./ARCHITECTURE.md) — как это работает внутри
