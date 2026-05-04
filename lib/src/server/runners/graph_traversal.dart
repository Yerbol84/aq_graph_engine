// Обход графа: рёбра, join strategy, parallel/sequential, cycle detection.
// Изолированная ответственность: traversal без lifecycle и без I/O репозитория.

import 'package:aq_schema/aq_schema.dart';
import 'package:aq_schema/graph/nodes/base/i_workflow_node.dart';
import 'package:aq_schema/graph/nodes/base/composite_node.dart';
import 'package:aq_schema/graph/nodes/base/interactive_node.dart';
import 'package:aq_schema/graph/nodes/state/i_stateful_node.dart';
import 'package:aq_schema/graph/engine/i_run_state_manager.dart';
import 'package:aq_schema/graph/engine/condition_evaluator.dart';
import '../monitoring/metrics.dart';
import '../../shared/logger.dart' show shortId;
import 'node_executor.dart';

/// Колбэк для уведомления о suspend из traversal в runner.
typedef OnSuspend = Future<void> Function(
  IWorkflowNode node,
  RunContext context,
  SuspendExecutionException reason,
  Map<String, Set<String>> arrivedEdges,
  Map<String, int> nodeIterations,
);

/// Колбэк после выполнения узла.
/// Возвращает false если traversal должен остановиться (run отменён/suspended извне).
typedef OnNodeExecuted = Future<bool> Function(bool success);

/// Обходит граф, выполняет узлы через [NodeExecutor].
/// Не знает о lifecycle run — только о traversal.
final class GraphTraversal {
  final String runId;
  final String projectId;
  final TypedWorkflowGraph graph;
  final IRunStateManager stateManager;
  final OnNodeExecuted onNodeExecuted;
  final NodeExecutor nodeExecutor;
  final void Function(String) log;
  final OnSuspend onSuspend;

  // Traversal state
  final Set<String> visitedEdges;
  final Map<String, Set<String>> arrivedEdges;
  final Map<String, int> nodeIterations;
  static const _maxNodeIterations = 100;

  GraphTraversal({
    required this.runId,
    required this.projectId,
    required this.graph,
    required this.stateManager,
    required this.onNodeExecuted,
    required this.nodeExecutor,
    required this.log,
    required this.onSuspend,
    required this.visitedEdges,
    required this.arrivedEdges,
    required this.nodeIterations,
  });

  Future<void> processNode(
    IWorkflowNode node,
    int depth,
    RunContext context, {
    bool isResume = false,
  }) async {
    log('▶ Executing: ${node.nodeType} [${shortId(node.id, 4)}]');

    final iterations = (nodeIterations[node.id] ?? 0) + 1;
    if (iterations > _maxNodeIterations) {
      log('🔁 Max iterations ($iterations) reached at [${shortId(node.id, 4)}] — breaking cycle');
      return;
    }
    nodeIterations[node.id] = iterations;

    final nodeTimer = GraphEngineMetrics.nodeDuration.start(
        attributes: {'node_type': node.nodeType, 'project_id': projectId});
    GraphEngineMetrics.nodeExecuted
        .inc(attributes: {'node_type': node.nodeType, 'project_id': projectId});

    dynamic result;
    bool success = true;

    try {
      result = await nodeExecutor.execute(node, context);
      nodeTimer.stop(attributes: {'status': 'ok'});

      if (node is IStatefulNode) {
        await stateManager.checkpointForNode(runId, context, node.stateHint);
      }
      if (node is CompositeNode && result is RunContext) {
        log('🔄 Composite node executed, applying output mapping');
        node.applyOutputMapping(result, context);
      }
    } on SuspendExecutionException catch (e) {
      log('⏸️ Execution suspended: ${e.reason}');
      nodeTimer.stop(attributes: {'status': 'suspended'});
      GraphEngineMetrics.runSuspended
          .inc(attributes: {'project_id': projectId, 'blueprint_id': graph.id});
      await onSuspend(node, context, e, arrivedEdges, nodeIterations);
      return;
    } catch (e) {
      log('❌ Node Error: $e');
      success = false;
      await onNodeExecuted(false);
    }

    if (!await onNodeExecuted(success) && !isResume) return;

    final allOutgoing = graph.edges.values.where((e) => e.sourceId == node.id).toList();
    if (allOutgoing.isEmpty) return;

    final candidates = allOutgoing.where((edge) {
      switch (edge.type) {
        case WorkflowEdgeType.onSuccess:
          return success;
        case WorkflowEdgeType.onError:
          return !success;
        case WorkflowEdgeType.conditional:
          if (edge.conditionExpression?.isNotEmpty == true) {
            try {
              return ConditionEvaluator.evaluate(edge.conditionExpression!, context.state);
            } catch (_) {
              log('⚠️ Condition error for edge ${edge.id}');
              return false;
            }
          }
          return true;
      }
    }).toList();

    if (candidates.isEmpty) {
      log('⚠️ No matching edges (success=$success)');
      return;
    }

    final selected = node.selectOutgoingEdges(candidates, result);
    final toExecute = selected != null
        ? candidates.where((e) => selected.contains(e.id)).toList()
        : candidates;

    if (toExecute.isEmpty) return;
    toExecute.sort((a, b) => b.priority.compareTo(a.priority));

    await _executeEdges(toExecute, depth, context, isResume: isResume);


  }

  Future<void> _executeEdges(
    List<WorkflowEdge> edges,
    int depth,
    RunContext context, {
    bool isResume = false,
  }) async {
    final sequential = <WorkflowEdge>[];
    final parallel = <WorkflowEdge>[];

    for (final edge in edges) {
      if (edge.isExclusive && sequential.isNotEmpty) {
        log('🚫 Exclusive edge ${shortId(edge.id, 4)} blocks remaining');
        break;
      }
      if (edge.executionMode == EdgeExecutionMode.parallel) {
        parallel.add(edge);
      } else {
        sequential.add(edge);
      }
      if (edge.isExclusive) {
        log('🔒 Exclusive edge ${shortId(edge.id, 4)} — stopping');
        break;
      }
    }

    for (final edge in sequential) {
      await _executeEdge(edge, depth, context, isResume: isResume);
    }
    if (parallel.isNotEmpty) {
      log('⚡ Executing ${parallel.length} edges in parallel');
      await Future.wait(
          parallel.map((e) => _executeEdge(e, depth, context, isResume: isResume)));
    }
  }

  Future<void> _executeEdge(
    WorkflowEdge edge,
    int depth,
    RunContext context, {
    bool isResume = false,
  }) async {
    visitedEdges.add(edge.id);
    final next = graph.nodes[edge.targetId];
    if (next == null) {
      log('⚠️ Target node ${edge.targetId} not found');
      return;
    }

    arrivedEdges.putIfAbsent(edge.targetId, () => {}).add(edge.id);

    if (next.joinStrategy == NodeJoinStrategy.waitAll) {
      final incoming = graph.edges.values.where((e) => e.targetId == edge.targetId).toList();
      final arrived = arrivedEdges[edge.targetId] ?? {};
      if (!incoming.every((e) => arrived.contains(e.id))) {
        log('⏳ Node [${shortId(edge.targetId, 4)}] waiting for ${incoming.length - arrived.length} more edge(s)');
        return;
      }
      log('✅ All ${incoming.length} edges arrived at [${shortId(edge.targetId, 4)}]');
    }

    final nextContext = context.cloneForBranch(edge.branchName);
    log('→ Transmitting to [${edge.branchName}]...');
    await processNode(next, depth + 1, nextContext, isResume: isResume);
  }

}
