// Вспомогательные функции для интеграционных тестов

import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:uuid/uuid.dart';
import 'package:dart_vault/dart_vault.dart';
import 'package:aq_schema/aq_schema.dart';

const _uuid = Uuid();

/// Генерация UUID
String uuid() => _uuid.v4();

/// URL сервисов из переменных окружения
class TestConfig {
  static String get dataServiceUrl =>
      Platform.environment['DATA_SERVICE_URL'] ?? 'http://localhost:8765';

  static String get graphEngineUrl =>
      Platform.environment['GRAPH_ENGINE_URL'] ?? 'http://localhost:8081';

  static const String testTenantId = 'test';
}

/// Подключение к Data Service
Future<void> connectToDataService() async {
  await Vault.connect(
    TestConfig.dataServiceUrl,
    tenantId: TestConfig.testTenantId,
  );
}

/// Создание тестового проекта
Future<AqStudioProject> createTestProject({String? name}) async {
  final projectRepo = Vault.instance.direct<AqStudioProject>(
    collection: AqStudioProject.kCollection,
    fromMap: AqStudioProject.fromMap,
  );

  final project = AqStudioProject(
    id: uuid(),
    tenantId: TestConfig.testTenantId,
    ownerId: TestConfig.testTenantId, // Используем tenantId как ownerId для тестов
    name: name ?? 'Test Project ${DateTime.now().millisecondsSinceEpoch}',
    path: '/tmp/test_project_${DateTime.now().millisecondsSinceEpoch}',
    projectType: 'test',
    lastOpened: DateTime.now(),
  );

  await projectRepo.save(project);
  return project;
}

/// Создание простого WorkflowGraph с одним узлом
Future<WorkflowGraph> createSimpleWorkflow({
  required String projectId,
  required String nodeType,
  required Map<String, dynamic> nodeConfig,
}) async {
  final workflowRepo = Vault.instance.versioned<WorkflowGraph>(
    collection: WorkflowGraph.kCollection,
    fromMap: WorkflowGraph.fromMap,
  );

  final workflow = WorkflowGraph(
    id: uuid(),
    tenantId: TestConfig.testTenantId,
    ownerId: projectId,
    name: 'Simple Workflow - $nodeType',
    nodes: {
      'node1': WorkflowNode(
        id: 'node1',
        type: WorkflowNodeType.values.byName(nodeType),
        config: nodeConfig,
      ),
    },
    edges: {},
  );

  await workflowRepo.createEntity(workflow);
  return workflow;
}

/// Создание WorkflowGraph с цепочкой узлов
Future<WorkflowGraph> createChainWorkflow({
  required String projectId,
  required List<Map<String, dynamic>> nodes,
}) async {
  final workflowRepo = Vault.instance.versioned<WorkflowGraph>(
    collection: WorkflowGraph.kCollection,
    fromMap: WorkflowGraph.fromMap,
  );

  final workflowNodes = <String, WorkflowNode>{};
  final workflowEdges = <String, WorkflowEdge>{};

  for (var i = 0; i < nodes.length; i++) {
    final nodeData = nodes[i];
    final nodeId = 'node${i + 1}';

    workflowNodes[nodeId] = WorkflowNode(
      id: nodeId,
      type: WorkflowNodeType.values.byName(nodeData['type'] as String),
      config: nodeData['config'] as Map<String, dynamic>,
    );

    // Создать ребро к следующему узлу
    if (i < nodes.length - 1) {
      final edgeId = 'edge${i + 1}';
      workflowEdges[edgeId] = WorkflowEdge(
        id: edgeId,
        sourceId: nodeId,
        targetId: 'node${i + 2}',
        branchName: 'main',
        type: WorkflowEdgeType.onSuccess,
      );
    }
  }

  final workflow = WorkflowGraph(
    id: uuid(),
    tenantId: TestConfig.testTenantId,
    ownerId: projectId,
    name: 'Chain Workflow',
    nodes: workflowNodes,
    edges: workflowEdges,
  );

  await workflowRepo.createEntity(workflow);
  return workflow;
}

/// Создание InstructionGraph
Future<InstructionGraph> createSimpleInstruction({
  required String projectId,
  required Map<String, dynamic> contract,
  required List<Map<String, dynamic>> nodes,
}) async {
  final instructionRepo = Vault.instance.versioned<InstructionGraph>(
    collection: InstructionGraph.kCollection,
    fromMap: InstructionGraph.fromMap,
  );

  final instructionNodes = <String, InstructionNode>{};
  final instructionEdges = <String, InstructionEdge>{};

  for (var i = 0; i < nodes.length; i++) {
    final nodeData = nodes[i];
    final nodeId = 'step${i + 1}';

    instructionNodes[nodeId] = InstructionNode(
      id: nodeId,
      type: InstructionNodeType.values.byName(nodeData['type'] as String),
      payload: nodeData['payload'] as Map<String, dynamic>,
    );

    // Создать ребро к следующему узлу
    if (i < nodes.length - 1) {
      final edgeId = 'edge${i + 1}';
      instructionEdges[edgeId] = InstructionEdge(
        id: edgeId,
        sourceId: nodeId,
        targetId: 'step${i + 2}',
        trigger: 'completed',
        branchName: 'main',
      );
    }
  }

  final instruction = InstructionGraph(
    id: uuid(),
    tenantId: TestConfig.testTenantId,
    ownerId: projectId,
    name: 'Simple Instruction',
    nodes: instructionNodes,
    edges: instructionEdges,
    contract: contract,
  );

  await instructionRepo.createEntity(instruction);
  return instruction;
}

