// Выполнение узла с retry механизмом.
// Изолированная ответственность: execute + backoff + метрики узла.

import 'package:aq_schema/graph/nodes/base/i_workflow_node.dart';
import 'package:aq_schema/graph/engine/run_context.dart';
import '../monitoring/metrics.dart';

/// Выполняет узел с retry и экспоненциальным backoff.
final class NodeExecutor {
  final String projectId;

  const NodeExecutor({required this.projectId});

  /// Выполнить узел. Бросает исключение если все попытки исчерпаны.
  Future<dynamic> execute(IWorkflowNode node, RunContext context) async {
    final maxRetries = node.maxRetries;
    var attempt = 0;
    var delayMs = node.retryDelayMs;

    while (true) {
      try {
        return await node.execute(context);
      } catch (e) {
        attempt++;
        if (!_shouldRetry(node, e) || attempt > maxRetries) {
          rethrow;
        }

        GraphEngineMetrics.nodeRetried.inc(attributes: {
          'node_type': node.nodeType,
          'project_id': projectId,
          'attempt': attempt.toString(),
        });

        await Future.delayed(Duration(milliseconds: delayMs));
        if (node.useExponentialBackoff) delayMs *= 2;
      }
    }
  }

  bool _shouldRetry(IWorkflowNode node, Object error) {
    final types = node.retryableExceptions;
    if (types == null) return true;
    return types.any((t) => error.runtimeType == t);
  }
}
