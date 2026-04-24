# Sprint 1: WebSocket Events + Client Library

**Дата начала:** 2026-04-08
**Длительность:** 3-5 дней
**Цель:** Добавить real-time события через WebSocket и клиентскую библиотеку

---

## Контекст

**Что уже есть:**
- ✅ HTTP сервер с REST API
- ✅ POST /api/v1/runs - запуск графа
- ✅ GET /admin/states - просмотр состояний
- ✅ GET /admin/alerts - просмотр алертов
- ✅ Auth middleware (JWT + API keys)
- ✅ 136 тестов

**Что нужно добавить:**
- ❌ WebSocket endpoint для real-time событий
- ❌ Клиентская библиотека (GraphEngineClient)
- ❌ Reconnect логика
- ❌ Тесты для WebSocket

---

## Архитектурные решения

### 1. WebSocket vs Server-Sent Events (SSE)

**Выбор: WebSocket**

**Причины:**
- Двусторонняя коммуникация (можем отправлять команды от клиента)
- Лучше для интерактивных графов (suspend/resume)
- Стандартная поддержка в браузерах и Flutter
- Меньше overhead чем HTTP polling

**Альтернатива (SSE):**
- Только односторонняя коммуникация (сервер → клиент)
- Проще реализация
- Автоматический reconnect в браузерах
- Но: нужны отдельные HTTP запросы для команд

### 2. WebSocket протокол

**Формат сообщений: JSON**

```json
// Событие от сервера
{
  "type": "event",
  "runId": "run-123",
  "event": {
    "type": "nodeStarted",
    "nodeId": "node-1",
    "timestamp": "2026-04-08T10:00:00Z"
  }
}

// Команда от клиента
{
  "type": "command",
  "command": "subscribe",
  "runId": "run-123"
}
```

**Типы событий (GraphRunEvent из aq_schema):**
- `runStarted` - граф начал выполнение
- `nodeStarted` - узел начал выполнение
- `nodeCompleted` - узел завершён
- `runSuspended` - граф приостановлен (ждёт ввода)
- `runCompleted` - граф завершён успешно
- `runFailed` - граф завершён с ошибкой
- `runCancelled` - граф отменён

**Команды от клиента:**
- `subscribe` - подписаться на события run
- `unsubscribe` - отписаться от событий
- `ping` - keep-alive

### 3. Управление подписками

**Проблема:** Как хранить активные WebSocket соединения?

**Решение:** In-memory Map с cleanup

```dart
class WebSocketManager {
  final Map<String, Set<WebSocketChannel>> _subscriptions = {};

  void subscribe(String runId, WebSocketChannel channel) {
    _subscriptions.putIfAbsent(runId, () => {}).add(channel);
  }

  void broadcast(String runId, GraphRunEvent event) {
    final channels = _subscriptions[runId];
    if (channels == null) return;

    for (final channel in channels) {
      channel.sink.add(jsonEncode(event.toJson()));
    }
  }
}
```

**Cleanup:**
- При disconnect - удалить channel из подписок
- Периодический cleanup закрытых соединений
- Timeout для неактивных соединений (5 минут)

### 4. Интеграция с GraphEngine

**Текущая проблема:** GraphEngine возвращает `Stream<GraphRunEvent>`, но как транслировать в WebSocket?

**Решение:** Хранить активные streams в памяти

```dart
class EventStreamManager {
  final Map<String, StreamSubscription<GraphRunEvent>> _streams = {};

  void startStreaming(String runId, Stream<GraphRunEvent> events, WebSocketManager ws) {
    final subscription = events.listen((event) {
      ws.broadcast(runId, event);
    });

    _streams[runId] = subscription;
  }

  void stopStreaming(String runId) {
    _streams[runId]?.cancel();
    _streams.remove(runId);
  }
}
```

---

## План реализации

### День 1: WebSocket Handler (4-6 часов)

**Задачи:**

