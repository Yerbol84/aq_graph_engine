# GraphEngineClient - Руководство по использованию

## Быстрый старт

```dart
import 'package:aq_graph_engine/aq_graph_engine.dart';

// Создать клиент
final client = GraphEngineClient(
  baseUrl: 'http://localhost:8080',
);

// Запустить граф
final response = await client.startRun(GraphRunRequest(
  runId: 'run-123',
  blueprintId: 'bp-1',
  projectId: 'proj-1',
  projectPath: '',
));

print('Run started: ${response.runId}');

// Подключиться к событиям
final stream = client.connectToRun(response.runId);

await for (final event in stream.events) {
  print('Event: ${event.type} - ${event.message}');

  if (event.type == GraphRunEventType.completed) {
    break;
  }
}

await stream.disconnect();
client.close();
```

## Установка

Добавьте зависимость в `pubspec.yaml`:

```yaml
dependencies:
  aq_graph_engine: ^1.0.0
  aq_schema: ^1.0.0
```

## API Reference

### GraphEngineClient

#### Конструктор

```dart
GraphEngineClient({
  required String baseUrl,
  http.Client? httpClient,
  Duration timeout = const Duration(seconds: 30),
  Map<String, String>? defaultHeaders,
})
```

**Параметры:**
- `baseUrl` - URL Graph Engine Server (например: `http://localhost:8080`)
- `httpClient` - Кастомный HTTP клиент (опционально)
- `timeout` - Таймаут для HTTP запросов (по умолчанию: 30 секунд)
- `defaultHeaders` - Заголовки для всех запросов (например: API ключи)

#### Методы

##### startRun

Запустить выполнение графа.

```dart
Future<GraphRunResponse> startRun(GraphRunRequest request)
```

**Пример:**
```dart
final response = await client.startRun(GraphRunRequest(
  runId: 'run-123',
  blueprintId: 'bp-1',
  projectId: 'proj-1',
  projectPath: '/path/to/project',
  initialVariables: {'key': 'value'},
));

print('Run ID: ${response.runId}');
print('Status: ${response.status}');
print('WebSocket URL: ${response.wsUrl}');
```

##### getStatus

Получить текущий статус выполнения.

```dart
Future<GraphRunStatusResponse> getStatus(String runId)
```

**Пример:**
```dart
final status = await client.getStatus('run-123');

print('Status: ${status.status}');
print('Current node: ${status.currentNodeId}');
print('Started at: ${status.startedAt}');
```

##### cancelRun

Отменить выполнение графа.

```dart
Future<void> cancelRun(String runId)
```

**Пример:**
```dart
await client.cancelRun('run-123');
print('Run cancelled');
```

##### resumeRun

Возобновить приостановленный граф (после suspend).

```dart
Future<void> resumeRun(String runId, Map<String, dynamic> input)
```

**Пример:**
```dart
await client.resumeRun('run-123', {
  'userInput': 'yes',
  'selectedOption': 'option1',
});
```

##### connectToRun

Подключиться к WebSocket для получения событий в реальном времени.

```dart
GraphRunStream connectToRun(String runId, {String? token, String? apiKey})
```

**Параметры:**
- `runId` - ID запуска
- `token` - JWT токен для авторизации (опционально)
- `apiKey` - API ключ для авторизации (опционально)

**Пример:**
```dart
final stream = client.connectToRun(
  'run-123',
  apiKey: 'aq_test_key',
);

await for (final event in stream.events) {
  print('Event: ${event.type}');
}
```

### GraphRunStream

#### Параметры конструктора

```dart
GraphRunStream({
  required String runId,
  required String wsUrl,
  Duration connectionTimeout = const Duration(seconds: 10),
  bool enableKeepAlive = true,
  Duration keepAliveInterval = const Duration(seconds: 30),
})
```

**Параметры:**
- `enableKeepAlive` - Автоматический ping для поддержания соединения (по умолчанию: true)
- `keepAliveInterval` - Интервал между ping (по умолчанию: 30 секунд)

#### Свойства

