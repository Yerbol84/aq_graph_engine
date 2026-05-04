// Интеграционный тест DataLayerRunRepository.
// Требует запущенного Data Service (dart_vault server).
// Запуск: DATA_SERVICE_URL=http://localhost:8765 dart test test/integration/
//
// Без сервера тесты пропускаются автоматически.

import 'package:test/test.dart';
import 'package:dart_vault/dart_vault.dart';
import 'package:aq_schema/aq_schema.dart';
import 'package:aq_graph_engine/server.dart';

void main() {
  final dataServiceUrl = const String.fromEnvironment(
    'DATA_SERVICE_URL',
    defaultValue: '',
  );

  if (dataServiceUrl.isEmpty) {
    test('DataLayerRunRepository integration tests', () {}, skip:
        'Set DATA_SERVICE_URL env var to run integration tests. '
        'Example: DATA_SERVICE_URL=http://localhost:8765 dart test test/integration/');
    return;
  }

  setUpAll(() async {
    await initializeDataLayer(endpoint: dataServiceUrl, useBuffer: false);
  });

  group('DataLayerRunRepository', () {
    late DataLayerRunRepository repo;

    setUp(() {
      repo = DataLayerRunRepository();
    });

    test('createRun и getRun возвращают корректный run', () async {
      final run = WorkflowRun(
        id: 'run-integ-1',
        projectId: 'proj-1',
        blueprintId: 'bp-1',
        graphSnapshot: const {},
        status: WorkflowRunStatus.running,
        logsJson: '[]',
        createdAt: DateTime.now(),
      );
      await repo.createRun(run);

      final found = await repo.getRun('run-integ-1');
      expect(found, isNotNull);
      expect(found!.status, WorkflowRunStatus.running);
    });

    test('updateRunLog guard — пустой список без статуса не делает write', () async {
      final run = WorkflowRun(
        id: 'run-integ-2',
        projectId: 'proj-1',
        blueprintId: 'bp-1',
        graphSnapshot: const {},
        status: WorkflowRunStatus.running,
        logsJson: '[]',
        createdAt: DateTime.now(),
      );
      await repo.createRun(run);
      await repo.updateRunLog('run-integ-2', []);

      final found = await repo.getRun('run-integ-2');
      expect(found!.logsJson, '[]');
    });

    test('suspendRun не дублирует логи', () async {
      final run = WorkflowRun(
        id: 'run-integ-3',
        projectId: 'proj-1',
        blueprintId: 'bp-1',
        graphSnapshot: const {},
        status: WorkflowRunStatus.running,
        logsJson: '[]',
        createdAt: DateTime.now(),
      );
      await repo.createRun(run);
      await repo.updateRunLog('run-integ-3', ['log1', 'log2']);

      await repo.suspendRun(
        runId: 'run-integ-3',
        contextJson: '{"state":"test"}',
        nodeId: 'node-1',
      );

      final found = await repo.getRun('run-integ-3');
      expect(found!.status, WorkflowRunStatus.suspended);
      expect(found.contextJson, '{"state":"test"}');
      // Логи не дублируются
      expect(found.logsJson.split('log1').length - 1, 1);
    });

    test('getDLQJobs возвращает failed runs', () async {
      final run = WorkflowRun(
        id: 'run-integ-dlq',
        projectId: 'proj-1',
        blueprintId: 'bp-1',
        graphSnapshot: const {},
        status: WorkflowRunStatus.running,
        logsJson: '[]',
        createdAt: DateTime.now(),
      );
      await repo.createRun(run);
      await repo.updateRunLog('run-integ-dlq', [], status: WorkflowRunStatus.failed);

      final dlq = await repo.getDLQJobs();
      expect(dlq.any((r) => r.id == 'run-integ-dlq'), isTrue);
    });

    test('retryFromDLQ переводит failed → running', () async {
      final run = WorkflowRun(
        id: 'run-integ-retry',
        projectId: 'proj-1',
        blueprintId: 'bp-1',
        graphSnapshot: const {},
        status: WorkflowRunStatus.failed,
        logsJson: '[]',
        createdAt: DateTime.now(),
      );
      await repo.createRun(run);

      final result = await repo.retryFromDLQ(runId: 'run-integ-retry');
      expect(result, isTrue);

      final found = await repo.getRun('run-integ-retry');
      expect(found!.status, WorkflowRunStatus.running);
    });
  });
}
