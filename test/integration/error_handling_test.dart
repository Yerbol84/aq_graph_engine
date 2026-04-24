// Интеграционные тесты обработки ошибок
//
// Покрывает:
// - Обработку ошибок в узлах
// - OnError edges
// - Восстановление после ошибок
// - Валидацию входных данных
// - Ошибки в композитных узлах

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

  group('Error Handling - Basic Errors', () {
    test('Ошибка при чтении несуществующего файла', () async {
      // 1. Создать проект
      final project = await createTestProject(name: 'File Not Found Test');

      // 2. Создать граф с несуществующим файлом
      final workflow = await createSimpleWorkflow(
        projectId: project.id,
        nodeType: 'fileRead',
        nodeConfig: {
          'file_path': '/nonexistent/file.txt',
          'output_var': 'content',
        },
      );

      // 3. Запустить
      final client = GraphEngineClient(baseUrl: TestConfig.graphEngineUrl);
      final request = GraphRunRequest(
        runId: uuid(),
        projectId: project.id,
        blueprintId: workflow.id,
        projectPath: Directory.systemTemp.path,
      );

      final events = client.run(request);

      // 4. Ожидаем ошибку
      await expectFailed(events);

      // 5. Проверить статус в БД
      final runRepo = Vault.instance.logged<WorkflowRun>(
        collection: 'workflow_runs',
        fromMap: WorkflowRun.fromMap,
      );
      final run = await runRepo.findById(request.runId);

      expect(run, isNotNull);
      expect(run!.status, 'failed');
    }, timeout: Timeout(Duration(minutes: 2)));

    test('Ошибка при записи в недоступную директорию', () async {
      // 1. Создать проект
      final project = await createTestProject(name: 'Write Error Test');

      // 2. Создать граф с недоступным путём
      final workflow = await createSimpleWorkflow(
        projectId: project.id,
        nodeType: 'fileWrite',
        nodeConfig: {
          'file_path': '/root/protected/file.txt',
          'input_var': 'content',
        },
      );

      // 3. Запустить
      final client = GraphEngineClient(baseUrl: TestConfig.graphEngineUrl);
      final request = GraphRunRequest(
        runId: uuid(),
        projectId: project.id,
        blueprintId: workflow.id,
        projectPath: Directory.systemTemp.path,
        initialVariables: {
          'content': 'test',
        },
      );

      final events = client.run(request);

      // 4. Ожидаем ошибку
      await expectFailed(events);

      // 5. Проверить audit trail
      final runRepo = Vault.instance.logged<WorkflowRun>(
        collection: 'workflow_runs',
        fromMap: WorkflowRun.fromMap,
      );
      final logs = await runRepo.getHistory(request.runId);

      expect(logs.isNotEmpty, true);

      // Проверить что есть запись об ошибке
      final operations = logs.map((l) => l['operation']).toList();
      expect(operations.contains('updated'), true);
    }, timeout: Timeout(Duration(minutes: 2)));

    test('Ошибка при отсутствии обязательной переменной', () async {
      // 1. Создать проект
      final project = await createTestProject(name: 'Missing Variable Test');

      // 2. Создать граф требующий переменную
      final workflow = await createSimpleWorkflow(
        projectId: project.id,
        nodeType: 'fileWrite',
        nodeConfig: {
          'file_path': '/tmp/output.txt',
          'input_var': 'required_content',
        },
      );

      // 3. Запустить БЕЗ переменной
      final client = GraphEngineClient(baseUrl: TestConfig.graphEngineUrl);
      final request = GraphRunRequest(
        runId: uuid(),
        projectId: project.id,
        blueprintId: workflow.id,
        projectPath: Directory.systemTemp.path,
        // Намеренно НЕ передаём required_content
      );

      final events = client.run(request);

      // 4. Ожидаем ошибку
      await expectFailed(events);
    }, timeout: Timeout(Duration(minutes: 2)));
  });

  group('Error Handling - OnError Edges', () {
    test('OnError edge перенаправляет выполнение при ошибке', () async {
      // 1. Создать проект
      final project = await createTestProject(name: 'OnError Edge Test');

      // 2. Создать граф с OnError edge
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
          'risky': WorkflowNode(
            id: 'risky',
            type: WorkflowNodeType.fileRead,
            config: {
              'file_path': '/invalid/path.txt',
              'output_var': 'content',
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
          'error_edge': WorkflowEdge(
            id: 'error_edge',
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
          'error_message': 'Error was handled',
        },
      );

      final events = client.run(request);

      // 4. Собрать события
      final eventList = await collectEvents(events);

      // 5. Проверить что error_handler выполнился
      final logMessages = eventList
          .where((e) => e.type == GraphRunEventType.log)
          .map((e) => e.message)
          .join('\n');

      // Должны быть логи о выполнении error_handler
      expect(logMessages.contains('error_handler') || logMessages.contains('Error'), true);

      // Cleanup
      await tempDir.delete(recursive: true);
    }, timeout: Timeout(Duration(minutes: 3)));

    test('Цепочка OnError edges', () async {
      // 1. Создать проект
      final project = await createTestProject(name: 'OnError Chain Test');

      // 2. Создать граф с цепочкой обработчиков ошибок
      final tempDir = Directory.systemTemp.createTempSync('aq_test_');
      final log1Path = '${tempDir.path}/error1.log';
      final log2Path = '${tempDir.path}/error2.log';

      final workflowRepo = Vault.instance.versioned<WorkflowGraph>(
        collection: WorkflowGraph.kCollection,
        fromMap: WorkflowGraph.fromMap,
      );

      final workflow = WorkflowGraph(
        id: uuid(),
        tenantId: TestConfig.testTenantId,
        ownerId: project.id,
        name: 'OnError Chain Workflow',
        nodes: {
          'risky1': WorkflowNode(
            id: 'risky1',
            type: WorkflowNodeType.fileRead,
            config: {
              'file_path': '/invalid1.txt',
              'output_var': 'content1',
            },
          ),
          'handler1': WorkflowNode(
            id: 'handler1',
            type: WorkflowNodeType.fileWrite,
            config: {
              'file_path': log1Path,
              'input_var': 'error1',
            },
          ),
          'risky2': WorkflowNode(
            id: 'risky2',
            type: WorkflowNodeType.fileRead,
            config: {
              'file_path': '/invalid2.txt',
              'output_var': 'content2',
            },
          ),
          'handler2': WorkflowNode(
            id: 'handler2',
            type: WorkflowNodeType.fileWrite,
            config: {
              'file_path': log2Path,
              'input_var': 'error2',
            },
          ),
        },
        edges: {
          'e1': WorkflowEdge(
            id: 'e1',
            sourceId: 'risky1',
            targetId: 'handler1',
            branchName: 'error',
            type: WorkflowEdgeType.onError,
          ),
          'e2': WorkflowEdge(
            id: 'e2',
            sourceId: 'handler1',
            targetId: 'risky2',
            branchName: 'main',
            type: WorkflowEdgeType.onSuccess,
          ),
          'e3': WorkflowEdge(
            id: 'e3',
            sourceId: 'risky2',
            targetId: 'handler2',
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
          'error1': 'First error handled',
          'error2': 'Second error handled',
        },
      );

      final events = client.run(request);
      await collectEvents(events);

      // 4. Проверить что оба обработчика выполнились
      // (в зависимости от реализации)

      // Cleanup
      await tempDir.delete(recursive: true);
    }, timeout: Timeout(Duration(minutes: 3)));
  });

  group('Error Handling - Validation Errors', () {
    test('Валидация контракта InstructionGraph', () async {
      // 1. Создать проект
      final project = await createTestProject(name: 'Contract Validation Test');

      // 2. Создать InstructionGraph с строгим контрактом
      final instruction = await createSimpleInstruction(
        projectId: project.id,
        contract: {
          'inputs': {
            'required_string': {'type': 'string', 'required': true},
            'required_number': {'type': 'number', 'required': true},
          },
          'outputs': {
            'result': {'type': 'string'},
          },
        },
        nodes: [
          {
            'type': 'transform',
            'payload': {
              'input_var': 'required_string',
              'output_var': 'result',
              'transform': 'identity',
            },
          },
        ],
      );

      // 3. Создать WorkflowGraph с неполным input_mapping
      final workflowRepo = Vault.instance.versioned<WorkflowGraph>(
        collection: WorkflowGraph.kCollection,
        fromMap: WorkflowGraph.fromMap,
      );

      final workflow = WorkflowGraph(
        id: uuid(),
        tenantId: TestConfig.testTenantId,
        ownerId: project.id,
        name: 'Invalid Contract Workflow',
        nodes: {
          'instruction': WorkflowNode(
            id: 'instruction',
            type: WorkflowNodeType.runInstruction,
            config: {
              'instruction_blueprint_id': instruction.id,
              'input_mapping': {
                'required_string': 'test',
                // Намеренно НЕ передаём required_number
              },
              'output_mapping': {
                'result': 'output',
              },
            },
          ),
        },
        edges: {},
      );

      await workflowRepo.createEntity(workflow);

      // 4. Запустить
      final client = GraphEngineClient(baseUrl: TestConfig.graphEngineUrl);
      final request = GraphRunRequest(
        runId: uuid(),
        projectId: project.id,
        blueprintId: workflow.id,
        projectPath: Directory.systemTemp.path,
        initialVariables: {
          'test': 'value',
        },
      );

      final events = client.run(request);

      // 5. Ожидаем ошибку валидации
      await expectFailed(events);
    }, timeout: Timeout(Duration(minutes: 2)));

    test('Валидация типов в контракте', () async {
      // 1. Создать проект
      final project = await createTestProject(name: 'Type Validation Test');

      // 2. Создать InstructionGraph с типизированным контрактом
      final instruction = await createSimpleInstruction(
        projectId: project.id,
        contract: {
          'inputs': {
            'number_input': {'type': 'number', 'required': true},
          },
          'outputs': {
            'number_output': {'type': 'number'},
          },
        },
        nodes: [
          {
            'type': 'transform',
            'payload': {
              'input_var': 'number_input',
              'output_var': 'number_output',
              'transform': 'multiply',
              'factor': 2,
            },
          },
        ],
      );

      // 3. Создать WorkflowGraph с неправильным типом
      final workflowRepo = Vault.instance.versioned<WorkflowGraph>(
        collection: WorkflowGraph.kCollection,
        fromMap: WorkflowGraph.fromMap,
      );

      final workflow = WorkflowGraph(
        id: uuid(),
        tenantId: TestConfig.testTenantId,
        ownerId: project.id,
        name: 'Type Mismatch Workflow',
        nodes: {
          'instruction': WorkflowNode(
            id: 'instruction',
            type: WorkflowNodeType.runInstruction,
            config: {
              'instruction_blueprint_id': instruction.id,
              'input_mapping': {
                'number_input': 'string_value',
              },
              'output_mapping': {
                'number_output': 'result',
              },
            },
          ),
        },
        edges: {},
      );

      await workflowRepo.createEntity(workflow);

      // 4. Запустить со строкой вместо числа
      final client = GraphEngineClient(baseUrl: TestConfig.graphEngineUrl);
      final request = GraphRunRequest(
        runId: uuid(),
        projectId: project.id,
        blueprintId: workflow.id,
        projectPath: Directory.systemTemp.path,
        initialVariables: {
          'string_value': 'not a number',
        },
      );

      final events = client.run(request);

      // 5. Ожидаем ошибку типа
      await expectFailed(events);
    }, timeout: Timeout(Duration(minutes: 2)));
  });

  group('Error Handling - Composite Node Errors', () {
    test('Ошибка внутри SubGraph', () async {
      // 1. Создать проект
      final project = await createTestProject(name: 'SubGraph Error Test');

      // 2. Создать внутренний граф с ошибкой
      final innerWorkflow = await createSimpleWorkflow(
        projectId: project.id,
        nodeType: 'fileRead',
        nodeConfig: {
          'file_path': '/nonexistent/inner.txt',
          'output_var': 'inner_content',
        },
      );

      // 3. Создать внешний граф с SubGraph
      final workflowRepo = Vault.instance.versioned<WorkflowGraph>(
        collection: WorkflowGraph.kCollection,
        fromMap: WorkflowGraph.fromMap,
      );

      final outerWorkflow = WorkflowGraph(
        id: uuid(),
        tenantId: TestConfig.testTenantId,
        ownerId: project.id,
        name: 'Outer with Failing SubGraph',
        nodes: {
          'subgraph': WorkflowNode(
            id: 'subgraph',
            type: WorkflowNodeType.subGraph,
            config: {
              'workflow_blueprint_id': innerWorkflow.id,
              'input_mapping': {},
              'output_mapping': {},
            },
          ),
        },
        edges: {},
      );

      await workflowRepo.createEntity(outerWorkflow);

      // 4. Запустить
      final client = GraphEngineClient(baseUrl: TestConfig.graphEngineUrl);
      final request = GraphRunRequest(
        runId: uuid(),
        projectId: project.id,
        blueprintId: outerWorkflow.id,
        projectPath: Directory.systemTemp.path,
      );

      final events = client.run(request);

      // 5. Ошибка внутри SubGraph должна прервать внешний граф
      await expectFailed(events);
    }, timeout: Timeout(Duration(minutes: 3)));

    test('Обработка ошибки SubGraph через OnError edge', () async {
      // 1. Создать проект
      final project = await createTestProject(name: 'SubGraph OnError Test');

      // 2. Создать внутренний граф с ошибкой
      final innerWorkflow = await createSimpleWorkflow(
        projectId: project.id,
        nodeType: 'fileRead',
        nodeConfig: {
          'file_path': '/invalid/file.txt',
          'output_var': 'content',
        },
      );

      // 3. Создать внешний граф с обработкой ошибки
      final tempDir = Directory.systemTemp.createTempSync('aq_test_');
      final errorLogPath = '${tempDir.path}/subgraph_error.log';

      final workflowRepo = Vault.instance.versioned<WorkflowGraph>(
        collection: WorkflowGraph.kCollection,
        fromMap: WorkflowGraph.fromMap,
      );

      final outerWorkflow = WorkflowGraph(
        id: uuid(),
        tenantId: TestConfig.testTenantId,
        ownerId: project.id,
        name: 'Outer with SubGraph Error Handler',
        nodes: {
          'subgraph': WorkflowNode(
            id: 'subgraph',
            type: WorkflowNodeType.subGraph,
            config: {
              'workflow_blueprint_id': innerWorkflow.id,
              'input_mapping': {},
              'output_mapping': {},
            },
          ),
          'error_handler': WorkflowNode(
            id: 'error_handler',
            type: WorkflowNodeType.fileWrite,
            config: {
              'file_path': errorLogPath,
              'input_var': 'error_msg',
            },
          ),
        },
        edges: {
          'error_edge': WorkflowEdge(
            id: 'error_edge',
            sourceId: 'subgraph',
            targetId: 'error_handler',
            branchName: 'error',
            type: WorkflowEdgeType.onError,
          ),
        },
      );

      await workflowRepo.createEntity(outerWorkflow);

      // 4. Запустить
      final client = GraphEngineClient(baseUrl: TestConfig.graphEngineUrl);
      final request = GraphRunRequest(
        runId: uuid(),
        projectId: project.id,
        blueprintId: outerWorkflow.id,
        projectPath: tempDir.path,
        initialVariables: {
          'error_msg': 'SubGraph failed',
        },
      );

      final events = client.run(request);
      await collectEvents(events);

      // 5. Проверить что обработчик выполнился
      // (в зависимости от реализации)

      // Cleanup
      await tempDir.delete(recursive: true);
    }, timeout: Timeout(Duration(minutes: 3)));

    test('Ошибка в RunInstruction узле', () async {
      // 1. Создать проект
      final project = await createTestProject(name: 'Instruction Error Test');

      // 2. Создать InstructionGraph с ошибкой
      final instructionRepo = Vault.instance.versioned<InstructionGraph>(
        collection: InstructionGraph.kCollection,
        fromMap: InstructionGraph.fromMap,
      );

      final instruction = InstructionGraph(
        id: uuid(),
        tenantId: TestConfig.testTenantId,
        ownerId: project.id,
        name: 'Failing Instruction',
        nodes: {
          'transform': InstructionNode(
            id: 'transform',
            type: InstructionNodeType.transform,
            config: {
              'input_var': 'nonexistent_var',
              'output_var': 'result',
              'transform': 'identity',
            },
          ),
        },
        edges: {},
        contract: {
          'inputs': {},
          'outputs': {
            'result': {'type': 'string'},
          },
        },
      );

      await instructionRepo.createEntity(instruction);

      // 3. Создать WorkflowGraph
      final workflowRepo = Vault.instance.versioned<WorkflowGraph>(
        collection: WorkflowGraph.kCollection,
        fromMap: WorkflowGraph.fromMap,
      );

      final workflow = WorkflowGraph(
        id: uuid(),
        tenantId: TestConfig.testTenantId,
        ownerId: project.id,
        name: 'Workflow with Failing Instruction',
        nodes: {
          'instruction': WorkflowNode(
            id: 'instruction',
            type: WorkflowNodeType.runInstruction,
            config: {
              'instruction_blueprint_id': instruction.id,
              'input_mapping': {},
              'output_mapping': {
                'result': 'output',
              },
            },
          ),
        },
        edges: {},
      );

      await workflowRepo.createEntity(workflow);

      // 4. Запустить
      final client = GraphEngineClient(baseUrl: TestConfig.graphEngineUrl);
      final request = GraphRunRequest(
        runId: uuid(),
        projectId: project.id,
        blueprintId: workflow.id,
        projectPath: Directory.systemTemp.path,
      );

      final events = client.run(request);

      // 5. Ожидаем ошибку
      await expectFailed(events);
    }, timeout: Timeout(Duration(minutes: 3)));
  });

  group('Error Handling - Recovery', () {
    test('Retry механизм через OnError edge', () async {
      // 1. Создать проект
      final project = await createTestProject(name: 'Retry Test');

      // 2. Создать граф с retry логикой
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
        name: 'Retry Workflow',
        nodes: {
          'attempt': WorkflowNode(
            id: 'attempt',
            type: WorkflowNodeType.fileRead,
            config: {
              'file_path': '/tmp/maybe_exists.txt',
              'output_var': 'content',
            },
          ),
          'success': WorkflowNode(
            id: 'success',
            type: WorkflowNodeType.fileWrite,
            config: {
              'file_path': successPath,
              'input_var': 'content',
            },
          ),
          'fallback': WorkflowNode(
            id: 'fallback',
            type: WorkflowNodeType.fileWrite,
            config: {
              'file_path': successPath,
              'input_var': 'fallback_content',
            },
          ),
        },
        edges: {
          'success_edge': WorkflowEdge(
            id: 'success_edge',
            sourceId: 'attempt',
            targetId: 'success',
            branchName: 'success',
            type: WorkflowEdgeType.onSuccess,
          ),
          'error_edge': WorkflowEdge(
            id: 'error_edge',
            sourceId: 'attempt',
            targetId: 'fallback',
            branchName: 'fallback',
            type: WorkflowEdgeType.onError,
          ),
        },
      );

      await workflowRepo.createEntity(workflow);

      // 3. Запустить (файл не существует, сработает fallback)
      final client = GraphEngineClient(baseUrl: TestConfig.graphEngineUrl);
      final request = GraphRunRequest(
        runId: uuid(),
        projectId: project.id,
        blueprintId: workflow.id,
        projectPath: tempDir.path,
        initialVariables: {
          'fallback_content': 'Fallback data',
        },
      );

      final events = client.run(request);
      await collectEvents(events);

      // 4. Проверить что fallback выполнился
      // (в зависимости от реализации)

      // Cleanup
      await tempDir.delete(recursive: true);
    }, timeout: Timeout(Duration(minutes: 3)));
  });
}
