// Локальная реализация транспорта — движок запускается в том же процессе.
// Используется в десктопном приложении AQ Studio.
//
// В будущем можно создать HttpEngineTransport который отправляет
// те же GraphRunRequest по HTTP к удалённому серверу.

import 'dart:async';
import 'package:aq_schema/aq_schema.dart';
import 'package:aq_schema/tools.dart';
import 'package:aq_schema/graph/nodes/base/i_workflow_node.dart';
import '../interfaces/i_run_repository.dart';
import '../interfaces/i_graph_repository.dart';
import '../server/runners/workflow_runner.dart';
import '../server/registry/node_type_registry.dart';
import '../server/engine/engine_execution_context.dart';

class LocalEngineTransport implements IEngineTransport {
  final IToolService tools;
  final IRunRepository runRepo;
  final IGraphRepository graphRepo;
  final AQAuthClient? auth;

  // Активные контроллеры для отмены запусков
  final Map<String, StreamController<GraphRunEvent>> _controllers = {};

  LocalEngineTransport({
    required this.tools,
    required this.runRepo,
    required this.graphRepo,
    this.auth,
  });

  @override
  Stream<GraphRunEvent> run(GraphRunRequest request) {
    final controller = StreamController<GraphRunEvent>.broadcast();
    _controllers[request.runId] = controller;

    _execute(request, controller).whenComplete(() {
      _controllers.remove(request.runId);
      if (!controller.isClosed) controller.close();
    });

    return controller.stream;
  }

  Future<void> _execute(
    GraphRunRequest request,
    StreamController<GraphRunEvent> controller,
  ) async {
    try {
      print('🔍 LocalEngineTransport._execute: Starting for runId=${request.runId}');

      // 0. Проверяем токен перед запуском (если auth доступен)
      if (auth != null) {
        final token = await auth!.currentToken;
        if (token == null) {
          print('❌ LocalEngineTransport: No valid token available');
          controller.add(GraphRunEvent.error(
            runId: request.runId,
            message: 'Authentication required: no valid token',
          ));
          return;
        }
        print('✅ LocalEngineTransport: Token valid until ${token.expiresAt}');
      }

      // 1. Загружаем граф по blueprintId из запроса
      final graph = await graphRepo.loadGraph(request.blueprintId);
      if (graph == null) {
        print('❌ LocalEngineTransport: Graph not found: ${request.blueprintId}');
        controller.add(GraphRunEvent.error(
          runId: request.runId,
          message: 'Graph not found: ${request.blueprintId}',
        ));
        return;
      }

      print('✅ LocalEngineTransport: Graph loaded: ${graph.runtimeType}');

      // Конвертируем WorkflowGraph (deprecated) в TypedWorkflowGraph если нужно
      TypedWorkflowGraph typedGraph;
      if (graph is TypedWorkflowGraph) {
        typedGraph = graph;
      } else if (graph is WorkflowGraph) { // ignore: deprecated_member_use
        // Конвертируем через NodeTypeRegistry
        final registry = buildDefaultRegistry();
        final typedNodes = <String, IWorkflowNode>{};
        for (final entry in graph.nodes.entries) {
          try {
            typedNodes[entry.key] = registry.workflowFromJson(entry.value.toJson());
          } catch (e) {
            print('⚠️ LocalEngineTransport: Cannot convert node ${entry.key}: $e');
          }
        }
        typedGraph = TypedWorkflowGraph(
          id: graph.id,
          tenantId: graph.tenantId,
          ownerId: graph.ownerId,
          name: graph.name,
          nodes: typedNodes,
          edges: graph.edges,
        );
        print('✅ LocalEngineTransport: Converted WorkflowGraph → TypedWorkflowGraph');
      } else {
        print('❌ LocalEngineTransport: Unsupported graph type: ${graph.runtimeType}');
        controller.add(GraphRunEvent.error(
          runId: request.runId,
          message: 'Unsupported graph type: ${graph.runtimeType}',
        ));
        return;
      }

      // 2. Создаём внутренний контекст для движка с загруженным графом
      final execContext = EngineExecutionContext(
        runId: request.runId,
        projectId: request.projectId,
        projectPath: request.projectPath,
        graph: typedGraph,
        initialVariables: request.initialVariables,
        resumeStateJson: request.resumeStateJson,
        resumeFromNodeId: request.resumeFromNodeId,
      );

      // 3. Создаём запись в БД
      if (!execContext.isResume) {
        print('💾 LocalEngineTransport: Creating run record in DB...');
        await runRepo.createRun(
          runId: execContext.runId,
          projectId: execContext.projectId,
          graphSnapshot: execContext.graph.toMap(),
        );
        print('✅ LocalEngineTransport: Run record created with status=running');
      }

      controller.add(GraphRunEvent.statusChanged(
        runId: execContext.runId,
        status: GraphRunStatus.running,
      ));

      print('🏗️ LocalEngineTransport: Creating WorkflowRunner...');

      // 4. Создаём runner с загруженным графом из контекста
      final runner = WorkflowRunner(
        runId: execContext.runId,
        projectId: execContext.projectId,
        projectPath: execContext.projectPath,
        graph: execContext.graph,
        repo: _RunRepoWithEvents(runRepo, execContext.runId, controller),
        graphRepo: graphRepo,
        tools: tools,
      );

      print('▶️ LocalEngineTransport: Starting runner...');

      await runner.start(
        startNodeId: execContext.resumeFromNodeId,
        injectedVariables: execContext.initialVariables,
      );

      print('✅ LocalEngineTransport: Runner completed successfully');
      controller.add(GraphRunEvent.completed(runId: execContext.runId));
    } catch (e, stack) {
      print('❌ LocalEngineTransport: EXCEPTION: $e');
      print('Stack trace: $stack');
      controller.add(GraphRunEvent.error(
        runId: request.runId,
        message: e.toString(),
      ));
    }
  }

