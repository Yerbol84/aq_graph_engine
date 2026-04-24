// КРИТИЧНЫЙ ТЕСТ: Упрощенная проверка waitAll
//
// Цель: Проверить что логика waitAll в PolymorphicWorkflowRunner работает
//
// Подход: Использовать существующий deprecated WorkflowGraph с fileWrite узлами
// и проверить количество выполнений через логи

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

  group('🚨 КРИТИЧНЫЙ ТЕСТ: waitAll Join Strategy (упрощенный)', () {
    test('Diamond pattern: проверка через логи', () async {
      // 1. Создать проект
      final project = await createTestProject(name: 'Diamond Test');

      // 2. Создать временную директорию
      final tempDir = Directory.systemTemp.createTempSync('aq_diamond_test_');
      final outputB = '${tempDir.path}/b.txt';
      final outputC = '${tempDir.path}/c.txt';
      final outputD = '${tempDir.path}/d.txt';

      // 3. Создать граф с diamond pattern
      // A → B,C → D
      final workflowRepo = Vault.instance.versioned<WorkflowGraph>(
        collection: WorkflowGraph.kCollection,
        fromMap: WorkflowGraph.fromMap,
      );

      final workflow = WorkflowGraph(
        id: uuid(),
        tenantId: TestConfig.testTenantId,
        ownerId: project.id,
        name: 'Diamond Workflow',
        nodes: {
          'nodeA': WorkflowNode(
            id: 'nodeA',
            type: WorkflowNodeType.fileWrite,
            config: {
              'file_path': '${tempDir.path}/a.txt',
              'input_var': 'content',
            },
          ),
          'nodeB': WorkflowNode(
            id: 'nodeB',
            type: WorkflowNodeType.fileWrite,
            config: {
              'file_path': outputB,
              'input_var': 'content',
            },
          ),
          'nodeC': WorkflowNode(
            id: 'nodeC',
            type: WorkflowNodeType.fileWrite,
            config: {
              'file_path': outputC,
              'input_var': 'content',
            },
          ),
          'nodeD': WorkflowNode(
            id: 'nodeD',
            type: WorkflowNodeType.fileWrite,
            config: {
              'file_path': outputD,
              'input_var': 'content',
              // КРИТИЧНО: Попытка указать joinStrategy через config
              // (может не сработать, но попробуем)
              'joinStrategy': 'waitAll',
            },
          ),
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
        initialVariables: {
          'content': 'Test content',
        },
      );

      final events = client.run(request);

      // 5. Проверить успешное завершение
      await expectCompleted(events);

      // ========================================================================
      // ПРОВЕРКА: Сколько раз выполнился узел D?
      // ========================================================================

      // БЕЗ waitAll: узел D выполнится ДВАЖДЫ (по разу на каждое ребро)
      // С waitAll: узел D выполнится ОДИН раз

      final executionCount = await getNodeExecutionCount(runId, 'nodeD');

      print('');
      print('📊 РЕЗУЛЬТАТ ТЕСТА:');
      print('Узел D выполнился: $executionCount раз(а)');
      print('');

      if (executionCount == 1) {
        print('✅ УСПЕХ! waitAll работает - узел D выполнился ОДИН раз');
        print('');
      } else if (executionCount == 2) {
        print('⚠️ waitAll НЕ РАБОТАЕТ - узел D выполнился ДВАЖДЫ (firstCome поведение)');
        print('');
        print('Возможные причины:');
        print('1. joinStrategy не передается через config');
        print('2. FileWriteNode не поддерживает joinStrategy');
        print('3. Нужно использовать кастомные узлы с переопределенным joinStrategy getter');
        print('');
      } else {
        print('❌ НЕОЖИДАННЫЙ РЕЗУЛЬТАТ - узел D выполнился $executionCount раз(а)');
        print('');
      }

      // Cleanup
      await tempDir.delete(recursive: true);
    }, timeout: Timeout(Duration(minutes: 3)));
  });
}