/// Создание PromptGraph
Future<PromptGraph> createSimplePrompt({
  required String projectId,
  required String text,
}) async {
  final promptRepo = Vault.instance.versioned<PromptGraph>(
    collection: PromptGraph.kCollection,
    fromMap: PromptGraph.fromMap,
  );

  final prompt = PromptGraph(
    id: uuid(),
    tenantId: TestConfig.testTenantId,
    ownerId: projectId,
    name: 'Simple Prompt',
    nodes: {
      'text1': PromptNode(
        id: 'text1',
        type: PromptNodeType.textBlock,
        data: {'text': text},
      ),
    },
    edges: {},
  );

  await promptRepo.createEntity(prompt);
  return prompt;
}

/// Создание тестового файла
Future<String> createTestFile(String content) async {
  final tempDir = Directory.systemTemp.createTempSync('aq_test_');
  final file = File('${tempDir.path}/test.txt');
  await file.writeAsString(content);
  return file.path;
}

/// Очистка тестового файла
Future<void> cleanupTestFile(String path) async {
  final file = File(path);
  if (await file.exists()) {
    await file.delete();
  }
  final dir = file.parent;
  if (await dir.exists()) {
    await dir.delete(recursive: true);
  }
}

/// Ожидание события определённого типа
Future<GraphRunEvent> waitForEvent(
  Stream<GraphRunEvent> events,
  GraphRunEventType type, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  await for (final event in events.timeout(timeout)) {
    if (event.type == type) {
      return event;
    }
  }
  throw TimeoutException('Event $type not received', timeout);
}

/// Сбор всех событий до completed/error
Future<List<GraphRunEvent>> collectEvents(
  Stream<GraphRunEvent> events, {
  Duration timeout = const Duration(minutes: 2),
}) async {
  final result = <GraphRunEvent>[];

  await for (final event in events.timeout(timeout)) {
    result.add(event);

    if (event.type == GraphRunEventType.completed ||
        event.type == GraphRunEventType.error) {
      break;
    }
  }

  return result;
}

/// Проверка что граф завершился успешно
Future<void> expectCompleted(Stream<GraphRunEvent> events) async {
  final eventList = await collectEvents(events);
  final hasCompleted =
      eventList.any((e) => e.type == GraphRunEventType.completed);

  if (!hasCompleted) {
    final errorEvent = eventList.firstWhere(
      (e) => e.type == GraphRunEventType.error,
      orElse: () => throw Exception('No completed or error event'),
    );
    throw Exception('Graph failed: ${errorEvent.errorMessage}');
  }
}

/// Проверка что граф завершился с ошибкой
Future<void> expectFailed(Stream<GraphRunEvent> events) async {
  final eventList = await collectEvents(events);
  final hasError = eventList.any((e) => e.type == GraphRunEventType.error);

  if (!hasError) {
    throw Exception('Expected error but graph completed successfully');
  }
}

/// Проверка что граф приостановлен
Future<void> expectSuspended(Stream<GraphRunEvent> events) async {
  final event = await waitForEvent(events, GraphRunEventType.userInputRequired);
  if (event.type != GraphRunEventType.userInputRequired) {
    throw Exception('Expected suspended but got ${event.type}');
  }
}

// ============================================================================
// НОВЫЕ HELPER ФУНКЦИИ ДЛЯ ПРОВЕРКИ ЛОГОВ И СОСТОЯНИЯ БД
// ============================================================================

/// Получить логи выполнения из БД
Future<List<String>> getRunLogs(String runId) async {
  final runRepo = Vault.instance.logged<WorkflowRun>(
    collection: WorkflowRun.kCollection,
    fromMap: WorkflowRun.fromMap,
  );

  final runs = await runRepo.findAll();
  final run = runs.firstWhere(
    (r) => r.id == runId,
    orElse: () => throw Exception('Run $runId not found in database'),
  );

  // Логи хранятся в logsJson как JSON array строк
  final logsJson = run.logsJson;
  if (logsJson == null || logsJson.isEmpty) {
    return [];
  }

  // Парсим JSON
  final dynamic parsed = jsonDecode(logsJson);
  if (parsed is List) {
    return parsed.map((e) => e.toString()).toList();
  }

  return [];
}

