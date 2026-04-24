# Интерфейсы для интеграции с приложением

**Дата:** 2026-04-11
**Пакет:** aq_graph_engine
**Статус:** Production Ready

---

## 📋 Обзор

При подключении пакета `aq_graph_engine` к приложению, приложение должно предоставить **реализации двух интерфейсов**:

1. **IRunRepository** — хранилище запусков графов
2. **IGraphRepository** — хранилище графов (blueprints)

Эти интерфейсы экспортируются в клиентской части пакета:

```dart
import 'package:aq_graph_engine/aq_graph_engine.dart';

// Доступны интерфейсы:
// - IRunRepository
// - IGraphRepository
```

---

## 🔌 Интерфейс #1: IRunRepository

**Назначение:** Хранилище запусков графов (run state, logs, suspend/resume)

**Файл:** `lib/src/interfaces/i_run_repository.dart`

### Методы:

#### 1. Создание запуска

```dart
Future<void> createRun({
  required String runId,
  required String projectId,
  required Map<String, dynamic> graphSnapshot,
});
```

**Когда вызывается:** При старте нового запуска графа

**Что должно сохраниться:**
- `runId` — уникальный ID запуска
- `projectId` — ID проекта
- `graphSnapshot` — снимок графа на момент запуска
- `status` — начальный статус (обычно "queued" или "running")

---

#### 2. Обновление логов

```dart
Future<void> updateRunLog(
  String runId,
  List<String> logs, {
  String? status,
});
```

**Когда вызывается:** После выполнения каждого узла

**Что должно обновиться:**
- Добавить новые логи к существующим
- Опционально обновить статус ("running", "completed", "failed")

---

#### 3. Приостановка запуска

```dart
Future<void> suspendRun({
  required String runId,
  required String contextJson,
  required String nodeId,
  required List<String> logs,
});
```

**Когда вызывается:** Когда граф ждёт ввода пользователя (userInput, manualReview)

**Что должно сохраниться:**
- `contextJson` — сериализованный контекст выполнения
- `nodeId` — ID узла, на котором приостановлен
- `status` — "suspended"
- Обновлённые логи

---

#### 4. Получение запуска

```dart
Future<Map<String, dynamic>?> getRun(String runId);
```

**Когда вызывается:** При resume, при проверке статуса

**Что должно вернуться:**
```dart
{
  'id': 'run-123',
  'status': 'suspended',
  'contextJson': '{"state": {...}}',
  'suspendedNodeId': 'node-5',
  'logsJson': '["log1", "log2"]',
  'projectId': 'project-1',
  'graphSnapshot': {...},
}
```

---

#### 5. Atomic compare-and-set статуса

```dart
Future<bool> compareAndSetStatus({
  required String runId,
  required String expectedStatus,
  required String newStatus,
});
```

**Когда вызывается:** Для защиты от race conditions при одновременном запуске

**Пример:**
```dart
// Пытаемся перевести из 'queued' в 'running'
final success = await repo.compareAndSetStatus(
  runId: 'run-123',
  expectedStatus: 'queued',
  newStatus: 'running',
);

if (!success) {
  // Кто-то другой уже запустил этот run
  throw StateError('Run already started');
}
```

---

#### 6. Distributed locking

```dart
Future<bool> tryAcquireLock({
  required String runId,
  required String workerId,
  required Duration ttl,
});

Future<bool> releaseLock({
  required String runId,
  required String workerId,
});
```

**Когда вызывается:** В distributed системах с несколькими workers

**Пример:**
```dart
final locked = await repo.tryAcquireLock(
  runId: 'run-123',
  workerId: 'worker-1',
  ttl: Duration(minutes: 5),
);

if (!locked) {
  // Run уже выполняется другим worker'ом
  return;
}

try {
  // Выполняем run
} finally {
  await repo.releaseLock(runId: 'run-123', workerId: 'worker-1');
}
```

---

#### 7. Dead Letter Queue (DLQ)

```dart
// Переместить failed run в DLQ
Future<void> moveToDLQ({
  required String runId,
  required String reason,
  required int failureCount,
  String? lastError,
});

// Получить список runs в DLQ
Future<List<Map<String, dynamic>>> getDLQJobs({
  int limit = 100,
  int offset = 0,
});

// Retry run из DLQ
Future<bool> retryFromDLQ({required String runId});

// Удалить старые записи из DLQ
Future<int> cleanupDLQ({required Duration olderThan});
```

**Когда вызывается:** Для обработки failed runs после всех retry попыток

---

## 🔌 Интерфейс #2: IGraphRepository

**Назначение:** Хранилище графов (blueprints)

**Файл:** `lib/src/interfaces/i_graph_repository.dart`

### Методы:

#### 1. Загрузка графа