- `Stream<GraphRunEvent> events` - Stream событий от графа
- `bool isConnected` - Подключён ли к WebSocket

#### Методы

- `Future<void> connect()` - Подключиться к WebSocket
- `Future<void> disconnect()` - Отключиться от WebSocket
- `Future<void> ping()` - Отправить ping (обычно не нужно, автоматический keep-alive)

## Обработка событий

### Типы событий

```dart
enum GraphRunEventType {
  log,              // Лог сообщение
  statusChanged,    // Статус изменился
  completed,        // Граф завершён
  error,            // Ошибка
  userInputRequired // Требуется ввод пользователя
}
```

### Пример обработки

```dart
await for (final event in stream.events) {
  switch (event.type) {
    case GraphRunEventType.log:
      print('📝 ${event.message}');
      if (event.logType == 'error') {
        print('  ❌ Error log');
      }
      break;

    case GraphRunEventType.statusChanged:
      print('🔄 Status changed to: ${event.newStatus}');
      break;

    case GraphRunEventType.completed:
      print('✅ Run completed successfully');
      break;

    case GraphRunEventType.error:
      print('❌ Error: ${event.errorMessage}');
      break;

    case GraphRunEventType.userInputRequired:
      print('⏸️  User input required');
      print('Payload: ${event.inputRequiredPayload}');
      // Вызвать resumeRun с вводом пользователя
      break;
  }
}
```

## Error Handling

### Типы исключений

```dart
GraphEngineException              // Базовое исключение
GraphEngineConnectionException    // Ошибка подключения
GraphEngineTimeoutException       // Таймаут
GraphEngineNotFoundException      // 404 Not Found
GraphEngineUnauthorizedException  // 401 Unauthorized
GraphEngineForbiddenException     // 403 Forbidden
GraphEngineValidationException    // 400 Bad Request
GraphEngineServerException        // 500 Internal Server Error
```

### Пример обработки

```dart
try {
  final response = await client.startRun(request);
  print('Success: ${response.runId}');
} on GraphEngineValidationException catch (e) {
  print('Validation error: ${e.message}');
  print('Details: ${e.details}');
} on GraphEngineUnauthorizedException catch (e) {
  print('Auth required: ${e.message}');
  // Запросить авторизацию
} on GraphEngineConnectionException catch (e) {
  print('Connection failed: ${e.message}');
  // Повторить попытку
} on GraphEngineException catch (e) {
  print('Error: ${e.message} (HTTP ${e.statusCode})');
}
```

## Авторизация

### API Key

```dart
final client = GraphEngineClient(
  baseUrl: 'http://localhost:8080',
  defaultHeaders: {
    'X-API-Key': 'aq_your_api_key',
  },
);

// WebSocket с API key
final stream = client.connectToRun('run-123', apiKey: 'aq_your_api_key');
```

### JWT Token

```dart
final client = GraphEngineClient(
  baseUrl: 'http://localhost:8080',
  defaultHeaders: {
    'Authorization': 'Bearer your_jwt_token',
  },
);

// WebSocket с JWT
final stream = client.connectToRun('run-123', token: 'your_jwt_token');
```

## Best Practices

### 1. Всегда закрывайте клиент

```dart
final client = GraphEngineClient(baseUrl: 'http://localhost:8080');

try {
  // Используйте клиент
} finally {
  client.close(); // Освобождает ресурсы
}
```

### 2. Обрабатывайте disconnect

```dart
final stream = client.connectToRun('run-123');

try {
  await for (final event in stream.events) {
    print('Event: ${event.type}');
  }
} catch (e) {
  print('Stream error: $e');
} finally {
  await stream.disconnect();
}
```

### 3. Используйте timeout

```dart
final client = GraphEngineClient(
  baseUrl: 'http://localhost:8080',
  timeout: const Duration(seconds: 60), // Для долгих операций
);
```

### 4. Keep-alive для долгих соединений

