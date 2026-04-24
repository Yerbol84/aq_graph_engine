// E2E тесты для Graph Engine в Docker
//
// Проверяет полный стек в изолированном окружении:
// - PostgreSQL в контейнере
// - Data Service в контейнере
// - Graph Engine в контейнере
// - Тесты запускаются в отдельном контейнере
//
// Это имитирует production окружение

import 'dart:io';
import 'dart:convert';
import 'package:test/test.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Конфигурация из переменных окружения
class E2EConfig {
  static String get dataServiceUrl =>
      Platform.environment['DATA_SERVICE_URL'] ?? 'http://localhost:8765';

  static String get graphEngineUrl =>
      Platform.environment['GRAPH_ENGINE_URL'] ?? 'http://localhost:8081';

  static String get postgresHost =>
      Platform.environment['POSTGRES_HOST'] ?? 'localhost';

  static int get postgresPort =>
      int.parse(Platform.environment['POSTGRES_PORT'] ?? '5432');

  static String get postgresDb =>
      Platform.environment['POSTGRES_DB'] ?? 'aq_test';

  static String get postgresUser =>
      Platform.environment['POSTGRES_USER'] ?? 'aq_test';

  static String get postgresPassword =>
      Platform.environment['POSTGRES_PASSWORD'] ?? 'aq_test_secret';

  static const String testTenantId = 'e2e_test';
}