  @override
  Future<void> respondToInput(UserInputResponse response) async {
    // Для локального транспорта Resume — это новый запуск с restoredStateJson
    // Логика Resume полностью в WorkflowRunner.start()
    // Здесь нам нужно только обновить данные в репозитории
    final existingRun = await runRepo.getRun(response.runId);
    if (existingRun == null) return;

    // Инжектируем ответ пользователя как переменные
    final newRequest = GraphRunRequest(
      runId: response.runId,
      projectId: existingRun['projectId'] as String,
      projectPath: existingRun['projectPath'] as String? ?? '',
      blueprintId: existingRun['blueprintId'] as String? ?? '',
      initialVariables: response.values,
      resumeStateJson: existingRun['contextJson'] as String?,
      resumeFromNodeId: existingRun['suspendedNodeId'] as String?,
    );

    run(newRequest);
  }

  @override
  Future<void> cancel(String runId) async {
    await runRepo.updateRunLog(runId, [], status: 'cancelled');
    final controller = _controllers[runId];
    if (controller != null && !controller.isClosed) {
      controller.add(GraphRunEvent.statusChanged(
        runId: runId,
        status: GraphRunStatus.cancelled,
      ));
      await controller.close();
    }
  }

  @override
  Future<bool> isAvailable() async => true;

  @override
  void dispose() {
    for (final c in _controllers.values) {
      if (!c.isClosed) c.close();
    }
    _controllers.clear();
  }
}

// Обёртка репозитория которая дополнительно шлёт события в stream
class _RunRepoWithEvents implements IRunRepository {
  final IRunRepository _delegate;
  final String _runId;
  final StreamController<GraphRunEvent> _controller;

  _RunRepoWithEvents(this._delegate, this._runId, this._controller);

  @override
  Future<void> createRun(
          {required String runId,
          required String projectId,
          required Map<String, dynamic> graphSnapshot}) =>
      _delegate.createRun(
          runId: runId, projectId: projectId, graphSnapshot: graphSnapshot);

  @override
  Future<void> updateRunLog(String runId, List<String> logs,
      {String? status}) async {
    await _delegate.updateRunLog(runId, logs, status: status);
    if (status != null) {
      final s =
          GraphRunStatus.values.where((v) => v.name == status).firstOrNull;
      if (s != null && !_controller.isClosed) {
        _controller.add(GraphRunEvent.statusChanged(runId: _runId, status: s));
      }
    }
    // Последний лог шлём как событие
    if (logs.isNotEmpty && !_controller.isClosed) {
      _controller.add(GraphRunEvent.log(
        runId: _runId,
        message: logs.last,
        logType: 'system',
        branch: 'main',
      ));
    }
  }

  @override
  Future<void> suspendRun(
      {required String runId,
      required String contextJson,
      required String nodeId,
      required List<String> logs}) async {
    await _delegate.suspendRun(
        runId: runId, contextJson: contextJson, nodeId: nodeId, logs: logs);
    if (!_controller.isClosed) {
      _controller.add(GraphRunEvent.userInputRequired(
        runId: runId,
        payload: {'nodeId': nodeId},
      ));
    }
  }

  @override
  Future<Map<String, dynamic>?> getRun(String runId) => _delegate.getRun(runId);

  @override
  Future<bool> compareAndSetStatus({
    required String runId,
    required String expectedStatus,
    required String newStatus,
  }) =>
      _delegate.compareAndSetStatus(
        runId: runId,
        expectedStatus: expectedStatus,
        newStatus: newStatus,
      );

  @override
  Future<bool> tryAcquireLock({
    required String runId,
    required String workerId,
    required Duration ttl,
  }) =>
      _delegate.tryAcquireLock(
        runId: runId,
        workerId: workerId,
        ttl: ttl,
      );

  @override
  Future<bool> releaseLock({
    required String runId,
    required String workerId,
  }) =>
      _delegate.releaseLock(
        runId: runId,
        workerId: workerId,
      );

  @override
  Future<void> moveToDLQ({
    required String runId,
    required String reason,
    required int failureCount,
    String? lastError,
  }) =>
      _delegate.moveToDLQ(
        runId: runId,
        reason: reason,
        failureCount: failureCount,
        lastError: lastError,
      );

  @override
  Future<List<Map<String, dynamic>>> getDLQJobs({
    int limit = 100,
    int offset = 0,
  }) =>
      _delegate.getDLQJobs(limit: limit, offset: offset);

  @override
  Future<bool> retryFromDLQ({required String runId}) =>
      _delegate.retryFromDLQ(runId: runId);

  @override
  Future<int> cleanupDLQ({required Duration olderThan}) =>
      _delegate.cleanupDLQ(olderThan: olderThan);
}