```dart
final stream = GraphRunStream(
  runId: 'run-123',
  wsUrl: 'ws://localhost:8080/api/v1/runs/run-123/ws',
  enableKeepAlive: true,
  keepAliveInterval: const Duration(seconds: 30),
);
```

### 5. Обрабатывайте все типы событий

```dart
await for (final event in stream.events) {
  switch (event.type) {
    case GraphRunEventType.log:
      // Обработать лог
      break;
    case GraphRunEventType.statusChanged:
      // Обработать изменение статуса
      break;
    case GraphRunEventType.completed:
      // Граф завершён
      break;
    case GraphRunEventType.error:
      // Обработать ошибку
      break;
    case GraphRunEventType.userInputRequired:
      // Запросить ввод пользователя
      break;
  }
}
```

## Полный пример

```dart
import 'package:aq_graph_engine/aq_graph_engine.dart';

Future<void> main() async {
  // Создать клиент
  final client = GraphEngineClient(
    baseUrl: 'http://localhost:8080',
    defaultHeaders: {
      'X-API-Key': 'aq_test_key',
    },
  );

  try {
    // Запустить граф
    print('Starting graph...');
    final response = await client.startRun(GraphRunRequest(
      runId: 'run-${DateTime.now().millisecondsSinceEpoch}',
      blueprintId: 'my-blueprint',
      projectId: 'my-project',
      projectPath: '/path/to/project',
    ));

    print('✅ Run started: ${response.runId}');

    // Подключиться к событиям
    final stream = client.connectToRun(
      response.runId,
      apiKey: 'aq_test_key',
    );

    print('📡 Listening for events...');

    await for (final event in stream.events) {
      switch (event.type) {
        case GraphRunEventType.log:
          print('📝 ${event.message}');
          break;

        case GraphRunEventType.statusChanged:
          print('🔄 Status: ${event.newStatus}');
          break;

        case GraphRunEventType.completed:
          print('✅ Completed!');
          break;

        case GraphRunEventType.error:
          print('❌ Error: ${event.errorMessage}');
          break;

        case GraphRunEventType.userInputRequired:
          print('⏸️  Input required: ${event.inputRequiredPayload}');
          // В реальном приложении - запросить ввод у пользователя
          await client.resumeRun(response.runId, {'input': 'user response'});
          break;
      }

      if (event.type == GraphRunEventType.completed ||
          event.type == GraphRunEventType.error) {
        break;
      }
    }

    await stream.disconnect();
    print('🔌 Disconnected');
  } catch (e) {
    print('❌ Error: $e');
  } finally {
    client.close();
  }
}
```

## FAQ

### Q: Как узнать, что граф завершился?

A: Слушайте событие `GraphRunEventType.completed`:

```dart
await for (final event in stream.events) {
  if (event.type == GraphRunEventType.completed) {
    print('Graph completed!');
    break;
  }
}
```

### Q: Что делать при обрыве соединения?

A: Keep-alive автоматически поддерживает соединение. Если соединение оборвалось, stream завершится. В будущих версиях будет автоматический reconnect.

### Q: Можно ли подключиться к уже запущенному графу?

A: Да, просто вызовите `connectToRun()` с существующим `runId`:

```dart
final stream = client.connectToRun('existing-run-id');
```

### Q: Как отменить выполнение графа?

A: Используйте `cancelRun()`:

```dart
await client.cancelRun('run-123');
```

### Q: Нужно ли вручную отправлять ping?

A: Нет, keep-alive автоматически отправляет ping каждые 30 секунд (по умолчанию).

### Q: Как обработать ошибки авторизации?

A: Ловите `GraphEngineUnauthorizedException`:

```dart
try {
  await client.startRun(request);
} on GraphEngineUnauthorizedException catch (e) {
  print('Auth failed: ${e.message}');
  // Запросить новый токен
}
```

## См. также

- [WEBSOCKET_API.md](WEBSOCKET_API.md) - Протокол WebSocket
- [SPRINT_1_FINAL_REPORT.md](SPRINT_1_FINAL_REPORT.md) - Отчёт о реализации
- [aq_schema](../aq_schema/) - Модели данных
