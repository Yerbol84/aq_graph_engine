// Локальная реализация транспорта — движок запускается в том же процессе.

import 'dart:async';
import 'package:aq_schema/aq_schema.dart';
import 'package:aq_schema/tools.dart';
import 'package:aq_schema/graph/engine/i_run_repository.dart';
import 'package:aq_schema/graph/engine/i_graph_repository.dart';
import '../server/runners/workflow_runner.dart';
import '../server/engine/engine_execution_context.dart';
import '../shared/logger.dart';
import 'run_repo_event_bridge.dart';

class LocalEngineTransport implements IEngineTransport {
  final IToolService tools;
  final IRunRepository runRepo;
  final IGraphRepository graphRepo;
  final AQAuthClient? auth;

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
      if (auth != null) {
        final token = await auth!.currentToken;
        if (token == null) {
          controller.add(GraphRunEvent.error(
              runId: request.runId,
              message: 'Authentication required: no valid token'));
          return;
        }
        graphEngineServerLogger.fine('Token valid until ${token.expiresAt}');
      }

      final graph = await graphRepo.loadGraph(request.blueprintId);
      if (graph == null) {
        controller.add(GraphRunEvent.error(
            runId: request.runId,
            message: 'Graph not found: ${request.blueprintId}'));
        return;
      }

      if (graph is! TypedWorkflowGraph) {
        controller.add(GraphRunEvent.error(
            runId: request.runId,
            message: 'Unsupported graph type: ${graph.runtimeType}. Use TypedWorkflowGraph.'));
        return;
      }

      final execContext = EngineExecutionContext(
        runId: request.runId,
        projectId: request.projectId,
        projectPath: request.projectPath,
        graph: graph,
        initialVariables: request.initialVariables,
        resumeStateJson: request.resumeStateJson,
        resumeFromNodeId: request.resumeFromNodeId,
      );

      if (!execContext.isResume) {
        await runRepo.createRun(WorkflowRun(
          id: execContext.runId,
          projectId: execContext.projectId,
          blueprintId: execContext.graph.id,
          // TECH DEBT: projectPath сохраняется в graphSnapshot до добавления поля в WorkflowRun (aq_schema)
          graphSnapshot: {...execContext.graph.toMap(), '_projectPath': execContext.projectPath},
          status: WorkflowRunStatus.running,
          logsJson: '[]',
          createdAt: DateTime.now(),
        ));
      }

      controller.add(GraphRunEvent.statusChanged(
          runId: execContext.runId, status: GraphRunStatus.running));

      final runner = WorkflowRunner(
        runId: execContext.runId,
        projectId: execContext.projectId,
        projectPath: execContext.projectPath,
        graph: execContext.graph,
        repo: RunRepoEventBridge(runRepo, execContext.runId, controller),
      );

      await runner.start(
        startNodeId: execContext.resumeFromNodeId,
        restoredStateJson: execContext.resumeStateJson,
        injectedVariables: execContext.initialVariables,
      );

      controller.add(GraphRunEvent.completed(runId: execContext.runId));
    } catch (e, stack) {
      graphEngineServerLogger.severe('LocalEngineTransport exception', e, stack);
      controller.add(GraphRunEvent.error(
          runId: request.runId, message: e.toString()));
    }
  }

  @override
  Future<void> respondToInput(UserInputResponse response) async {
    final existingRun = await runRepo.getRun(response.runId);
    if (existingRun == null) return;
    // TECH DEBT: восстанавливаем projectPath из graphSnapshot до добавления поля в WorkflowRun
    final projectPath = existingRun.graphSnapshot['_projectPath'] as String? ?? '';
    run(GraphRunRequest(
      runId: response.runId,
      projectId: existingRun.projectId,
      projectPath: projectPath,
      blueprintId: existingRun.blueprintId,
      initialVariables: response.values,
      resumeStateJson: existingRun.contextJson,
      resumeFromNodeId: existingRun.suspendedNodeId,
    ));
  }

  @override
  Future<void> cancel(String runId) async {
    await runRepo.updateRunLog(runId, [], status: WorkflowRunStatus.cancelled);
    final controller = _controllers[runId];
    if (controller != null && !controller.isClosed) {
      controller.add(GraphRunEvent.statusChanged(
          runId: runId, status: GraphRunStatus.cancelled));
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
