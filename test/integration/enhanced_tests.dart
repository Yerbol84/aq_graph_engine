// Улучшенные integration тесты с проверкой логов и состояния БД
//
// Демонстрирует правильный подход к тестированию:
// - Проверка результата (файлы созданы)
// - Проверка процесса (логи, количество выполнений)
// - Проверка состояния БД (Run сохранён корректно)

import 'dart:io';
import 'package:test/test.dart';
import 'package:aq_schema/aq_schema.dart';
import 'package:aq_graph_engine/aq_graph_engine.dart';
import 'package:dart_vault/dart_vault.dart';
import 'test_helpers.dart';

void main() {
  setUpAll(() async {
    await connectToDataService();
  });

  group('Enhanced Integration Tests - With Log Verification', () {
    test('Параллельные ветки: проверка результата, логов и БД', () async {
      // 1. Создать проект
      final project = await createTestProject(name: 'Enhanced Parallel Test');

      // 2. Создать выходные пути
      final tempDir = Directory.systemTemp.createTempSync('aq_test_');
      final path1 = '${tempDir.path}/branch1.txt';
      final path2 = '${tempDir.path}/branch2.txt';

      // 3. Создать граф с параллельными ветками
      final workflowRepo = Vault.instance.versioned<WorkflowGraph>(
        collection: WorkflowGraph.kCollection,
        fromMap: WorkflowGraph.fromMap,
      );

      final workflow = WorkflowGraph(
        id: uuid(),
        tenantId: TestConfig.testTenantId,
        ownerId: project.id,
        name: 'Enhanced Parallel Workflow',
        nodes: {
          'start': WorkflowNode(
            id: 'start',
            type: WorkflowNodeType.fileRead,
            config: {
              'file_path': await createTestFile('Start'),
              'output_var': 'content',
            },
          ),
          'branch1': WorkflowNode(
            id: 'branch1',
            type: WorkflowNodeType.fileWrite,
            config: {
              'file_path': path1,
              'input_var': 'content',
            },
          ),
          'branch2': WorkflowNode(
            id: 'branch2',
            type: WorkflowNodeType.fileWrite,
            config: {
              'file_path': path2,
              'input_var': 'content',
            },
          ),
        },
        edges: {
          'edge1': WorkflowEdge(
            id: 'edge1',
            sourceId: 'start',
            targetId: 'branch1',
            branchName: 'branch_a',
            type: WorkflowEdgeType.onSuccess,
          ),
          'edge2': WorkflowEdge(
            id: 'edge2',
            sourceId: 'start',
            targetId: 'branch2',
            branchName: 'branch_b',
            type: WorkflowEdgeType.onSuccess,
          ),
        },
      );

      await workflowRepo.createEntity(workflow);

      // 4. Запустить
      final client = GraphEngineClient(baseUrl: TestConfig.graphEngineUrl);
      final runId = uuid();
      final request = GraphRunRequest(
        runId: runId,
        projectId: project.id,
        blueprintId: workflow.id,
        projectPath: tempDir.path,
      );

      final events = client.run(request);

      // 5. Проверить успешное завершение
      await expectCompleted(events);

      // ========================================================================
      // ПРОВЕРКА 1: РЕЗУЛЬТАТ - файлы созданы
      // ========================================================================
      final file1 = File(path1);
      final file2 = File(path2);

      expect(await file1.exists(), true, reason: 'Branch 1 file should exist');
      expect(await file2.exists(), true, reason: 'Branch 2 file should exist');

      final content1 = await file1.readAsString();
      final content2 = await file2.readAsString();

      expect(content1, 'Start', reason: 'Branch 1 content should match');
      expect(content2, 'Start', reason: 'Branch 2 content should match');

      // ========================================================================
      // ПРОВЕРКА 2: ПРОЦЕСС - логи и количество выполнений
      // ========================================================================

      // Проверить что каждый узел выполнился ровно один раз
      await expectNodeExecutionCount(
        runId,
        'start',
        1,
        reason: 'Start node should execute once',
      );

      await expectNodeExecutionCount(
        runId,
        'branch1',
        1,
        reason: 'Branch 1 should execute once',
      );

      await expectNodeExecutionCount(
        runId,
        'branch2',
        1,
        reason: 'Branch 2 should execute once',
      );

      // Проверить что логи содержат правильные сообщения
      await expectLogContains(
        runId,
        'Executing',
        reason: 'Logs should contain execution messages',
      );

      // Проверить что branch1 и branch2 выполнялись параллельно
      await expectParallelExecution(
        runId,
        ['branch1', 'branch2'],
        threshold: Duration(seconds: 2),
        reason: 'Branches should execute in parallel',
      );

      // ========================================================================
      // ПРОВЕРКА 3: СОСТОЯНИЕ БД - Run сохранён корректно
      // ========================================================================

      await expectRunStatus(
        runId,
        'completed',
        reason: 'Run should be marked as completed in DB',
      );

      final run = await getRunState(runId);
      expect(run.projectId, project.id, reason: 'Run should reference correct project');
      expect(run.blueprintId, workflow.id, reason: 'Run should reference correct workflow');

      // Cleanup
      await tempDir.delete(recursive: true);
    }, timeout: Timeout(Duration(minutes: 3)));

    test('Ошибка в узле: проверка логов ошибки и состояния БД', () async {
      // 1. Создать проект
      final project = await createTestProject(name: 'Error Test');

      // 2. Создать граф с узлом который упадёт
      final tempDir = Directory.systemTemp.createTempSync('aq_test_');

      final workflowRepo = Vault.instance.versioned<WorkflowGraph>(
        collection: WorkflowGraph.kCollection,
        fromMap: WorkflowGraph.fromMap,
      );

      final workflow = WorkflowGraph(
        id: uuid(),
        tenantId: TestConfig.testTenantId,
        ownerId: project.id,
        name: 'Error Workflow',
        nodes: {
          'failing_node': WorkflowNode(
            id: 'failing_node',
            type: WorkflowNodeType.fileRead,
            config: {
              'file_path': '/nonexistent/file.txt',
              'output_var': 'content',
            },
          ),
        },
        edges: {},
      );

      await workflowRepo.createEntity(workflow);

      // 3. Запустить
      final client = GraphEngineClient(baseUrl: TestConfig.graphEngineUrl);
      final runId = uuid();
      final request = GraphRunRequest(
        runId: runId,
        projectId: project.id,
        blueprintId: workflow.id,
        projectPath: tempDir.path,
      );

      final events = client.run(request);

      // 4. Проверить что граф упал
      await expectFailed(events);

      // ========================================================================
      // ПРОВЕРКА 1: ЛОГИ - содержат информацию об ошибке
      // ========================================================================

      final logs = await getRunLogs(runId);
      expect(logs.isNotEmpty, true, reason: 'Logs should not be empty');

      // Проверить что логи содержат сообщение об ошибке
      final hasErrorLog = logs.any((log) =>
        log.toLowerCase().contains('error') ||
        log.toLowerCase().contains('failed') ||
        log.toLowerCase().contains('exception')
      );
      expect(hasErrorLog, true, reason: 'Logs should contain error message');

      // ========================================================================
      // ПРОВЕРКА 2: СОСТОЯНИЕ БД - Run помечен как failed
      // ========================================================================

      await expectRunStatus(
        runId,
        'failed',
        reason: 'Run should be marked as failed in DB',
      );

      final run = await getRunState(runId);
      expect(run.errorMessage, isNotNull, reason: 'Run should have error message');
      expect(run.errorMessage!.isNotEmpty, true, reason: 'Error message should not be empty');

      // Cleanup
      await tempDir.delete(recursive: true);
    }, timeout: Timeout(Duration(minutes: 3)));

    test('Последовательное выполнение: проверка порядка', () async {
      // 1. Создать проект
      final project = await createTestProject(name: 'Sequential Test');

      // 2. Создать граф с цепочкой узлов
      final tempDir = Directory.systemTemp.createTempSync('aq_test_');
      final file1 = await createTestFile('Step 1');
      final file2 = '${tempDir.path}/step2.txt';
      final file3 = '${tempDir.path}/step3.txt';

      final workflowRepo = Vault.instance.versioned<WorkflowGraph>(
        collection: WorkflowGraph.kCollection,
        fromMap: WorkflowGraph.fromMap,
      );

      final workflow = WorkflowGraph(
        id: uuid(),
        tenantId: TestConfig.testTenantId,
        ownerId: project.id,
        name: 'Sequential Workflow',
        nodes: {
          'node1': WorkflowNode(
            id: 'node1',
            type: WorkflowNodeType.fileRead,
            config: {
              'file_path': file1,
              'output_var': 'content',
            },
          ),
          'node2': WorkflowNode(
            id: 'node2',
            type: WorkflowNodeType.fileWrite,
            config: {
              'file_path': file2,
              'input_var': 'content',
            },
          ),
          'node3': WorkflowNode(
            id: 'node3',
            type: WorkflowNodeType.fileWrite,
            config: {
              'file_path': file3,
              'input_var': 'content',
            },
          ),
        },
        edges: {
          'edge1': WorkflowEdge(
            id: 'edge1',
            sourceId: 'node1',
            targetId: 'node2',
            branchName: 'main',
            type: WorkflowEdgeType.onSuccess,
          ),
          'edge2': WorkflowEdge(
            id: 'edge2',
            sourceId: 'node2',
            targetId: 'node3',
            branchName: 'main',
            type: WorkflowEdgeType.onSuccess,
          ),
        },
      );

      await workflowRepo.createEntity(workflow);

      // 3. Запустить
      final client = GraphEngineClient(baseUrl: TestConfig.graphEngineUrl);
      final runId = uuid();
      final request = GraphRunRequest(
        runId: runId,
        projectId: project.id,
        blueprintId: workflow.id,
        projectPath: tempDir.path,
      );

      final events = client.run(request);
      await expectCompleted(events);

      // ========================================================================
      // ПРОВЕРКА 1: РЕЗУЛЬТАТ
      // ========================================================================
      expect(await File(file2).exists(), true);
      expect(await File(file3).exists(), true);

      // ========================================================================
      // ПРОВЕРКА 2: ПОРЯДОК ВЫПОЛНЕНИЯ
      // ========================================================================

      // Проверить что узлы выполнились в правильном порядке
      await expectExecutionOrder(
        runId,
        ['node1', 'node2', 'node3'],
        reason: 'Nodes should execute in sequential order',
      );

      // Cleanup
      await cleanupTestFile(file1);
      await tempDir.delete(recursive: true);
    }, timeout: Timeout(Duration(minutes: 3)));
  });
}