/// Подсчитать количество выполнений узла по логам
int countNodeExecutions(List<String> logs, String nodeId) {
  return logs.where((log) =>
    log.contains('Executing') && log.contains('[$nodeId]')
  ).length;
}

/// Проверить что узел выполнился определённое количество раз
/// Получить количество выполнений узла
Future<int> getNodeExecutionCount(
  String runId,
  String nodeId,
) async {
  final logs = await getRunLogs(runId);
  return countNodeExecutions(logs, nodeId);
}

Future<void> expectNodeExecutionCount(
  String runId,
  String nodeId,
  int expectedCount, {
  String? reason,
}) async {
  final actualCount = await getNodeExecutionCount(runId, nodeId);

  if (actualCount != expectedCount) {
    final logs = await getRunLogs(runId);
    throw Exception(
      'Node $nodeId executed $actualCount times, expected $expectedCount. '
      '${reason ?? ""}\nLogs:\n${logs.join("\n")}'
    );
  }
}

/// Проверить что лог содержит определённое сообщение
Future<void> expectLogContains(
  String runId,
  String message, {
  String? reason,
}) async {
  final logs = await getRunLogs(runId);
  final found = logs.any((log) => log.contains(message));

  if (!found) {
    throw Exception(
      'Log does not contain "$message". ${reason ?? ""}\n'
      'Logs:\n${logs.join("\n")}'
    );
  }
}

/// Получить состояние Run из БД
Future<WorkflowRun> getRunState(String runId) async {
  final runRepo = Vault.instance.logged<WorkflowRun>(
    collection: WorkflowRun.kCollection,
    fromMap: WorkflowRun.fromMap,
  );

  final runs = await runRepo.findAll();
  final run = runs.firstWhere(
    (r) => r.id == runId,
    orElse: () => throw Exception('Run $runId not found in database'),
  );

  return run;
}

/// Проверить статус Run в БД
Future<void> expectRunStatus(
  String runId,
  String expectedStatus, {
  String? reason,
}) async {
  final run = await getRunState(runId);

  if (run.status != expectedStatus) {
    throw Exception(
      'Run status is "${run.status}", expected "$expectedStatus". '
      '${reason ?? ""}'
    );
  }
}

/// Получить timestamp выполнения узла из логов
DateTime? getNodeExecutionTimestamp(List<String> logs, String nodeId) {
  // Ищем лог вида: "[2026-04-09T15:30:00.000Z] Executing: nodeType [nodeId]"
  final pattern = RegExp(r'\[(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z)\].*\[$nodeId\]');

  for (final log in logs) {
    final match = pattern.firstMatch(log);
    if (match != null) {
      return DateTime.parse(match.group(1)!);
    }
  }

  return null;
}

/// Проверить что узлы выполнялись параллельно (разница во времени < threshold)
Future<void> expectParallelExecution(
  String runId,
  List<String> nodeIds, {
  Duration threshold = const Duration(seconds: 1),
  String? reason,
}) async {
  final logs = await getRunLogs(runId);
  final timestamps = <String, DateTime>{};

  for (final nodeId in nodeIds) {
    final timestamp = getNodeExecutionTimestamp(logs, nodeId);
    if (timestamp == null) {
      throw Exception('No execution timestamp found for node $nodeId');
    }
    timestamps[nodeId] = timestamp;
  }

  // Проверить что все узлы выполнились примерно в одно время
  final times = timestamps.values.toList()..sort();
  final minTime = times.first;
  final maxTime = times.last;
  final diff = maxTime.difference(minTime);

  if (diff > threshold) {
    throw Exception(
      'Nodes did not execute in parallel. Time difference: ${diff.inMilliseconds}ms > ${threshold.inMilliseconds}ms. '
      '${reason ?? ""}\nTimestamps: $timestamps'
    );
  }
}

/// Проверить порядок выполнения узлов
Future<void> expectExecutionOrder(
  String runId,
  List<String> nodeIds, {
  String? reason,
}) async {
  final logs = await getRunLogs(runId);
  final timestamps = <String, DateTime>{};

  for (final nodeId in nodeIds) {
    final timestamp = getNodeExecutionTimestamp(logs, nodeId);
    if (timestamp == null) {
      throw Exception('No execution timestamp found for node $nodeId');
    }
    timestamps[nodeId] = timestamp;
  }

  // Проверить что узлы выполнились в правильном порядке
  for (var i = 0; i < nodeIds.length - 1; i++) {
    final current = timestamps[nodeIds[i]]!;
    final next = timestamps[nodeIds[i + 1]]!;

    if (current.isAfter(next)) {
      throw Exception(
        'Node ${nodeIds[i]} executed after ${nodeIds[i + 1]}. '
        'Expected order: ${nodeIds.join(" -> ")}. '
        '${reason ?? ""}\nTimestamps: $timestamps'
      );
    }
  }
}
