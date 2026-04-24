// Prometheus метрики для Graph Engine
//
// Собирает метрики выполнения графов для мониторинга в production

import 'package:prometheus_client/prometheus_client.dart';

/// Метрики Graph Engine для Prometheus
class GraphEngineMetrics {
  // ── Счётчики ────────────────────────────────────────────────────────────

  /// Общее количество запущенных графов
  static final runStartedCounter = Counter(
    name: 'graph_runs_started_total',
    help: 'Total number of graph runs started',
    labelNames: ['project_id', 'blueprint_id'],
  );

  /// Количество успешно завершенных графов
  static final runCompletedCounter = Counter(
    name: 'graph_runs_completed_total',
    help: 'Total number of graph runs completed successfully',
    labelNames: ['project_id', 'blueprint_id'],
  );

  /// Количество упавших графов
  static final runFailedCounter = Counter(
    name: 'graph_runs_failed_total',
    help: 'Total number of graph runs failed',
    labelNames: ['project_id', 'blueprint_id', 'error_type'],
  );

  /// Количество приостановленных графов (suspended)
  static final runSuspendedCounter = Counter(
    name: 'graph_runs_suspended_total',
    help: 'Total number of graph runs suspended',
    labelNames: ['project_id', 'blueprint_id'],
  );

  /// Количество выполненных узлов
  static final nodeExecutionCounter = Counter(
    name: 'graph_node_executions_total',
    help: 'Total number of node executions',
    labelNames: ['node_type', 'project_id'],
  );

  /// Количество retry попыток узлов
  static final nodeRetryCounter = Counter(
    name: 'graph_node_retries_total',
    help: 'Total number of node retry attempts',
    labelNames: ['node_type', 'project_id', 'attempt'],
  );

  // ── Гистограммы ─────────────────────────────────────────────────────────

  /// Длительность выполнения графа
  static final runDurationHistogram = Histogram(
    name: 'graph_run_duration_seconds',
    help: 'Duration of graph run execution in seconds',
    labelNames: ['project_id', 'blueprint_id'],
    buckets: [0.1, 0.5, 1, 2, 5, 10, 30, 60, 120, 300, 600],
  );

  /// Длительность выполнения узла
  static final nodeExecutionHistogram = Histogram(
    name: 'graph_node_execution_seconds',
    help: 'Duration of individual node execution in seconds',
    labelNames: ['node_type', 'project_id'],
    buckets: [0.01, 0.05, 0.1, 0.5, 1, 2, 5, 10, 30, 60],
  );

  // ── Gauge ───────────────────────────────────────────────────────────────

  /// Количество активных запусков
  static final activeRunsGauge = Gauge(
    name: 'graph_active_runs',
    help: 'Number of currently active graph runs',
  );

  /// Количество запусков в очереди
  static final queuedRunsGauge = Gauge(
    name: 'graph_queued_runs',
    help: 'Number of runs waiting in queue',
  );

  /// Количество приостановленных запусков
  static final suspendedRunsGauge = Gauge(
    name: 'graph_suspended_runs',
    help: 'Number of suspended runs waiting for input',
  );

  /// Количество записей в DLQ
  static final dlqSizeGauge = Gauge(
    name: 'graph_dlq_size',
    help: 'Number of runs in Dead Letter Queue',
  );

  /// Состояние circuit breaker (0=closed, 1=open, 2=half-open)
  static final circuitBreakerStateGauge = Gauge(
    name: 'graph_circuit_breaker_state',
    help: 'Circuit breaker state (0=closed, 1=open, 2=half-open)',
    labelNames: ['transport'],
  );

  /// Количество активных worker'ов
  static final activeWorkersGauge = Gauge(
    name: 'graph_active_workers',
    help: 'Number of active workers',
  );

  /// Количество idle worker'ов
  static final idleWorkersGauge = Gauge(
    name: 'graph_idle_workers',
    help: 'Number of idle workers',
  );

  // ── Error tracking ──────────────────────────────────────────────────────

  /// Ошибки по типам
  static final errorsByTypeCounter = Counter(
    name: 'graph_errors_by_type_total',
    help: 'Total number of errors by type',
    labelNames: ['error_type', 'project_id'],
  );

  /// Retry успешность
  static final retrySuccessCounter = Counter(
    name: 'graph_retry_success_total',
    help: 'Total number of successful retries',
    labelNames: ['node_type', 'attempt'],
  );

  /// Circuit breaker открытия
  static final circuitBreakerOpenCounter = Counter(
    name: 'graph_circuit_breaker_open_total',
    help: 'Total number of circuit breaker opens',
    labelNames: ['transport'],
  );

  // ── Регистрация ─────────────────────────────────────────────────────────

  /// Зарегистрировать все метрики в registry
  static void register() {
    final registry = CollectorRegistry.defaultRegistry;

    // Счётчики
    registry.register(runStartedCounter);
    registry.register(runCompletedCounter);
    registry.register(runFailedCounter);
    registry.register(runSuspendedCounter);
    registry.register(nodeExecutionCounter);
    registry.register(nodeRetryCounter);
    registry.register(errorsByTypeCounter);
    registry.register(retrySuccessCounter);
    registry.register(circuitBreakerOpenCounter);

    // Гистограммы
    registry.register(runDurationHistogram);
    registry.register(nodeExecutionHistogram);

    // Gauge
    registry.register(activeRunsGauge);
    registry.register(queuedRunsGauge);
    registry.register(suspendedRunsGauge);
    registry.register(dlqSizeGauge);
    registry.register(circuitBreakerStateGauge);
    registry.register(activeWorkersGauge);
    registry.register(idleWorkersGauge);
  }
}
