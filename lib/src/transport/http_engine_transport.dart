// HTTP транспорт для удалённого выполнения графов (клиентская сторона)
//
// Отправляет GraphRunRequest по HTTP к graph_engine_server и получает события через SSE.
// Включает retry логику и circuit breaker для production-ready работы.

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../shared/logger.dart';
import 'package:aq_schema/aq_schema.dart';

/// HTTP транспорт для удалённого выполнения графов
class HttpEngineTransport implements IEngineTransport {
  final String serverUrl;
  final AQAuthClient? auth;
  final http.Client? httpClient;
  final Duration timeout;
  final int maxRetries;
  final Duration initialRetryDelay;

  // Circuit breaker state
  CircuitBreakerState _circuitState = CircuitBreakerState.closed;
  int _consecutiveFailures = 0;
  DateTime? _circuitOpenedAt;
  final int _failureThreshold = 5;
  final Duration _circuitOpenDuration = const Duration(seconds: 30);

  // Активные подключения
  final Map<String, StreamController<GraphRunEvent>> _controllers = {};
  final Map<String, http.Client> _sseClients = {};

  HttpEngineTransport({
    required this.serverUrl,
    this.auth,
    this.httpClient,
    this.timeout = const Duration(seconds: 30),
    this.maxRetries = 3,
    this.initialRetryDelay = const Duration(seconds: 1),
  });

  @override
  Stream<GraphRunEvent> run(GraphRunRequest request) {
    final controller = StreamController<GraphRunEvent>.broadcast();
    _controllers[request.runId] = controller;

    _executeWithRetry(request, controller).whenComplete(() {
      _controllers.remove(request.runId);
      if (!controller.isClosed) controller.close();
    });

    return controller.stream;
  }

  Future<void> _executeWithRetry(
    GraphRunRequest request,
    StreamController<GraphRunEvent> controller,
  ) async {
    var attempt = 0;
    var delay = initialRetryDelay;

    while (attempt <= maxRetries) {
      try {
        // Проверяем circuit breaker
        if (!_canAttempt()) {
          controller.add(GraphRunEvent.error(
            runId: request.runId,
            message: 'Circuit breaker is open - server unavailable',
          ));
          return;
        }

        await _execute(request, controller);
        _onSuccess();
        return;
      } catch (e) {
        _onFailure();
        attempt++;

        if (attempt > maxRetries) {
          controller.add(GraphRunEvent.error(
            runId: request.runId,
            message: 'Failed after $maxRetries retries: $e',
          ));
          return;
        }

        graphEngineClientLogger.warning('HttpEngineTransport: Attempt $attempt failed: $e');
        graphEngineClientLogger.fine('Retrying in ${delay.inSeconds}s...');

        await Future.delayed(delay);
        delay *= 2; // Exponential backoff
      }
    }
  }

