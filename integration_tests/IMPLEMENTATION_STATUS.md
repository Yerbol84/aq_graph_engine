# Статус реализации интеграционных тестов

## ✅ Что сделано

### 1. Созданы все тестовые файлы (72 теста)
- `workflow_lifecycle_test.dart` (12 тестов)
- `instruction_lifecycle_test.dart` (10 тестов)
- `prompt_lifecycle_test.dart` (8 тестов)
- `suspend_resume_test.dart` (11 тестов)
- `parallel_execution_test.dart` (9 тестов)
- `composite_nodes_test.dart` (8 тестов)
- `error_handling_test.dart` (14 тестов)
- `test_helpers.dart` - вспомогательные функции
- `README.md` - полная документация

### 2. Покрытие
- ✅ Все 17 типов узлов (10 Workflow + 4 Instruction + 3 Prompt)
- ✅ Все 8 сценариев выполнения
- ✅ Принцип "Тонкий клиент" (только через репозитории)
- ✅ Audit trail и версионирование
- ✅ Suspend/Resume механизм
- ✅ Параллельное выполнение
- ✅ Обработка ошибок

### 3. Архитектура тестов
Тесты следуют правильному паттерну:
1. Подключение через `Vault.connect()`
2. Создание через `DirectRepository` / `VersionedRepository`
3. Запуск через `GraphEngineClient`
4. Проверка через `LoggedRepository`

## ❌ Что нужно исправить для запуска тестов

### 1. Добавить `dart:io` импорт во все тестовые файлы
```dart
import 'dart:io';
```

Файлы требующие исправления:
- `workflow_lifecycle_test.dart`
- `instruction_lifecycle_test.dart`
- `prompt_lifecycle_test.dart`
- `suspend_resume_test.dart`
- `parallel_execution_test.dart`
- `composite_nodes_test.dart`
- `error_handling_test.dart`

### 2. Исправить AqStudioProject - добавить параметр `path`
В `test_helpers.dart`:
```dart
final project = AqStudioProject(
  id: uuid(),
  tenantId: TestConfig.testTenantId,
  ownerId: TestConfig.testTenantId,
  name: name ?? 'Test Project ${DateTime.now().millisecondsSinceEpoch}',
  projectType: 'test',
  path: '/tmp/test_projects/${uuid()}', // ДОБАВИТЬ ЭТО
);
```

### 3. Реализовать метод `run()` в GraphEngineClient

Текущий API:
```dart
Future<GraphRunResponse> startRun(GraphRunRequest request)
```

Нужный API для тестов:
```dart
Stream<GraphRunEvent> run(GraphRunRequest request)
```

Этот метод должен:
1. Вызвать `startRun()` для запуска графа
2. Подключиться к `eventsUrl` или `wsUrl` из ответа
3. Стримить события типа `GraphRunEvent`
4. Завершить стрим при получении `completed` или `error`

### 4. Реализовать метод `resume()` в GraphEngineClient

Нужный API:
```dart
Stream<GraphRunEvent> resume(GraphResumeRequest request)
```

Аналогично `run()`, но для возобновления приостановленного графа.

### 5. Исправить доступ к LogEntry

В тестах используется:
```dart
final operations = logs.map((l) => l['operation']).toList();
```

Но `LogEntry` не поддерживает `[]` оператор. Нужно использовать:
```dart
final operations = logs.map((l) => l.operation).toList();
```

Или проверить структуру `LogEntry` в aq_schema.

## 🔄 Следующие шаги

### Вариант 1: Реализовать недостающее API (рекомендуется)
1. Добавить метод `Stream<GraphRunEvent> run(GraphRunRequest)` в GraphEngineClient
2. Реализовать подключение к SSE/WebSocket для получения событий
3. Добавить метод `Stream<GraphRunEvent> resume(GraphResumeRequest)`
4. Исправить все мелкие ошибки (импорты, параметры)
5. Запустить тесты

### Вариант 2: Адаптировать тесты под текущее API
1. Переписать тесты для использования `startRun()` + polling `getStatus()`
2. Убрать проверки событий (или эмулировать их)
3. Упростить тесты до базовой проверки статусов

## 📊 Оценка работы

### Для Варианта 1 (полная реализация):
- Реализация `run()` метода: ~2-3 часа
- Реализация `resume()` метода: ~1 час
- Исправление мелких ошибок: ~1 час
- Отладка и запуск тестов: ~2-3 часа
- **Итого: 6-8 часов**

### Для Варианта 2 (адаптация тестов):
- Переписывание тестов: ~3-4 часа
- Упрощение проверок: ~1-2 часа
- Отладка: ~1-2 часа
- **Итого: 5-8 часов**

## 🎯 Рекомендация

**Вариант 1** предпочтительнее, так как:
- Тесты уже написаны под правильную архитектуру
- API со стримингом событий более удобен для пользователей
- Полное покрытие всех сценариев
- Соответствует документации и ожиданиям

После реализации Варианта 1 получим:
- ✅ 72 полноценных интеграционных теста
- ✅ Удобный клиентский API с событиями
- ✅ Полное покрытие всех узлов и сценариев
- ✅ Готовность к production использованию
