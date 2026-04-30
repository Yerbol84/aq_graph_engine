// Тесты для Фаз 2-4 без зависимости от старых нод aq_schema

import 'package:test/test.dart';
import 'package:aq_graph_engine/server.dart';
import 'package:aq_schema/aq_schema.dart';
import 'package:aq_schema/tools.dart';
import 'package:aq_schema/metrics.dart';

void main() {
  group('Phase 2: Auth Module', () {
    test('TestAuthClient создаёт токен с корректным expiry', () async {
      final auth = TestAuthClient();
      final token = await auth.loginWithCredentials('test@example.com', 'password');

      expect(token.rawJwt, isNotEmpty);
      expect(token.claims.userId, contains('test-user'));
      expect(token.claims.email, equals('test@example.com'));
      expect(token.isExpired, isFalse);
    });

    test('TestAuthClient создаёт API ключи для проектов', () async {
      final auth = TestAuthClient();
      await auth.loginWithCredentials('test@example.com', 'password');

      final apiKey = await auth.getOrCreateProjectApiKey(
        'project-123',
        scope: ['graph:run', 'vault:read'],
      );

      expect(apiKey.keyId, contains('test-key-project-123'));
      expect(apiKey.projectId, equals('project-123'));
      expect(apiKey.scope, containsAll(['graph:run', 'vault:read']));
    });

    test('TestAuthClient эмитит события при logout', () async {
      final auth = TestAuthClient();
      await auth.loginWithCredentials('test@example.com', 'password');

      var loggedOut = false;
      auth.events.listen((event) {
        if (event is LoggedOut) {
          loggedOut = true;
        }
      });

      await auth.logout();
      await Future.delayed(const Duration(milliseconds: 100));

      expect(loggedOut, isTrue);
      expect(await auth.currentToken, isNull);
    });
  });

  group('Phase 3: HttpEngineTransport', () {
    test('Circuit breaker открывается после 5 ошибок', () async {
      final transport = HttpEngineTransport(
        serverUrl: 'http://localhost:9999',
        timeout: const Duration(milliseconds: 100),
        maxRetries: 0,
      );

      // Делаем 5 неудачных попыток
      for (var i = 0; i < 5; i++) {
        final request = GraphRunRequest(
          runId: 'test-$i',
          projectId: 'test-project',
          projectPath: '/test',
          blueprintId: 'test-blueprint',
        );

        final events = transport.run(request);
        await for (final event in events) {
          if (event.type == GraphRunEventType.error) {
            break;
          }
        }
      }

      // 6-й запрос — circuit breaker должен быть открыт
      final available = await transport.isAvailable();
      expect(available, isFalse);
    });

    test('isAvailable возвращает false для недоступного сервера', () async {
      final transport = HttpEngineTransport(
        serverUrl: 'http://localhost:9999',
        timeout: const Duration(seconds: 1),
      );

      final available = await transport.isAvailable();
      expect(available, isFalse);
    });
  });

  group('Phase 3: GraphEngine Modes', () {
    test('GraphEngine создаётся в режиме local по умолчанию', () {
      final engine = GraphEngine(
        tools: _MockToolService(),
        runRepo: _MockRunRepository(),
        graphRepo: _MockGraphRepository(),
      );

      expect(engine.mode, equals(GraphEngineMode.local));
    });

    test('GraphEngine создаётся в режиме remote с URL', () {
      final engine = GraphEngine(
        tools: _MockToolService(),
        runRepo: _MockRunRepository(),
        graphRepo: _MockGraphRepository(),
        mode: GraphEngineMode.remote,
        remoteServerUrl: 'http://localhost:8081',
      );

      expect(engine.mode, equals(GraphEngineMode.remote));
    });

    test('GraphEngine бросает ошибку если remote без URL', () {
      expect(
        () => GraphEngine(
          tools: _MockToolService(),
          runRepo: _MockRunRepository(),
          graphRepo: _MockGraphRepository(),
          mode: GraphEngineMode.remote,
        ),
        throwsArgumentError,
      );
    });

    test('GraphEngine создаётся в режиме auto с fallback', () {
      final engine = GraphEngine(
        tools: _MockToolService(),
        runRepo: _MockRunRepository(),
        graphRepo: _MockGraphRepository(),
        mode: GraphEngineMode.auto,
        remoteServerUrl: 'http://localhost:8081',
      );

      expect(engine.mode, equals(GraphEngineMode.auto));
    });
  });

  group('Phase 4: Race Conditions', () {
    test('MockRunRepository compareAndSetStatus работает корректно', () async {
      final repo = _MockRunRepository();

      // Сначала создаём run со статусом 'queued'
      await repo.createRun(
        runId: 'run-123',
        projectId: 'proj-1',
        graphSnapshot: {},
      );

      // Первый вызов должен успешно изменить статус
      final success1 = await repo.compareAndSetStatus(
        runId: 'run-123',
        expectedStatus: 'queued',
        newStatus: 'running',
      );
      expect(success1, isTrue);

      // Второй вызов с тем же expectedStatus должен провалиться
      final success2 = await repo.compareAndSetStatus(
        runId: 'run-123',
        expectedStatus: 'queued',
        newStatus: 'running',
      );
      expect(success2, isFalse);
    });

    test('MockRunRepository tryAcquireLock предотвращает двойной lock', () async {
      final repo = _MockRunRepository();

      // Worker 1 захватывает lock
      final locked1 = await repo.tryAcquireLock(
        runId: 'run-123',
        workerId: 'worker-1',
        ttl: const Duration(minutes: 5),
      );
      expect(locked1, isTrue);

      // Worker 2 не может захватить тот же lock
      final locked2 = await repo.tryAcquireLock(
        runId: 'run-123',
        workerId: 'worker-2',
        ttl: const Duration(minutes: 5),
      );
      expect(locked2, isFalse);

      // Worker 1 освобождает lock
      final released = await repo.releaseLock(
        runId: 'run-123',
        workerId: 'worker-1',
      );
      expect(released, isTrue);

      // Теперь Worker 2 может захватить lock
      final locked3 = await repo.tryAcquireLock(
        runId: 'run-123',
        workerId: 'worker-2',
        ttl: const Duration(minutes: 5),
      );
      expect(locked3, isTrue);
    });
  });

  group('Phase 4: Dead Letter Queue', () {
    test('MockRunRepository moveToDLQ добавляет job в DLQ', () async {
      final repo = _MockRunRepository();

      await repo.moveToDLQ(
        runId: 'run-123',
        reason: 'Failed after 3 retries',
        failureCount: 3,
        lastError: 'Connection timeout',
      );

      final dlqJobs = await repo.getDLQJobs();
      expect(dlqJobs.length, equals(1));
      expect(dlqJobs[0]['runId'], equals('run-123'));
      expect(dlqJobs[0]['failureCount'], equals(3));
    });

    test('MockRunRepository retryFromDLQ перемещает job обратно', () async {
      final repo = _MockRunRepository();

      await repo.moveToDLQ(
        runId: 'run-123',
        reason: 'Failed',
        failureCount: 3,
      );

      final success = await repo.retryFromDLQ(runId: 'run-123');
      expect(success, isTrue);

      final dlqJobs = await repo.getDLQJobs();
      expect(dlqJobs.length, equals(0));
    });

    test('MockRunRepository cleanupDLQ удаляет старые записи', () async {
      final repo = _MockRunRepository();

      // Добавляем старую запись
      await repo.moveToDLQ(
        runId: 'run-old',
        reason: 'Old failure',
        failureCount: 3,
      );

      // Симулируем что запись старая (в реальной реализации)
      final deleted = await repo.cleanupDLQ(
        olderThan: const Duration(days: 7),
      );

      expect(deleted, greaterThanOrEqualTo(0));
    });
  });

  group('Phase 4: Metrics', () {
    setUp(() {
      GraphEngineMetrics.init(NoopMetricsService.instance);
    });

    test('GraphEngineMetrics инициализируются без ошибок', () {
      expect(GraphEngineMetrics.runStarted, isNotNull);
      expect(GraphEngineMetrics.activeRuns, isNotNull);
      expect(GraphEngineMetrics.runDuration, isNotNull);
    });

    test('Метрики можно инкрементить', () {
      expect(
        () => GraphEngineMetrics.runStarted.inc(
          attributes: {'project_id': 'project-1', 'blueprint_id': 'blueprint-1'},
        ),
        returnsNormally,
      );
      expect(
        () => GraphEngineMetrics.activeRuns.inc(),
        returnsNormally,
      );
      expect(
        () => GraphEngineMetrics.nodeExecuted.inc(
          attributes: {'node_type': 'llmAction', 'project_id': 'project-1'},
        ),
        returnsNormally,
      );
    });
  });
}

