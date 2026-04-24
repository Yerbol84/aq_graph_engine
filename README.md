# AQ Graph Engine

**Pure Dart runtime для выполнения графов трёх типов: Workflow, Instruction и Prompt.**

Может работать локально (desktop) или на сервере (web service/worker).

---

## 🎯 Философия "Граф как Закон"

В AQ Studio **любая активность — это выполнение графа**:
- Написание кода → Workflow граф
- Анализ кода → Instruction граф
- Генерация промпта → Prompt граф

**Преимущества:**
- ✅ Унификация — один механизм для всех процессов
- ✅ Версионирование — каждый граф автоматически версионируется
- ✅ Визуализация — логика видна визуально
- ✅ Переносимость — экспорт/импорт через JSON
- ✅ Композиция — графы вызывают другие графы

---

## 📊 Три типа графов

### 1. WorkflowGraph — Основной сценарий агента

**Главный pipeline** — полный сценарий работы от начала до конца.

**Возможности:**
- Параллельное выполнение (branches)
- Приостановка для UI ввода
- Интерактивные узлы (userInput, manualReview, fileUpload)
- Композиция (вызов InstructionGraph)

**Пример:**
```
[fileRead] → [llmAction] → [userInput] → [fileWrite] → [gitCommit]
```

---

### 2. InstructionGraph — Переиспользуемая инструкция

**Атомарная бизнес-логика** с контрактом входов/выходов.

**Возможности:**
- Контракт (JSON Schema валидация)
- Циклы разрешены (с защитой maxSteps = 20)
- Ветвления через validationCheck
- Вызов из Workflow

**Пример:**
```
Instruction "Code Analyzer":
  Вход: source_code
  [systemAction: llm_ask] → [validationCheck]
    ├─ true → [Возврат analysis]
    └─ false → [Ошибка]
```

---

### 3. PromptGraph — Шаблон промпта

**Конструктор промптов** с переменными `{{var}}`.

**Возможности:**
- Подстановка переменных из контекста
- Версионирование промптов
- Переиспользование в разных Workflow

**Пример:**
```
"Ты опытный разработчик.\n\nПроанализируй код:\n\n{{source_code}}"
```

---

## 🚀 Быстрый старт

### Установка

```yaml
dependencies:
  aq_graph_engine:
    path: ../aq_graph_engine
```

### Использование

```dart
import 'package:aq_graph_engine/aq_graph_engine.dart';

// Создать движок
final engine = GraphEngine(
  tools: buildToolRegistry(),
  runRepo: LocalRunRepository(),
  graphRepo: LocalGraphRepository(),
);

// Запустить граф
final request = GraphRunRequest(
  runId: uuid,
  blueprintId: workflowId,
  projectId: projectId,
  projectPath: '/path/to/project',
);

Stream<GraphRunEvent> events = engine.run(request);

// Обработать события
await for (final event in events) {
  switch (event.type) {
    case GraphRunEventType.log:
      print(event.message);
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

---

## 📚 Документация

### Обзор
- [OVERVIEW.md](./docs/OVERVIEW.md) — общий обзор системы
- [SUMMARY.md](./docs/SUMMARY.md) — краткое резюме по типам графов

### Типы графов
- [WORKFLOW_GRAPH.md](./docs/WORKFLOW_GRAPH.md) — WorkflowGraph в деталях
- [INSTRUCTION_GRAPH.md](./docs/INSTRUCTION_GRAPH.md) — InstructionGraph в деталях
- [PROMPT_GRAPH.md](./docs/PROMPT_GRAPH.md) — PromptGraph в деталях

### Разработка
- [ARCHITECTURE.md](./docs/ARCHITECTURE.md) — архитектура движка (TODO)
- [WORKERS.md](./docs/WORKERS.md) — разработка воркеров (TODO)

---

## 🏗️ Архитектура

```
GraphEngine (фасад)
  │
  ├─── ToolRegistry (реестр Skills)
  ├─── IRunRepository (хранилище запусков)
  ├─── IGraphRepository (хранилище графов)
  └─── IEngineTransport (транспорт)
          │
          ├─── LocalEngineTransport (локальное выполнение)
          ├─── HttpEngineTransport (удалённый сервер)
          └─── CustomTransport (ваша реализация)
                  │
        ┌─────────┼─────────┐
        │         │         │
  WorkflowRunner  InstructionRunner  PromptRunner
```

---

## 🔧 Разработка

### Запуск тестов

```bash
dart test
```

### Линтинг

```bash
dart analyze
```

---

## 📝 Лицензия

Proprietary — только для использования в AQ Studio.

---

## 🤝 Контрибьюция

Пакет находится в активной разработке. Для предложений и багов создавайте issues в основном репозитории.

---

## 📞 Поддержка

Для вопросов по использованию читайте документацию в `docs/`.
