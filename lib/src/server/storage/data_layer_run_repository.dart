// Реализация IRunRepository через IDataLayer.instance (из aq_schema).

import 'dart:convert';
import 'package:aq_schema/aq_schema.dart';
import 'package:aq_schema/data_layer/models/query/vault_query.dart';
import 'package:aq_schema/data_layer/models/query/vault_operator.dart';
import 'package:aq_schema/graph/engine/i_run_repository.dart';

final class DataLayerRunRepository extends IRunRepository {
  DataLayerRunRepository();

  LoggedRepository<WorkflowRun> get _runs => IDataLayer.instance.logged<WorkflowRun>(
        collection: WorkflowRun.kCollection,
        fromMap: WorkflowRun.fromMap,
      );

  @override
  Future<void> createRun(WorkflowRun run) async {
    await _runs.save(run, actorId: 'graph_engine');
  }

  @override
  Future<void> updateRunLog(
    String runId,
    List<String> logs, {
    WorkflowRunStatus? status,
  }) async {
    if (logs.isEmpty && status == null) return;
    final run = await _runs.findById(runId);
    if (run == null) return;

    final existingLogs = _parseLogs(run.logsJson);
    existingLogs.addAll(logs);

    await _runs.save(
      run.copyWith(
        logsJson: jsonEncode(existingLogs),
        status: status,
      ),
      actorId: 'graph_engine',
    );
  }

  @override
  Future<void> suspendRun({
    required String runId,
    required String contextJson,
    required String nodeId,
  }) async {
    final run = await _runs.findById(runId);
    if (run == null) return;
    await _runs.save(
      run.copyWith(
        status: WorkflowRunStatus.suspended,
        contextJson: contextJson,
        suspendedNodeId: nodeId,
      ),
      actorId: 'graph_engine',
    );
  }

  @override
  Future<WorkflowRun?> getRun(String runId) => _runs.findById(runId);

  @override
  Future<void> appendLog(String runId, String entry) async {
    final run = await _runs.findById(runId);
    if (run == null) return;
    final logs = _parseLogs(run.logsJson)..add(entry);
    await _runs.save(run.copyWith(logsJson: jsonEncode(logs)), actorId: 'graph_engine');
  }

  @override
  Future<bool> compareAndSetStatus({
    required String runId,
    required WorkflowRunStatus expectedStatus,
    required WorkflowRunStatus newStatus,
  }) async {
    final run = await _runs.findById(runId);
    if (run == null || run.status != expectedStatus) return false;
    await _runs.save(
      run.copyWith(status: newStatus),
      actorId: 'graph_engine',
    );
    return true;
  }

  @override
  Future<bool> tryAcquireLock({
    required String runId,
    required String workerId,
    required Duration ttl,
  }) async => true;

  @override
  Future<bool> releaseLock({
    required String runId,
    required String workerId,
  }) async => true;

  @override
  Future<void> moveToDLQ({
    required String runId,
    required String reason,
    required int failureCount,
    String? lastError,
  }) async {
    final run = await _runs.findById(runId);
    if (run == null) return;
    await _runs.save(
      run.copyWith(status: WorkflowRunStatus.failed),
      actorId: 'graph_engine',
    );
  }

  @override
  Future<List<WorkflowRun>> getDLQJobs({int limit = 100, int offset = 0}) async {
    return _runs.findAll(
      query: VaultQuery()
          .where('status', VaultOperator.equals, WorkflowRunStatus.failed.value)
          .orderBy('createdAt', descending: true)
          .page(limit: limit, offset: offset),
    );
  }

  @override
  Future<bool> retryFromDLQ({required String runId}) async {
    final run = await _runs.findById(runId);
    if (run == null || run.status != WorkflowRunStatus.failed) return false;
    await _runs.save(run.copyWith(status: WorkflowRunStatus.running), actorId: 'graph_engine');
    return true;
  }

  @override
  Future<int> cleanupDLQ({required Duration olderThan}) async {
    final cutoff = DateTime.now().subtract(olderThan).toIso8601String();
    final old = await _runs.findAll(
      query: VaultQuery()
          .where('status', VaultOperator.equals, WorkflowRunStatus.failed.value)
          .where('createdAt', VaultOperator.lessThan, cutoff),
    );
    for (final run in old) {
      await _runs.delete(run.id, actorId: 'graph_engine');
    }
    return old.length;
  }

  List<String> _parseLogs(String raw) {
    try {
      return (jsonDecode(raw) as List).cast<String>();
    } catch (_) {
      return [];
    }
  }
}
