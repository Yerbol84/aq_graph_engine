# AQ Graph Engine — Обзор

## 📋 Содержание

1. [Введение](#введение)
2. [Философия "Граф как Закон"](#философия-граф-как-закон)
3. [Архитектура движка](#архитектура-движка)
4. [Три типа графов](#три-типа-графов)
5. [Жизненный цикл выполнения](#жизненный-цикл-выполнения)
6. [Использование](#использование)

---

## Введение

**AQ Graph Engine** — это pure Dart runtime для выполнения графов трёх типов:
- **WorkflowGraph** — основной сценарий выполнения (pipeline агента)
- **InstructionGraph** — переиспользуемая инструкция с контрактом
- **PromptGraph** — шаблон промпта для LLM

Движок может работать:
- **Локально** (desktop приложение) — через `LocalEngineTransport`
- **На сервере** (web service) — через `HttpEngineTransport` (планируется)
- **В воркере** (background job) — через `GraphWorker`

---

## Философия "Граф как Закон"

### Ключевая идея

В AQ Studio **любая активность — это выполнение графа**:
- Написание кода → Workflow граф
- Создание спецификации → Workflow граф
- Генерация промпта → Prompt граф
- Анализ кода → Instruction граф

### Преимущества подхода

1. **Унификация** — один механизм для всех процессов
2. **Версионирование** — каждый граф автоматически версионируется
3. **Визуализация** — логика видна визуально
4. **Переносимость** — экспорт/импорт через JSON
5. **Композиция** — графы вызывают другие графы
6. **Приостановка** — можно остановить и продолжить позже

---

## Архитектура движка

### Компоненты

```
┌─────────────────────────────────────────────────────────────┐
│                        GraphEngine                          │
│  (единая точка входа для выполнения любых графов)           │
└─────────────────────────────────────────────────────────────┘
                              │
                              ├─── ToolRegistry (реестр Skills)
                              ├─── IRunRepository (хранилище запусков)
                              ├─── IGraphRepository (хранилище графов)
                              └─── IEngineTransport (транспорт)
                                          │
                    ┌─────────────────────┼─────────────────────┐
                    │                     │                     │
          LocalEngineTransport   HttpEngineTransport   CustomTransport
          (локальное выполнение)  (удалённый сервер)   (ваша реализация)
                    │
        ┌───────────┼───────────┐
        │           │           │
  WorkflowRunner  InstructionRunner  PromptRunner
  (выполняет      (выполняет         (компилирует
   Workflow)       Instruction)       Prompt)
```

### Слои абстракции

1. **GraphEngine** — фасад, скрывает детали
2. **IEngineTransport** — абстракция транспорта (локальный/удалённый)
3. **Runners** — исполнители конкретных типов графов
4. **Repositories** — абстракция хранилища данных

---

## Три типа графов

### 1. WorkflowGraph — Основной сценарий

**Назначение:** Автоматизация процесса от начала до конца.

**Узлы:**
- `llmAction` — запрос к LLM
- `fileRead` / `fileWrite` — работа с файлами
- `userInput` — запрос данных у пользователя
- `manualReview` — ожидание подтверждения
- `fileUpload` — загрузка файла
- `coCreationChat` — совместное создание с AI
- `runInstruction` — вызов Instruction графа
- `gitCommit` — коммит в Git

**Рёбра:**
- `onSuccess` — переход при успехе
- `onError` — переход при ошибке
- `conditional` — условный переход

**Особенности:**
- Поддержка параллельных веток (branches)
- Приостановка для UI ввода (`suspended`)
- Сохранение состояния после каждого шага

**Пример:**
```
[fileRead] → [llmAction] → [userInput] → [fileWrite] → [gitCommit]
```

---

### 2. InstructionGraph — Переиспользуемая инструкция

**Назначение:** Атомарная бизнес-логика с контрактом входов/выходов.

**Узлы:**
- `systemAction` — вызов Skill (LLM, файлы, векторный поиск)
- `validationCheck` — проверка условия (ветвление)
- `stepDescription` — описательный шаг
- `userInputRequest` — запрос ввода

**Контракт:**
```json
{
  "inputs": [
    {"name": "source_code", "type": "string", "required": true}
  ],
  "outputs": [
    {"name": "analysis", "type": "string"}
  ]
}
```

**Особенности:**
- Валидация контракта через JSON Schema
- Может содержать циклы (защита: maxSteps = 20)
- Можно вызывать из Workflow как функцию

**Пример:**
```
Instruction "Code Analyzer":
  Вход: source_code
  [systemAction: llm_ask] → [validationCheck: результат не пустой?]
    ├─ true → [Возврат analysis]
    └─ false → [Ошибка]
```

---

### 3. PromptGraph — Шаблон промпта

**Назначение:** Конструирование промптов для LLM с переменными.

**Узлы:**
- `textBlock` — блок текста с `{{переменными}}`
- `variable` — объявление переменной
- `fileContext` — контекст из файла

**Компиляция:**
```
Граф: [textBlock: "Проанализируй: {{source_code}}"]
Контекст: {source_code: "function main() {}"}
Результат: "Проанализируй: function main() {}"
```

**Особенности:**
- Промпты версионируются как графы
- Можно переиспользовать в разных Workflow
- Подстановка переменных из RunContext

---

## Жизненный цикл выполнения

### 1. Создание запроса

```dart
final request = GraphRunRequest(
  runId: uuid,
  blueprintId: workflowId,
  projectId: projectId,
  projectPath: '/path/to/project',
);
```

### 2. Запуск через движок

```dart
final engine = GraphEngine(
  tools: toolRegistry,
  runRepo: runRepository,
  graphRepo: graphRepository,
);

Stream<GraphRunEvent> events = engine.run(request);
```

### 3. Обработка событий

```dart
await for (final event in events) {
  switch (event.type) {
    case GraphRunEventType.log:
      print(event.message);
    case GraphRunEventType.statusChanged:
      print('Status: ${event.newStatus}');
    case GraphRunEventType.userInputRequired:
      // Показать UI форму
      final input = await showDialog(...);
      await engine.resumeWithInput(UserInputResponse(
        runId: event.runId,
        data: input,
      ));
    case GraphRunEventType.completed:
      print('Done!');
    case GraphRunEventType.error:
      print('Error: ${event.errorMessage}');
  }
}
```

### 4. Статусы выполнения

```
pending → running → suspended → running → completed
                 ↘ failed
```

- `pending` — в очереди
- `running` — выполняется
- `suspended` — ждёт ввода пользователя
- `completed` — успешно завершён
- `failed` — ошибка

---

## Использование

### Локальное выполнение (desktop)

```dart
import 'package:aq_graph_engine/aq_graph_engine.dart';

final engine = GraphEngine(
  tools: buildToolRegistry(),
  runRepo: LocalRunRepository(),
  graphRepo: LocalGraphRepository(),
  // transport не указан → используется LocalEngineTransport
);

final events = engine.run(request);
```

### Удалённое выполнение (web service)

```dart
final engine = GraphEngine(
  tools: buildToolRegistry(),
  runRepo: RemoteRunRepository(dataServiceUrl),
  graphRepo: RemoteGraphRepository(dataServiceUrl),
  transport: HttpEngineTransport(workerServiceUrl),
);

final events = engine.run(request);
```

### Фоновое выполнение (worker)

```dart
// Клиент отправляет задание в очередь
await queue.enqueue(WorkerJobImpl(
  jobId: uuid,
  tool: 'run_graph',
  payload: request.toJson(),
));

// Воркер выполняет
final worker = GraphWorker(config: workerConfig);
await worker.start();
```

---

## Следующие шаги

Читайте подробную документацию по каждому типу графа:
- [WorkflowGraph](./WORKFLOW_GRAPH.md)
- [InstructionGraph](./INSTRUCTION_GRAPH.md)
- [PromptGraph](./PROMPT_GRAPH.md)

Документация по разработке:
- [Архитектура движка](./ARCHITECTURE.md)
- [Создание кастомных узлов](./CUSTOM_NODES.md)
- [Разработка воркеров](./WORKERS.md)
