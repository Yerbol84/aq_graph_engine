# Архитектура клиент-сервер

**Последнее обновление:** 2026-05-02

---

## Принцип "Тонкий клиент"

**Клиент не реализует бизнес-логику. Клиент использует то, что дано.**

Если клиенту чего-то не хватает — это задача для сервиса, не для клиента.

---

## Трёхслойная архитектура

```
┌─────────────────────────────────────────────────────────────┐
│                    Flutter Application                      │
│              (UI + вызовы готовых сервисов)                 │
│                   НИКАКОЙ БИЗНЕС-ЛОГИКИ                     │
└─────────────────────────────────────────────────────────────┘
                              │ HTTP / SSE / WebSocket
                              ↓
┌─────────────────────────────────────────────────────────────┐
│                  Graph Engine Server                        │
│           (выполнение графов, оркестрация)                  │
│                                                             │
│  GraphEngine → WorkflowRunner → InstructionRunner           │
│                              → PromptRunner                 │
└─────────────────────────────────────────────────────────────┘
                              │
                ┌─────────────┼─────────────┐
                ↓             ↓             ↓
        ┌──────────┐  ┌──────────┐  ┌──────────┐
        │   Data   │  │ Security │  │  Queue   │
        │  Layer   │  │  Layer   │  │  Layer   │
        └──────────┘  └──────────┘  └──────────┘
```

---

## Режимы работы GraphEngine

### Локальный (desktop)

GraphEngine выполняет граф в том же процессе через `LocalEngineTransport`.
Используется в desktop приложении и тестах.

```dart
final engine = GraphEngine(
  tools: buildToolRegistry(),
  runRepo: myRunRepository,
  graphRepo: myGraphRepository,
  mode: GraphEngineMode.local,
);

final events = engine.run(GraphRunRequest(
  runId: uuid,
  blueprintId: workflowId,
  projectId: projectId,
  projectPath: '/path/to/project',
));
```

### Удалённый (web service)

GraphEngine делегирует выполнение на сервер через `HttpEngineTransport`.
Клиент получает события через SSE.

```dart
final engine = GraphEngine(
  tools: buildToolRegistry(),
  runRepo: myRunRepository,
  graphRepo: myGraphRepository,
  mode: GraphEngineMode.remote,
  remoteServerUrl: 'http://graph-engine-server:8080',
);
```

### Авто (auto)

Пробует remote, при недоступности падает на local.

```dart
final engine = GraphEngine(
  // ...
  mode: GraphEngineMode.auto,
  remoteServerUrl: 'http://graph-engine-server:8080',
);
```

---

## GraphEngineClient (HTTP клиент)

Для прямой работы с GraphEngine Server без `GraphEngine`:

```dart
import 'package:aq_graph_engine/aq_graph_engine.dart';

final client = GraphEngineClient(
  baseUrl: 'http://localhost:8080',
  defaultHeaders: {'X-API-Key': 'aq_your_key'},
);

// Запустить граф
final response = await client.startRun(GraphRunRequest(
  runId: uuid,
  blueprintId: workflowId,
  projectId: projectId,
  projectPath: '/path/to/project',
));

// Получать события
final stream = client.connectToRun(response.runId);
await for (final event in stream.events) {
  switch (event.type) {
    case GraphRunEventType.log:          print(event.message);
    case GraphRunEventType.statusChanged: print('Status: ${event.newStatus}');
    case GraphRunEventType.completed:    break;
    case GraphRunEventType.error:        print('Error: ${event.errorMessage}');
    case GraphRunEventType.userInputRequired:
      await client.resumeRun(response.runId, {'answer': 'yes'});
  }
}

client.close();
```

---

## Контракты (интерфейсы в aq_schema)

### IEngineTransport

```dart
abstract class IEngineTransport {
  Stream<GraphRunEvent> run(GraphRunRequest request);
  Future<void> respondToInput(UserInputResponse response);
  Future<void> cancel(String runId);
  Future<bool> isAvailable();
  void dispose();
}
```

Реализации: `LocalEngineTransport`, `HttpEngineTransport`.

### IRunRepository

```dart
abstract class IRunRepository {
  Future<WorkflowRun?> getRun(String runId);
  Future<void> createRun(WorkflowRun run);
  Future<void> updateRunLog(String runId, List<String> logs, {WorkflowRunStatus? status});
  Future<void> suspendRun({required String runId, required String contextJson, required String nodeId});
  Future<void> resume(String runId);
  Future<void> complete(String runId);
  Future<void> appendLog(String runId, String entry); // дефолт: no-op
}
```

### IGraphRepository

```dart
abstract class IGraphRepository {
  Future<$Graph?> loadGraph(String graphId);
}
```

---

## Правила слоёв

### Flutter Application

- ✅ Отображать UI, вызывать сервисы, обрабатывать события
- ❌ Реализовывать логику выполнения графов
- ❌ Реализовывать репозитории (это Data Layer)
- ❌ Дублировать серверную логику

### Graph Engine Server

- ✅ Выполнять графы, управлять lifecycle, компилировать промпты
- ✅ Использовать готовые репозитории от Data Layer
- ❌ Реализовывать хранение данных (это Data Layer)
- ❌ Реализовывать авторизацию (это Security Layer)

---

## Антипаттерны

**❌ Клиент реализует логику выполнения:**
```dart
// ПЛОХО — клиент знает как выполнять узлы
class ClientSideRunner {
  Future<void> executeNode(node) { ... }
}
```

**✅ Клиент только отправляет запрос:**
```dart
// ХОРОШО
final events = engine.run(request);
```

**❌ Приложение реализует репозиторий:**
```dart
// ПЛОХО — логика хранения в приложении
class AppRunRepository implements IRunRepository { ... }
```

**✅ Используется готовый репозиторий от Data Layer:**
```dart
// ХОРОШО
final runRepo = DataLayerRunRepository();
```