void main() {
  late http.Client client;

  setUpAll(() async {
    client = http.Client();

    // Дождаться готовности сервисов
    print('Waiting for services to be ready...');
    await _waitForService(E2EConfig.dataServiceUrl, '/health');
    await _waitForService(E2EConfig.graphEngineUrl, '/health');
    print('All services are ready!');
  });

  tearDownAll(() {
    client.close();
  });

  group('E2E - Full Stack in Docker', () {
    test('Health checks: все сервисы доступны', () async {
      // Проверить Data Service
      final dataServiceHealth = await client.get(
        Uri.parse('${E2EConfig.dataServiceUrl}/health'),
      );
      expect(dataServiceHealth.statusCode, 200);

      // Проверить Graph Engine
      final graphEngineHealth = await client.get(
        Uri.parse('${E2EConfig.graphEngineUrl}/health'),
      );
      expect(graphEngineHealth.statusCode, 200);

      print('✅ All services are healthy');
    });

    test('E2E: Создание и выполнение простого workflow через API', () async {
      final projectId = _uuid.v4();
      final workflowId = _uuid.v4();
      final runId = _uuid.v4();

      // 1. Создать проект через Data Service API
      final createProjectResponse = await client.post(
        Uri.parse('${E2EConfig.dataServiceUrl}/api/projects'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'id': projectId,
          'tenantId': E2EConfig.testTenantId,
          'ownerId': E2EConfig.testTenantId,
          'name': 'E2E Test Project',
          'projectType': 'test',
          'path': '/tmp/e2e_test',
          'lastOpened': DateTime.now().toIso8601String(),
        }),
      );

      expect(
        createProjectResponse.statusCode,
        anyOf([200, 201]),
        reason: 'Project creation should succeed',
      );

      print('✅ Project created: $projectId');

      // 2. Создать workflow через Data Service API
      final createWorkflowResponse = await client.post(
        Uri.parse('${E2EConfig.dataServiceUrl}/api/workflows'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'id': workflowId,
          'tenantId': E2EConfig.testTenantId,
          'ownerId': projectId,
          'name': 'E2E Test Workflow',
          'nodes': {
            'node1': {
              'id': 'node1',
              'type': 'fileWrite',
              'config': {
                'file_path': '/tmp/e2e_output.txt',
                'content': 'E2E Test Success',
              },
            },
          },
          'edges': {},
        }),
      );

      expect(
        createWorkflowResponse.statusCode,
        anyOf([200, 201]),
        reason: 'Workflow creation should succeed',
      );

      print('✅ Workflow created: $workflowId');

      // 3. Запустить workflow через Graph Engine API
      final runWorkflowResponse = await client.post(
        Uri.parse('${E2EConfig.graphEngineUrl}/api/runs'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'runId': runId,
          'projectId': projectId,
          'blueprintId': workflowId,
          'projectPath': '/tmp',
        }),
      );

      expect(
        runWorkflowResponse.statusCode,
        anyOf([200, 201, 202]),
        reason: 'Run should be accepted',
      );

      print('✅ Workflow run started: $runId');

      // 4. Подождать завершения (polling)
      var completed = false;
      var attempts = 0;
      const maxAttempts = 30; // 30 секунд

      while (!completed && attempts < maxAttempts) {
        await Future.delayed(Duration(seconds: 1));
        attempts++;

        final statusResponse = await client.get(
          Uri.parse('${E2EConfig.graphEngineUrl}/api/runs/$runId'),
        );

        if (statusResponse.statusCode == 200) {
          final status = jsonDecode(statusResponse.body);
          print('Run status: ${status['status']} (attempt $attempts)');

          if (status['status'] == 'completed') {
            completed = true;
            print('✅ Workflow completed successfully');
          } else if (status['status'] == 'failed') {
            fail('Workflow failed: ${status['errorMessage']}');
          }
        }
      }

      expect(completed, true, reason: 'Workflow should complete within 30 seconds');

      // 5. Проверить результат в БД через Data Service API
      final runStateResponse = await client.get(
        Uri.parse('${E2EConfig.dataServiceUrl}/api/runs/$runId'),
      );

      expect(runStateResponse.statusCode, 200);

      final runState = jsonDecode(runStateResponse.body);
      expect(runState['status'], 'completed');
      expect(runState['projectId'], projectId);
      expect(runState['blueprintId'], workflowId);

      print('✅ Run state verified in database');
    }, timeout: Timeout(Duration(minutes: 2)));

    test('E2E: Параллельное выполнение через API', () async {
      final projectId = _uuid.v4();
      final workflowId = _uuid.v4();
      final runId = _uuid.v4();

      // 1. Создать проект
      await client.post(
        Uri.parse('${E2EConfig.dataServiceUrl}/api/projects'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'id': projectId,
          'tenantId': E2EConfig.testTenantId,
          'ownerId': E2EConfig.testTenantId,
          'name': 'E2E Parallel Test',
          'projectType': 'test',
          'path': '/tmp/e2e_parallel',
          'lastOpened': DateTime.now().toIso8601String(),
        }),
      );

      // 2. Создать workflow с параллельными ветками
      await client.post(
        Uri.parse('${E2EConfig.dataServiceUrl}/api/workflows'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'id': workflowId,
          'tenantId': E2EConfig.testTenantId,
          'ownerId': projectId,
          'name': 'E2E Parallel Workflow',
          'nodes': {
            'start': {
              'id': 'start',
              'type': 'fileWrite',
              'config': {
                'file_path': '/tmp/start.txt',
                'content': 'Start',
              },
            },
            'branch1': {
              'id': 'branch1',
              'type': 'fileWrite',
              'config': {
                'file_path': '/tmp/branch1.txt',
                'content': 'Branch 1',
              },
            },
            'branch2': {
              'id': 'branch2',
              'type': 'fileWrite',
              'config': {
                'file_path': '/tmp/branch2.txt',
                'content': 'Branch 2',
              },
            },
          },
          'edges': {
            'edge1': {
              'id': 'edge1',
              'sourceId': 'start',
              'targetId': 'branch1',
              'branchName': 'branch_a',
              'type': 'onSuccess',
            },
            'edge2': {
              'id': 'edge2',
              'sourceId': 'start',
              'targetId': 'branch2',
              'branchName': 'branch_b',
              'type': 'onSuccess',
            },
          },
        }),
      );

      // 3. Запустить
      await client.post(
        Uri.parse('${E2EConfig.graphEngineUrl}/api/runs'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'runId': runId,
          'projectId': projectId,
          'blueprintId': workflowId,
          'projectPath': '/tmp',
        }),
      );

      // 4. Дождаться завершения
      await _waitForRunCompletion(client, runId);

      // 5. Проверить что все узлы выполнились
      final runStateResponse = await client.get(
        Uri.parse('${E2EConfig.dataServiceUrl}/api/runs/$runId'),
      );

      final runState = jsonDecode(runStateResponse.body);
      expect(runState['status'], 'completed');

      // Проверить логи
      final logs = runState['logsJson'] as String?;
      expect(logs, isNotNull);
      expect(logs!.contains('start'), true);
      expect(logs.contains('branch1'), true);
      expect(logs.contains('branch2'), true);

      print('✅ Parallel execution verified');
    }, timeout: Timeout(Duration(minutes: 2)));

    test('E2E: Обработка ошибок через API', () async {
      final projectId = _uuid.v4();
      final workflowId = _uuid.v4();
      final runId = _uuid.v4();

      // 1. Создать проект
      await client.post(
        Uri.parse('${E2EConfig.dataServiceUrl}/api/projects'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'id': projectId,
          'tenantId': E2EConfig.testTenantId,
          'ownerId': E2EConfig.testTenantId,
          'name': 'E2E Error Test',
          'projectType': 'test',
          'path': '/tmp/e2e_error',
          'lastOpened': DateTime.now().toIso8601String(),
        }),
      );

      // 2. Создать workflow с узлом который упадёт
      await client.post(
        Uri.parse('${E2EConfig.dataServiceUrl}/api/workflows'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'id': workflowId,
          'tenantId': E2EConfig.testTenantId,
          'ownerId': projectId,
          'name': 'E2E Error Workflow',
          'nodes': {
            'failing_node': {
              'id': 'failing_node',
              'type': 'fileRead',
              'config': {
                'file_path': '/nonexistent/file.txt',
                'output_var': 'content',
              },
            },
          },
          'edges': {},
        }),
      );

      // 3. Запустить
      await client.post(
        Uri.parse('${E2EConfig.graphEngineUrl}/api/runs'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'runId': runId,
          'projectId': projectId,
          'blueprintId': workflowId,
          'projectPath': '/tmp',
        }),
      );

      // 4. Дождаться завершения (с ошибкой)
      var failed = false;
      var attempts = 0;
      const maxAttempts = 30;

      while (!failed && attempts < maxAttempts) {
        await Future.delayed(Duration(seconds: 1));
        attempts++;

        final statusResponse = await client.get(
          Uri.parse('${E2EConfig.graphEngineUrl}/api/runs/$runId'),
        );

        if (statusResponse.statusCode == 200) {
          final status = jsonDecode(statusResponse.body);

          if (status['status'] == 'failed') {
            failed = true;
            print('✅ Workflow failed as expected');
          }
        }
      }

      expect(failed, true, reason: 'Workflow should fail');

      // 5. Проверить errorMessage в БД
      final runStateResponse = await client.get(
        Uri.parse('${E2EConfig.dataServiceUrl}/api/runs/$runId'),
      );

      final runState = jsonDecode(runStateResponse.body);
      expect(runState['status'], 'failed');
      expect(runState['errorMessage'], isNotNull);
      expect(runState['errorMessage'], isNotEmpty);

      print('✅ Error handling verified');
    }, timeout: Timeout(Duration(minutes: 2)));
  });
}

