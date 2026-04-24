// КРИТИЧНЫЙ ТЕСТ: Проверка работы waitAll в diamond pattern
//
// Цель: Проверить что узел D выполняется ОДИН раз когда используется waitAll
//
// Diamond pattern:
//     A
//    / \
//   B   C
//    \ /
//     D (joinStrategy = waitAll)
//
// Ожидаемое поведение:
// - Узел D должен выполниться ОДИН раз после прихода обоих рёбер (B->D и C->D)
//
// Если тест ПРОХОДИТ: Join Strategies работают! ✅
// Если тест ПАДАЕТ: Реализация требует исправления ❌

import 'dart:io';
import 'package:test/test.dart';
import 'package:aq_schema/aq_schema.dart';
import 'package:aq_graph_engine/aq_graph_engine.dart';
import 'package:dart_vault/dart_vault.dart';
import '../integration/test_helpers.dart';

void main() {
  setUpAll(() async {
    await connectToDataService();
  });

  group('🚨 КРИТИЧНЫЙ ТЕСТ: waitAll Join Strategy', () {
    test('Diamond pattern с waitAll: узел D выполняется ОДИН раз', () async {
      // 1. Создать проект
      final project = await createTestProject(name: 'Diamond waitAll Test');

      // 2. Создать временную директорию
      final tempDir = Directory.systemTemp.createTempSync('aq_diamond_test_');
      final inputFile = await createTestFile('Start');
      final outputB = '${tempDir.path}/b.txt';
      final outputC = '${tempDir.path}/c.txt';
      final outputD = '${tempDir.path}/d.txt';

      // 3. Создать граф с diamond pattern
      final workflowRepo = Vault.instance.versioned<TypedWorkflowGraph>(
        collection: TypedWorkflowGraph.kCollection,
        fromMap: TypedWorkflowGraph.fromMap,
      );

      // Создать узлы
      final nodeA = FileReadNode(
        id: 'nodeA',
        filePath: inputFile,
        outputVar: 'content',
      );

      final nodeB = FileWriteNode(
        id: 'nodeB',
        filePath: outputB,
        contentSource: FileWriteContentSource.variable('content'),
      );

      final nodeC = FileWriteNode(
        id: 'nodeC',
        filePath: outputC,
        contentSource: FileWriteContentSource.variable('content'),
      );

      // КРИТИЧНО: Узел D с joinStrategy = waitAll
      final nodeD = FileWriteNode(
        id: 'nodeD',
        filePath: outputD,
        contentSource: FileWriteContentSource.variable('content'),
        joinStrategy: NodeJoinStrategy.waitAll, // 🎯 КЛЮЧЕВОЙ МОМЕНТ
      );

      final workflow = TypedWorkflowGraph(
        id: uuid(),
        tenantId: TestConfig.testTenantId,
        ownerId: project.id,
        name: 'Diamond waitAll Workflow',
        nodes: {
          'nodeA': nodeA,
          'nodeB': nodeB,
          'nodeC': nodeC,
          'nodeD': nodeD,
        },
        edges: {
          'edgeAB': WorkflowEdge(
            id: 'edgeAB',
            sourceId: 'nodeA',
            targetId: 'nodeB',
            branchName: 'branch_b',
            type: WorkflowEdgeType.onSuccess,
          ),
          'edgeAC': WorkflowEdge(
            id: 'edgeAC',
            sourceId: 'nodeA',
            targetId: 'nodeC',
            branchName: 'branch_c',
            type: WorkflowEdgeType.onSuccess,
          ),
          'edgeBD': WorkflowEdge(
            id: 'edgeBD',
            sourceId: 'nodeB',
            targetId: 'nodeD',
            branchName: 'merge_b',
            type: WorkflowEdgeType.onSuccess,
          ),
          'edgeCD': WorkflowEdge(
            id: 'edgeCD',
            sourceId: 'nodeC',
            targetId: 'nodeD',
            branchName: 'merge_c',
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
      // КРИТИЧНАЯ ПРОВЕРКА 1: Файл D создан
      // ========================================================================
      final fileD = File(outputD);
      expect(await fileD.exists(), true, reason: 'Node D should execute and create file');

      // ========================================================================
      // КРИТИЧНАЯ ПРОВЕРКА 2: Узел D выполнился ОДИН раз
      // ========================================================================
      await expectNodeExecutionCount(
        runId,
        'nodeD',
        1,
        reason: 'Node D with waitAll should execute ONCE after both edges arrive',
      );

      // ========================================================================
      // КРИТИЧНАЯ ПРОВЕРКА 3: Логи содержат сообщения о ожидании
      // ========================================================================
      await expectLogContains(
        runId,
        'waiting for',
        reason: 'Logs should contain waiting message',
      );

      await expectLogContains(
        runId,
        'All',
        reason: 'Logs should contain "All edges arrived" message',
      );

      // ========================================================================
      // КРИТИЧНАЯ ПРОВЕРКА 4: Узлы B и C выполнились по одному разу
      // ========================================================================
      await expectNodeExecutionCount(runId, 'nodeB', 1);
      await expectNodeExecutionCount(runId, 'nodeC', 1);

      print('');
      print('🎉 ✅ ТЕСТ ПРОШЁЛ! Join Strategies работают!');
      print('');
      print('Результаты:');
      print('- Узел A выполнился: 1 раз');
      print('- Узел B выполнился: 1 раз');
      print('- Узел C выполнился: 1 раз');
      print('- Узел D выполнился: 1 раз (waitAll работает!)');
      print('');

      // Cleanup
      await cleanupTestFile(inputFile);
      await tempDir.delete(recursive: true);
    }, timeout: Timeout(Duration(minutes: 3)));

    test('Diamond pattern БЕЗ waitAll (firstCome): узел D выполняется ДВАЖДЫ', () async {
      // Этот тест проверяет поведение по умолчанию (firstCome)
      // Узел D должен выполниться ДВАЖДЫ

      final project = await createTestProject(name: 'Diamond firstCome Test');
      final tempDir = Directory.systemTemp.createTempSync('aq_diamond_test_');
      final inputFile = await createTestFile('Start');
      final outputB = '${tempDir.path}/b.txt';
      final outputC = '${tempDir.path}/c.txt';
      final outputD = '${tempDir.path}/d.txt';

      final workflowRepo = Vault.instance.versioned<TypedWorkflowGraph>(
        collection: TypedWorkflowGraph.kCollection,
        fromMap: TypedWorkflowGraph.fromMap,
      );

      final nodeA = FileReadNode(id: 'nodeA', filePath: inputFile, outputVar: 'content');
      final nodeB = FileWriteNode(id: 'nodeB', filePath: outputB, contentSource: FileWriteContentSource.variable('content'));
      final nodeC = FileWriteNode(id: 'nodeC', filePath: outputC, contentSource: FileWriteContentSource.variable('content'));

      // Узел D БЕЗ waitAll (по умолчанию firstCome)
      final nodeD = FileWriteNode(
        id: 'nodeD',
        filePath: outputD,
        contentSource: FileWriteContentSource.variable('content'),
        // joinStrategy НЕ указан - по умолчанию firstCome
      );

      final workflow = TypedWorkflowGraph(
        id: uuid(),
        tenantId: TestConfig.testTenantId,
        ownerId: project.id,
        name: 'Diamond firstCome Workflow',
        nodes: {'nodeA': nodeA, 'nodeB': nodeB, 'nodeC': nodeC, 'nodeD': nodeD},
        edges: {
          'edgeAB': WorkflowEdge(id: 'edgeAB', sourceId: 'nodeA', targetId: 'nodeB', branchName: 'branch_b', type: WorkflowEdgeType.onSuccess),
          'edgeAC': WorkflowEdge(id: 'edgeAC', sourceId: 'nodeA', targetId: 'nodeC', branchName: 'branch_c', type: WorkflowEdgeType.onSuccess),
          'edgeBD': WorkflowEdge(id: 'edgeBD', sourceId: 'nodeB', targetId: 'nodeD', branchName: 'merge_b', type: WorkflowEdgeType.onSuccess),
          'edgeCD': WorkflowEdge(id: 'edgeCD', sourceId: 'nodeC', targetId: 'nodeD', branchName: 'merge_c', type: WorkflowEdgeType.onSuccess),
        },
      );

      await workflowRepo.createEntity(workflow);

      final client = GraphEngineClient(baseUrl: TestConfig.graphEngineUrl);
      final runId = uuid();
      final request = GraphRunRequest(runId: runId, projectId: project.id, blueprintId: workflow.id, projectPath: tempDir.path);

      final events = client.run(request);
      await expectCompleted(events);

      // ПРОВЕРКА: Узел D выполнился ДВАЖДЫ (firstCome поведение)
      await expectNodeExecutionCount(
        runId,
        'nodeD',
        2,
        reason: 'Node D with firstCome (default) should execute TWICE',
      );

      print('');
      print('✅ ТЕСТ ПРОШЁЛ! firstCome работает как ожидается');
      print('');
      print('Результаты:');
      print('- Узел D выполнился: 2 раза (firstCome - каждое ребро запускает узел)');
      print('');

      await cleanupTestFile(inputFile);
      await tempDir.delete(recursive: true);
    }, timeout: Timeout(Duration(minutes: 3)));
  });
}