```dart
Future<$Graph?> loadGraph(String blueprintId);
```

**Когда вызывается:** При старте запуска, при вызове subGraph/runInstruction

**Что должно вернуться:**
- `WorkflowGraph` — для workflow
- `InstructionGraph` — для instruction
- `PromptGraph` — для prompt
- `null` — если граф не найден

**Пример:**
```dart
final graph = await graphRepo.loadGraph('workflow-123');

if (graph == null) {
  throw Exception('Graph not found');
}

if (graph is WorkflowGraph) {
  // Выполнить workflow
} else if (graph is InstructionGraph) {
  // Выполнить instruction
}
```

---

## 📦 Пример реализации для приложения

### Вариант 1: Локальное хранилище (SQLite/Drift)

```dart
import 'package:aq_graph_engine/aq_graph_engine.dart';
import 'package:drift/drift.dart';

class DriftRunRepository implements IRunRepository {
  final AppDatabase db;

  DriftRunRepository(this.db);

  @override
  Future<void> createRun({
    required String runId,
    required String projectId,
    required Map<String, dynamic> graphSnapshot,
  }) async {
    await db.into(db.runs).insert(
      RunsCompanion.insert(
        id: runId,
        projectId: projectId,
        status: 'queued',
        graphSnapshot: jsonEncode(graphSnapshot),
        createdAt: DateTime.now(),
      ),
    );
  }

  @override
  Future<void> updateRunLog(
    String runId,
    List<String> logs, {
    String? status,
  }) async {
    final existing = await (db.select(db.runs)
          ..where((r) => r.id.equals(runId)))
        .getSingleOrNull();

    if (existing == null) return;

    final existingLogs = jsonDecode(existing.logsJson) as List;
    final newLogs = [...existingLogs, ...logs];

    await (db.update(db.runs)..where((r) => r.id.equals(runId))).write(
      RunsCompanion(
        logsJson: Value(jsonEncode(newLogs)),
        status: status != null ? Value(status) : Value.absent(),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  @override
  Future<void> suspendRun({
    required String runId,
    required String contextJson,
    required String nodeId,
    required List<String> logs,
  }) async {
    await updateRunLog(runId, logs, status: 'suspended');

    await (db.update(db.runs)..where((r) => r.id.equals(runId))).write(
      RunsCompanion(
        contextJson: Value(contextJson),
        suspendedNodeId: Value(nodeId),
      ),
    );
  }

  @override
  Future<Map<String, dynamic>?> getRun(String runId) async {
    final run = await (db.select(db.runs)
          ..where((r) => r.id.equals(runId)))
        .getSingleOrNull();

    if (run == null) return null;

    return {
      'id': run.id,
      'status': run.status,
      'contextJson': run.contextJson,
      'suspendedNodeId': run.suspendedNodeId,
      'logsJson': run.logsJson,
      'projectId': run.projectId,
      'graphSnapshot': jsonDecode(run.graphSnapshot),
    };
  }

  @override
  Future<bool> compareAndSetStatus({
    required String runId,
    required String expectedStatus,
    required String newStatus,
  }) async {
    final updated = await db.customUpdate(
      'UPDATE runs SET status = ? WHERE id = ? AND status = ?',
      variables: [
        Variable.withString(newStatus),
        Variable.withString(runId),
        Variable.withString(expectedStatus),
      ],
      updates: {db.runs},
    );

    return updated > 0;
  }

  // ... остальные методы
}
```

---

### Вариант 2: Удалённое хранилище (через Data Layer)

```dart
import 'package:aq_graph_engine/aq_graph_engine.dart';
import 'package:dart_vault/dart_vault.dart';

class VaultRunRepository implements IRunRepository {
  final Vault vault;

  VaultRunRepository(this.vault);

  @override
  Future<void> createRun({
    required String runId,
    required String projectId,
    required Map<String, dynamic> graphSnapshot,
  }) async {
    await vault.direct<GraphRun>(
      collection: 'graph_runs',
      fromMap: GraphRun.fromMap,
    ).save(
      GraphRun(
        id: runId,
        projectId: projectId,
        status: 'queued',
        graphSnapshot: graphSnapshot,
        logs: [],
        createdAt: DateTime.now(),
      ),
    );
  }

  @override
  Future<Map<String, dynamic>?> getRun(String runId) async {
    final run = await vault.direct<GraphRun>(
      collection: 'graph_runs',
      fromMap: GraphRun.fromMap,
    ).get(runId);

    if (run == null) return null;

    return run.toMap();
  }

  // ... остальные методы
}
```

---

### Вариант 3: In-memory (для тестов)

