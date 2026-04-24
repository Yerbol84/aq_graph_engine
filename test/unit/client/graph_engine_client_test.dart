// Unit тесты для GraphEngineClient

import 'package:test/test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'dart:convert';
import 'package:aq_schema/aq_schema.dart';
import 'package:aq_graph_engine/aq_graph_engine.dart';

void main() {
  group('GraphEngineClient', () {
    late GraphEngineClient client;
    late MockClient mockHttpClient;

    setUp(() {
      mockHttpClient = MockClient((request) async {
        return http.Response('{}', 200);
      });

      client = GraphEngineClient(
        baseUrl: 'http://localhost:8080',
        httpClient: mockHttpClient,
      );
    });

    tearDown(() {
      client.close();
    });

    group('startRun', () {
      test('отправляет POST запрос с правильными параметрами', () async {
        mockHttpClient = MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.toString(), 'http://localhost:8080/api/v1/runs');
          expect(request.headers['Content-Type'], 'application/json');

          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['blueprintId'], 'bp-1');
          expect(body['projectId'], 'proj-1');

          return http.Response(
            jsonEncode({
              'runId': 'run-123',
              'status': 'started',
              'eventsUrl': '/api/v1/runs/run-123/events',
              'wsUrl': '/api/v1/runs/run-123/ws',
            }),
            200,
          );
        });

        client = GraphEngineClient(
          baseUrl: 'http://localhost:8080',
          httpClient: mockHttpClient,
        );

        final request = GraphRunRequest(
          runId: 'run-123',
          blueprintId: 'bp-1',
          projectId: 'proj-1',
          projectPath: '',
        );

        final response = await client.startRun(request);

        expect(response.runId, 'run-123');
        expect(response.status, 'started');
        expect(response.wsUrl, '/api/v1/runs/run-123/ws');
      });

      test('выбрасывает GraphEngineValidationException при 400', () async {
        mockHttpClient = MockClient((request) async {
          return http.Response(
            jsonEncode({
              'error': 'Missing blueprintId',
              'code': 'VALIDATION_ERROR',
            }),
            400,
          );
        });

        client = GraphEngineClient(
          baseUrl: 'http://localhost:8080',
          httpClient: mockHttpClient,
        );

        final request = GraphRunRequest(
          runId: 'run-456',
          blueprintId: '',
          projectId: 'proj-1',
          projectPath: '',
        );

        expect(
          () => client.startRun(request),
          throwsA(isA<GraphEngineValidationException>()),
        );
      });

      test('выбрасывает GraphEngineUnauthorizedException при 401', () async {
        mockHttpClient = MockClient((request) async {
          return http.Response(
            jsonEncode({'error': 'Unauthorized'}),
            401,
          );
        });

        client = GraphEngineClient(
          baseUrl: 'http://localhost:8080',
          httpClient: mockHttpClient,
        );

        final request = GraphRunRequest(
          runId: 'run-123',
          blueprintId: 'bp-1',
          projectId: 'proj-1',
          projectPath: '',
        );

        expect(
          () => client.startRun(request),
          throwsA(isA<GraphEngineUnauthorizedException>()),
        );
      });

      test('выбрасывает GraphEngineServerException при 500', () async {
        mockHttpClient = MockClient((request) async {
          return http.Response(
            jsonEncode({'error': 'Internal server error'}),
            500,
          );
        });

        client = GraphEngineClient(
          baseUrl: 'http://localhost:8080',
          httpClient: mockHttpClient,
        );

        final request = GraphRunRequest(
          runId: 'run-123',
          blueprintId: 'bp-1',
          projectId: 'proj-1',
          projectPath: '',
        );

        expect(
          () => client.startRun(request),
          throwsA(isA<GraphEngineServerException>()),
        );
      });
    });

    group('getStatus', () {
      test('отправляет GET запрос и парсит ответ', () async {
        mockHttpClient = MockClient((request) async {
          expect(request.method, 'GET');
          expect(
            request.url.toString(),
            'http://localhost:8080/api/v1/runs/run-123/status',
          );

          return http.Response(
            jsonEncode({
              'runId': 'run-123',
              'status': 'running',
              'currentNodeId': 'node-1',
              'startedAt': '2026-04-08T06:00:00.000Z',
            }),
            200,
          );
        });

        client = GraphEngineClient(
          baseUrl: 'http://localhost:8080',
          httpClient: mockHttpClient,
        );

        final response = await client.getStatus('run-123');

        expect(response.runId, 'run-123');
        expect(response.status, GraphRunStatus.running);
        expect(response.currentNodeId, 'node-1');
        expect(response.startedAt, isNotNull);
      });

      test('выбрасывает GraphEngineNotFoundException при 404', () async {
        mockHttpClient = MockClient((request) async {
          return http.Response(
            jsonEncode({'error': 'Run not found'}),
            404,
          );
        });

        client = GraphEngineClient(
          baseUrl: 'http://localhost:8080',
          httpClient: mockHttpClient,
        );

        expect(
          () => client.getStatus('non-existent'),
          throwsA(isA<GraphEngineNotFoundException>()),
        );
      });
    });

    group('cancelRun', () {
      test('отправляет DELETE запрос', () async {
        mockHttpClient = MockClient((request) async {
          expect(request.method, 'DELETE');
          expect(
            request.url.toString(),
            'http://localhost:8080/api/v1/runs/run-123',
          );

          return http.Response('', 200);
        });

        client = GraphEngineClient(
          baseUrl: 'http://localhost:8080',
          httpClient: mockHttpClient,
        );

        await client.cancelRun('run-123');
      });
    });

    group('resumeRun', () {
      test('отправляет POST запрос с input', () async {
        mockHttpClient = MockClient((request) async {
          expect(request.method, 'POST');
          expect(
            request.url.toString(),
            'http://localhost:8080/api/v1/runs/run-123/resume',
          );

          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['input'], {'answer': 'yes'});

          return http.Response('', 200);
        });

        client = GraphEngineClient(
          baseUrl: 'http://localhost:8080',
          httpClient: mockHttpClient,
        );

        await client.resumeRun('run-123', {'answer': 'yes'});
      });
    });

    group('connectToRun', () {
      test('создаёт GraphRunStream с правильным URL', () {
        final stream = client.connectToRun('run-123');

        expect(stream.runId, 'run-123');
        expect(
          stream.wsUrl,
          'ws://localhost:8080/api/v1/runs/run-123/ws',
        );
      });

      test('конвертирует https в wss', () {
        client = GraphEngineClient(
          baseUrl: 'https://example.com',
          httpClient: mockHttpClient,
        );

        final stream = client.connectToRun('run-123');

        expect(
          stream.wsUrl,
          'wss://example.com/api/v1/runs/run-123/ws',
        );
      });
    });

    group('defaultHeaders', () {
      test('добавляет default headers к запросам', () async {
        mockHttpClient = MockClient((request) async {
          expect(request.headers['X-API-Key'], 'test-key');
          expect(request.headers['X-Custom'], 'value');

          return http.Response(
            jsonEncode({
              'runId': 'run-123',
              'status': 'started',
              'eventsUrl': '/api/v1/runs/run-123/events',
              'wsUrl': '/api/v1/runs/run-123/ws',
            }),
            200,
          );
        });

        client = GraphEngineClient(
          baseUrl: 'http://localhost:8080',
          httpClient: mockHttpClient,
          defaultHeaders: {
            'X-API-Key': 'test-key',
            'X-Custom': 'value',
          },
        );

        final request = GraphRunRequest(
          runId: 'run-123',
          blueprintId: 'bp-1',
          projectId: 'proj-1',
          projectPath: '',
        );

        await client.startRun(request);
      });
    });
  });
}
