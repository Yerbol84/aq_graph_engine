// Интеграционные тесты жизненного цикла InstructionGraph
//
// Покрывает:
// - Создание InstructionGraph через репозитории
// - Вызов из WorkflowGraph через RunInstructionNode
// - Валидацию контракта (inputs/outputs)
// - Циклы в InstructionGraph
// - Изолированный контекст выполнения

import 'package:test/test.dart';
import 'package:aq_schema/aq_schema.dart';
import 'package:aq_graph_engine/aq_graph_engine.dart';
import 'package:dart_vault/dart_vault.dart';
import 'test_helpers.dart';

void main() {
  setUpAll(() async {
    await connectToDataService();
  });

  group('InstructionGraph Lifecycle - Simple Execution', () {
    test('Создание и вызов простой инструкции через RunInstructionNode', () async {
      // 1. Создать проект
      final project = await createTestProject(name: 'Instruction Test');

      // 2. Создать InstructionGraph с контрактом
      final instruction = await createSimpleInstruction(
        projectId: project.id,
        contract: {
          'inputs': {
            'input_text': {'type': 'string', 'required': true},
          },
          'outputs': {
            'output_text': {'type': 'string'},
          },
        },
        nodes: [
          {
            'type': 'transform',
            'payload': {
              'input_var': 'input_text',
              'output_var': 'output_text',
              'transform': 'uppercase',
            },
          },
        ],
      );

      // 3. Создать WorkflowGraph с RunInstructionNode
      final workflowRepo = Vault.instance.versioned<WorkflowGraph>(
        collection: WorkflowGraph.kCollection,
        fromMap: WorkflowGraph.fromMap,
      );

      final workflow = WorkflowGraph(
        id: uuid(),
        tenantId: TestConfig.testTenantId,
        ownerId: project.id,
        name: 'Workflow with Instruction',
        nodes: {
          'node1': WorkflowNode(
            id: 'node1',
            type: WorkflowNodeType.runInstruction,
            config: {
              'instruction_blueprint_id': instruction.id,
              'input_mapping': {
                'input_text': 'test_value',
              },
              'output_mapping': {
                'output_text': 'result',
              },
            },
          ),
        },
        edges: {},
      );

      await workflowRepo.createEntity(workflow);

      // 4. Запустить через движок
      final client = GraphEngineClient(baseUrl: TestConfig.graphEngineUrl);
      final request = GraphRunRequest(
        runId: uuid(),
        projectId: project.id,
        blueprintId: workflow.id,
        projectPath: Directory.systemTemp.path,
        initialVariables: {
          'test_value': 'hello world',
        },
      );

      final events = client.run(request);

      // 5. Проверить успешное завершение
      await expectCompleted(events);

      // 6. Проверить результат
      final runRepo = Vault.instance.logged<WorkflowRun>(
        collection: 'workflow_runs',
        fromMap: WorkflowRun.fromMap,
      );
      final run = await runRepo.findById(request.runId);

      expect(run, isNotNull);
      expect(run!.status, 'completed');
    }, timeout: Timeout(Duration(minutes: 2)));

    test('Инструкция с несколькими узлами transform', () async {
      // 1. Создать проект
      final project = await createTestProject(name: 'Multi-Transform Test');

      // 2. Создать InstructionGraph с цепочкой преобразований
      final instruction = await createSimpleInstruction(
        projectId: project.id,
        contract: {
          'inputs': {
            'number': {'type': 'number', 'required': true},
          },
          'outputs': {
            'result': {'type': 'number'},
          },
        },
        nodes: [
          {
            'type': 'transform',
            'payload': {
              'input_var': 'number',
              'output_var': 'doubled',
              'transform': 'multiply',
              'factor': 2,
            },
          },
          {
            'type': 'transform',
            'payload': {
              'input_var': 'doubled',
              'output_var': 'result',
              'transform': 'add',
              'value': 10,
            },
          },
        ],
      );

      // 3. Создать WorkflowGraph
      final workflowRepo = Vault.instance.versioned<WorkflowGraph>(
        collection: WorkflowGraph.kCollection,
        fromMap: WorkflowGraph.fromMap,
      );

      final workflow = WorkflowGraph(
        id: uuid(),
        tenantId: TestConfig.testTenantId,
        ownerId: project.id,
        name: 'Workflow with Multi-Transform',
        nodes: {
          'node1': WorkflowNode(
            id: 'node1',
            type: WorkflowNodeType.runInstruction,
            config: {
              'instruction_blueprint_id': instruction.id,
              'input_mapping': {
                'number': 'input_number',
              },
              'output_mapping': {
                'result': 'final_result',
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
          'input_number': 5,
        },
      );

      final events = client.run(request);
      await expectCompleted(events);

      // 5. Проверить результат (5 * 2 + 10 = 20)
      final runRepo = Vault.instance.logged<WorkflowRun>(
        collection: 'workflow_runs',
        fromMap: WorkflowRun.fromMap,
      );
      final run = await runRepo.findById(request.runId);

      expect(run, isNotNull);
      expect(run!.status, 'completed');
    }, timeout: Timeout(Duration(minutes: 2)));
  });

  group('InstructionGraph Lifecycle - Contract Validation', () {
    test('Валидация обязательных входных параметров', () async {
      // 1. Создать проект
      final project = await createTestProject(name: 'Contract Validation Test');

      // 2. Создать InstructionGraph с обязательным параметром
      final instruction = await createSimpleInstruction(
        projectId: project.id,
        contract: {
          'inputs': {
            'required_param': {'type': 'string', 'required': true},
          },
          'outputs': {
            'result': {'type': 'string'},
          },
        },
        nodes: [
          {
            'type': 'transform',
            'payload': {
              'input_var': 'required_param',
              'output_var': 'result',
              'transform': 'identity',
            },
          },
        ],
      );

      // 3. Создать WorkflowGraph БЕЗ передачи обязательного параметра
      final workflowRepo = Vault.instance.versioned<WorkflowGraph>(
        collection: WorkflowGraph.kCollection,
        fromMap: WorkflowGraph.fromMap,
      );

      final workflow = WorkflowGraph(
        id: uuid(),
        tenantId: TestConfig.testTenantId,
        ownerId: project.id,
        name: 'Workflow with Missing Param',
        nodes: {
          'node1': WorkflowNode(
            id: 'node1',
            type: WorkflowNodeType.runInstruction,
            config: {
              'instruction_blueprint_id': instruction.id,
              'input_mapping': {
                // Намеренно НЕ передаём required_param
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
      );

      final events = client.run(request);

      // 5. Ожидаем ошибку валидации контракта
      await expectFailed(events);

      // 6. Проверить что ошибка связана с контрактом
      final runRepo = Vault.instance.logged<WorkflowRun>(
        collection: 'workflow_runs',
        fromMap: WorkflowRun.fromMap,
      );
      final run = await runRepo.findById(request.runId);

      expect(run, isNotNull);
      expect(run!.status, 'failed');
    }, timeout: Timeout(Duration(minutes: 2)));

    test('Валидация типов входных параметров', () async {
      // 1. Создать проект
      final project = await createTestProject(name: 'Type Validation Test');

      // 2. Создать InstructionGraph с типизированным параметром
      final instruction = await createSimpleInstruction(
        projectId: project.id,
        contract: {
          'inputs': {
            'number_param': {'type': 'number', 'required': true},
          },
          'outputs': {
            'result': {'type': 'number'},
          },
        },
        nodes: [
          {
            'type': 'transform',
            'payload': {
              'input_var': 'number_param',
              'output_var': 'result',
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
        name: 'Workflow with Wrong Type',
        nodes: {
          'node1': WorkflowNode(
            id: 'node1',
            type: WorkflowNodeType.runInstruction,
            config: {
              'instruction_blueprint_id': instruction.id,
              'input_mapping': {
                'number_param': 'string_value',
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

      // 4. Запустить с строкой вместо числа
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

      // 5. Ожидаем ошибку валидации типа
      await expectFailed(events);
    }, timeout: Timeout(Duration(minutes: 2)));
  });

  group('InstructionGraph Lifecycle - Conditional Logic', () {
    test('Условный узел с ветвлением', () async {
      // 1. Создать проект
      final project = await createTestProject(name: 'Condition Test');

      // 2. Создать InstructionGraph с условием
      final instructionRepo = Vault.instance.versioned<InstructionGraph>(
        collection: InstructionGraph.kCollection,
        fromMap: InstructionGraph.fromMap,
      );

      final instruction = InstructionGraph(
        id: uuid(),
        tenantId: TestConfig.testTenantId,
        ownerId: project.id,
        name: 'Conditional Instruction',
        nodes: {
          'check': InstructionNode(
            id: 'check',
            type: InstructionNodeType.condition,
            payload: {
              'condition': 'value > 10',
              'input_var': 'value',
            },
          ),
          'then_branch': InstructionNode(
            id: 'then_branch',
            type: InstructionNodeType.transform,
            payload: {
              'input_var': 'value',
              'output_var': 'result',
              'transform': 'set',
              'value': 'high',
            },
          ),
          'else_branch': InstructionNode(
            id: 'else_branch',
            type: InstructionNodeType.transform,
            payload: {
              'input_var': 'value',
              'output_var': 'result',
              'transform': 'set',
              'value': 'low',
            },
          ),
        },
        edges: {
          'edge1': InstructionEdge(
            id: 'edge1',
            sourceId: 'check',
            targetId: 'then_branch',
            trigger: 'true',
            branchName: 'then',
          ),
          'edge2': InstructionEdge(
            id: 'edge2',
            sourceId: 'check',
            targetId: 'else_branch',
            trigger: 'false',
            branchName: 'else',
          ),
        },
        contract: {
          'inputs': {
            'value': {'type': 'number', 'required': true},
          },
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
        name: 'Workflow with Condition',
        nodes: {
          'node1': WorkflowNode(
            id: 'node1',
            type: WorkflowNodeType.runInstruction,
            config: {
              'instruction_blueprint_id': instruction.id,
              'input_mapping': {
                'value': 'test_value',
              },
              'output_mapping': {
                'result': 'condition_result',
              },
            },
          ),
        },
        edges: {},
      );

      await workflowRepo.createEntity(workflow);

      // 4. Запустить с value > 10
      final client = GraphEngineClient(baseUrl: TestConfig.graphEngineUrl);
      final request1 = GraphRunRequest(
        runId: uuid(),
        projectId: project.id,
        blueprintId: workflow.id,
        projectPath: Directory.systemTemp.path,
        initialVariables: {
          'test_value': 15,
        },
      );

      final events1 = client.run(request1);
      await expectCompleted(events1);

      // 5. Запустить с value <= 10
      final request2 = GraphRunRequest(
        runId: uuid(),
        projectId: project.id,
        blueprintId: workflow.id,
        projectPath: Directory.systemTemp.path,
        initialVariables: {
          'test_value': 5,
        },
      );

      final events2 = client.run(request2);
      await expectCompleted(events2);

      // 6. Проверить результаты
      final runRepo = Vault.instance.logged<WorkflowRun>(
        collection: 'workflow_runs',
        fromMap: WorkflowRun.fromMap,
      );

      final run1 = await runRepo.findById(request1.runId);
      final run2 = await runRepo.findById(request2.runId);

      expect(run1, isNotNull);
      expect(run1!.status, 'completed');
      expect(run2, isNotNull);
      expect(run2!.status, 'completed');
    }, timeout: Timeout(Duration(minutes: 3)));
  });

  group('InstructionGraph Lifecycle - Loops', () {
    test('Цикл в InstructionGraph с ограничением maxSteps', () async {
      // 1. Создать проект
      final project = await createTestProject(name: 'Loop Test');

      // 2. Создать InstructionGraph с циклом
      final instructionRepo = Vault.instance.versioned<InstructionGraph>(
        collection: InstructionGraph.kCollection,
        fromMap: InstructionGraph.fromMap,
      );

      final instruction = InstructionGraph(
        id: uuid(),
        tenantId: TestConfig.testTenantId,
        ownerId: project.id,
        name: 'Loop Instruction',
        nodes: {
          'increment': InstructionNode(
            id: 'increment',
            type: InstructionNodeType.transform,
            payload: {
              'input_var': 'counter',
              'output_var': 'counter',
              'transform': 'add',
              'value': 1,
            },
          ),
          'check': InstructionNode(
            id: 'check',
            type: InstructionNodeType.condition,
            payload: {
              'condition': 'counter < 5',
              'input_var': 'counter',
            },
          ),
        },
        edges: {
          'edge1': InstructionEdge(
            id: 'edge1',
            sourceId: 'increment',
            targetId: 'check',
            trigger: 'completed',
            branchName: 'main',
          ),
          'edge2': InstructionEdge(
            id: 'edge2',
            sourceId: 'check',
            targetId: 'increment',
            trigger: 'true',
            branchName: 'loop',
          ),
        },
        contract: {
          'inputs': {
            'counter': {'type': 'number', 'required': true},
          },
          'outputs': {
            'counter': {'type': 'number'},
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
        name: 'Workflow with Loop',
        nodes: {
          'node1': WorkflowNode(
            id: 'node1',
            type: WorkflowNodeType.runInstruction,
            config: {
              'instruction_blueprint_id': instruction.id,
              'input_mapping': {
                'counter': 'initial_counter',
              },
              'output_mapping': {
                'counter': 'final_counter',
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
          'initial_counter': 0,
        },
      );

      final events = client.run(request);
      await expectCompleted(events);

      // 5. Проверить что цикл выполнился
      final runRepo = Vault.instance.logged<WorkflowRun>(
        collection: 'workflow_runs',
        fromMap: WorkflowRun.fromMap,
      );
      final run = await runRepo.findById(request.runId);

      expect(run, isNotNull);
      expect(run!.status, 'completed');
    }, timeout: Timeout(Duration(minutes: 3)));

    test('Защита от бесконечного цикла (maxSteps=20)', () async {
      // 1. Создать проект
      final project = await createTestProject(name: 'Infinite Loop Test');

      // 2. Создать InstructionGraph с бесконечным циклом
      final instructionRepo = Vault.instance.versioned<InstructionGraph>(
        collection: InstructionGraph.kCollection,
        fromMap: InstructionGraph.fromMap,
      );

      final instruction = InstructionGraph(
        id: uuid(),
        tenantId: TestConfig.testTenantId,
        ownerId: project.id,
        name: 'Infinite Loop Instruction',
        nodes: {
          'step': InstructionNode(
            id: 'step',
            type: InstructionNodeType.transform,
            payload: {
              'input_var': 'value',
              'output_var': 'value',
              'transform': 'identity',
            },
          ),
        },
        edges: {
          'loop': InstructionEdge(
            id: 'loop',
            sourceId: 'step',
            targetId: 'step',
            trigger: 'completed',
            branchName: 'main',
          ),
        },
        contract: {
          'inputs': {
            'value': {'type': 'string', 'required': true},
          },
          'outputs': {
            'value': {'type': 'string'},
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
        name: 'Workflow with Infinite Loop',
        nodes: {
          'node1': WorkflowNode(
            id: 'node1',
            type: WorkflowNodeType.runInstruction,
            config: {
              'instruction_blueprint_id': instruction.id,
              'input_mapping': {
                'value': 'test',
              },
              'output_mapping': {
                'value': 'result',
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

      // 5. Ожидаем ошибку из-за превышения maxSteps
      await expectFailed(events);

      // 6. Проверить что ошибка связана с maxSteps
      final runRepo = Vault.instance.logged<WorkflowRun>(
        collection: 'workflow_runs',
        fromMap: WorkflowRun.fromMap,
      );
      final run = await runRepo.findById(request.runId);

      expect(run, isNotNull);
      expect(run!.status, 'failed');
    }, timeout: Timeout(Duration(minutes: 3)));
  });

  group('InstructionGraph Lifecycle - Isolated Context', () {
    test('Изоляция контекста между инструкциями', () async {
      // 1. Создать проект
      final project = await createTestProject(name: 'Context Isolation Test');

      // 2. Создать первую инструкцию
      final instruction1 = await createSimpleInstruction(
        projectId: project.id,
        contract: {
          'inputs': {},
          'outputs': {
            'internal_var': {'type': 'string'},
          },
        },
        nodes: [
          {
            'type': 'transform',
            'payload': {
              'output_var': 'internal_var',
              'transform': 'set',
              'value': 'secret_value',
            },
          },
        ],
      );

      // 3. Создать вторую инструкцию (не должна видеть internal_var)
      final instruction2 = await createSimpleInstruction(
        projectId: project.id,
        contract: {
          'inputs': {},
          'outputs': {
            'result': {'type': 'string'},
          },
        },
        nodes: [
          {
            'type': 'transform',
            'payload': {
              'input_var': 'internal_var',
              'output_var': 'result',
              'transform': 'identity',
            },
          },
        ],
      );

      // 4. Создать WorkflowGraph с двумя инструкциями
      final workflowRepo = Vault.instance.versioned<WorkflowGraph>(
        collection: WorkflowGraph.kCollection,
        fromMap: WorkflowGraph.fromMap,
      );

      final workflow = WorkflowGraph(
        id: uuid(),
        tenantId: TestConfig.testTenantId,
        ownerId: project.id,
        name: 'Workflow with Isolated Instructions',
        nodes: {
          'inst1': WorkflowNode(
            id: 'inst1',
            type: WorkflowNodeType.runInstruction,
            config: {
              'instruction_blueprint_id': instruction1.id,
              'input_mapping': {},
              'output_mapping': {
                'internal_var': 'var1',
              },
            },
          ),
          'inst2': WorkflowNode(
            id: 'inst2',
            type: WorkflowNodeType.runInstruction,
            config: {
              'instruction_blueprint_id': instruction2.id,
              'input_mapping': {},
              'output_mapping': {
                'result': 'var2',
              },
            },
          ),
        },
        edges: {
          'edge1': WorkflowEdge(
            id: 'edge1',
            sourceId: 'inst1',
            targetId: 'inst2',
            branchName: 'main',
            type: WorkflowEdgeType.onSuccess,
          ),
        },
      );

      await workflowRepo.createEntity(workflow);

      // 5. Запустить
      final client = GraphEngineClient(baseUrl: TestConfig.graphEngineUrl);
      final request = GraphRunRequest(
        runId: uuid(),
        projectId: project.id,
        blueprintId: workflow.id,
        projectPath: Directory.systemTemp.path,
      );

      final events = client.run(request);

      // 6. Вторая инструкция должна упасть из-за отсутствия internal_var
      await expectFailed(events);
    }, timeout: Timeout(Duration(minutes: 3)));
  });
}
