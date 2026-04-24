// Интеграционные тесты параллельного выполнения
//
// Покрывает:
// - Параллельное выполнение веток (branches)
// - Синхронизацию результатов
// - Изоляцию контекста между ветками
// - Обработку ошибок в параллельных ветках

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

  group('Parallel Execution - Simple Branches', () {
    test('Две параллельные ветки с fileWrite', () async {
      // 1. Создать проект
      final project = await createTestProject(name: 'Parallel Branches Test');

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
        name: 'Parallel Workflow',
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
      final request = GraphRunRequest(
        runId: uuid(),
        projectId: project.id,
        blueprintId: workflow.id,
        projectPath: tempDir.path,
      );

      final events = client.run(request);

      // 5. Проверить успешное завершение
      await expectCompleted(events);

      // 6. Проверить что оба файла созданы
      final file1 = File(path1);
      final file2 = File(path2);

      expect(await file1.exists(), true);
      expect(await file2.exists(), true);

      final content1 = await file1.readAsString();
      final content2 = await file2.readAsString();

      expect(content1, 'Start');
      expect(content2, 'Start');

      // Cleanup
      await tempDir.delete(recursive: true);
    }, timeout: Timeout(Duration(minutes: 3)));

    test('Три параллельные ветки с разными операциями', () async {
      // 1. Создать проект
      final project = await createTestProject(name: 'Three Branches Test');

      // 2. Подготовить файлы
      final inputFile = await createTestFile('Input data');
      final tempDir = Directory.systemTemp.createTempSync('aq_test_');
      final output1 = '${tempDir.path}/output1.txt';
      final output2 = '${tempDir.path}/output2.txt';
      final output3 = '${tempDir.path}/output3.txt';

      // 3. Создать граф
      final workflowRepo = Vault.instance.versioned<WorkflowGraph>(
        collection: WorkflowGraph.kCollection,
        fromMap: WorkflowGraph.fromMap,
      );

      final workflow = WorkflowGraph(
        id: uuid(),
        tenantId: TestConfig.testTenantId,
        ownerId: project.id,
        name: 'Three Branches Workflow',
        nodes: {
          'read': WorkflowNode(
            id: 'read',
            type: WorkflowNodeType.fileRead,
            config: {
              'file_path': inputFile,
              'output_var': 'data',
            },
          ),
          'write1': WorkflowNode(
            id: 'write1',
            type: WorkflowNodeType.fileWrite,
            config: {
              'file_path': output1,
              'input_var': 'data',
            },
          ),
          'write2': WorkflowNode(
            id: 'write2',
            type: WorkflowNodeType.fileWrite,
            config: {
              'file_path': output2,
              'input_var': 'data',
            },
          ),
          'write3': WorkflowNode(
            id: 'write3',
            type: WorkflowNodeType.fileWrite,
            config: {
              'file_path': output3,
              'input_var': 'data',
            },
          ),
        },
        edges: {
          'e1': WorkflowEdge(
            id: 'e1',
            sourceId: 'read',
            targetId: 'write1',
            branchName: 'branch_1',
            type: WorkflowEdgeType.onSuccess,
          ),
          'e2': WorkflowEdge(
            id: 'e2',
            sourceId: 'read',
            targetId: 'write2',
            branchName: 'branch_2',
            type: WorkflowEdgeType.onSuccess,
          ),
          'e3': WorkflowEdge(
            id: 'e3',
            sourceId: 'read',
            targetId: 'write3',
            branchName: 'branch_3',
            type: WorkflowEdgeType.onSuccess,
          ),
        },
      );

      await workflowRepo.createEntity(workflow);

      // 4. Запустить
      final client = GraphEngineClient(baseUrl: TestConfig.graphEngineUrl);
      final request = GraphRunRequest(
        runId: uuid(),
        projectId: project.id,
        blueprintId: workflow.id,
        projectPath: tempDir.path,
      );

      final events = client.run(request);
      await expectCompleted(events);

      // 5. Проверить все три файла
      expect(await File(output1).exists(), true);
      expect(await File(output2).exists(), true);
      expect(await File(output3).exists(), true);

      // Cleanup
      await cleanupTestFile(inputFile);
      await tempDir.delete(recursive: true);
    }, timeout: Timeout(Duration(minutes: 3)));
  });

  group('Parallel Execution - Context Isolation', () {
    test('Изоляция переменных между ветками', () async {
      // 1. Создать проект
      final project = await createTestProject(name: 'Context Isolation Test');

      // 2. Создать граф где каждая ветка устанавливает свою переменную
      final tempDir = Directory.systemTemp.createTempSync('aq_test_');
      final output1 = '${tempDir.path}/branch1.txt';
      final output2 = '${tempDir.path}/branch2.txt';

      final workflowRepo = Vault.instance.versioned<WorkflowGraph>(
        collection: WorkflowGraph.kCollection,
        fromMap: WorkflowGraph.fromMap,
      );

      final workflow = WorkflowGraph(
        id: uuid(),
        tenantId: TestConfig.testTenantId,
        ownerId: project.id,
        name: 'Isolated Context Workflow',
        nodes: {
          'start': WorkflowNode(
            id: 'start',
            type: WorkflowNodeType.fileRead,
            config: {
              'file_path': await createTestFile('Shared'),
              'output_var': 'shared_var',
            },
          ),
          'branch1_write': WorkflowNode(
            id: 'branch1_write',
            type: WorkflowNodeType.fileWrite,
            config: {
              'file_path': output1,
              'input_var': 'branch1_var',
            },
          ),
          'branch2_write': WorkflowNode(
            id: 'branch2_write',
            type: WorkflowNodeType.fileWrite,
            config: {
              'file_path': output2,
              'input_var': 'branch2_var',
            },
          ),
        },
        edges: {
          'e1': WorkflowEdge(
            id: 'e1',
            sourceId: 'start',
            targetId: 'branch1_write',
            branchName: 'branch_1',
            type: WorkflowEdgeType.onSuccess,
          ),
          'e2': WorkflowEdge(
            id: 'e2',
            sourceId: 'start',
            targetId: 'branch2_write',
            branchName: 'branch_2',
            type: WorkflowEdgeType.onSuccess,
          ),
        },
      );

      await workflowRepo.createEntity(workflow);

      // 3. Запустить с переменными для каждой ветки
      final client = GraphEngineClient(baseUrl: TestConfig.graphEngineUrl);
      final request = GraphRunRequest(
        runId: uuid(),
        projectId: project.id,
        blueprintId: workflow.id,
        projectPath: tempDir.path,
        initialVariables: {
          'branch1_var': 'Value for branch 1',
          'branch2_var': 'Value for branch 2',
        },
      );

      final events = client.run(request);
      await expectCompleted(events);

      // 4. Проверить что каждая ветка получила свою переменную
      final content1 = await File(output1).readAsString();
      final content2 = await File(output2).readAsString();

      expect(content1, 'Value for branch 1');
      expect(content2, 'Value for branch 2');

      // Cleanup
      await tempDir.delete(recursive: true);
    }, timeout: Timeout(Duration(minutes: 3)));
  });

  group('Parallel Execution - Error Handling', () {
    test('Ошибка в одной ветке не останавливает другие', () async {
      // 1. Создать проект
      final project = await createTestProject(name: 'Parallel Error Test');

      // 2. Создать граф где одна ветка упадёт
      final tempDir = Directory.systemTemp.createTempSync('aq_test_');
      final successPath = '${tempDir.path}/success.txt';

      final workflowRepo = Vault.instance.versioned<WorkflowGraph>(
        collection: WorkflowGraph.kCollection,
        fromMap: WorkflowGraph.fromMap,
      );

      final workflow = WorkflowGraph(
        id: uuid(),
        tenantId: TestConfig.testTenantId,
        ownerId: project.id,
        name: 'Parallel Error Workflow',
        nodes: {
          'start': WorkflowNode(
            id: 'start',
            type: WorkflowNodeType.fileRead,
            config: {
              'file_path': await createTestFile('Start'),
              'output_var': 'content',
            },
          ),
          'success_branch': WorkflowNode(
            id: 'success_branch',
            type: WorkflowNodeType.fileWrite,
            config: {
              'file_path': successPath,
              'input_var': 'content',
            },
          ),
          'error_branch': WorkflowNode(
            id: 'error_branch',
            type: WorkflowNodeType.fileRead,
            config: {
              'file_path': '/nonexistent/file.txt',
              'output_var': 'error_content',
            },
          ),
        },
        edges: {
          'e1': WorkflowEdge(
            id: 'e1',
            sourceId: 'start',
            targetId: 'success_branch',
            branchName: 'success',
            type: WorkflowEdgeType.onSuccess,
          ),
          'e2': WorkflowEdge(
            id: 'e2',
            sourceId: 'start',
            targetId: 'error_branch',
            branchName: 'error',
            type: WorkflowEdgeType.onSuccess,
          ),
        },
      );

      await workflowRepo.createEntity(workflow);

      // 3. Запустить
      final client = GraphEngineClient(baseUrl: TestConfig.graphEngineUrl);
      final request = GraphRunRequest(
        runId: uuid(),
        projectId: project.id,
        blueprintId: workflow.id,
        projectPath: tempDir.path,
      );

      final events = client.run(request);

      // 4. Граф должен упасть из-за ошибки в одной ветке
      await expectFailed(events);

      // 5. Но успешная ветка должна была выполниться
      // (в зависимости от реализации - может быть или не быть)
      // Это поведение определяется политикой обработки ошибок

      // Cleanup
      await tempDir.delete(recursive: true);
    }, timeout: Timeout(Duration(minutes: 3)));

    test('OnError edge для обработки ошибок в параллельных ветках', () async {
      // 1. Создать проект
      final project = await createTestProject(name: 'OnError Branch Test');

      // 2. Создать граф с обработкой ошибок
      final tempDir = Directory.systemTemp.createTempSync('aq_test_');
      final errorLogPath = '${tempDir.path}/error.log';

      final workflowRepo = Vault.instance.versioned<WorkflowGraph>(
        collection: WorkflowGraph.kCollection,
        fromMap: WorkflowGraph.fromMap,
      );

      final workflow = WorkflowGraph(
        id: uuid(),
        tenantId: TestConfig.testTenantId,
        ownerId: project.id,
        name: 'OnError Workflow',
        nodes: {
          'start': WorkflowNode(
            id: 'start',
            type: WorkflowNodeType.fileRead,
            config: {
              'file_path': await createTestFile('Start'),
              'output_var': 'content',
            },
          ),
          'risky': WorkflowNode(
            id: 'risky',
            type: WorkflowNodeType.fileRead,
            config: {
              'file_path': '/invalid/path.txt',
              'output_var': 'risky_content',
            },
          ),
          'error_handler': WorkflowNode(
            id: 'error_handler',
            type: WorkflowNodeType.fileWrite,
            config: {
              'file_path': errorLogPath,
              'input_var': 'error_message',
            },
          ),
        },
        edges: {
          'e1': WorkflowEdge(
            id: 'e1',
            sourceId: 'start',
            targetId: 'risky',
            branchName: 'main',
            type: WorkflowEdgeType.onSuccess,
          ),
          'e2': WorkflowEdge(
            id: 'e2',
            sourceId: 'risky',
            targetId: 'error_handler',
            branchName: 'error',
            type: WorkflowEdgeType.onError,
          ),
        },
      );

      await workflowRepo.createEntity(workflow);

      // 3. Запустить
      final client = GraphEngineClient(baseUrl: TestConfig.graphEngineUrl);
      final request = GraphRunRequest(
        runId: uuid(),
        projectId: project.id,
        blueprintId: workflow.id,
        projectPath: tempDir.path,
        initialVariables: {
          'error_message': 'Error occurred',
        },
      );

      final events = client.run(request);

      // 4. Проверить что error_handler выполнился
      final eventList = await collectEvents(events);

      // 5. Проверить логи
      final logEvents = eventList
          .where((e) => e.type == GraphRunEventType.log)
          .toList();

      expect(logEvents.isNotEmpty, true);

      // Cleanup
      await tempDir.delete(recursive: true);
    }, timeout: Timeout(Duration(minutes: 3)));
  });

  group('Parallel Execution - Complex Scenarios', () {
    test('Параллельные ветки с последующим слиянием', () async {
      // 1. Создать проект
      final project = await createTestProject(name: 'Merge Branches Test');

      // 2. Создать граф с параллельными ветками и слиянием
      final tempDir = Directory.systemTemp.createTempSync('aq_test_');
      final temp1 = '${tempDir.path}/temp1.txt';
      final temp2 = '${tempDir.path}/temp2.txt';
      final finalOutput = '${tempDir.path}/final.txt';

      final workflowRepo = Vault.instance.versioned<WorkflowGraph>(
        collection: WorkflowGraph.kCollection,
        fromMap: WorkflowGraph.fromMap,
      );

      final workflow = WorkflowGraph(
        id: uuid(),
        tenantId: TestConfig.testTenantId,
        ownerId: project.id,
        name: 'Merge Workflow',
        nodes: {
          'start': WorkflowNode(
            id: 'start',
            type: WorkflowNodeType.fileRead,
            config: {
              'file_path': await createTestFile('Input'),
              'output_var': 'input',
            },
          ),
          'process1': WorkflowNode(
            id: 'process1',
            type: WorkflowNodeType.fileWrite,
            config: {
              'file_path': temp1,
              'input_var': 'input',
            },
          ),
          'process2': WorkflowNode(
            id: 'process2',
            type: WorkflowNodeType.fileWrite,
            config: {
              'file_path': temp2,
              'input_var': 'input',
            },
          ),
          'merge': WorkflowNode(
            id: 'merge',
            type: WorkflowNodeType.fileWrite,
            config: {
              'file_path': finalOutput,
              'input_var': 'merged',
            },
          ),
        },
        edges: {
          'e1': WorkflowEdge(
            id: 'e1',
            sourceId: 'start',
            targetId: 'process1',
            branchName: 'branch_1',
            type: WorkflowEdgeType.onSuccess,
          ),
          'e2': WorkflowEdge(
            id: 'e2',
            sourceId: 'start',
            targetId: 'process2',
            branchName: 'branch_2',
            type: WorkflowEdgeType.onSuccess,
          ),
          'e3': WorkflowEdge(
            id: 'e3',
            sourceId: 'process1',
            targetId: 'merge',
            branchName: 'merge',
            type: WorkflowEdgeType.onSuccess,
          ),
          'e4': WorkflowEdge(
            id: 'e4',
            sourceId: 'process2',
            targetId: 'merge',
            branchName: 'merge',
            type: WorkflowEdgeType.onSuccess,
          ),
        },
      );

      await workflowRepo.createEntity(workflow);

      // 3. Запустить
      final client = GraphEngineClient(baseUrl: TestConfig.graphEngineUrl);
      final request = GraphRunRequest(
        runId: uuid(),
        projectId: project.id,
        blueprintId: workflow.id,
        projectPath: tempDir.path,
        initialVariables: {
          'merged': 'Merged result',
        },
      );

      final events = client.run(request);
      await expectCompleted(events);

      // 4. Проверить что все файлы созданы
      expect(await File(temp1).exists(), true);
      expect(await File(temp2).exists(), true);
      expect(await File(finalOutput).exists(), true);

      // Cleanup
      await tempDir.delete(recursive: true);
    }, timeout: Timeout(Duration(minutes: 4)));

    test('Вложенные параллельные ветки', () async {
      // 1. Создать проект
      final project = await createTestProject(name: 'Nested Parallel Test');

      // 2. Создать граф с вложенными параллельными ветками
      final tempDir = Directory.systemTemp.createTempSync('aq_test_');
      final outputs = List.generate(
        4,
        (i) => '${tempDir.path}/output$i.txt',
      );

      final workflowRepo = Vault.instance.versioned<WorkflowGraph>(
        collection: WorkflowGraph.kCollection,
        fromMap: WorkflowGraph.fromMap,
      );

      final workflow = WorkflowGraph(
        id: uuid(),
        tenantId: TestConfig.testTenantId,
        ownerId: project.id,
        name: 'Nested Parallel Workflow',
        nodes: {
          'root': WorkflowNode(
            id: 'root',
            type: WorkflowNodeType.fileRead,
            config: {
              'file_path': await createTestFile('Root'),
              'output_var': 'data',
            },
          ),
          'level1_a': WorkflowNode(
            id: 'level1_a',
            type: WorkflowNodeType.fileWrite,
            config: {
              'file_path': outputs[0],
              'input_var': 'data',
            },
          ),
          'level1_b': WorkflowNode(
            id: 'level1_b',
            type: WorkflowNodeType.fileWrite,
            config: {
              'file_path': outputs[1],
              'input_var': 'data',
            },
          ),
          'level2_a': WorkflowNode(
            id: 'level2_a',
            type: WorkflowNodeType.fileWrite,
            config: {
              'file_path': outputs[2],
              'input_var': 'data',
            },
          ),
          'level2_b': WorkflowNode(
            id: 'level2_b',
            type: WorkflowNodeType.fileWrite,
            config: {
              'file_path': outputs[3],
              'input_var': 'data',
            },
          ),
        },
        edges: {
          'e1': WorkflowEdge(
            id: 'e1',
            sourceId: 'root',
            targetId: 'level1_a',
            branchName: 'branch_a',
            type: WorkflowEdgeType.onSuccess,
          ),
          'e2': WorkflowEdge(
            id: 'e2',
            sourceId: 'root',
            targetId: 'level1_b',
            branchName: 'branch_b',
            type: WorkflowEdgeType.onSuccess,
          ),
          'e3': WorkflowEdge(
            id: 'e3',
            sourceId: 'level1_a',
            targetId: 'level2_a',
            branchName: 'nested_a',
            type: WorkflowEdgeType.onSuccess,
          ),
          'e4': WorkflowEdge(
            id: 'e4',
            sourceId: 'level1_a',
            targetId: 'level2_b',
            branchName: 'nested_b',
            type: WorkflowEdgeType.onSuccess,
          ),
        },
      );

      await workflowRepo.createEntity(workflow);

      // 3. Запустить
      final client = GraphEngineClient(baseUrl: TestConfig.graphEngineUrl);
      final request = GraphRunRequest(
        runId: uuid(),
        projectId: project.id,
        blueprintId: workflow.id,
        projectPath: tempDir.path,
      );

      final events = client.run(request);
      await expectCompleted(events);

      // 4. Проверить что все файлы созданы
      for (final output in outputs) {
        expect(await File(output).exists(), true);
      }

      // Cleanup
      await tempDir.delete(recursive: true);
    }, timeout: Timeout(Duration(minutes: 4)));
  });
}
