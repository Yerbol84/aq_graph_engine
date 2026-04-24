// Интеграционные тесты композитных узлов
//
// Покрывает:
// - SubGraph узел (вложенный WorkflowGraph)
// - RunInstruction узел (вызов InstructionGraph)
// - Передачу контекста между уровнями
// - Вложенность нескольких уровней
// - Output mapping

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

  group('Composite Nodes - SubGraph', () {
    test('Простой SubGraph с одним узлом', () async {
      // 1. Создать проект
      final project = await createTestProject(name: 'SubGraph Test');

      // 2. Создать внутренний граф (SubGraph)
      final tempDir = Directory.systemTemp.createTempSync('aq_test_');
      final innerOutput = '${tempDir.path}/inner.txt';

      final innerWorkflow = await createSimpleWorkflow(
        projectId: project.id,
        nodeType: 'fileWrite',
        nodeConfig: {
          'file_path': innerOutput,
          'input_var': 'inner_data',
        },
      );

      // 3. Создать внешний граф с SubGraph узлом
      final workflowRepo = Vault.instance.versioned<WorkflowGraph>(
        collection: WorkflowGraph.kCollection,
        fromMap: WorkflowGraph.fromMap,
      );

      final outerWorkflow = WorkflowGraph(
        id: uuid(),
        tenantId: TestConfig.testTenantId,
        ownerId: project.id,
        name: 'Outer Workflow with SubGraph',
        nodes: {
          'subgraph': WorkflowNode(
            id: 'subgraph',
            type: WorkflowNodeType.subGraph,
            config: {
              'workflow_blueprint_id': innerWorkflow.id,
              'input_mapping': {
                'inner_data': 'outer_data',
              },
              'output_mapping': {},
            },
          ),
        },
        edges: {},
      );

      await workflowRepo.createEntity(outerWorkflow);

      // 4. Запустить внешний граф
      final client = GraphEngineClient(baseUrl: TestConfig.graphEngineUrl);
      final request = GraphRunRequest(
        runId: uuid(),
        projectId: project.id,
        blueprintId: outerWorkflow.id,
        projectPath: tempDir.path,
        initialVariables: {
          'outer_data': 'Data from outer workflow',
        },
      );

      final events = client.run(request);

      // 5. Проверить успешное завершение
      await expectCompleted(events);

      // 6. Проверить что внутренний граф выполнился
      final outputFile = File(innerOutput);
      expect(await outputFile.exists(), true);
      final content = await outputFile.readAsString();
      expect(content, 'Data from outer workflow');

      // Cleanup
      await tempDir.delete(recursive: true);
    }, timeout: Timeout(Duration(minutes: 3)));

    test('SubGraph с output mapping', () async {
      // 1. Создать проект
      final project = await createTestProject(name: 'SubGraph Output Test');

      // 2. Создать внутренний граф который читает файл
      final inputFile = await createTestFile('Inner content');

      final innerWorkflow = await createSimpleWorkflow(
        projectId: project.id,
        nodeType: 'fileRead',
        nodeConfig: {
          'file_path': inputFile,
          'output_var': 'inner_result',
        },
      );

      // 3. Создать внешний граф с SubGraph и последующей обработкой
      final tempDir = Directory.systemTemp.createTempSync('aq_test_');
      final finalOutput = '${tempDir.path}/final.txt';

      final workflowRepo = Vault.instance.versioned<WorkflowGraph>(
        collection: WorkflowGraph.kCollection,
        fromMap: WorkflowGraph.fromMap,
      );

      final outerWorkflow = WorkflowGraph(
        id: uuid(),
        tenantId: TestConfig.testTenantId,
        ownerId: project.id,
        name: 'Outer with Output Mapping',
        nodes: {
          'subgraph': WorkflowNode(
            id: 'subgraph',
            type: WorkflowNodeType.subGraph,
            config: {
              'workflow_blueprint_id': innerWorkflow.id,
              'input_mapping': {},
              'output_mapping': {
                'inner_result': 'outer_result',
              },
            },
          ),
          'process': WorkflowNode(
            id: 'process',
            type: WorkflowNodeType.fileWrite,
            config: {
              'file_path': finalOutput,
              'input_var': 'outer_result',
            },
          ),
        },
        edges: {
          'edge1': WorkflowEdge(
            id: 'edge1',
            sourceId: 'subgraph',
            targetId: 'process',
            branchName: 'main',
            type: WorkflowEdgeType.onSuccess,
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
      );

      final events = client.run(request);
      await expectCompleted(events);

      // 5. Проверить что результат передан из SubGraph
      final outputFile = File(finalOutput);
      expect(await outputFile.exists(), true);
      final content = await outputFile.readAsString();
      expect(content, 'Inner content');

      // Cleanup
      await cleanupTestFile(inputFile);
      await tempDir.delete(recursive: true);
    }, timeout: Timeout(Duration(minutes: 3)));

    test('Вложенные SubGraph (3 уровня)', () async {
      // 1. Создать проект
      final project = await createTestProject(name: 'Nested SubGraph Test');

      // 2. Создать самый внутренний граф (уровень 3)
      final tempDir = Directory.systemTemp.createTempSync('aq_test_');
      final level3Output = '${tempDir.path}/level3.txt';

      final level3Workflow = await createSimpleWorkflow(
        projectId: project.id,
        nodeType: 'fileWrite',
        nodeConfig: {
          'file_path': level3Output,
          'input_var': 'level3_data',
        },
      );

      // 3. Создать средний граф (уровень 2) с SubGraph
      final workflowRepo = Vault.instance.versioned<WorkflowGraph>(
        collection: WorkflowGraph.kCollection,
        fromMap: WorkflowGraph.fromMap,
      );

      final level2Workflow = WorkflowGraph(
        id: uuid(),
        tenantId: TestConfig.testTenantId,
        ownerId: project.id,
        name: 'Level 2 Workflow',
        nodes: {
          'subgraph': WorkflowNode(
            id: 'subgraph',
            type: WorkflowNodeType.subGraph,
            config: {
              'workflow_blueprint_id': level3Workflow.id,
              'input_mapping': {
                'level3_data': 'level2_data',
              },
              'output_mapping': {},
            },
          ),
        },
        edges: {},
      );

      await workflowRepo.createEntity(level2Workflow);

      // 4. Создать внешний граф (уровень 1) с SubGraph
      final level1Workflow = WorkflowGraph(
        id: uuid(),
        tenantId: TestConfig.testTenantId,
        ownerId: project.id,
        name: 'Level 1 Workflow',
        nodes: {
          'subgraph': WorkflowNode(
            id: 'subgraph',
            type: WorkflowNodeType.subGraph,
            config: {
              'workflow_blueprint_id': level2Workflow.id,
              'input_mapping': {
                'level2_data': 'level1_data',
              },
              'output_mapping': {},
            },
          ),
        },
        edges: {},
      );

      await workflowRepo.createEntity(level1Workflow);

      // 5. Запустить уровень 1
      final client = GraphEngineClient(baseUrl: TestConfig.graphEngineUrl);
      final request = GraphRunRequest(
        runId: uuid(),
        projectId: project.id,
        blueprintId: level1Workflow.id,
        projectPath: tempDir.path,
        initialVariables: {
          'level1_data': 'Data from level 1',
        },
      );

      final events = client.run(request);
      await expectCompleted(events);

      // 6. Проверить что данные прошли через все уровни
      final outputFile = File(level3Output);
      expect(await outputFile.exists(), true);
      final content = await outputFile.readAsString();
      expect(content, 'Data from level 1');

      // Cleanup
      await tempDir.delete(recursive: true);
    }, timeout: Timeout(Duration(minutes: 4)));
  });

  group('Composite Nodes - RunInstruction', () {
    test('Простой RunInstruction с transform', () async {
      // 1. Создать проект
      final project = await createTestProject(name: 'RunInstruction Test');

      // 2. Создать InstructionGraph
      final instruction = await createSimpleInstruction(
        projectId: project.id,
        contract: {
          'inputs': {
            'input': {'type': 'string', 'required': true},
          },
          'outputs': {
            'output': {'type': 'string'},
          },
        },
        nodes: [
          {
            'type': 'transform',
            'payload': {
              'input_var': 'input',
              'output_var': 'output',
              'transform': 'uppercase',
            },
          },
        ],
      );

      // 3. Создать WorkflowGraph с RunInstruction
      final tempDir = Directory.systemTemp.createTempSync('aq_test_');
      final outputPath = '${tempDir.path}/output.txt';

      final workflowRepo = Vault.instance.versioned<WorkflowGraph>(
        collection: WorkflowGraph.kCollection,
        fromMap: WorkflowGraph.fromMap,
      );

      final workflow = WorkflowGraph(
        id: uuid(),
        tenantId: TestConfig.testTenantId,
        ownerId: project.id,
        name: 'Workflow with RunInstruction',
        nodes: {
          'instruction': WorkflowNode(
            id: 'instruction',
            type: WorkflowNodeType.runInstruction,
            config: {
              'instruction_blueprint_id': instruction.id,
              'input_mapping': {
                'input': 'workflow_data',
              },
              'output_mapping': {
                'output': 'transformed_data',
              },
            },
          ),
          'write': WorkflowNode(
            id: 'write',
            type: WorkflowNodeType.fileWrite,
            config: {
              'file_path': outputPath,
              'input_var': 'transformed_data',
            },
          ),
        },
        edges: {
          'edge1': WorkflowEdge(
            id: 'edge1',
            sourceId: 'instruction',
            targetId: 'write',
            branchName: 'main',
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
        initialVariables: {
          'workflow_data': 'hello world',
        },
      );

      final events = client.run(request);
      await expectCompleted(events);

      // 5. Проверить результат
      final outputFile = File(outputPath);
      expect(await outputFile.exists(), true);
      final content = await outputFile.readAsString();
      expect(content, 'HELLO WORLD');

      // Cleanup
      await tempDir.delete(recursive: true);
    }, timeout: Timeout(Duration(minutes: 3)));

    test('RunInstruction с условной логикой', () async {
      // 1. Создать проект
      final project = await createTestProject(name: 'Conditional Instruction Test');

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
              'condition': 'value > 0',
              'input_var': 'value',
            },
          ),
          'positive': InstructionNode(
            id: 'positive',
            type: InstructionNodeType.transform,
            payload: {
              'output_var': 'result',
              'transform': 'set',
              'value': 'positive',
            },
          ),
          'negative': InstructionNode(
            id: 'negative',
            type: InstructionNodeType.transform,
            payload: {
              'output_var': 'result',
              'transform': 'set',
              'value': 'negative',
            },
          ),
        },
        edges: {
          'e1': InstructionEdge(
            id: 'e1',
            sourceId: 'check',
            targetId: 'positive',
            trigger: 'true',
            branchName: 'positive',
          ),
          'e2': InstructionEdge(
            id: 'e2',
            sourceId: 'check',
            targetId: 'negative',
            trigger: 'false',
            branchName: 'negative',
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
      final tempDir = Directory.systemTemp.createTempSync('aq_test_');
      final outputPath = '${tempDir.path}/result.txt';

      final workflowRepo = Vault.instance.versioned<WorkflowGraph>(
        collection: WorkflowGraph.kCollection,
        fromMap: WorkflowGraph.fromMap,
      );

      final workflow = WorkflowGraph(
        id: uuid(),
        tenantId: TestConfig.testTenantId,
        ownerId: project.id,
        name: 'Workflow with Conditional Instruction',
        nodes: {
          'instruction': WorkflowNode(
            id: 'instruction',
            type: WorkflowNodeType.runInstruction,
            config: {
              'instruction_blueprint_id': instruction.id,
              'input_mapping': {
                'value': 'test_value',
              },
              'output_mapping': {
                'result': 'instruction_result',
              },
            },
          ),
          'write': WorkflowNode(
            id: 'write',
            type: WorkflowNodeType.fileWrite,
            config: {
              'file_path': outputPath,
              'input_var': 'instruction_result',
            },
          ),
        },
        edges: {
          'edge1': WorkflowEdge(
            id: 'edge1',
            sourceId: 'instruction',
            targetId: 'write',
            branchName: 'main',
            type: WorkflowEdgeType.onSuccess,
          ),
        },
      );

      await workflowRepo.createEntity(workflow);

      // 4. Запустить с положительным значением
      final client = GraphEngineClient(baseUrl: TestConfig.graphEngineUrl);
      final request1 = GraphRunRequest(
        runId: uuid(),
        projectId: project.id,
        blueprintId: workflow.id,
        projectPath: tempDir.path,
        initialVariables: {
          'test_value': 10,
        },
      );

      final events1 = client.run(request1);
      await expectCompleted(events1);

      // 5. Проверить результат
      final outputFile = File(outputPath);
      expect(await outputFile.exists(), true);
      final content = await outputFile.readAsString();
      expect(content, 'positive');

      // Cleanup
      await tempDir.delete(recursive: true);
    }, timeout: Timeout(Duration(minutes: 3)));
  });

  group('Composite Nodes - Mixed Composition', () {
    test('SubGraph содержащий RunInstruction', () async {
      // 1. Создать проект
      final project = await createTestProject(name: 'Mixed Composition Test');

      // 2. Создать InstructionGraph
      final instruction = await createSimpleInstruction(
        projectId: project.id,
        contract: {
          'inputs': {
            'text': {'type': 'string', 'required': true},
          },
          'outputs': {
            'processed': {'type': 'string'},
          },
        },
        nodes: [
          {
            'type': 'transform',
            'payload': {
              'input_var': 'text',
              'output_var': 'processed',
              'transform': 'uppercase',
            },
          },
        ],
      );

      // 3. Создать внутренний WorkflowGraph с RunInstruction
      final workflowRepo = Vault.instance.versioned<WorkflowGraph>(
        collection: WorkflowGraph.kCollection,
        fromMap: WorkflowGraph.fromMap,
      );

      final innerWorkflow = WorkflowGraph(
        id: uuid(),
        tenantId: TestConfig.testTenantId,
        ownerId: project.id,
        name: 'Inner Workflow with Instruction',
        nodes: {
          'instruction': WorkflowNode(
            id: 'instruction',
            type: WorkflowNodeType.runInstruction,
            config: {
              'instruction_blueprint_id': instruction.id,
              'input_mapping': {
                'text': 'inner_input',
              },
              'output_mapping': {
                'processed': 'inner_output',
              },
            },
          ),
        },
        edges: {},
      );

      await workflowRepo.createEntity(innerWorkflow);

      // 4. Создать внешний WorkflowGraph с SubGraph
      final tempDir = Directory.systemTemp.createTempSync('aq_test_');
      final outputPath = '${tempDir.path}/final.txt';

      final outerWorkflow = WorkflowGraph(
        id: uuid(),
        tenantId: TestConfig.testTenantId,
        ownerId: project.id,
        name: 'Outer Workflow with SubGraph',
        nodes: {
          'subgraph': WorkflowNode(
            id: 'subgraph',
            type: WorkflowNodeType.subGraph,
            config: {
              'workflow_blueprint_id': innerWorkflow.id,
              'input_mapping': {
                'inner_input': 'outer_input',
              },
              'output_mapping': {
                'inner_output': 'outer_output',
              },
            },
          ),
          'write': WorkflowNode(
            id: 'write',
            type: WorkflowNodeType.fileWrite,
            config: {
              'file_path': outputPath,
              'input_var': 'outer_output',
            },
          ),
        },
        edges: {
          'edge1': WorkflowEdge(
            id: 'edge1',
            sourceId: 'subgraph',
            targetId: 'write',
            branchName: 'main',
            type: WorkflowEdgeType.onSuccess,
          ),
        },
      );

      await workflowRepo.createEntity(outerWorkflow);

      // 5. Запустить
      final client = GraphEngineClient(baseUrl: TestConfig.graphEngineUrl);
      final request = GraphRunRequest(
        runId: uuid(),
        projectId: project.id,
        blueprintId: outerWorkflow.id,
        projectPath: tempDir.path,
        initialVariables: {
          'outer_input': 'test data',
        },
      );

      final events = client.run(request);
      await expectCompleted(events);

      // 6. Проверить результат
      final outputFile = File(outputPath);
      expect(await outputFile.exists(), true);
      final content = await outputFile.readAsString();
      expect(content, 'TEST DATA');

      // Cleanup
      await tempDir.delete(recursive: true);
    }, timeout: Timeout(Duration(minutes: 4)));

    test('Сложная композиция: Workflow → SubGraph → Instruction → SubGraph', () async {
      // 1. Создать проект
      final project = await createTestProject(name: 'Complex Composition Test');

      // 2. Создать самый внутренний SubGraph (уровень 4)
      final tempDir = Directory.systemTemp.createTempSync('aq_test_');
      final level4Output = '${tempDir.path}/level4.txt';

      final level4Workflow = await createSimpleWorkflow(
        projectId: project.id,
        nodeType: 'fileWrite',
        nodeConfig: {
          'file_path': level4Output,
          'input_var': 'level4_data',
        },
      );

      // 3. Создать InstructionGraph (уровень 3) с вызовом SubGraph
      final instructionRepo = Vault.instance.versioned<InstructionGraph>(
        collection: InstructionGraph.kCollection,
        fromMap: InstructionGraph.fromMap,
      );

      // Примечание: InstructionGraph не может содержать WorkflowNode,
      // поэтому упростим: Instruction просто трансформирует данные
      final instruction = InstructionGraph(
        id: uuid(),
        tenantId: TestConfig.testTenantId,
        ownerId: project.id,
        name: 'Level 3 Instruction',
        nodes: {
          'transform': InstructionNode(
            id: 'transform',
            type: InstructionNodeType.transform,
            payload: {
              'input_var': 'level3_input',
              'output_var': 'level3_output',
              'transform': 'uppercase',
            },
          ),
        },
        edges: {},
        contract: {
          'inputs': {
            'level3_input': {'type': 'string', 'required': true},
          },
          'outputs': {
            'level3_output': {'type': 'string'},
          },
        },
      );

      await instructionRepo.createEntity(instruction);

      // 4. Создать SubGraph (уровень 2) с RunInstruction
      final workflowRepo = Vault.instance.versioned<WorkflowGraph>(
        collection: WorkflowGraph.kCollection,
        fromMap: WorkflowGraph.fromMap,
      );

      final level2Workflow = WorkflowGraph(
        id: uuid(),
        tenantId: TestConfig.testTenantId,
        ownerId: project.id,
        name: 'Level 2 SubGraph',
        nodes: {
          'instruction': WorkflowNode(
            id: 'instruction',
            type: WorkflowNodeType.runInstruction,
            config: {
              'instruction_blueprint_id': instruction.id,
              'input_mapping': {
                'level3_input': 'level2_input',
              },
              'output_mapping': {
                'level3_output': 'level2_output',
              },
            },
          ),
          'subgraph': WorkflowNode(
            id: 'subgraph',
            type: WorkflowNodeType.subGraph,
            config: {
              'workflow_blueprint_id': level4Workflow.id,
              'input_mapping': {
                'level4_data': 'level2_output',
              },
              'output_mapping': {},
            },
          ),
        },
        edges: {
          'edge1': WorkflowEdge(
            id: 'edge1',
            sourceId: 'instruction',
            targetId: 'subgraph',
            branchName: 'main',
            type: WorkflowEdgeType.onSuccess,
          ),
        },
      );

      await workflowRepo.createEntity(level2Workflow);

      // 5. Создать внешний Workflow (уровень 1)
      final level1Workflow = WorkflowGraph(
        id: uuid(),
        tenantId: TestConfig.testTenantId,
        ownerId: project.id,
        name: 'Level 1 Workflow',
        nodes: {
          'subgraph': WorkflowNode(
            id: 'subgraph',
            type: WorkflowNodeType.subGraph,
            config: {
              'workflow_blueprint_id': level2Workflow.id,
              'input_mapping': {
                'level2_input': 'level1_input',
              },
              'output_mapping': {},
            },
          ),
        },
        edges: {},
      );

      await workflowRepo.createEntity(level1Workflow);

      // 6. Запустить
      final client = GraphEngineClient(baseUrl: TestConfig.graphEngineUrl);
      final request = GraphRunRequest(
        runId: uuid(),
        projectId: project.id,
        blueprintId: level1Workflow.id,
        projectPath: tempDir.path,
        initialVariables: {
          'level1_input': 'complex data',
        },
      );

      final events = client.run(request);
      await expectCompleted(events);

      // 7. Проверить что данные прошли через все уровни
      final outputFile = File(level4Output);
      expect(await outputFile.exists(), true);
      final content = await outputFile.readAsString();
      expect(content, 'COMPLEX DATA');

      // Cleanup
      await tempDir.delete(recursive: true);
    }, timeout: Timeout(Duration(minutes: 5)));
  });
}
