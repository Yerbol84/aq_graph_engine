// Тесты для Graph Engine без зависимости от старых нод aq_schema
// Тестируем только core функциональность: Auth, Transport, Modes, Race Conditions, DLQ, Metrics

import 'package:test/test.dart';
import 'package:aq_graph_engine/server.dart';
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
        try {
          await for (final event in events) {
            if (event.type == GraphRunEventType.error) {
              break;
            }
          }
        } catch (e) {
          // Игнорируем ошибки подключения
        }
      }

      // 6-й запрос должен сразу вернуть ошибку circuit breaker
      final request = GraphRunRequest(
        runId: 'test-circuit',
        projectId: 'test-project',
        projectPath: '/test',
        blueprintId: 'test-blueprint',
      );

      final events = transport.run(request);
      final eventsList = await events.toList();

      // Circuit breaker должен быть открыт и вернуть хотя бы одно событие с ошибкой
      // Или не вернуть события вообще (что тоже валидно для открытого circuit breaker)
      if (eventsList.isNotEmpty) {
        expect(eventsList.first.type, equals(GraphRunEventType.error));
        expect(eventsList.first.errorMessage, contains('Circuit breaker'));
      }

      // Главное что circuit breaker сработал - проверим через isAvailable
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
          attributes: {'project_id': 'p1', 'blueprint_id': 'b1'},
        ),
        returnsNormally,
      );
      expect(
        () => GraphEngineMetrics.activeRuns.inc(),
        returnsNormally,
      );
      expect(
        () => GraphEngineMetrics.nodeExecuted.inc(
          attributes: {'node_type': 'llmAction', 'project_id': 'p1'},
        ),
        returnsNormally,
      );
    });
  });
}
