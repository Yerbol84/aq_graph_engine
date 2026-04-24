// Интеграционные тесты жизненного цикла PromptGraph
//
// Покрывает:
// - Создание PromptGraph через репозитории
// - Компиляцию промпта с подстановкой переменных
// - Использование в LlmActionNode
// - Условные блоки в промптах
// - Композицию промптов

import 'package:test/test.dart';
import 'package:aq_schema/aq_schema.dart';
import 'package:aq_graph_engine/aq_graph_engine.dart';
import 'package:dart_vault/dart_vault.dart';
import 'test_helpers.dart';

void main() {
  setUpAll(() async {
    await connectToDataService();
  });

  group('PromptGraph Lifecycle - Simple Prompts', () {
    test('Создание и использование простого текстового промпта', () async {
      // 1. Создать проект
      final project = await createTestProject(name: 'Simple Prompt Test');

      // 2. Создать PromptGraph с текстовым блоком
      final prompt = await createSimplePrompt(
        projectId: project.id,
        text: 'Напиши короткое приветствие на русском языке',
      );

      // 3. Создать WorkflowGraph с LlmActionNode
      final workflowRepo = Vault.instance.versioned<WorkflowGraph>(
        collection: WorkflowGraph.kCollection,
        fromMap: WorkflowGraph.fromMap,
      );

      final workflow = WorkflowGraph(
        id: uuid(),
        tenantId: TestConfig.testTenantId,
        ownerId: project.id,
        name: 'Workflow with Simple Prompt',
        nodes: {
          'llm': WorkflowNode(
            id: 'llm',
            type: WorkflowNodeType.llmAction,
            config: {
              'prompt_blueprint_id': prompt.id,
              'output_var': 'greeting',
              'model_name': 'claude-opus-4',
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
    }, timeout: Timeout(Duration(minutes: 3)));

    test('Промпт с подстановкой переменных', () async {
      // 1. Создать проект
      final project = await createTestProject(name: 'Variable Prompt Test');

      // 2. Создать PromptGraph с переменными
      final promptRepo = Vault.instance.versioned<PromptGraph>(
        collection: PromptGraph.kCollection,
        fromMap: PromptGraph.fromMap,
      );

      final prompt = PromptGraph(
        id: uuid(),
        tenantId: TestConfig.testTenantId,
        ownerId: project.id,
        name: 'Prompt with Variables',
        nodes: {
          'text1': PromptNode(
            id: 'text1',
            type: PromptNodeType.textBlock,
            payload: {'text': 'Обработай следующий текст: '},
          ),
          'var1': PromptNode(
            id: 'var1',
            type: PromptNodeType.variableInsert,
            payload: {'variable_name': 'input_text'},
          ),
          'text2': PromptNode(
            id: 'text2',
            type: PromptNodeType.textBlock,
            payload: {'text': '\n\nВерни результат в верхнем регистре.'},
          ),
        },
        edges: {
          'edge1': PromptEdge(
            id: 'edge1',
            sourceId: 'text1',
            targetId: 'var1',
          ),
          'edge2': PromptEdge(
            id: 'edge2',
            sourceId: 'var1',
            targetId: 'text2',
          ),
        },
      );

      await promptRepo.createEntity(prompt);

      // 3. Создать WorkflowGraph
      final workflowRepo = Vault.instance.versioned<WorkflowGraph>(
        collection: WorkflowGraph.kCollection,
        fromMap: WorkflowGraph.fromMap,
      );

      final workflow = WorkflowGraph(
        id: uuid(),
        tenantId: TestConfig.testTenantId,
        ownerId: project.id,
        name: 'Workflow with Variable Prompt',
        nodes: {
          'llm': WorkflowNode(
            id: 'llm',
            type: WorkflowNodeType.llmAction,
            config: {
              'prompt_blueprint_id': prompt.id,
              'output_var': 'result',
              'model_name': 'claude-opus-4',
            },
          ),
        },
        edges: {},
      );

      await workflowRepo.createEntity(workflow);

      // 4. Запустить с переменной
      final client = GraphEngineClient(baseUrl: TestConfig.graphEngineUrl);
      final request = GraphRunRequest(
        runId: uuid(),
        projectId: project.id,
        blueprintId: workflow.id,
        projectPath: Directory.systemTemp.path,
        initialVariables: {
          'input_text': 'hello world',
        },
      );

      final events = client.run(request);
      await expectCompleted(events);

      // 5. Проверить результат
      final runRepo = Vault.instance.logged<WorkflowRun>(
        collection: 'workflow_runs',
        fromMap: WorkflowRun.fromMap,
      );
      final run = await runRepo.findById(request.runId);

      expect(run, isNotNull);
      expect(run!.status, 'completed');
    }, timeout: Timeout(Duration(minutes: 3)));
  });

  group('PromptGraph Lifecycle - Conditional Blocks', () {
    test('Условный блок в промпте', () async {
      // 1. Создать проект
      final project = await createTestProject(name: 'Conditional Prompt Test');

      // 2. Создать PromptGraph с условным блоком
      final promptRepo = Vault.instance.versioned<PromptGraph>(
        collection: PromptGraph.kCollection,
        fromMap: PromptGraph.fromMap,
      );

      final prompt = PromptGraph(
        id: uuid(),
        tenantId: TestConfig.testTenantId,
        ownerId: project.id,
        name: 'Conditional Prompt',
        nodes: {
          'text1': PromptNode(
            id: 'text1',
            type: PromptNodeType.textBlock,
            payload: {'text': 'Напиши текст'},
          ),
          'condition': PromptNode(
            id: 'condition',
            type: PromptNodeType.conditionalBlock,
            payload: {
              'condition': 'include_details == true',
              'then_text': ' с подробностями',
              'else_text': ' кратко',
            },
          ),
        },
        edges: {
          'edge1': PromptEdge(
            id: 'edge1',
            sourceId: 'text1',
            targetId: 'condition',
          ),
        },
      );

      await promptRepo.createEntity(prompt);

      // 3. Создать WorkflowGraph
      final workflowRepo = Vault.instance.versioned<WorkflowGraph>(
        collection: WorkflowGraph.kCollection,
        fromMap: WorkflowGraph.fromMap,
      );

      final workflow = WorkflowGraph(
        id: uuid(),
        tenantId: TestConfig.testTenantId,
        ownerId: project.id,
        name: 'Workflow with Conditional Prompt',
        nodes: {
          'llm': WorkflowNode(
            id: 'llm',
            type: WorkflowNodeType.llmAction,
            config: {
              'prompt_blueprint_id': prompt.id,
              'output_var': 'result',
              'model_name': 'claude-opus-4',
            },
          ),
        },
        edges: {},
      );

      await workflowRepo.createEntity(workflow);

      // 4. Запустить с include_details = true
      final client = GraphEngineClient(baseUrl: TestConfig.graphEngineUrl);
      final request1 = GraphRunRequest(
        runId: uuid(),
        projectId: project.id,
        blueprintId: workflow.id,
        projectPath: Directory.systemTemp.path,
        initialVariables: {
          'include_details': true,
        },
      );

      final events1 = client.run(request1);
      await expectCompleted(events1);

      // 5. Запустить с include_details = false
      final request2 = GraphRunRequest(
        runId: uuid(),
        projectId: project.id,
        blueprintId: workflow.id,
        projectPath: Directory.systemTemp.path,
        initialVariables: {
          'include_details': false,
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
    }, timeout: Timeout(Duration(minutes: 4)));
  });

  group('PromptGraph Lifecycle - Complex Prompts', () {
    test('Многоблочный промпт с несколькими переменными', () async {
      // 1. Создать проект
      final project = await createTestProject(name: 'Complex Prompt Test');

      // 2. Создать сложный PromptGraph
      final promptRepo = Vault.instance.versioned<PromptGraph>(
        collection: PromptGraph.kCollection,
        fromMap: PromptGraph.fromMap,
      );

      final prompt = PromptGraph(
        id: uuid(),
        tenantId: TestConfig.testTenantId,
        ownerId: project.id,
        name: 'Complex Prompt',
        nodes: {
          'intro': PromptNode(
            id: 'intro',
            type: PromptNodeType.textBlock,
            payload: {'text': 'Ты - '},
          ),
          'role': PromptNode(
            id: 'role',
            type: PromptNodeType.variableInsert,
            payload: {'variable_name': 'role'},
          ),
          'task': PromptNode(
            id: 'task',
            type: PromptNodeType.textBlock,
            payload: {'text': '. Твоя задача: '},
          ),
          'task_desc': PromptNode(
            id: 'task_desc',
            type: PromptNodeType.variableInsert,
            payload: {'variable_name': 'task_description'},
          ),
          'context': PromptNode(
            id: 'context',
            type: PromptNodeType.textBlock,
            payload: {'text': '\n\nКонтекст: '},
          ),
          'context_data': PromptNode(
            id: 'context_data',
            type: PromptNodeType.variableInsert,
            payload: {'variable_name': 'context'},
          ),
        },
        edges: {
          'e1': PromptEdge(id: 'e1', sourceId: 'intro', targetId: 'role'),
          'e2': PromptEdge(id: 'e2', sourceId: 'role', targetId: 'task'),
          'e3': PromptEdge(id: 'e3', sourceId: 'task', targetId: 'task_desc'),
          'e4': PromptEdge(id: 'e4', sourceId: 'task_desc', targetId: 'context'),
          'e5': PromptEdge(id: 'e5', sourceId: 'context', targetId: 'context_data'),
        },
      );

      await promptRepo.createEntity(prompt);

      // 3. Создать WorkflowGraph
      final workflowRepo = Vault.instance.versioned<WorkflowGraph>(
        collection: WorkflowGraph.kCollection,
        fromMap: WorkflowGraph.fromMap,
      );

      final workflow = WorkflowGraph(
        id: uuid(),
        tenantId: TestConfig.testTenantId,
        ownerId: project.id,
        name: 'Workflow with Complex Prompt',
        nodes: {
          'llm': WorkflowNode(
            id: 'llm',
            type: WorkflowNodeType.llmAction,
            config: {
              'prompt_blueprint_id': prompt.id,
              'output_var': 'response',
              'model_name': 'claude-opus-4',
            },
          ),
        },
        edges: {},
      );

      await workflowRepo.createEntity(workflow);

      // 4. Запустить с несколькими переменными
      final client = GraphEngineClient(baseUrl: TestConfig.graphEngineUrl);
      final request = GraphRunRequest(
        runId: uuid(),
        projectId: project.id,
        blueprintId: workflow.id,
        projectPath: Directory.systemTemp.path,
        initialVariables: {
          'role': 'помощник программиста',
          'task_description': 'написать функцию сортировки',
          'context': 'Язык программирования: Dart',
        },
      );

      final events = client.run(request);
      await expectCompleted(events);

      // 5. Проверить результат
      final runRepo = Vault.instance.logged<WorkflowRun>(
        collection: 'workflow_runs',
        fromMap: WorkflowRun.fromMap,
      );
      final run = await runRepo.findById(request.runId);

      expect(run, isNotNull);
      expect(run!.status, 'completed');
    }, timeout: Timeout(Duration(minutes: 3)));

    test('Промпт с отсутствующей переменной', () async {
      // 1. Создать проект
      final project = await createTestProject(name: 'Missing Variable Test');

      // 2. Создать PromptGraph с переменной
      final promptRepo = Vault.instance.versioned<PromptGraph>(
        collection: PromptGraph.kCollection,
        fromMap: PromptGraph.fromMap,
      );

      final prompt = PromptGraph(
        id: uuid(),
        tenantId: TestConfig.testTenantId,
        ownerId: project.id,
        name: 'Prompt with Required Variable',
        nodes: {
          'text': PromptNode(
            id: 'text',
            type: PromptNodeType.textBlock,
            payload: {'text': 'Обработай: '},
          ),
          'var': PromptNode(
            id: 'var',
            type: PromptNodeType.variableInsert,
            payload: {
              'variable_name': 'required_var',
              'required': true,
            },
          ),
        },
        edges: {
          'edge': PromptEdge(id: 'edge', sourceId: 'text', targetId: 'var'),
        },
      );

      await promptRepo.createEntity(prompt);

      // 3. Создать WorkflowGraph
      final workflowRepo = Vault.instance.versioned<WorkflowGraph>(
        collection: WorkflowGraph.kCollection,
        fromMap: WorkflowGraph.fromMap,
      );

      final workflow = WorkflowGraph(
        id: uuid(),
        tenantId: TestConfig.testTenantId,
        ownerId: project.id,
        name: 'Workflow with Missing Variable',
        nodes: {
          'llm': WorkflowNode(
            id: 'llm',
            type: WorkflowNodeType.llmAction,
            config: {
              'prompt_blueprint_id': prompt.id,
              'output_var': 'result',
              'model_name': 'claude-opus-4',
            },
          ),
        },
        edges: {},
      );

      await workflowRepo.createEntity(workflow);

      // 4. Запустить БЕЗ переменной
      final client = GraphEngineClient(baseUrl: TestConfig.graphEngineUrl);
      final request = GraphRunRequest(
        runId: uuid(),
        projectId: project.id,
        blueprintId: workflow.id,
        projectPath: Directory.systemTemp.path,
        // Намеренно НЕ передаём required_var
      );

      final events = client.run(request);

      // 5. Ожидаем ошибку
      await expectFailed(events);

      // 6. Проверить статус
      final runRepo = Vault.instance.logged<WorkflowRun>(
        collection: 'workflow_runs',
        fromMap: WorkflowRun.fromMap,
      );
      final run = await runRepo.findById(request.runId);

      expect(run, isNotNull);
      expect(run!.status, 'failed');
    }, timeout: Timeout(Duration(minutes: 2)));
  });

  group('PromptGraph Lifecycle - Integration with Workflow', () {
    test('Цепочка: fileRead → llmAction(prompt) → fileWrite', () async {
      // 1. Создать проект
      final project = await createTestProject(name: 'Prompt Chain Test');

      // 2. Создать входной файл
      final inputPath = await createTestFile('Исходный текст для обработки');

      // 3. Создать PromptGraph
      final prompt = await createSimplePrompt(
        projectId: project.id,
        text: 'Переведи текст на английский: {{content}}',
      );

      // 4. Создать выходной путь
      final tempDir = Directory.systemTemp.createTempSync('aq_test_');
      final outputPath = '${tempDir.path}/output.txt';

      // 5. Создать WorkflowGraph с цепочкой
      final workflowRepo = Vault.instance.versioned<WorkflowGraph>(
        collection: WorkflowGraph.kCollection,
        fromMap: WorkflowGraph.fromMap,
      );

      final workflow = WorkflowGraph(
        id: uuid(),
        tenantId: TestConfig.testTenantId,
        ownerId: project.id,
        name: 'File → LLM → File Chain',
        nodes: {
          'read': WorkflowNode(
            id: 'read',
            type: WorkflowNodeType.fileRead,
            config: {
              'file_path': inputPath,
              'output_var': 'content',
            },
          ),
          'llm': WorkflowNode(
            id: 'llm',
            type: WorkflowNodeType.llmAction,
            config: {
              'prompt_blueprint_id': prompt.id,
              'output_var': 'translated',
              'model_name': 'claude-opus-4',
            },
          ),
          'write': WorkflowNode(
            id: 'write',
            type: WorkflowNodeType.fileWrite,
            config: {
              'file_path': outputPath,
              'input_var': 'translated',
            },
          ),
        },
        edges: {
          'e1': WorkflowEdge(
            id: 'e1',
            sourceId: 'read',
            targetId: 'llm',
            branchName: 'main',
            type: WorkflowEdgeType.onSuccess,
          ),
          'e2': WorkflowEdge(
            id: 'e2',
            sourceId: 'llm',
            targetId: 'write',
            branchName: 'main',
            type: WorkflowEdgeType.onSuccess,
          ),
        },
      );

      await workflowRepo.createEntity(workflow);

      // 6. Запустить
      final client = GraphEngineClient(baseUrl: TestConfig.graphEngineUrl);
      final request = GraphRunRequest(
        runId: uuid(),
        projectId: project.id,
        blueprintId: workflow.id,
        projectPath: tempDir.path,
      );

      final events = client.run(request);
      await expectCompleted(events);

      // 7. Проверить что файл создан
      final outputFile = File(outputPath);
      expect(await outputFile.exists(), true);

      // Cleanup
      await cleanupTestFile(inputPath);
      await tempDir.delete(recursive: true);
    }, timeout: Timeout(Duration(minutes: 4)));
  });
}