1. **Добавить зависимость `shelf_web_socket`**
   ```yaml
   dependencies:
     shelf_web_socket: ^1.0.4
   ```

2. **Создать WebSocketManager**
   - Файл: `lib/core/websocket/websocket_manager.dart`
   - Методы: `subscribe()`, `unsubscribe()`, `broadcast()`
   - Cleanup закрытых соединений

3. **Создать EventStreamManager**
   - Файл: `lib/core/websocket/event_stream_manager.dart`
   - Методы: `startStreaming()`, `stopStreaming()`
   - Интеграция с GraphEngine streams

4. **Создать WebSocketHandler**
   - Файл: `lib/handlers/websocket_handler.dart`
   - Endpoint: `GET /api/v1/runs/:id/events`
   - Upgrade HTTP → WebSocket
   - Обработка команд (subscribe, unsubscribe, ping)

5. **Интегрировать в Router**
   - Добавить route в `lib/routing/app_router.dart`
   - Зарегистрировать в DI

**Тесты:**
- Unit тест: WebSocketManager subscribe/broadcast
- Unit тест: EventStreamManager streaming
- Integration тест: WebSocket подключение

**Результат дня:**
✅ WebSocket endpoint работает
✅ Можем подписаться на события run

---

### День 2: Клиентская библиотека - Базовая (4-6 часов)

**Задачи:**

1. **Создать GraphEngineClient**
   - Файл: `lib/src/client/graph_engine_client.dart`
   - Конструктор: `GraphEngineClient({required String baseUrl})`
   - Методы:
     - `Future<String> runGraph(GraphRunRequest request)` - запуск графа
     - `Future<void> cancel(String runId)` - отмена
     - `Stream<GraphRunEvent> subscribeToEvents(String runId)` - подписка

2. **HTTP клиент для REST API**
   - Использовать `package:http`
   - POST /api/v1/runs
   - DELETE /api/v1/runs/:id
   - Обработка ошибок (401, 403, 404, 500)

3. **WebSocket клиент**
   - Использовать `package:web_socket_channel`
   - Подключение к `/api/v1/runs/:id/events`
   - Парсинг JSON событий
   - Преобразование в `Stream<GraphRunEvent>`

**Тесты:**
- Unit тест: HTTP запросы
- Unit тест: WebSocket подключение
- Mock тесты с fake сервером

**Результат дня:**
✅ GraphEngineClient работает
✅ Можем запустить граф и получить события

---

### День 3: Reconnect логика (4-6 часов)

**Задачи:**

1. **Добавить автоматический reconnect**
   - Экспоненциальная задержка (1s, 2s, 4s, 8s, max 30s)
   - Максимум попыток: 10
   - Восстановление подписки после reconnect

2. **Обработка ошибок**
   - Network timeout
   - Server disconnect
   - Invalid JSON
   - Auth errors (401)

3. **Keep-alive механизм**
   - Ping каждые 30 секунд
   - Pong от сервера
   - Disconnect если нет pong 60 секунд

4. **Буферизация событий**
   - Если disconnect - буферизовать события
   - После reconnect - отправить буфер
   - Максимум буфера: 100 событий

**Тесты:**
- Unit тест: reconnect с задержкой
- Unit тест: keep-alive ping/pong
- Integration тест: disconnect → reconnect → события продолжают приходить

**Результат дня:**
✅ Reconnect работает автоматически
✅ Keep-alive предотвращает timeout
✅ События не теряются при disconnect

---

### День 4: Тестирование и документация (4-6 часов)

**Задачи:**

1. **Integration тесты**
   - Тест: Запуск графа → подписка → получение событий
   - Тест: Suspend → Resume через WebSocket
   - Тест: Множество клиентов подписаны на один run
   - Тест: Disconnect → Reconnect → события продолжают приходить

2. **Performance тесты**
   - 100 одновременных WebSocket соединений
   - 1000 событий в секунду
   - Memory leak проверка