  Future<void> _execute(
    GraphRunRequest request,
    StreamController<GraphRunEvent> controller,
  ) async {
    final client = httpClient ?? http.Client();

    try {
      // 1. Получаем токен если auth доступен
      String? authToken;
      if (auth != null) {
        final token = await auth!.currentToken;
        if (token == null) {
          throw Exception('No valid auth token available');
        }
        authToken = token.rawJwt;
      }

      // 2. Отправляем POST запрос для запуска графа
      final headers = {
        'Content-Type': 'application/json',
        if (authToken != null) 'Authorization': 'Bearer $authToken',
      };

      final response = await client
          .post(
            Uri.parse('$serverUrl/api/v1/runs'),
            headers: headers,
            body: jsonEncode(request.toJson()),
          )
          .timeout(timeout);

      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception(
          'Server returned ${response.statusCode}: ${response.body}',
        );
      }

      // 3. Подключаемся к SSE для получения событий
      await _subscribeToEvents(request.runId, controller, authToken);
    } finally {
      if (httpClient == null) {
        client.close();
      }
    }
  }

  Future<void> _subscribeToEvents(
    String runId,
    StreamController<GraphRunEvent> controller,
    String? authToken,
  ) async {
    final sseClient = http.Client();
    _sseClients[runId] = sseClient;

    try {
      final uri = Uri.parse('$serverUrl/api/v1/runs/$runId/events');
      final request = http.Request('GET', uri);

      if (authToken != null) {
        request.headers['Authorization'] = 'Bearer $authToken';
      }
      request.headers['Accept'] = 'text/event-stream';
      request.headers['Cache-Control'] = 'no-cache';

      final response = await sseClient.send(request);

      if (response.statusCode != 200) {
        throw Exception('SSE connection failed: ${response.statusCode}');
      }

      // Читаем SSE stream
      await for (final chunk in response.stream.transform(utf8.decoder)) {
        final lines = chunk.split('\n');

        for (final line in lines) {
          if (line.startsWith('data: ')) {
            final data = line.substring(6);
            if (data.trim().isEmpty) continue;

            try {
              final json = jsonDecode(data) as Map<String, dynamic>;

              // Парсим событие вручную
              final typeStr = json['type'] as String;
              final type = GraphRunEventType.values.firstWhere(
                (e) => e.name == typeStr,
                orElse: () => GraphRunEventType.log,
              );

              final event = GraphRunEvent(
                runId: json['runId'] as String,
                type: type,
                timestamp: DateTime.parse(json['timestamp'] as String),
                message: json['message'] as String?,
                logType: json['logType'] as String?,
                branch: json['branch'] as String?,
                depth: json['depth'] as int? ?? 0,
                newStatus: json['newStatus'] != null
                    ? GraphRunStatus.fromJson(json['newStatus'] as String)
                    : null,
                inputRequiredPayload: json['inputRequiredPayload'] as Map<String, dynamic>?,
                errorMessage: json['errorMessage'] as String?,
              );

              if (!controller.isClosed) {
                controller.add(event);
              }

              // Завершаем stream при финальных событиях
              if (event.type == GraphRunEventType.completed ||
                  event.type == GraphRunEventType.error) {
                return;
              }
            } catch (e) {
              graphEngineClientLogger.warning('Failed to parse SSE event: $e');
            }
          }
        }
      }
    } finally {
      _sseClients.remove(runId);
      sseClient.close();
    }
  }

  @override
  Future<void> respondToInput(UserInputResponse response) async {
    final client = httpClient ?? http.Client();

    try {
      String? authToken;
      if (auth != null) {
        final token = await auth!.currentToken;
        authToken = token?.rawJwt;
      }

      final headers = {
        'Content-Type': 'application/json',
        if (authToken != null) 'Authorization': 'Bearer $authToken',
      };

      final httpResponse = await client
          .post(
            Uri.parse('$serverUrl/api/v1/runs/${response.runId}/resume'),
            headers: headers,
            body: jsonEncode(response.toJson()),
          )
          .timeout(timeout);

      if (httpResponse.statusCode != 200) {
        throw Exception(
          'Resume failed: ${httpResponse.statusCode} ${httpResponse.body}',
        );
      }
    } finally {
      if (httpClient == null) {
        client.close();
      }
    }
  }

  @override
  Future<void> cancel(String runId) async {
    final client = httpClient ?? http.Client();

    try {
      String? authToken;
      if (auth != null) {
        final token = await auth!.currentToken;
        authToken = token?.rawJwt;
      }

      final headers = {
        if (authToken != null) 'Authorization': 'Bearer $authToken',
      };

      final response = await client
          .delete(
            Uri.parse('$serverUrl/api/v1/runs/$runId'),
            headers: headers,
          )
          .timeout(timeout);

      if (response.statusCode != 200) {
        throw Exception('Cancel failed: ${response.statusCode}');
      }

      // Закрываем SSE подключение
      final sseClient = _sseClients[runId];
      if (sseClient != null) {
        sseClient.close();
        _sseClients.remove(runId);
      }

      // Закрываем controller
      final controller = _controllers[runId];
      if (controller != null && !controller.isClosed) {
        controller.add(GraphRunEvent.statusChanged(
          runId: runId,
          status: GraphRunStatus.cancelled,
        ));
        await controller.close();
      }
    } finally {
      if (httpClient == null) {
        client.close();
      }
    }
  }

  @override
  Future<bool> isAvailable() async {
    if (!_canAttempt()) {
      return false;
    }

    final client = httpClient ?? http.Client();

    try {
      final response = await client
          .get(Uri.parse('$serverUrl/health'))
          .timeout(const Duration(seconds: 5));

      return response.statusCode == 200;
    } catch (e) {
      return false;
    } finally {
      if (httpClient == null) {
        client.close();
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      if (!controller.isClosed) controller.close();
    }
    _controllers.clear();

    for (final client in _sseClients.values) {
      client.close();
    }
    _sseClients.clear();
  }

  // ── Circuit Breaker ──────────────────────────────────────────────────────

  bool _canAttempt() {
    if (_circuitState == CircuitBreakerState.closed) {
      return true;
    }

    if (_circuitState == CircuitBreakerState.open) {
      final now = DateTime.now();
      if (_circuitOpenedAt != null &&
          now.difference(_circuitOpenedAt!) > _circuitOpenDuration) {
        graphEngineClientLogger.info('Circuit breaker: transitioning to half-open');
        _circuitState = CircuitBreakerState.halfOpen;
        return true;
      }
      return false;
    }

    // half-open: пропускаем одну попытку
    return true;
  }

  void _onSuccess() {
    if (_circuitState == CircuitBreakerState.halfOpen) {
      graphEngineClientLogger.info('Circuit breaker: closing after successful request');
      _circuitState = CircuitBreakerState.closed;
    }
    _consecutiveFailures = 0;
  }

  void _onFailure() {
    _consecutiveFailures++;

    if (_consecutiveFailures >= _failureThreshold) {
      if (_circuitState != CircuitBreakerState.open) {
        graphEngineClientLogger.warning('Circuit breaker: opening after $_consecutiveFailures failures');
        _circuitState = CircuitBreakerState.open;
        _circuitOpenedAt = DateTime.now();
      }
    }
  }
}

/// Состояние circuit breaker
enum CircuitBreakerState {
  closed,   // Нормальная работа
  open,     // Блокируем запросы
  halfOpen, // Пробуем восстановиться
}