/// Дождаться готовности сервиса
Future<void> _waitForService(String baseUrl, String healthPath) async {
  const maxAttempts = 60; // 60 секунд
  var attempts = 0;

  while (attempts < maxAttempts) {
    try {
      final response = await http.get(Uri.parse('$baseUrl$healthPath'));
      if (response.statusCode == 200) {
        print('✅ Service ready: $baseUrl');
        return;
      }
    } catch (e) {
      // Сервис ещё не готов
    }

    await Future.delayed(Duration(seconds: 1));
    attempts++;
  }

  throw Exception('Service $baseUrl did not become ready in time');
}

/// Дождаться завершения run
Future<void> _waitForRunCompletion(http.Client client, String runId) async {
  var completed = false;
  var attempts = 0;
  const maxAttempts = 30;

  while (!completed && attempts < maxAttempts) {
    await Future.delayed(Duration(seconds: 1));
    attempts++;

    final statusResponse = await client.get(
      Uri.parse('${E2EConfig.graphEngineUrl}/api/runs/$runId'),
    );

    if (statusResponse.statusCode == 200) {
      final status = jsonDecode(statusResponse.body);

      if (status['status'] == 'completed') {
        completed = true;
      } else if (status['status'] == 'failed') {
        throw Exception('Run failed: ${status['errorMessage']}');
      }
    }
  }

  if (!completed) {
    throw Exception('Run did not complete in time');
  }
}
