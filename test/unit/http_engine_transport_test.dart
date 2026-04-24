// Тесты для HttpEngineTransport

import 'package:test/test.dart';
import 'package:aq_graph_engine/aq_graph_engine.dart';
import 'package:aq_schema/aq_schema.dart';

void main() {
  group('HttpEngineTransport', () {
    test('создаётся с корректными параметрами', () {
      final transport = HttpEngineTransport(
        serverUrl: 'http://localhost:8081',
        timeout: const Duration(seconds: 10),
        maxRetries: 5,
      );

      expect(transport, isNotNull);
    });

    test('isAvailable возвращает false для недоступного сервера', () async {
      final transport = HttpEngineTransport(
        serverUrl: 'http://localhost:9999',
        timeout: const Duration(seconds: 1),
      );

      final available = await transport.isAvailable();
      expect(available, isFalse);
    });

    test('circuit breaker открывается после нескольких ошибок', () async {
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

      // После 5 ошибок circuit breaker должен открыться
      // Следующий запрос должен сразу вернуть ошибку
      final request = GraphRunRequest(
        runId: 'test-circuit',
        projectId: 'test-project',
        projectPath: '/test',
        blueprintId: 'test-blueprint',
      );

      final events = transport.run(request);
      final firstEvent = await events.first;

      expect(firstEvent.type, equals(GraphRunEventType.error));
      expect(
        firstEvent.errorMessage,
        contains('Circuit breaker is open'),
      );
    });
  });

  group('GraphEngine modes', () {
    test('создаётся в режиме local по умолчанию', () {
      final engine = GraphEngine(
        tools: _createMockTools(),
        runRepo: _createMockRunRepo(),
        graphRepo: _createMockGraphRepo(),
      );

      expect(engine.mode, equals(GraphEngineMode.local));
    });

    test('создаётся в режиме remote с URL', () {
      final engine = GraphEngine(
        tools: _createMockTools(),
        runRepo: _createMockRunRepo(),
        graphRepo: _createMockGraphRepo(),
        mode: GraphEngineMode.remote,
        remoteServerUrl: 'http://localhost:8081',
      );

      expect(engine.mode, equals(GraphEngineMode.remote));
    });

    test('бросает ошибку если remote без URL', () {
      expect(
        () => GraphEngine(
          tools: _createMockTools(),
          runRepo: _createMockRunRepo(),
          graphRepo: _createMockGraphRepo(),
          mode: GraphEngineMode.remote,
        ),
        throwsArgumentError,
      );
    });

    test('создаётся в режиме auto с fallback', () {
      final engine = GraphEngine(
        tools: _createMockTools(),
        runRepo: _createMockRunRepo(),
        graphRepo: _createMockGraphRepo(),
        mode: GraphEngineMode.auto,
        remoteServerUrl: 'http://localhost:8081',
      );

      expect(engine.mode, equals(GraphEngineMode.auto));
    });
  });
}

// ── Mock helpers ──────────────────────────────────────────────────────────

AQToolService _createMockTools() {
  return _MockToolService();
}

IRunRepository _createMockRunRepo() {
  return _MockRunRepository();
}

IGraphRepository _createMockGraphRepo() {
  return _MockGraphRepository();
}

class _MockToolService implements AQToolService {
  @override
  IAQLlmService get llm => throw UnimplementedError();

  @override
  IAQVaultService get vault => throw UnimplementedError();

  @override
  Future<dynamic> callTool(String toolName, Map<String, dynamic> args, RunContext ctx) async {
    return null;
  }

  @override
  bool hasTool(String toolName) => false;

  @override
  List<AQToolDescriptor> get availableTools => [];

  @override
  Future<bool> isAvailable() async => true;
}

class _MockRunRepository implements IRunRepository {
  @override
  Future<void> createRun({
    required String runId,
    required String projectId,
    required Map<String, dynamic> graphSnapshot,
  }) async {}

  @override
  Future<void> updateRunLog(String runId, List<String> logs, {String? status}) async {}

  @override
  Future<void> suspendRun({
    required String runId,
    required String contextJson,
    required String nodeId,
    required List<String> logs,
  }) async {}

  @override
  Future<Map<String, dynamic>?> getRun(String runId) async => null;
}

class _MockGraphRepository implements IGraphRepository {
  @override
  Future<dynamic> loadGraph(String blueprintId) async => null;
}
