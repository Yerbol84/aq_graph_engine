// GraphEngine — единая точка входа.
// Приложение создаёт один экземпляр GraphEngine и работает только через него.

import 'package:aq_schema/aq_schema.dart';
import 'package:aq_schema/tools.dart';
import 'package:aq_schema/metrics.dart';
import '../../interfaces/i_run_repository.dart';
import '../../interfaces/i_graph_repository.dart';
import '../../transport/local_engine_transport.dart';
import '../../transport/http_engine_transport.dart';
import '../monitoring/metrics.dart' show GraphEngineMetrics;

/// Режим работы GraphEngine
enum GraphEngineMode {
  /// Локальное выполнение в том же процессе
  local,

  /// Удалённое выполнение через HTTP
  remote,

  /// Автоматический выбор: remote если доступен, иначе local
  auto,
}

class GraphEngine {
  final IToolService tools;
  final IRunRepository runRepo;
  final IGraphRepository graphRepo;
  final AQAuthClient? auth;
  final GraphEngineMode mode;
  final String? remoteServerUrl;
  late final IEngineTransport _transport;

  GraphEngine({
    required this.tools,
    required this.runRepo,
    required this.graphRepo,
    this.auth,
    this.mode = GraphEngineMode.local,
    this.remoteServerUrl,
    IEngineTransport? transport,
  }) {
    GraphEngineMetrics.init(IMetricsService.instance);

    if (transport != null) {
      _transport = transport;
      return;
    }

    switch (mode) {
      case GraphEngineMode.local:
        _transport = LocalEngineTransport(
          tools: tools,
          runRepo: runRepo,
          graphRepo: graphRepo,
          auth: auth,
        );
        break;

      case GraphEngineMode.remote:
        if (remoteServerUrl == null) {
          throw ArgumentError(
            'remoteServerUrl is required for GraphEngineMode.remote',
          );
        }
        _transport = HttpEngineTransport(
          serverUrl: remoteServerUrl!,
          auth: auth,
        );
        break;

      case GraphEngineMode.auto:
        if (remoteServerUrl != null) {
          _transport = _AutoFallbackTransport(
            primary: HttpEngineTransport(
              serverUrl: remoteServerUrl!,
              auth: auth,
            ),
            fallback: LocalEngineTransport(
              tools: tools,
              runRepo: runRepo,
              graphRepo: graphRepo,
              auth: auth,
            ),
          );
        } else {
          _transport = LocalEngineTransport(
            tools: tools,
            runRepo: runRepo,
            graphRepo: graphRepo,
            auth: auth,
          );
        }
        break;
    }
  }

  /// Запустить граф. Возвращает stream событий.
  Stream<GraphRunEvent> run(GraphRunRequest request) => _transport.run(request);

  /// Продолжить выполнение после ввода пользователя.
  Future<void> resumeWithInput(UserInputResponse response) =>
      _transport.respondToInput(response);

  /// Отменить выполнение.
  Future<void> cancel(String runId) => _transport.cancel(runId);

  /// Проверить доступность движка.
  Future<bool> isAvailable() => _transport.isAvailable();

  void dispose() => _transport.dispose();
}

/// Транспорт с автоматическим fallback на local при недоступности remote
class _AutoFallbackTransport implements IEngineTransport {
  final IEngineTransport primary;
  final IEngineTransport fallback;
  bool _primaryAvailable = true;
  DateTime? _lastCheck;
  final Duration _recheckInterval = const Duration(minutes: 1);

  _AutoFallbackTransport({required this.primary, required this.fallback});

  Future<IEngineTransport> _selectTransport() async {
    final now = DateTime.now();
    if (_lastCheck == null || now.difference(_lastCheck!) > _recheckInterval) {
      _lastCheck = now;
      _primaryAvailable = await primary.isAvailable();
      if (_primaryAvailable) {
        print('✅ Remote server available, using HttpEngineTransport');
      } else {
        print('⚠️ Remote server unavailable, falling back to LocalEngineTransport');
      }
    }
    return _primaryAvailable ? primary : fallback;
  }

  @override
  Stream<GraphRunEvent> run(GraphRunRequest request) async* {
    final transport = await _selectTransport();
    yield* transport.run(request);
  }

  @override
  Future<void> respondToInput(UserInputResponse response) async {
    final transport = await _selectTransport();
    await transport.respondToInput(response);
  }

  @override
  Future<void> cancel(String runId) async {
    final transport = await _selectTransport();
    await transport.cancel(runId);
  }

  @override
  Future<bool> isAvailable() async =>
      await primary.isAvailable() || await fallback.isAvailable();

  @override
  void dispose() {
    primary.dispose();
    fallback.dispose();
  }
}
