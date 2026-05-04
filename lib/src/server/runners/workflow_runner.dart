// WorkflowRunner — оркестратор lifecycle выполнения графа.
// Ответственность: start/complete/fail/suspend, snapshot, метрики run.
// Traversal делегируется GraphTraversal, execution — NodeExecutor.

import 'dart:convert';
import 'package:aq_schema/aq_schema.dart';
import 'package:aq_schema/graph/nodes/base/i_workflow_node.dart';
import 'package:aq_schema/graph/nodes/base/interactive_node.dart';
import 'package:aq_schema/graph/engine/i_run_repository.dart';
import 'package:aq_schema/graph/engine/i_run_state_manager.dart';
import 'package:aq_schema/graph/engine/state_strategies/in_memory_state_manager.dart';
import '../monitoring/metrics.dart';
import '../../shared/logger.dart';
import 'node_executor.dart';
import 'graph_traversal.dart';

class WorkflowRunner {
  final String runId;
  final String projectId;
  final String projectPath;
  final TypedWorkflowGraph graph;
  final IRunRepository _repo;
  final IRunStateManager _stateManager;

  final List<String> _logs = [];

  WorkflowRunner({
    required this.runId,
    required this.projectId,
    required this.projectPath,
    required this.graph,
    required IRunRepository repo,
    IRunStateManager? stateManager,
  })  : _repo = repo,
        _stateManager = stateManager ?? InMemoryStateManager();

  Future<void> start({
    String? startNodeId,
    String? restoredStateJson,
    Map<String, dynamic>? injectedVariables,
  }) async {
    GraphEngineMetrics.runStarted
        .inc(attributes: {'project_id': projectId, 'blueprint_id': graph.id});
    GraphEngineMetrics.activeRuns.inc();
    final runTimer = GraphEngineMetrics.runDuration
        .start(attributes: {'project_id': projectId, 'blueprint_id': graph.id});

    // Traversal state — восстанавливается из снапшота при resume
    final visitedEdges = <String>{};
    final arrivedEdges = <String, Set<String>>{};
    final nodeIterations = <String, int>{};

    if (restoredStateJson == null) {
      _log('🚀 Run Started (ID: ${shortId(runId)})');
    } else {
      _log('⚡ Run Resumed from node [${shortId(startNodeId ?? '', 4)}]');
      final savedRun = await _repo.getRun(runId);
      if (savedRun != null) {
        _logs.clear();
        _logs.addAll((jsonDecode(savedRun.logsJson) as List).map((e) => e.toString()));
      }
      await _repo.resume(runId);
    }

    final traversal = GraphTraversal(
      runId: runId,
      projectId: projectId,
      graph: graph,
      stateManager: _stateManager,
      nodeExecutor: NodeExecutor(projectId: projectId),
      log: _log,
      onSuspend: (node, context, e, arrivedEdges, nodeIterations) =>
          _handleSuspend(node, context, e, visitedEdges, arrivedEdges, nodeIterations),
      onNodeExecuted: (success) async {
        // Обновляем статус и проверяем не был ли run остановлен извне
        if (!success) {
          await _repo.updateRunLog(runId, _logs, status: WorkflowRunStatus.failed);
          return false;
        }
        final run = await _repo.getRun(runId);
        if (run?.status == WorkflowRunStatus.suspended) return false;
        await _repo.updateRunLog(runId, _logs, status: WorkflowRunStatus.running);
        return true;
      },
      visitedEdges: visitedEdges,
      arrivedEdges: arrivedEdges,
      nodeIterations: nodeIterations,
    );

    try {
      final allTargetIds = graph.edges.values.map((e) => e.targetId).toSet();
      final startNodes =
          graph.nodes.values.where((n) => !allTargetIds.contains(n.id)).toList();

      _log('📊 Graph has ${graph.nodes.length} nodes, ${graph.edges.length} edges');
      _log('🎯 Start nodes found: ${startNodes.length}');

      final context = _buildContext(restoredStateJson, visitedEdges, arrivedEdges, nodeIterations, injectedVariables);

      if (startNodeId != null) {
        final resumeNode = graph.nodes[startNodeId];
        if (resumeNode == null) {
          _log('⚠️ Resume node not found: $startNodeId');
          await _repo.updateRunLog(runId, _logs, status: WorkflowRunStatus.failed);
          return;
        }
        _log('✅ Resuming from node: ${resumeNode.id} (type: ${resumeNode.nodeType})');
        await traversal.processNode(resumeNode, 0, context, isResume: true);
      } else {
        if (startNodes.isEmpty) {
          _log('⚠️ No valid starting nodes found.');
          await _repo.updateRunLog(runId, _logs, status: WorkflowRunStatus.failed);
          return;
        }
        if (startNodes.length == 1) {
          _log('✅ Starting from node: ${startNodes.first.id}');
          await traversal.processNode(startNodes.first, 0, context);
        } else {
          _log('⚡ Starting ${startNodes.length} nodes in parallel');
          await Future.wait(startNodes.map((n) async {
            _log('✅ Starting node: ${n.id}');
            await traversal.processNode(n, 0, context);
          }));
        }
      }

      _log('🏁 Run Completed!');
      final currentRun = await _repo.getRun(runId);
      if (currentRun?.status != WorkflowRunStatus.suspended || startNodeId != null) {
        await _repo.updateRunLog(runId, _logs, status: WorkflowRunStatus.completed);
      }

      await _repo.complete(runId);
      await _stateManager.evict(runId);
      runTimer.stop(attributes: {'status': 'completed'});
      GraphEngineMetrics.runCompleted
          .inc(attributes: {'project_id': projectId, 'blueprint_id': graph.id});
      GraphEngineMetrics.activeRuns.dec();
    } catch (e, stack) {
      _log('❌ CRITICAL ERROR: $e');
      _log('Stack trace: $stack');
      await _repo.updateRunLog(runId, _logs, status: WorkflowRunStatus.failed);
      await _repo.complete(runId);
      await _stateManager.evict(runId);
      runTimer.stop(attributes: {'status': 'failed'});
      GraphEngineMetrics.runFailed.inc(attributes: {
        'project_id': projectId,
        'blueprint_id': graph.id,
        'error_type': e.runtimeType.toString(),
      });
      GraphEngineMetrics.activeRuns.dec();
    }
  }

