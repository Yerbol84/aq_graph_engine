# PromptGraph — Шаблон промпта для LLM

## 📋 Содержание

1. [Назначение](#назначение)
2. [Структура графа](#структура-графа)
3. [Типы узлов](#типы-узлов)
4. [Переменные и подстановка](#переменные-и-подстановка)
5. [Компиляция промпта](#компиляция-промпта)
6. [Использование в графах](#использование-в-графах)
7. [Примеры](#примеры)

---

## Назначение

**PromptGraph** — это **шаблон промпта для LLM** с поддержкой переменных. Промпты тоже графы!

### Зачем нужен

1. **Переиспользование** — один промпт для разных Workflow
2. **Версионирование** — изменили промпт → новая версия
3. **Композиция** — промпт из нескольких блоков
4. **Подстановка переменных** — `{{source_code}}` заменяется значением
5. **Визуализация** — видно структуру промпта

### Альтернатива

Можно хранить промпты как строки в коде:
```dart
final prompt = "Проанализируй код: $sourceCode";
```

**Но PromptGraph даёт:**
- Версионирование через VersionedStorable
- Визуальное редактирование
- Экспорт/импорт через JSON
- Переиспользование в разных проектах

---

## Структура графа

### JSON формат

```json
{
  "id": "uuid",
  "tenantId": "tenant-id",
  "ownerId": "project-id",
  "name": "Code Analysis Prompt",
  "nodes": [
    {
      "id": "pnod-001",
      "type": "textBlock",
      "data": {
        "content": "Ты опытный разработчик Dart/Flutter.\n\nПроанализируй следующий код:\n\n{{source_code}}\n\nНайди проблемы и предложи улучшения."
      }
    }
  ],
  "edges": []
}
```

### Dart модель

```dart
class PromptGraph extends $Graph<PromptNode, PromptEdge>
    implements VersionedStorable {
  final String id;
  final String tenantId;
  final String ownerId; // projectId
  final String name;
  final Map<String, PromptNode> nodes;
  final Map<String, PromptEdge> edges;
}
```

---

## Типы узлов

### 1. `textBlock` — Блок текста

**Назначение:** Основной контент промпта с переменными.

**Конфигурация:**
```json
{
  "id": "pnod-001",
  "type": "textBlock",
  "data": {
    "content": "Ты опытный разработчик.\n\nПроанализируй код:\n\n{{source_code}}\n\nОтвет дай на русском языке."
  }
}
```

**Переменные:**
- Формат: `{{имя_переменной}}`
- Берутся из `RunContext.state`
- Если переменная не найдена → `[MISSING VARIABLE: имя]`

**Пример:**
```
Контекст: {source_code: "function main() {}"}
Шаблон: "Проанализируй: {{source_code}}"
Результат: "Проанализируй: function main() {}"
```

---

### 2. `variable` — Объявление переменной

**Назначение:** Документация, какие переменные нужны.

**Конфигурация:**
```json
{
  "id": "pnod-002",
  "type": "variable",
  "data": {
    "name": "source_code",
    "description": "Исходный код для анализа"
  }
}
```

**Примечание:** Узел не влияет на компиляцию, только документирует.

---

### 3. `fileContext` — Контекст из файла

**Назначение:** Включить содержимое файла в промпт.

**Конфигурация:**
```json
{
  "id": "pnod-003",
  "type": "fileContext",
  "data": {
    "file_path": "{{current_file_path}}",
    "description": "Содержимое текущего файла"
  }
}
```

**Примечание:** В текущей реализации не используется. Планируется доработка.

---

## Переменные и подстановка

### Синтаксис

```
{{имя_переменной}}
```

### Источник переменных

Переменные берутся из `RunContext.state`:

```dart
context.setVar('source_code', 'function main() {}');
context.setVar('language', 'Dart');
```

### Подстановка

```dart
final regex = RegExp(r'\{\{(.*?)\}\}');
compiledPrompt = compiledPrompt.replaceAllMapped(regex, (match) {
  final varName = match.group(1)?.trim();
  final value = context.getVar(varName ?? '');
  return value?.toString() ?? "[MISSING VARIABLE: $varName]";
});
```

### Примеры

**Простая переменная:**
```
Шаблон: "Язык: {{language}}"
Контекст: {language: "Dart"}
Результат: "Язык: Dart"
```

**Вложенная переменная:**
```
Шаблон: "Файл: {{project.name}}/{{file.name}}"
Контекст: {project: {name: "MyApp"}, file: {name: "main.dart"}}
Результат: "Файл: MyApp/main.dart"
```

**Отсутствующая переменная:**
```
Шаблон: "Код: {{source_code}}"
Контекст: {}
Результат: "Код: [MISSING VARIABLE: source_code]"
```

---

## Компиляция промпта

### PromptRunner

```dart
class PromptRunner {
  final IGraphRepository graphRepo;
  final RunContext context;

  Future<String> run(String promptId) async {
    // 1. Загрузить граф
    final promptBlueprint = await graphRepo.loadGraph(promptId);
    if (promptBlueprint == null || promptBlueprint is! PromptGraph) {
      return '';
    }

    // 2. Собрать текст из узлов
    String compiledPrompt = "";
    for (final pNode in promptBlueprint.nodes.values) {
      if (pNode.type == PromptNodeType.textBlock) {
        compiledPrompt += (pNode.data['content'] ?? "") + "\n\n";
      }
    }

    // 3. Подставить переменные
    final regex = RegExp(r'\{\{(.*?)\}\}');
    compiledPrompt = compiledPrompt.replaceAllMapped(regex, (match) {
      final varName = match.group(1)?.trim();
      final value = context.getVar(varName ?? '');
      return value?.toString() ?? "[MISSING VARIABLE: $varName]";
    });

    return compiledPrompt.trim();
  }
}
```

### Порядок узлов

Узлы обрабатываются **в порядке добавления** (порядок в `nodes.values`).

Если нужен конкретный порядок — используйте рёбра:

```json
{
  "nodes": [
    {"id": "intro", "type": "textBlock"},
    {"id": "task", "type": "textBlock"},
    {"id": "format", "type": "textBlock"}
  ],
  "edges": [
    {"sourceId": "intro", "targetId": "task"},
    {"sourceId": "task", "targetId": "format"}
  ]
}
```

**Примечание:** В текущей реализации рёбра не влияют на порядок. Планируется доработка.

---

## Использование в графах

### В WorkflowGraph

Узел `llmAction`:
```json
{
  "type": "llmAction",
  "config": {
    "label": "Анализ кода",
    "prompt_blueprint_id": "uuid-промпта",
    "output_var": "analysis"
  }
}
```

**Выполнение:**
1. WorkflowRunner загружает PromptGraph
2. Создаёт PromptRunner
3. Компилирует промпт: `await promptRunner.run(promptId)`
4. Вызывает LLM Skill с скомпилированным промптом

---

### В InstructionGraph

Узел `systemAction` с `tool_id: "llm_ask"`:
```json
{
  "type": "systemAction",
  "payload": {
    "tool_id": "llm_ask",
    "output_var": "result",
    "prompt_blueprint_id": "uuid-промпта"
  }
}
```

**Выполнение:**
1. InstructionRunner проверяет `tool_id == "llm_ask"`
2. Создаёт PromptRunner
3. Компилирует промпт
4. Передаёт в `args['prompt']`

---

### В coCreationChat

Узел `coCreationChat` в WorkflowGraph:
```json
{
  "type": "coCreationChat",
  "config": {
    "system_prompt_id": "uuid-системного",
    "initial_prompt_id": "uuid-начального",
    "validation_prompt_id": "uuid-валидации"
  }
}
```

**Выполнение:**
1. WorkflowRunner компилирует **все три промпта**
2. Подставляет переменные из текущего контекста
3. Передаёт в UI для чата

---

## Примеры

### Пример 1: Простой промпт

```json
{
  "name": "Code Analyzer Prompt",
  "nodes": [
    {
      "id": "pnod-001",
      "type": "textBlock",
      "data": {
        "content": "Ты опытный разработчик Dart/Flutter.\n\nПроанализируй следующий код и найди проблемы:\n\n{{source_code}}\n\nОтвет дай на русском языке. Будь конкретен."
      }
    }
  ],
  "edges": []
}
```

**Использование:**
```dart
context.setVar('source_code', 'function main() { print("Hello"); }');
final prompt = await promptRunner.run(promptId);
// Результат:
// "Ты опытный разработчик Dart/Flutter.
//
// Проанализируй следующий код и найди проблемы:
//
// function main() { print("Hello"); }
//
// Ответ дай на русском языке. Будь конкретен."
```

---

### Пример 2: Многоблочный промпт

```json
{
  "name": "Complex Analysis Prompt",
  "nodes": [
    {
      "id": "intro",
      "type": "textBlock",
      "data": {
        "content": "Ты опытный разработчик {{language}}."
      }
    },
    {
      "id": "task",
      "type": "textBlock",
      "data": {
        "content": "Проанализируй код:\n\n{{source_code}}"
      }
    },
    {
      "id": "format",
      "type": "textBlock",
      "data": {
        "content": "Формат ответа:\n1. Проблемы\n2. Рекомендации\n3. Оценка качества (1-10)"
      }
    }
  ],
  "edges": []
}
```

**Результат:**
```
Ты опытный разработчик Dart.

Проанализируй код:

function main() {}

Формат ответа:
1. Проблемы
2. Рекомендации
3. Оценка качества (1-10)
```

---

### Пример 3: С документацией переменных

```json
{
  "name": "Documented Prompt",
  "nodes": [
    {
      "id": "var-1",
      "type": "variable",
      "data": {
        "name": "source_code",
        "description": "Исходный код для анализа"
      }
    },
    {
      "id": "var-2",
      "type": "variable",
      "data": {
        "name": "language",
        "description": "Язык программирования (Dart, Python, etc.)"
      }
    },
    {
      "id": "text",
      "type": "textBlock",
      "data": {
        "content": "Проанализируй {{language}} код:\n\n{{source_code}}"
      }
    }
  ],
  "edges": []
}
```

**Примечание:** Узлы `variable` не влияют на компиляцию, только документируют.

---

### Пример 4: Системный промпт для Co-Creation

```json
{
  "name": "README Generator System Prompt",
  "nodes": [
    {
      "id": "system",
      "type": "textBlock",
      "data": {
        "content": "Ты помощник для создания README файлов.\n\nПроект: {{project_name}}\nТип: {{project_type}}\n\nТвоя задача:\n1. Задавать уточняющие вопросы\n2. Генерировать разделы README\n3. Учитывать feedback пользователя\n\nПиши на русском языке. Будь кратким и конкретным."
      }
    }
  ],
  "edges": []
}
```

**Использование в coCreationChat:**
```json
{
  "type": "coCreationChat",
  "config": {
    "system_prompt_id": "uuid-этого-промпта",
    "initial_prompt_id": "uuid-начального",
    "output_var": "readme_content"
  }
}
```

---

## Версионирование промптов

### Зачем

Промпты часто меняются:
- Улучшение формулировок
- Добавление примеров
- Изменение формата ответа

**Версионирование** позволяет:
- Откатиться к предыдущей версии
- Сравнить разные версии
- A/B тестирование промптов

### Как

PromptGraph реализует `VersionedStorable`:

```dart
// Создать версию
await repo.publishDraft(nodeId, increment: IncrementType.patch);

// Загрузить версию
final prompt = await repo.getVersion(nodeId);

// Список версий
final versions = await repo.listVersions(promptId);
```

### Пример workflow

```
v1.0.0: "Проанализируй код"
  ↓ (улучшили формулировку)
v1.1.0: "Проанализируй код и найди проблемы"
  ↓ (добавили формат ответа)
v1.2.0: "Проанализируй код и найди проблемы. Формат: 1. Проблемы 2. Рекомендации"
```

Если v1.2.0 работает хуже → откат к v1.1.0.

---

## Ограничения и рекомендации

### Ограничения

1. **Нет условной логики** — нельзя `if (language == "Dart") { ... }`
2. **Нет циклов** — нельзя повторить блок N раз
3. **Порядок узлов не гарантирован** — рёбра пока не влияют
4. **Нет вложенных промптов** — нельзя включить один промпт в другой

### Рекомендации

1. **Используйте для статических промптов** — без сложной логики
2. **Документируйте переменные** — используйте узлы `variable`
3. **Версионируйте изменения** — каждое улучшение = новая версия
4. **Тестируйте на реальных данных** — перед использованием в Workflow
5. **Держите промпты короткими** — длинные промпты = дорогие запросы
6. **Используйте понятные имена переменных** — `source_code`, не `sc`

---

## Планы развития

### Планируется добавить

1. **Условные блоки:**
   ```json
   {
     "type": "conditionalBlock",
     "data": {
       "condition": "language == 'Dart'",
       "content": "Используй Dart-специфичные рекомендации"
     }
   }
   ```

2. **Циклы:**
   ```json
   {
     "type": "loopBlock",
     "data": {
       "items": "{{files}}",
       "template": "Файл: {{item.name}}\n{{item.content}}\n\n"
     }
   }
   ```

3. **Вложенные промпты:**
   ```json
   {
     "type": "includePrompt",
     "data": {
       "prompt_id": "uuid-другого-промпта"
     }
   }
   ```

4. **Функции:**
   ```json
   {
     "type": "textBlock",
     "data": {
       "content": "Длина кода: {{length(source_code)}} символов"
     }
   }
   ```

---

## Следующие шаги

- [WorkflowGraph](./WORKFLOW_GRAPH.md) — основные сценарии
- [InstructionGraph](./INSTRUCTION_GRAPH.md) — переиспользуемые инструкции
- [Архитектура движка](./ARCHITECTURE.md) — как это работает внутри