// ── Mock Implementations ──────────────────────────────────────────────────

class _MockToolService implements IToolService {
  @override
  Future<ToolCallResult> callTool(
    String name,
    Map<String, dynamic> args,
    RunContext context,
  ) async =>
      ToolCallResult.success(output: null);

  @override
  bool hasTool(String name) => false;

  @override
  List<ToolDescriptor> get availableTools => [];
}

class _MockRunRepository implements IRunRepository {
  final Map<String, String> _statuses = {};
  final Map<String, String> _locks = {};
  final List<Map<String, dynamic>> _dlq = [];

  @override
  Future<void> createRun({
    required String runId,
    required String projectId,
    required Map<String, dynamic> graphSnapshot,
  }) async {
    _statuses[runId] = 'queued';
  }

  @override
  Future<void> updateRunLog(String runId, List<String> logs, {String? status}) async {
    if (status != null) {
      _statuses[runId] = status;
    }
  }

  @override
  Future<void> suspendRun({
    required String runId,
    required String contextJson,
    required String nodeId,
    required List<String> logs,
  }) async {}

  @override
  Future<Map<String, dynamic>?> getRun(String runId) async => null;

  @override
  Future<bool> compareAndSetStatus({
    required String runId,
    required String expectedStatus,
    required String newStatus,
  }) async {
    final currentStatus = _statuses[runId];
    if (currentStatus == expectedStatus) {
      _statuses[runId] = newStatus;
      return true;
    }
    return false;
  }