  // ── Snapshot ────────────────────────────────────────────────────────────────

  RunContext _buildContext(
    String? restoredStateJson,
    Set<String> visitedEdges,
    Map<String, Set<String>> arrivedEdges,
    Map<String, int> nodeIterations,
    Map<String, dynamic>? injectedVariables,
  ) {
    if (restoredStateJson != null) {
      final parsed = jsonDecode(restoredStateJson) as Map<String, dynamic>;
      final ctx = RunContext.fromJson(
        parsed['user_context'] as Map<String, dynamic>,
        (msg, {type = 'info', depth = 0, required branch, details}) => _log(msg),
      );
      final engineState = parsed['engine_state'] as Map<String, dynamic>?;
      if (engineState != null) {
        if (engineState['visited_edges'] != null) {
          visitedEdges.addAll(List<String>.from(engineState['visited_edges'] as List));
        }
        if (engineState['arrived_edges'] != null) {
          (engineState['arrived_edges'] as Map).forEach((k, v) {
            arrivedEdges[k as String] = Set<String>.from(v as List);
          });
        }
        if (engineState['node_iterations'] != null) {
          (engineState['node_iterations'] as Map).forEach((k, v) {
            nodeIterations[k as String] = v as int;
          });
        }
      }
      if (injectedVariables != null) {
        ctx.state.addAll(injectedVariables);
        _log('💉 User Input received and injected.');
      }
      return ctx;
    }

    final ctx = RunContext(
      runId: runId,
      projectId: projectId,
      projectPath: projectPath,
      log: (msg, {type = 'info', depth = 0, required branch, details}) => _log(msg),
      currentBranch: 'main',
    );
    if (injectedVariables != null) {
      _log('💉 Injecting ${injectedVariables.length} variables');
      injectedVariables.forEach(ctx.setVar);
    }
    return ctx;
  }

  Future<void> _handleSuspend(
    IWorkflowNode node,
    RunContext context,
    SuspendExecutionException e,
    Set<String> visitedEdges,
    Map<String, Set<String>> arrivedEdges,
    Map<String, int> nodeIterations,
  ) async {
    final snapshot = {
      'user_context': context.toJson(),
      'engine_state': {
        'visited_edges': visitedEdges.toList(),
        'arrived_edges': arrivedEdges.map((k, v) => MapEntry(k, v.toList())),
        'node_iterations': nodeIterations,
        'suspended_node_id': node.id,
      },
    };
    await _repo.suspendRun(
      runId: runId,
      contextJson: jsonEncode(snapshot),
      nodeId: node.id,
    );
    await _repo.updateRunLog(runId, _logs, status: WorkflowRunStatus.suspended);
  }

  // ── Logging ─────────────────────────────────────────────────────────────────

  void _log(String message) {
    final entry = '[${DateTime.now().toString().substring(11, 19)}] $message';
    _logs.add(entry);
    graphEngineServerLogger.fine(entry);
  }

}
