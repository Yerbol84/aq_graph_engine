// pkgs/aq_graph_engine/lib/src/server/monitoring/metrics.dart
//
// Метрики Graph Engine — инициализируются через IMetricsService.
//
// ── Использование ────────────────────────────────────────────────────────────
//
//   // Инициализация (один раз при старте GraphEngine):
//   GraphEngineMetrics.init(metricsService);
//
//   // Использование в runner:
//   GraphEngineMetrics.runStarted.inc(attributes: {
//     'project_id': projectId,
//     'blueprint_id': blueprintId,
//   });
//
//   final handle = GraphEngineMetrics.runDuration.start(attributes: {
//     'project_id': projectId,
//   });
//   await runner.start();
//   handle.stop(attributes: {'status': 'completed'});

import 'package:aq_schema/metrics.dart';

/// Метрики Graph Engine.
///
/// Инициализируется один раз при старте через [GraphEngineMetrics.init].
/// До инициализации все метрики — no-op.
class GraphEngineMetrics {
  static IMetricsService _service = NoopMetricsService.instance;

  /// Инициализировать с конкретным сервисом метрик.
  static void init(IMetricsService service) {
    _service = service;
    _setup();
  }

  // ── Счётчики ────────────────────────────────────────────────────────────
  // Атрибуты: project_id, blueprint_id

  /// Запуски графов.
  /// Атрибуты: project_id, blueprint_id
  static late ICounter runStarted;

  /// Успешно завершённые запуски.
  /// Атрибуты: project_id, blueprint_id
  static late ICounter runCompleted;

  /// Упавшие запуски.
  /// Атрибуты: project_id, blueprint_id, error_type
  static late ICounter runFailed;

  /// Приостановленные запуски (ожидают ввода пользователя).
  /// Атрибуты: project_id, blueprint_id
  static late ICounter runSuspended;

  /// Выполненные узлы.
  /// Атрибуты: node_type, project_id
  static late ICounter nodeExecuted;

  /// Retry попытки узлов.
  /// Атрибуты: node_type, project_id, attempt
  static late ICounter nodeRetried;

  // ── Gauge ───────────────────────────────────────────────────────────────

  /// Количество активных запусков прямо сейчас.
  static late IGauge activeRuns;

  // ── Таймеры ─────────────────────────────────────────────────────────────

  /// Длительность выполнения графа.
  /// Атрибуты при start: project_id, blueprint_id
  /// Атрибуты при stop:  status (completed/failed/suspended)
  static late ITimer runDuration;

  /// Длительность выполнения узла.
  /// Атрибуты при start: node_type, project_id
  /// Атрибуты при stop:  status (ok/error/retry)
  static late ITimer nodeDuration;

  // ── Инициализация ────────────────────────────────────────────────────────

  static void _setup() {
    runStarted   = _service.counter('graph_runs_started_total');
    runCompleted = _service.counter('graph_runs_completed_total');
    runFailed    = _service.counter('graph_runs_failed_total');
    runSuspended = _service.counter('graph_runs_suspended_total');
    nodeExecuted = _service.counter('graph_node_executions_total');
    nodeRetried  = _service.counter('graph_node_retries_total');

    activeRuns = _service.gauge('graph_active_runs');

    runDuration = _service.timer(
      'graph_run_duration_seconds',
      buckets: [0.1, 0.5, 1, 2, 5, 10, 30, 60, 120, 300, 600],
    );
    nodeDuration = _service.timer(
      'graph_node_duration_seconds',
      buckets: [0.01, 0.05, 0.1, 0.5, 1, 2, 5, 10, 30, 60],
    );
  }

  // Инициализируем noop сразу — до первого вызова init()
  // ignore: unused_field
  static final bool _initialized = () { _setup(); return true; }();
}
