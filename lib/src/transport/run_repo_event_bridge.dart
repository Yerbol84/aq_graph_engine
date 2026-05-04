// Decorator над IRunRepository: при обновлении статуса шлёт события в stream.
// Изолированная ответственность: bridge между репозиторием и event stream транспорта.

import 'dart:async';
import 'package:aq_schema/aq_schema.dart';
import 'package:aq_schema/graph/engine/i_run_repository.dart';

final class RunRepoEventBridge extends IRunRepository {
  final IRunRepository _delegate;
  final String _runId;
  final StreamController<GraphRunEvent> _controller;

  RunRepoEventBridge(this._delegate, this._runId, this._controller);

  @override
  Future<void> createRun(WorkflowRun run) => _delegate.createRun(run);

  @override
  Future<void> updateRunLog(String runId, List<String> logs,
      {WorkflowRunStatus? status}) async {
    await _delegate.updateRunLog(runId, logs, status: status);
    if (status != null && !_controller.isClosed) {
      final s = GraphRunStatus.values.where((v) => v.name == status.name).firstOrNull;
      if (s != null) {
        _controller.add(GraphRunEvent.statusChanged(runId: _runId, status: s));
      }
    }
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
  Future<void> suspendRun({
    required String runId,
    required String contextJson,
    required String nodeId,
  }) async {
    await _delegate.suspendRun(runId: runId, contextJson: contextJson, nodeId: nodeId);
    if (!_controller.isClosed) {
      _controller.add(GraphRunEvent.userInputRequired(
          runId: runId, payload: {'nodeId': nodeId}));
    }
  }

  @override
  Future<WorkflowRun?> getRun(String runId) => _delegate.getRun(runId);

  @override
  Future<void> appendLog(String runId, String entry) =>
      _delegate.appendLog(runId, entry);

  @override
  Future<bool> compareAndSetStatus({
    required String runId,
    required WorkflowRunStatus expectedStatus,
    required WorkflowRunStatus newStatus,
  }) => _delegate.compareAndSetStatus(
      runId: runId, expectedStatus: expectedStatus, newStatus: newStatus);

  @override
  Future<bool> tryAcquireLock(
          {required String runId,
          required String workerId,
          required Duration ttl}) =>
      _delegate.tryAcquireLock(runId: runId, workerId: workerId, ttl: ttl);

  @override
  Future<bool> releaseLock(
          {required String runId, required String workerId}) =>
      _delegate.releaseLock(runId: runId, workerId: workerId);

  @override
  Future<void> moveToDLQ(
          {required String runId,
          required String reason,
          required int failureCount,
          String? lastError}) =>
      _delegate.moveToDLQ(
          runId: runId,
          reason: reason,
          failureCount: failureCount,
          lastError: lastError);

  @override
  Future<List<WorkflowRun>> getDLQJobs({int limit = 100, int offset = 0}) =>
      _delegate.getDLQJobs(limit: limit, offset: offset);

  @override
  Future<bool> retryFromDLQ({required String runId}) =>
      _delegate.retryFromDLQ(runId: runId);

  @override
  Future<int> cleanupDLQ({required Duration olderThan}) =>
      _delegate.cleanupDLQ(olderThan: olderThan);
}
