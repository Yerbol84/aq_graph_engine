# Sprint 1 Day 3 - План: Reconnect логика и документация

## Цель

Добавить автоматическое переподключение при обрыве WebSocket и завершить документацию.

## Задачи (3-4 часа)

### 1. Reconnect логика (2 часа)

**Файл:** `lib/src/client/graph_run_stream.dart` (обновить)

**Функции:**
- Автоматическое переподключение при обрыве
- Exponential backoff (1s, 2s, 4s, 8s, max 30s)
- Максимум попыток (по умолчанию: бесконечно)
- Буферизация событий при отключении (опционально)
- Callback для уведомлений о reconnect

**Параметры:**
```dart
class GraphRunStream {
  final bool autoReconnect;
  final Duration initialReconnectDelay;
  final Duration maxReconnectDelay;
  final int? maxReconnectAttempts;
  final void Function(int attempt)? onReconnecting;
  final void Function()? onReconnected;
}
```

**Логика:**
1. При обрыве соединения (onDone, onError)
2. Если autoReconnect = true
3. Ждём initialReconnectDelay * 2^attempt
4. Пытаемся переподключиться
5. При успехе - вызываем onReconnected
6. При неудаче - повторяем с увеличенной задержкой

### 2. Буферизация событий (30 минут)

**Опциональная функция:**
- Сохранять события в буфер при отключении
- Отправлять буфер после переподключения
- Ограничение размера буфера (по умолчанию: 100 событий)

```dart
class GraphRunStream {
  final bool bufferWhileDisconnected;
  final int maxBufferSize;
}
```

### 3. Unit тесты для reconnect (1 час)

**Файл:** `test/unit/client/graph_run_stream_reconnect_test.dart`

**Тесты:**
- Автоматическое переподключение после обрыва
- Exponential backoff работает
- maxReconnectAttempts соблюдается
- onReconnecting callback вызывается
- onReconnected callback вызывается
- Буферизация событий работает

### 4. Документация (1 час)

**Файл:** `pkgs/aq_graph_engine/docs/CLIENT_USAGE.md`

**Содержание:**
- Быстрый старт
- Установка и настройка
- Базовые примеры
- WebSocket события
- Reconnect логика
- Error handling
- Best practices
- FAQ

**Файл:** `pkgs/aq_graph_engine/README.md` (обновить)

Добавить секцию про клиентскую библиотеку.

## Порядок реализации

1. ✅ Добавить reconnect параметры в GraphRunStream
2. ✅ Реализовать reconnect логику
3. ✅ Добавить exponential backoff
4. ✅ Реализовать буферизацию (опционально)
5. ✅ Написать unit тесты
6. ✅ Написать CLIENT_USAGE.md
7. ✅ Обновить README.md

## Ожидаемый результат

```dart
// Пример с reconnect
final stream = GraphRunStream(
  runId: 'run-123',
  wsUrl: 'ws://localhost:8080/api/v1/runs/run-123/ws',
  autoReconnect: true,
  maxReconnectAttempts: 5,
  onReconnecting: (attempt) {
    print('Reconnecting... attempt $attempt');
  },
  onReconnected: () {
    print('Reconnected!');
  },
);

await for (final event in stream.events) {
  print('Event: ${event.type}');
  // Если соединение оборвётся - автоматически переподключится
}
```

## Критерии успеха

- ✅ Reconnect работает автоматически
- ✅ Exponential backoff реализован
- ✅ Callbacks вызываются корректно
- ✅ Unit тесты покрывают reconnect логику
- ✅ Документация полная и понятная
- ✅ Примеры работают

## Опциональные улучшения

Если останется время:
- Connection state machine (connecting, connected, reconnecting, disconnected)
- Metrics (количество reconnect, время без соединения)
- Heartbeat для проверки соединения
- Graceful degradation при долгом отключении
