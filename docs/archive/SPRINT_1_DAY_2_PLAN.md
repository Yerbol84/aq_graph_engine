# Sprint 1 Day 2 - План: Клиентская библиотека GraphEngineClient

## Цель

Создать удобную клиентскую библиотеку для работы с Graph Engine Server через HTTP и WebSocket.

## Задачи (4-6 часов)

### 1. Базовая структура клиента (1 час)

**Файл:** `pkgs/aq_graph_engine/lib/src/client/graph_engine_client.dart`

```dart
class GraphEngineClient {
  final String baseUrl;
  final http.Client _httpClient;

  // HTTP методы
  Future<GraphRunResponse> startRun(GraphRunRequest request);
  Future<GraphRunStatus> getStatus(String runId);
  Future<void> cancelRun(String runId);
  Future<void> resumeRun(String runId, Map<String, dynamic> input);

  // WebSocket подключение
  GraphRunStream connectToRun(String runId);
}
```

### 2. GraphRunStream - обёртка над WebSocket (2 часа)

**Файл:** `pkgs/aq_graph_engine/lib/src/client/graph_run_stream.dart`

```dart
class GraphRunStream {
  final String runId;
  final String wsUrl;

  // Stream событий
  Stream<GraphRunEvent> get events;

  // Управление подключением
  Future<void> connect();
  Future<void> disconnect();
  bool get isConnected;

  // Ping/pong
  Future<void> ping();
}
```

**Функции:**
- Автоматическое подключение при первом listen
- Парсинг JSON → GraphRunEvent
- Обработка welcome, pong, error, ack
- Graceful disconnect

### 3. Модели ответов (30 минут)

**Файл:** `pkgs/aq_graph_engine/lib/src/client/models.dart`

```dart
class GraphRunResponse {
  final String runId;
  final String status;
  final String eventsUrl;
  final String wsUrl;
}

class GraphRunStatusResponse {
  final String runId;
  final GraphRunStatus status;
  final String? currentNodeId;
  final DateTime? startedAt;
  final DateTime? completedAt;
}
```

### 4. Error handling (30 минут)

**Файл:** `pkgs/aq_graph_engine/lib/src/client/exceptions.dart`

```dart
class GraphEngineException implements Exception {
  final String message;
  final int? statusCode;
  final String? code;
}

class GraphEngineConnectionException extends GraphEngineException {}
class GraphEngineTimeoutException extends GraphEngineException {}
class GraphEngineNotFoundException extends GraphEngineException {}
```

### 5. Unit тесты (1-2 часа)

**Структура:**
```
test/unit/client/
  ├── graph_engine_client_test.dart
  ├── graph_run_stream_test.dart
  └── models_test.dart
```

**Покрытие:**
- HTTP запросы (с mock http.Client)
- WebSocket подключение (с mock channel)
- Парсинг ответов
- Error handling

### 6. Integration тест (1 час)

**Файл:** `test/integration/client_integration_test.dart`

**Сценарии:**
- Запуск графа через клиент
- Подключение к WebSocket
- Получение событий
- Отмена графа
- Полный lifecycle: start → events → complete

### 7. Документация (30 минут)

**Файл:** `pkgs/aq_graph_engine/docs/CLIENT_USAGE.md`

**Содержание:**
- Быстрый старт
- Примеры использования
- API reference
- Error handling
- Best practices

## Порядок реализации

1. ✅ Создать базовую структуру GraphEngineClient
2. ✅ Реализовать HTTP методы (startRun, getStatus, cancelRun, resumeRun)
3. ✅ Создать модели ответов
4. ✅ Создать GraphRunStream
5. ✅ Реализовать WebSocket подключение
6. ✅ Добавить error handling
7. ✅ Написать unit тесты
8. ✅ Написать integration тест
9. ✅ Документация

## Ожидаемый результат

```dart
// Пример использования
final client = GraphEngineClient(baseUrl: 'http://localhost:8080');

// Запуск графа
final response = await client.startRun(GraphRunRequest(
  blueprintId: 'bp-1',
  projectId: 'proj-1',
));

print('Run started: ${response.runId}');

// Подключение к событиям
final stream = client.connectToRun(response.runId);

await for (final event in stream.events) {
  print('Event: ${event.type} - ${event.message}');

  if (event.type == GraphRunEventType.completed) {
    break;
  }
}

await stream.disconnect();
```

## Критерии успеха

- ✅ Клиент работает с реальным сервером
- ✅ WebSocket подключение стабильно
- ✅ События парсятся корректно
- ✅ Error handling покрывает все случаи
- ✅ Unit тесты покрывают >80% кода
- ✅ Integration тест проходит
- ✅ Документация полная и понятная
