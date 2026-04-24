// Интеграционные тесты механизма Suspend/Resume
//
// Покрывает:
// - Приостановку выполнения на интерактивных узлах
// - Сохранение состояния контекста
// - Возобновление с пользовательским вводом
// - Все 4 типа интерактивных узлов

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

  group('Suspend/Resume - UserInput Node', () {
    test('Приостановка на userInput и возобновление с вводом', () async {
      // 1. Создать проект
      final project = await createTestProject(name: 'UserInput Test');

      // 2. Создать граф с userInput узлом
      final workflowRepo = Vault.instance.versioned<WorkflowGraph>(
        collection: WorkflowGraph.kCollection,
        fromMap: WorkflowGraph.fromMap,
      );

      final workflow = WorkflowGraph(
        id: uuid(),
        tenantId: TestConfig.testTenantId,
        ownerId: project.id,
        name: 'Workflow with UserInput',
        nodes: {
          'input': WorkflowNode(
            id: 'input',
            type: WorkflowNodeType.userInput,
            config: {
              'prompt': 'Введите ваше имя',
              'output_var': 'user_name',
            },
          ),
          'process': WorkflowNode(
            id: 'process',
            type: WorkflowNodeType.fileWrite,
            config: {
              'file_path': '/tmp/greeting.txt',
              'input_var': 'user_name',
            },
          ),
        },
        edges: {
          'edge1': WorkflowEdge(
            id: 'edge1',
            sourceId: 'input',
            targetId: 'process',
            branchName: 'main',
            type: WorkflowEdgeType.onSuccess,
          ),
        },
      );

      await workflowRepo.createEntity(workflow);

      // 3. Запустить граф
      final client = GraphEngineClient(baseUrl: TestConfig.graphEngineUrl);
      final runId = uuid();
      final request = GraphRunRequest(
        runId: runId,
        projectId: project.id,
        blueprintId: workflow.id,
        projectPath: Directory.systemTemp.path,
      );

      final events = client.run(request);

      // 4. Ожидаем приостановку
      await expectSuspended(events);

      // 5. Проверить статус в БД
      final runRepo = Vault.instance.logged<WorkflowRun>(
        collection: 'workflow_runs',
        fromMap: WorkflowRun.fromMap,
      );
      final suspendedRun = await runRepo.findById(runId);

      expect(suspendedRun, isNotNull);
      expect(suspendedRun!.status, 'suspended');
      expect(suspendedRun.suspendedNodeId, 'input');

      // 6. Возобновить с пользовательским вводом
      final resumeRequest = GraphResumeRequest(
        runId: runId,
        userInput: {
          'user_name': 'Алексей',
        },
      );

      final resumeEvents = client.resume(resumeRequest);

      // 7. Проверить успешное завершение
      await expectCompleted(resumeEvents);

      // 8. Проверить финальный статус
      final completedRun = await runRepo.findById(runId);
      expect(completedRun, isNotNull);
      expect(completedRun!.status, 'completed');

      // 9. Проверить что файл создан
      final outputFile = File('/tmp/greeting.txt');
      if (await outputFile.exists()) {
        final content = await outputFile.readAsString();
        expect(content, 'Алексей');
        await outputFile.delete();
      }
    }, timeout: Timeout(Duration(minutes: 3)));

    test('Множественные приостановки в одном графе', () async {
      // 1. Создать проект
      final project = await createTestProject(name: 'Multiple Suspend Test');

      // 2. Создать граф с двумя userInput узлами
      final workflowRepo = Vault.instance.versioned<WorkflowGraph>(
        collection: WorkflowGraph.kCollection,
        fromMap: WorkflowGraph.fromMap,
      );

      final workflow = WorkflowGraph(
        id: uuid(),
        tenantId: TestConfig.testTenantId,
        ownerId: project.id,
        name: 'Workflow with Multiple UserInputs',
        nodes: {
          'input1': WorkflowNode(
            id: 'input1',
            type: WorkflowNodeType.userInput,
            config: {
              'prompt': 'Введите первое значение',
              'output_var': 'value1',
            },
          ),
          'input2': WorkflowNode(
            id: 'input2',
            type: WorkflowNodeType.userInput,
            config: {
              'prompt': 'Введите второе значение',
              'output_var': 'value2',
            },
          ),
        },
        edges: {
          'edge1': WorkflowEdge(
            id: 'edge1',
            sourceId: 'input1',
            targetId: 'input2',
            branchName: 'main',
            type: WorkflowEdgeType.onSuccess,
          ),
        },
      );

      await workflowRepo.createEntity(workflow);

      // 3. Запустить граф
      final client = GraphEngineClient(baseUrl: TestConfig.graphEngineUrl);
      final runId = uuid();
      final request = GraphRunRequest(
        runId: runId,
        projectId: project.id,
        blueprintId: workflow.id,
        projectPath: Directory.systemTemp.path,
      );

      final events = client.run(request);

      // 4. Первая приостановка
      await expectSuspended(events);

      final runRepo = Vault.instance.logged<WorkflowRun>(
        collection: 'workflow_runs',
        fromMap: WorkflowRun.fromMap,
      );
      final run1 = await runRepo.findById(runId);
      expect(run1!.suspendedNodeId, 'input1');

      // 5. Возобновить с первым вводом
      final resume1 = GraphResumeRequest(
        runId: runId,
        userInput: {'value1': 'Первое'},
      );

      final events2 = client.resume(resume1);

      // 6. Вторая приостановка
      await expectSuspended(events2);

      final run2 = await runRepo.findById(runId);
      expect(run2!.suspendedNodeId, 'input2');

      // 7. Возобновить со вторым вводом
      final resume2 = GraphResumeRequest(
        runId: runId,
        userInput: {'value2': 'Второе'},
      );

      final events3 = client.resume(resume2);

      // 8. Проверить завершение
      await expectCompleted(events3);

      final finalRun = await runRepo.findById(runId);
      expect(finalRun!.status, 'completed');
    }, timeout: Timeout(Duration(minutes: 4)));
  });

  group('Suspend/Resume - ManualReview Node', () {
    test('Приостановка на manualReview и возобновление с решением', () async {
      // 1. Создать проект
      final project = await createTestProject(name: 'ManualReview Test');

      // 2. Создать тестовый файл для проверки
      final testFilePath = await createTestFile('Код для проверки');

      // 3. Создать граф с manualReview узлом
      final workflowRepo = Vault.instance.versioned<WorkflowGraph>(
        collection: WorkflowGraph.kCollection,
        fromMap: WorkflowGraph.fromMap,
      );

      final workflow = WorkflowGraph(
        id: uuid(),
        tenantId: TestConfig.testTenantId,
        ownerId: project.id,
        name: 'Workflow with ManualReview',
        nodes: {
          'read': WorkflowNode(
            id: 'read',
            type: WorkflowNodeType.fileRead,
            config: {
              'file_path': testFilePath,
              'output_var': 'code',
            },
          ),
          'review': WorkflowNode(
            id: 'review',
            type: WorkflowNodeType.manualReview,
            config: {
              'review_prompt': 'Проверьте код',
              'input_var': 'code',
              'output_var': 'review_result',
            },
          ),
        },
        edges: {
          'edge1': WorkflowEdge(
            id: 'edge1',
            sourceId: 'read',
            targetId: 'review',
            branchName: 'main',
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
        projectPath: Directory.systemTemp.path,
      );

      final events = client.run(request);

      // 5. Ожидаем приостановку
      await expectSuspended(events);

      // 6. Проверить статус
      final runRepo = Vault.instance.logged<WorkflowRun>(
        collection: 'workflow_runs',
        fromMap: WorkflowRun.fromMap,
      );
      final suspendedRun = await runRepo.findById(runId);
      expect(suspendedRun!.suspendedNodeId, 'review');

      // 7. Возобновить с решением
      final resumeRequest = GraphResumeRequest(
        runId: runId,
        userInput: {
          'review_result': 'approved',
        },
      );

      final resumeEvents = client.resume(resumeRequest);
      await expectCompleted(resumeEvents);

      // Cleanup
      await cleanupTestFile(testFilePath);
    }, timeout: Timeout(Duration(minutes: 3)));
  });

  group('Suspend/Resume - FileUpload Node', () {
    test('Приостановка на fileUpload и возобновление с путём к файлу', () async {
      // 1. Создать проект
      final project = await createTestProject(name: 'FileUpload Test');

      // 2. Создать граф с fileUpload узлом
      final workflowRepo = Vault.instance.versioned<WorkflowGraph>(
        collection: WorkflowGraph.kCollection,
        fromMap: WorkflowGraph.fromMap,
      );

      final workflow = WorkflowGraph(
        id: uuid(),
        tenantId: TestConfig.testTenantId,
        ownerId: project.id,
        name: 'Workflow with FileUpload',
        nodes: {
          'upload': WorkflowNode(
            id: 'upload',
            type: WorkflowNodeType.fileUpload,
            config: {
              'upload_prompt': 'Загрузите файл конфигурации',
              'output_var': 'config_path',
            },
          ),
          'read': WorkflowNode(
            id: 'read',
            type: WorkflowNodeType.fileRead,
            config: {
              'file_path_var': 'config_path',
              'output_var': 'config_content',
            },
          ),
        },
        edges: {
          'edge1': WorkflowEdge(
            id: 'edge1',
            sourceId: 'upload',
            targetId: 'read',
            branchName: 'main',
            type: WorkflowEdgeType.onSuccess,
          ),
        },
      );

      await workflowRepo.createEntity(workflow);

      // 3. Создать файл для "загрузки"
      final uploadedFile = await createTestFile('{"setting": "value"}');

      // 4. Запустить
      final client = GraphEngineClient(baseUrl: TestConfig.graphEngineUrl);
      final runId = uuid();
      final request = GraphRunRequest(
        runId: runId,
        projectId: project.id,
        blueprintId: workflow.id,
        projectPath: Directory.systemTemp.path,
      );

      final events = client.run(request);

      // 5. Ожидаем приостановку
      await expectSuspended(events);

      // 6. Возобновить с путём к файлу
      final resumeRequest = GraphResumeRequest(
        runId: runId,
        userInput: {
          'config_path': uploadedFile,
        },
      );

      final resumeEvents = client.resume(resumeRequest);
      await expectCompleted(resumeEvents);

      // 7. Проверить результат
      final runRepo = Vault.instance.logged<WorkflowRun>(
        collection: 'workflow_runs',
        fromMap: WorkflowRun.fromMap,
      );
      final run = await runRepo.findById(runId);
      expect(run!.status, 'completed');

      // Cleanup
      await cleanupTestFile(uploadedFile);
    }, timeout: Timeout(Duration(minutes: 3)));
  });

  group('Suspend/Resume - CoCreationChat Node', () {
    test('Приостановка на coCreationChat и возобновление с сообщением', () async {
      // 1. Создать проект
      final project = await createTestProject(name: 'CoCreation Test');

      // 2. Создать граф с coCreationChat узлом
      final workflowRepo = Vault.instance.versioned<WorkflowGraph>(
        collection: WorkflowGraph.kCollection,
        fromMap: WorkflowGraph.fromMap,
      );

      final workflow = WorkflowGraph(
        id: uuid(),
        tenantId: TestConfig.testTenantId,
        ownerId: project.id,
        name: 'Workflow with CoCreationChat',
        nodes: {
          'chat': WorkflowNode(
            id: 'chat',
            type: WorkflowNodeType.coCreationChat,
            config: {
              'initial_message': 'Давайте обсудим архитектуру',
              'output_var': 'chat_result',
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
        projectPath: Directory.systemTemp.path,
      );

      final events = client.run(request);

      // 4. Ожидаем приостановку
      await expectSuspended(events);

      // 5. Возобновить с ответом пользователя
      final resumeRequest = GraphResumeRequest(
        runId: runId,
        userInput: {
          'chat_result': 'Используем микросервисную архитектуру',
        },
      );

      final resumeEvents = client.resume(resumeRequest);
      await expectCompleted(resumeEvents);

      // 6. Проверить результат
      final runRepo = Vault.instance.logged<WorkflowRun>(
        collection: 'workflow_runs',
        fromMap: WorkflowRun.fromMap,
      );
      final run = await runRepo.findById(runId);
      expect(run!.status, 'completed');
    }, timeout: Timeout(Duration(minutes: 3)));
  });

  group('Suspend/Resume - Context Preservation', () {
    test('Сохранение контекста между suspend и resume', () async {
      // 1. Создать проект
      final project = await createTestProject(name: 'Context Preservation Test');

      // 2. Создать граф с переменными до и после suspend
      final workflowRepo = Vault.instance.versioned<WorkflowGraph>(
        collection: WorkflowGraph.kCollection,
        fromMap: WorkflowGraph.fromMap,
      );

      final tempDir = Directory.systemTemp.createTempSync('aq_test_');
      final outputPath = '${tempDir.path}/result.txt';

      final workflow = WorkflowGraph(
        id: uuid(),
        tenantId: TestConfig.testTenantId,
        ownerId: project.id,
        name: 'Context Preservation Workflow',
        nodes: {
          'set_var': WorkflowNode(
            id: 'set_var',
            type: WorkflowNodeType.fileWrite,
            config: {
              'file_path': '${tempDir.path}/temp.txt',
              'input_var': 'initial_value',
            },
          ),
          'input': WorkflowNode(
            id: 'input',
            type: WorkflowNodeType.userInput,
            config: {
              'prompt': 'Введите дополнительное значение',
              'output_var': 'additional_value',
            },
          ),
          'combine': WorkflowNode(
            id: 'combine',
            type: WorkflowNodeType.fileWrite,
            config: {
              'file_path': outputPath,
              'input_var': 'combined',
            },
          ),
        },
        edges: {
          'e1': WorkflowEdge(
            id: 'e1',
            sourceId: 'set_var',
            targetId: 'input',
            branchName: 'main',
            type: WorkflowEdgeType.onSuccess,
          ),
          'e2': WorkflowEdge(
            id: 'e2',
            sourceId: 'input',
            targetId: 'combine',
            branchName: 'main',
            type: WorkflowEdgeType.onSuccess,
          ),
        },
      );

      await workflowRepo.createEntity(workflow);

      // 3. Запустить с начальной переменной
      final client = GraphEngineClient(baseUrl: TestConfig.graphEngineUrl);
      final runId = uuid();
      final request = GraphRunRequest(
        runId: runId,
        projectId: project.id,
        blueprintId: workflow.id,
        projectPath: tempDir.path,
        initialVariables: {
          'initial_value': 'Начальное значение',
        },
      );

      final events = client.run(request);

      // 4. Ожидаем приостановку
      await expectSuspended(events);

      // 5. Возобновить с дополнительной переменной
      final resumeRequest = GraphResumeRequest(
        runId: runId,
        userInput: {
          'additional_value': 'Дополнительное значение',
          'combined': 'Начальное значение + Дополнительное значение',
        },
      );

      final resumeEvents = client.resume(resumeRequest);
      await expectCompleted(resumeEvents);

      // 6. Проверить что обе переменные доступны
      final outputFile = File(outputPath);
      expect(await outputFile.exists(), true);

      // Cleanup
      await tempDir.delete(recursive: true);
    }, timeout: Timeout(Duration(minutes: 3)));

    test('Audit trail при suspend/resume', () async {
      // 1. Создать проект
      final project = await createTestProject(name: 'Audit Trail Test');

      // 2. Создать простой граф с userInput
      final workflowRepo = Vault.instance.versioned<WorkflowGraph>(
        collection: WorkflowGraph.kCollection,
        fromMap: WorkflowGraph.fromMap,
      );

      final workflow = WorkflowGraph(
        id: uuid(),
        tenantId: TestConfig.testTenantId,
        ownerId: project.id,
        name: 'Audit Trail Workflow',
        nodes: {
          'input': WorkflowNode(
            id: 'input',
            type: WorkflowNodeType.userInput,
            config: {
              'prompt': 'Введите значение',
              'output_var': 'value',
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
        projectPath: Directory.systemTemp.path,
      );

      final events = client.run(request);
      await expectSuspended(events);

      // 4. Возобновить
      final resumeRequest = GraphResumeRequest(
        runId: runId,
        userInput: {'value': 'test'},
      );

      final resumeEvents = client.resume(resumeRequest);
      await expectCompleted(resumeEvents);

      // 5. Проверить audit trail
      final runRepo = Vault.instance.logged<WorkflowRun>(
        collection: 'workflow_runs',
        fromMap: WorkflowRun.fromMap,
      );

      final logs = await runRepo.getHistory(runId);

      expect(logs.isNotEmpty, true);

      // Проверить что есть записи о suspend и resume
      final operations = logs.map((l) => l['operation']).toList();
      expect(operations.contains('created'), true);
      expect(operations.contains('updated'), true);

      // Проверить что есть записи о смене статуса
      final statusChanges = logs.where((l) {
        final data = l['data'] as Map<String, dynamic>?;
        return data?['status'] != null;
      }).toList();

      expect(statusChanges.length >= 3, true); // created, suspended, completed
    }, timeout: Timeout(Duration(minutes: 3)));
  });
}
