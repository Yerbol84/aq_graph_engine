// Unit тесты для моделей клиента

import 'package:test/test.dart';
import 'package:aq_schema/aq_schema.dart';
import 'package:aq_graph_engine/aq_graph_engine.dart';

void main() {
  group('GraphRunResponse', () {
    test('fromJson парсит корректно', () {
      final json = {
        'runId': 'run-123',
        'status': 'started',
        'eventsUrl': '/api/v1/runs/run-123/events',
        'wsUrl': '/api/v1/runs/run-123/ws',
      };

      final response = GraphRunResponse.fromJson(json);

      expect(response.runId, 'run-123');
      expect(response.status, 'started');
      expect(response.eventsUrl, '/api/v1/runs/run-123/events');
      expect(response.wsUrl, '/api/v1/runs/run-123/ws');
    });

    test('toJson сериализует корректно', () {
      final response = GraphRunResponse(
        runId: 'run-123',
        status: 'started',
        eventsUrl: '/api/v1/runs/run-123/events',
        wsUrl: '/api/v1/runs/run-123/ws',
      );

      final json = response.toJson();

      expect(json['runId'], 'run-123');
      expect(json['status'], 'started');
      expect(json['eventsUrl'], '/api/v1/runs/run-123/events');
      expect(json['wsUrl'], '/api/v1/runs/run-123/ws');
    });
  });

  group('GraphRunStatusResponse', () {
    test('fromJson парсит минимальный ответ', () {
      final json = {
        'runId': 'run-123',
        'status': 'running',
      };

      final response = GraphRunStatusResponse.fromJson(json);

      expect(response.runId, 'run-123');
      expect(response.status, GraphRunStatus.running);
      expect(response.currentNodeId, isNull);
      expect(response.startedAt, isNull);
      expect(response.completedAt, isNull);
      expect(response.error, isNull);
    });

    test('fromJson парсит полный ответ', () {
      final json = {
        'runId': 'run-123',
        'status': 'completed',
        'currentNodeId': 'node-5',
        'startedAt': '2026-04-08T06:00:00.000Z',
        'completedAt': '2026-04-08T06:05:00.000Z',
      };

      final response = GraphRunStatusResponse.fromJson(json);

      expect(response.runId, 'run-123');
      expect(response.status, GraphRunStatus.completed);
      expect(response.currentNodeId, 'node-5');
      expect(response.startedAt, isNotNull);
      expect(response.completedAt, isNotNull);
    });

    test('fromJson парсит ответ с ошибкой', () {
      final json = {
        'runId': 'run-123',
        'status': 'failed',
        'error': 'Node execution failed',
      };

      final response = GraphRunStatusResponse.fromJson(json);

      expect(response.runId, 'run-123');
      expect(response.status, GraphRunStatus.failed);
      expect(response.error, 'Node execution failed');
    });

    test('toJson сериализует минимальный объект', () {
      final response = GraphRunStatusResponse(
        runId: 'run-123',
        status: GraphRunStatus.running,
      );

      final json = response.toJson();

      expect(json['runId'], 'run-123');
      expect(json['status'], 'running');
      expect(json.containsKey('currentNodeId'), false);
      expect(json.containsKey('startedAt'), false);
      expect(json.containsKey('completedAt'), false);
      expect(json.containsKey('error'), false);
    });

    test('toJson сериализует полный объект', () {
      final startedAt = DateTime.parse('2026-04-08T06:00:00.000Z');
      final completedAt = DateTime.parse('2026-04-08T06:05:00.000Z');

      final response = GraphRunStatusResponse(
        runId: 'run-123',
        status: GraphRunStatus.completed,
        currentNodeId: 'node-5',
        startedAt: startedAt,
        completedAt: completedAt,
        error: null,
      );

      final json = response.toJson();

      expect(json['runId'], 'run-123');
      expect(json['status'], 'completed');
      expect(json['currentNodeId'], 'node-5');
      expect(json['startedAt'], '2026-04-08T06:00:00.000Z');
      expect(json['completedAt'], '2026-04-08T06:05:00.000Z');
    });

    test('roundtrip fromJson -> toJson сохраняет данные', () {
      final original = {
        'runId': 'run-123',
        'status': 'suspended',
        'currentNodeId': 'node-3',
        'startedAt': '2026-04-08T06:00:00.000Z',
      };

      final response = GraphRunStatusResponse.fromJson(original);
      final json = response.toJson();

      expect(json['runId'], original['runId']);
      expect(json['status'], original['status']);
      expect(json['currentNodeId'], original['currentNodeId']);
      expect(json['startedAt'], original['startedAt']);
    });

    test('парсит все статусы GraphRunStatus', () {
      final statuses = [
        'queued',
        'running',
        'suspended',
        'completed',
        'failed',
        'cancelled',
      ];

      for (final status in statuses) {
        final json = {
          'runId': 'run-123',
          'status': status,
        };

        final response = GraphRunStatusResponse.fromJson(json);
        expect(response.status.toString().split('.').last, status);
      }
    });
  });
}
