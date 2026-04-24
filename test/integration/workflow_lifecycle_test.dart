// Интеграционные тесты жизненного цикла WorkflowGraph
//
// Покрывает:
// - Создание проекта и графа через репозитории
// - Запуск через GraphEngine
// - Обработку событий
// - Проверку результатов в БД

import 'package:test/test.dart';
import 'package:aq_schema/aq_schema.dart';
import 'package:aq_graph_engine/aq_graph_engine.dart';
import 'package:dart_vault/dart_vault.dart';
import 'test_helpers.dart';

void main() {
  setUpAll(() async {
    // Подключиться к Data Service один раз для всех тестов
    await connectToDataService();
  });

  group('WorkflowGraph Lifecycle - Simple Execution', () {
    test('Создание и запуск графа с одним узлом fileRead', () async {
      // 1. Создать проект
      final project = await createTestProject(name: 'FileRead Test');

      // 2. Создать тестовый файл
      final testFilePath = await createTestFile('Hello, World!');

      // 3. Создать граф с fileRead узлом
      final workflow = await createSimpleWorkflow(
        projectId: project.id,
        nodeType: 'fileRead',
        nodeConfig: {
          'file_path': testFilePath,
          'output_var': 'file_content',
        },
      );

      // 4. Запустить через движок
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

      // 6. Проверить результат в БД
      final runRepo = Vault.instance.logged<WorkflowRun>(
        collection: 'workflow_runs',
        fromMap: WorkflowRun.fromMap,
      );
      final run = await runRepo.findById(request.runId);

      expect(run, isNotNull);
      expect(run!.status, 'completed');
      expect(run.projectId, project.id);
      expect(run.blueprintId, workflow.id);

      // Cleanup
      await cleanupTestFile(testFilePath);
    }, timeout: Timeout(Duration(minutes: 2)));

    test('Создание и запуск графа с одним узлом fileWrite', () async {
      // 1. Создать проект
      final project = await createTestProject(name: 'FileWrite Test');

      // 2. Подготовить путь для записи
      final tempDir = Directory.systemTemp.createTempSync('aq_test_');
      final outputPath = '${tempDir.path}/output.txt';

      // 3. Создать граф с fileWrite узлом
      final workflow = await createSimpleWorkflow(
        projectId: project.id,
        nodeType: 'fileWrite',
        nodeConfig: {
          'file_path': outputPath,
          'input_var': 'test_content',
        },
      );

      // 4. Запустить с начальными переменными
      final client = GraphEngineClient(baseUrl: TestConfig.graphEngineUrl);
      final request = GraphRunRequest(
        runId: uuid(),
        projectId: project.id,
        blueprintId: workflow.id,
        projectPath: tempDir.path,
        initialVariables: {
          'test_content': 'Test content from workflow',
        },
      );

      final events = client.run(request);

      // 5. Проверить успешное завершение
      await expectCompleted(events);

      // 6. Проверить что файл создан
      final outputFile = File(outputPath);
      expect(await outputFile.exists(), true);
      final content = await outputFile.readAsString();
      expect(content, 'Test content from workflow');

      // Cleanup
      await tempDir.delete(recursive: true);
    }, timeout: Timeout(Duration(minutes: 2)));

    test('Создание и запуск графа с узлом llmAction', () async {
      // 1. Создать проект
      final project = await createTestProject(name: 'LLM Test');

      // 2. Создать PromptGraph
      final prompt = await createSimplePrompt(
        projectId: project.id,
        text: 'Скажи привет на русском языке',
      );

      // 3. Создать граф с llmAction узлом
      final workflow = await createSimpleWorkflow(
        projectId: project.id,
        nodeType: 'llmAction',
        nodeConfig: {
          'prompt_blueprint_id': prompt.id,
          'output_var': 'llm_response',
          'model_name': 'claude-opus-4',
        },
      );

      // 4. Запустить через движок
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
  });

  group('WorkflowGraph Lifecycle - Chain Execution', () {
    test('Последовательное выполнение: fileRead → fileWrite', () async {
      // 1. Создать проект
      final project = await createTestProject(name: 'Chain Test');

      // 2. Создать входной файл
      final inputPath = await createTestFile('Input content');
      final tempDir = Directory.systemTemp.createTempSync('aq_test_');
      final outputPath = '${tempDir.path}/output.txt';

      // 3. Создать граф с цепочкой узлов
      final workflow = await createChainWorkflow(
        projectId: project.id,
        nodes: [
          {
            'type': 'fileRead',
            'config': {
              'file_path': inputPath,
              'output_var': 'content',
            },
          },
          {
            'type': 'fileWrite',
            'config': {
              'file_path': outputPath,
              'input_var': 'content',
            },
          },
        ],
      );

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

      // 6. Проверить что содержимое скопировано
      final outputFile = File(outputPath);
      expect(await outputFile.exists(), true);
      final content = await outputFile.readAsString();
      expect(content, 'Input content');

      // Cleanup
      await cleanupTestFile(inputPath);
      await tempDir.delete(recursive: true);
    }, timeout: Timeout(Duration(minutes: 2)));

    test('Цепочка из 3 узлов: fileRead → llmAction → fileWrite', () async {
      // 1. Создать проект
      final project = await createTestProject(name: 'Complex Chain Test');

      // 2. Создать PromptGraph
      final prompt = await createSimplePrompt(
        projectId: project.id,
        text: 'Обработай текст: {{content}}',
      );

      // 3. Создать входной файл
      final inputPath = await createTestFile('Test input');
      final tempDir = Directory.systemTemp.createTempSync('aq_test_');
      final outputPath = '${tempDir.path}/result.txt';

      // 4. Создать граф
      final workflow = await createChainWorkflow(
        projectId: project.id,
        nodes: [
          {
            'type': 'fileRead',
            'config': {
              'file_path': inputPath,
              'output_var': 'content',
            },
          },
          {
            'type': 'llmAction',
            'config': {
              'prompt_blueprint_id': prompt.id,
              'output_var': 'processed',
            },
          },
          {
            'type': 'fileWrite',
            'config': {
              'file_path': outputPath,
              'input_var': 'processed',
            },
          },
        ],
      );

      // 5. Запустить
      final client = GraphEngineClient(baseUrl: TestConfig.graphEngineUrl);
      final request = GraphRunRequest(
        runId: uuid(),
        projectId: project.id,
        blueprintId: workflow.id,
        projectPath: tempDir.path,
      );

      final events = client.run(request);

      // 6. Проверить успешное завершение
      await expectCompleted(events);

      // 7. Проверить что результат записан
      final outputFile = File(outputPath);
      expect(await outputFile.exists(), true);

      // Cleanup
      await cleanupTestFile(inputPath);
      await tempDir.delete(recursive: true);
    }, timeout: Timeout(Duration(minutes: 3)));
  });

  group('WorkflowGraph Lifecycle - Event Stream', () {
    test('Проверка всех типов событий', () async {
      // 1. Создать проект и граф
      final project = await createTestProject(name: 'Events Test');
      final testFilePath = await createTestFile('Test');

      final workflow = await createSimpleWorkflow(
        projectId: project.id,
        nodeType: 'fileRead',
        nodeConfig: {
          'file_path': testFilePath,
          'output_var': 'content',
        },
      );

      // 2. Запустить
      final client = GraphEngineClient(baseUrl: TestConfig.graphEngineUrl);
      final request = GraphRunRequest(
        runId: uuid(),
        projectId: project.id,
        blueprintId: workflow.id,
        projectPath: Directory.systemTemp.path,
      );

      final events = client.run(request);

      // 3. Собрать все события
      final eventList = await collectEvents(events);

      // 4. Проверить типы событий
      final eventTypes = eventList.map((e) => e.type).toSet();

      expect(eventTypes.contains(GraphRunEventType.statusChanged), true);
      expect(eventTypes.contains(GraphRunEventType.log), true);
      expect(eventTypes.contains(GraphRunEventType.completed), true);

      // 5. Проверить порядок статусов
      final statusEvents = eventList
          .where((e) => e.type == GraphRunEventType.statusChanged)
          .toList();

      expect(statusEvents.isNotEmpty, true);
      expect(statusEvents.first.newStatus, GraphRunStatus.running);

      // Cleanup
      await cleanupTestFile(testFilePath);
    }, timeout: Timeout(Duration(minutes: 2)));

    test('Проверка логов выполнения', () async {
      // 1. Создать проект и граф
      final project = await createTestProject(name: 'Logs Test');
      final testFilePath = await createTestFile('Log test');

      final workflow = await createSimpleWorkflow(
        projectId: project.id,
        nodeType: 'fileRead',
        nodeConfig: {
          'file_path': testFilePath,
          'output_var': 'content',
        },
      );

      // 2. Запустить
      final client = GraphEngineClient(baseUrl: TestConfig.graphEngineUrl);
      final request = GraphRunRequest(
        runId: uuid(),
        projectId: project.id,
        blueprintId: workflow.id,
        projectPath: Directory.systemTemp.path,
      );

      final events = client.run(request);

      // 3. Собрать логи
      final eventList = await collectEvents(events);
      final logEvents =
          eventList.where((e) => e.type == GraphRunEventType.log).toList();

      // 4. Проверить что логи есть
      expect(logEvents.isNotEmpty, true);

      // 5. Проверить что логи содержат информацию о выполнении
      final logMessages = logEvents.map((e) => e.message).join('\n');
      expect(logMessages.contains('Run Started') || logMessages.contains('Executing'), true);

      // Cleanup
      await cleanupTestFile(testFilePath);
    }, timeout: Timeout(Duration(minutes: 2)));
  });

  group('WorkflowGraph Lifecycle - Error Handling', () {
    test('Обработка ошибки при чтении несуществующего файла', () async {
      // 1. Создать проект
      final project = await createTestProject(name: 'Error Test');

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

      // 4. Проверить что граф завершился с ошибкой
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

    test('Проверка audit trail при ошибке', () async {
      // 1. Создать проект
      final project = await createTestProject(name: 'Audit Trail Test');

      // 2. Создать граф с ошибкой
      final workflow = await createSimpleWorkflow(
        projectId: project.id,
        nodeType: 'fileRead',
        nodeConfig: {
          'file_path': '/invalid/path.txt',
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
      await expectFailed(events);

      // 4. Проверить audit trail
      final runRepo = Vault.instance.logged<WorkflowRun>(
        collection: 'workflow_runs',
        fromMap: WorkflowRun.fromMap,
      );

      // Получить логи изменений
      final logs = await runRepo.getHistory(request.runId);

      expect(logs.isNotEmpty, true);

      // Проверить что есть запись о создании и об ошибке
      final operations = logs.map((l) => l['operation']).toList();
      expect(operations.contains('created'), true);
      expect(operations.contains('updated'), true);
    }, timeout: Timeout(Duration(minutes: 2)));
  });
}
