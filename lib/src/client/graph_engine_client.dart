// Клиентская библиотека для работы с Graph Engine Server

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:aq_schema/aq_schema.dart';
import 'models.dart';
import 'exceptions.dart';
import 'graph_run_stream.dart';

final _log = Logger('GraphEngineClient');

/// Клиент для работы с Graph Engine Server
class GraphEngineClient {
  final String baseUrl;
  final http.Client _httpClient;
  final Duration timeout;
  final Map<String, String>? defaultHeaders;

  GraphEngineClient({
    required this.baseUrl,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 30),
    this.defaultHeaders,
  }) : _httpClient = httpClient ?? http.Client();

  /// Запустить граф
  Future<GraphRunResponse> startRun(GraphRunRequest request) async {
    try {
      final url = Uri.parse('$baseUrl/api/v1/runs');
      final headers = {
        'Content-Type': 'application/json',
        ...?defaultHeaders,
      };

      _log.info('Starting run: ${request.blueprintId}');

      // HTTP API ожидает упрощённый формат {projectId, workflowName, payload}
      // blueprintId используется как workflowName (может быть ID или имя графа)
      final httpBody = {
        'runId': request.runId,
        'projectId': request.projectId,
        'workflowName': request.blueprintId,
        'payload': request.initialVariables,
      };

      final response = await _httpClient
          .post(
            url,
            headers: headers,
            body: jsonEncode(httpBody),
          )
          .timeout(timeout);

      _checkResponse(response);

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final result = GraphRunResponse.fromJson(data);

      _log.info('Run started: ${result.runId}');

      return result;
    } on TimeoutException {
      throw GraphEngineTimeoutException(
        'Request timeout after ${timeout.inSeconds}s',
      );
    } on http.ClientException catch (e) {
      throw GraphEngineConnectionException(
        'Connection failed: $e',
      );
    } catch (e) {
      if (e is GraphEngineException) rethrow;
      throw GraphEngineException('Failed to start run: $e');
    }
  }

  /// Получить статус запуска
  Future<GraphRunStatusResponse> getStatus(String runId) async {
    try {
      final url = Uri.parse('$baseUrl/api/v1/runs/$runId/status');
      final headers = {
        'Content-Type': 'application/json',
        ...?defaultHeaders,
      };

      final response = await _httpClient
          .get(url, headers: headers)
          .timeout(timeout);

      _checkResponse(response);

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return GraphRunStatusResponse.fromJson(data);
    } on TimeoutException {
      throw GraphEngineTimeoutException(
        'Request timeout after ${timeout.inSeconds}s',
      );
    } on http.ClientException catch (e) {
      throw GraphEngineConnectionException(
        'Connection failed: $e',
      );
    } catch (e) {
      if (e is GraphEngineException) rethrow;
      throw GraphEngineException('Failed to get status: $e');
    }
  }

  /// Отменить запуск
  Future<void> cancelRun(String runId) async {
    try {
      final url = Uri.parse('$baseUrl/api/v1/runs/$runId');
      final headers = {
        'Content-Type': 'application/json',
        ...?defaultHeaders,
      };

      _log.info('Cancelling run: $runId');

      final response = await _httpClient
          .delete(url, headers: headers)
          .timeout(timeout);

      _checkResponse(response);

      _log.info('Run cancelled: $runId');
    } on TimeoutException {
      throw GraphEngineTimeoutException(
        'Request timeout after ${timeout.inSeconds}s',
      );
    } on http.ClientException catch (e) {
      throw GraphEngineConnectionException(
        'Connection failed: $e',
      );
    } catch (e) {
      if (e is GraphEngineException) rethrow;
      throw GraphEngineException('Failed to cancel run: $e');
    }
  }

  /// Возобновить приостановленный запуск
  Future<void> resumeRun(
    String runId,
    Map<String, dynamic> input,
  ) async {
    try {
      final url = Uri.parse('$baseUrl/api/v1/runs/$runId/resume');
      final headers = {
        'Content-Type': 'application/json',
        ...?defaultHeaders,
      };

      _log.info('Resuming run: $runId');

      final response = await _httpClient
          .post(
            url,
            headers: headers,
            body: jsonEncode({'input': input}),
          )
          .timeout(timeout);

      _checkResponse(response);

      _log.info('Run resumed: $runId');
    } on TimeoutException {
      throw GraphEngineTimeoutException(
        'Request timeout after ${timeout.inSeconds}s',
      );
    } on http.ClientException catch (e) {
      throw GraphEngineConnectionException(
        'Connection failed: $e',
      );
    } catch (e) {
      if (e is GraphEngineException) rethrow;
      throw GraphEngineException('Failed to resume run: $e');
    }
  }

  /// Подключиться к событиям запуска через WebSocket
  GraphRunStream connectToRun(String runId, {String? token, String? apiKey}) {
    final wsUrl = baseUrl.replaceFirst('http://', 'ws://').replaceFirst('https://', 'wss://');

    // Добавляем auth параметры в URL
    var url = '$wsUrl/api/v1/runs/$runId/ws';
    final queryParams = <String>[];

    if (token != null) {
      queryParams.add('token=$token');
    }
    if (apiKey != null) {
      queryParams.add('apiKey=$apiKey');
    }

    if (queryParams.isNotEmpty) {
      url += '?${queryParams.join('&')}';
    }

    return GraphRunStream(
      runId: runId,
      wsUrl: url,
    );
  }

  /// Запустить граф и получить стрим событий
  ///
  /// Комбинирует startRun() + connectToRun() для удобства
  Stream<GraphRunEvent> run(GraphRunRequest request) async* {
    // 1. Запустить граф
    final response = await startRun(request);

    // 2. Подключиться к стриму событий
    final stream = connectToRun(response.runId);

    // 3. Проксировать события
    await for (final event in stream.events) {
      yield event;
    }
  }

  /// Возобновить приостановленный граф и получить стрим событий
  Stream<GraphRunEvent> resume(GraphResumeRequest request) async* {
    // 1. Возобновить граф
    await resumeRun(request.runId, request.userInput);

    // 2. Подключиться к стриму событий
    final stream = connectToRun(request.runId);

    // 3. Проксировать события
    await for (final event in stream.events) {
      yield event;
    }
  }

  /// Проверить ответ сервера и выбросить исключение при ошибке
  void _checkResponse(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }

    String message = 'HTTP ${response.statusCode}';
    String? code;
    dynamic details;

    try {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      message = data['error'] as String? ?? message;
      code = data['code'] as String?;
      details = data['details'];
    } catch (_) {
      // Не удалось распарсить JSON, используем тело как есть
      message = response.body.isNotEmpty ? response.body : message;
    }

    switch (response.statusCode) {
      case 400:
        throw GraphEngineValidationException(
          message,
          statusCode: response.statusCode,
          code: code,
          details: details,
        );
      case 401:
        throw GraphEngineUnauthorizedException(
          message,
          statusCode: response.statusCode,
          code: code,
          details: details,
        );
      case 403:
        throw GraphEngineForbiddenException(
          message,
          statusCode: response.statusCode,
          code: code,
          details: details,
        );
      case 404:
        throw GraphEngineNotFoundException(
          message,
          statusCode: response.statusCode,
          code: code,
          details: details,
        );
      case 408:
        throw GraphEngineTimeoutException(
          message,
          statusCode: response.statusCode,
          code: code,
          details: details,
        );
      case >= 500:
        throw GraphEngineServerException(
          message,
          statusCode: response.statusCode,
          code: code,
          details: details,
        );
      default:
        throw GraphEngineException(
          message,
          statusCode: response.statusCode,
          code: code,
          details: details,
        );
    }
  }

  /// Закрыть клиент и освободить ресурсы
  void close() {
    _httpClient.close();
  }
}