```dart
import 'package:aq_graph_engine/aq_graph_engine.dart';

class InMemoryRunRepository implements IRunRepository {
  final Map<String, Map<String, dynamic>> _runs = {};

  @override
  Future<void> createRun({
    required String runId,
    required String projectId,
    required Map<String, dynamic> graphSnapshot,
  }) async {
    _runs[runId] = {
      'id': runId,
      'projectId': projectId,
      'status': 'queued',
      'graphSnapshot': graphSnapshot,
      'logs': <String>[],
      'createdAt': DateTime.now().toIso8601String(),
    };
  }

  @override
  Future<Map<String, dynamic>?> getRun(String runId) async {
    return _runs[runId];
  }

  @override
  Future<void> updateRunLog(
    String runId,
    List<String> logs, {
    String? status,
  }) async {
    final run = _runs[runId];
    if (run == null) return;

    final existingLogs = run['logs'] as List<String>;
    existingLogs.addAll(logs);

    if (status != null) {
      run['status'] = status;
    }
  }

  // ... остальные методы
}
```

---

## 🎯 Использование в приложении

### Инициализация GraphEngine

```dart
import 'package:aq_graph_engine/server.dart';

void main() async {
  // 1. Создать реализации интерфейсов
  final runRepo = DriftRunRepository(database);
  final graphRepo = VaultGraphRepository(vault);

  // 2. Создать движок
  final engine = GraphEngine(
    tools: AQToolService.instance,
    runRepo: runRepo,      // ← Ваша реализация
    graphRepo: graphRepo,  // ← Ваша реализация
    mode: GraphEngineMode.local,
  );

  // 3. Запустить граф
  final events = engine.run(GraphRunRequest(
    runId: 'run-123',
    blueprintId: 'workflow-456',
    projectId: 'project-789',
  ));

  await for (final event in events) {
    print('Event: ${event.type}');
  }
}
```

---

### Использование клиента

```dart
import 'package:aq_graph_engine/aq_graph_engine.dart';

void main() async {
  // Клиент НЕ нуждается в реализации репозиториев
  // Он работает через HTTP с сервером

  final client = GraphEngineClient(
    serverUrl: 'http://localhost:8080',
  );

  final events = client.run(GraphRunRequest(
    runId: 'run-123',
    blueprintId: 'workflow-456',
    projectId: 'project-789',
  ));

  await for (final event in events) {
    if (event.type == GraphRunEventType.userInputRequired) {
      final input = await showDialog(...);
      await client.resumeWithInput(input);
    }
  }
}
```

---

## 📊 Итоговая таблица интерфейсов

| Интерфейс | Методов | Обязательно | Используется в |
|-----------|---------|-------------|----------------|
| **IRunRepository** | 11 | ✅ Да | Сервер (GraphEngine) |
| **IGraphRepository** | 1 | ✅ Да | Сервер (GraphEngine) |

**Важно:** Клиент (Flutter приложение) **НЕ реализует** эти интерфейсы. Он работает через HTTP с сервером, который уже имеет реализации.

---

## ✅ Чек-лист для интеграции

### Для серверного приложения (worker):

- [ ] Реализовать `IRunRepository` (11 методов)
- [ ] Реализовать `IGraphRepository` (1 метод)
- [ ] Создать `GraphEngine` с вашими реализациями
- [ ] Запустить HTTP сервер (опционально)

### Для клиентского приложения (Flutter):

- [ ] Создать `GraphEngineClient` с URL сервера
- [ ] Использовать `client.run()` для запуска графов
- [ ] Обрабатывать события (userInput, progress, completed)
- [ ] **НЕ реализовывать** репозитории (это делает сервер)

---

## 📚 Дополнительные интерфейсы из aq_schema

Помимо интерфейсов из `aq_graph_engine`, приложение может использовать интерфейсы из `aq_schema`:

### AQToolService (из aq_schema)

```dart
abstract class AQToolService {
  static AQToolService get instance;

  Future<ToolCallResponse> callTool(
    String toolName,
    Map<String, dynamic> payload,
    RunContext context,
  );
}
```

**Используется:** Для вызова инструментов (LLM, Git, File operations)

---

### AQAuthClient (из aq_schema)

```dart
abstract class AQAuthClient {
  Future<bool> verifyToken(String token);
  Future<AQApiKeyClaims?> validateApiKey(String apiKey);
}
```

**Используется:** Для авторизации запросов к GraphEngine

---

## 🎯 Заключение

Для интеграции `aq_graph_engine` в приложение нужно:

1. **Серверная часть:** Реализовать 2 интерфейса (IRunRepository, IGraphRepository)
2. **Клиентская часть:** Использовать готовый GraphEngineClient

Все интерфейсы экспортируются в клиентской части пакета и доступны через:

```dart
import 'package:aq_graph_engine/aq_graph_engine.dart';
```

**Принцип "Тонкого клиента" соблюдён:** Клиент не реализует бизнес-логику, только использует готовые API.