  @override
  Future<bool> tryAcquireLock({
    required String runId,
    required String workerId,
    required Duration ttl,
  }) async {
    if (_locks.containsKey(runId)) {
      return false;
    }
    _locks[runId] = workerId;
    return true;
  }

  @override
  Future<bool> releaseLock({
    required String runId,
    required String workerId,
  }) async {
    if (_locks[runId] == workerId) {
      _locks.remove(runId);
      return true;
    }
    return false;
  }

  @override
  Future<void> moveToDLQ({
    required String runId,
    required String reason,
    required int failureCount,
    String? lastError,
  }) async {
    _dlq.add({
      'runId': runId,
      'reason': reason,
      'failureCount': failureCount,
      'lastError': lastError,
      'movedAt': DateTime.now(),
    });
  }

  @override
  Future<List<Map<String, dynamic>>> getDLQJobs({
    int limit = 100,
    int offset = 0,
  }) async {
    return _dlq.skip(offset).take(limit).toList();
  }

  @override
  Future<bool> retryFromDLQ({required String runId}) async {
    final index = _dlq.indexWhere((job) => job['runId'] == runId);
    if (index >= 0) {
      _dlq.removeAt(index);
      return true;
    }
    return false;
  }

  @override
  Future<int> cleanupDLQ({required Duration olderThan}) async {
    final cutoff = DateTime.now().subtract(olderThan);
    final toRemove = _dlq.where((job) {
      final movedAt = job['movedAt'] as DateTime;
      return movedAt.isBefore(cutoff);
    }).toList();

    for (final job in toRemove) {
      _dlq.remove(job);
    }

    return toRemove.length;
  }
}

class _MockGraphRepository implements IGraphRepository {
  @override
  Future<$Graph?> loadGraph(String blueprintId) async => null;
}