3. **Документация**
   - Обновить README с примерами WebSocket
   - Создать WEBSOCKET_API.md
   - Примеры кода для клиента

**Результат дня:**
✅ Все тесты проходят
✅ Документация обновлена
✅ Примеры кода работают

---

### День 5: Полировка и рефакторинг (опционально)

**Задачи:**

1. **Code review и рефакторинг**
   - Улучшить error handling
   - Добавить логирование
   - Оптимизировать память

2. **Дополнительные фичи**
   - Фильтрация событий (только определённые типы)
   - Batch отправка событий (если много)
   - Compression для больших событий

3. **Финальное тестирование**
   - Smoke тесты
   - Проверка всех edge cases

**Результат дня:**
✅ Код чистый и оптимизированный
✅ Все edge cases покрыты
✅ Готово к production

---

## Критерии готовности Sprint 1

### Must Have (обязательно)

- ✅ WebSocket endpoint `/api/v1/runs/:id/events` работает
- ✅ Клиент может подписаться на события
- ✅ События приходят в real-time
- ✅ GraphEngineClient реализован
- ✅ Reconnect работает автоматически
- ✅ Unit тесты проходят (coverage > 80%)
- ✅ Integration тесты проходят
- ✅ Документация обновлена

### Should Have (желательно)

- ✅ Keep-alive ping/pong
- ✅ Буферизация событий при disconnect
- ✅ Performance тесты (100+ соединений)
- ✅ Примеры кода

### Could Have (опционально)

- ⏳ Фильтрация событий
- ⏳ Batch отправка
- ⏳ Compression

---

## Технические детали

### WebSocket URL

```
ws://localhost:8080/api/v1/runs/{runId}/events
```

**Query параметры:**
- `?token=<jwt>` - JWT токен для auth
- `?apiKey=<key>` - API ключ для auth

### Протокол сообщений

**От сервера к клиенту:**

```json
{
  "type": "event",
  "runId": "run-123",
  "event": {
    "type": "nodeStarted",
    "nodeId": "node-1",
    "timestamp": "2026-04-08T10:00:00Z",
    "data": {}
  }
}
```

**От клиента к серверу:**

```json
{
  "type": "ping"
}
```

**Ответ сервера:**

```json
{
  "type": "pong",
  "timestamp": "2026-04-08T10:00:01Z"
}
```

### Error handling

**Коды ошибок:**
- `1000` - Normal closure
- `1001` - Going away (server shutdown)
- `1008` - Policy violation (auth failed)
- `1011` - Internal server error

**Error message:**

```json
{
  "type": "error",
  "code": "AUTH_FAILED",
  "message": "Invalid JWT token"
}
```

---

## Риски и митигация

### Риск 1: Memory leak от незакрытых WebSocket

**Митигация:**
- Timeout для неактивных соединений (5 минут)
- Периодический cleanup (каждую минуту)
- Мониторинг количества активных соединений

### Риск 2: Потеря событий при disconnect

**Митигация:**
- Буферизация на клиенте
- Sequence numbers для событий
- Возможность запросить пропущенные события

### Риск 3: Высокая нагрузка при множестве клиентов

**Митигация:**
- Rate limiting на WebSocket подключения
- Batch отправка событий
- Compression для больших событий

---

## Метрики успеха

- **Latency:** События приходят < 100ms после генерации
- **Throughput:** 1000+ событий/сек на один run
- **Connections:** 100+ одновременных WebSocket соединений
- **Reconnect time:** < 5 секунд после disconnect
- **Memory:** < 10MB на 100 соединений
- **CPU:** < 5% при 100 соединениях

---

## Следующие шаги после Sprint 1

1. **Sprint 2:** Retry механизм и timeout для узлов
2. **Sprint 3:** Горизонтальное масштабирование (stateless сервер)
3. **Sprint 4:** Визуальный дебаггер
4. **Sprint 5:** Production deployment

---

**Статус:** Готов к началу
**Приоритет:** High
**Оценка:** 3-5 дней
