// pkgs/aq_graph_engine/lib/src/client/http_graph_engine_client.dart
//
// Реализация IGraphEngineClient через HTTP + SSE.
// Адаптирует GraphEngineClient к протоколу IGraphEngineClient из aq_schema.

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:aq_schema/aq_schema.dart';

import 'graph_engine_client.dart';

/// HTTP реализация IGraphEngineClient.
///
/// Подключается к aq_graph_worker по HTTP.
/// Запускает графы через POST /api/execute-graph,
/// получает события через SSE stream.
///
/// Использование:
/// ```dart
/// IGraphEngineClient.init(HttpGraphEngineClient(
///   baseUrl: 'http://localhost:8092',
/// ));
/// ```
class HttpGraphEngineClient implements IGraphEngineClient {
  final String baseUrl;
  final Duration timeout;
  final Map<String, String>? defaultHeaders;

  late final GraphEngineClient _client;

  HttpGraphEngineClient({
    required this.baseUrl,
    this.timeout = const Duration(seconds: 30),
    this.defaultHeaders,
  }) {
    _client = GraphEngineClient(
      baseUrl: baseUrl,
      timeout: timeout,
      defaultHeaders: defaultHeaders,
    );
  }

  @override
  Stream<GraphRunEvent> run(GraphRunRequest request) {
    // WorkerHttpServer принимает POST /api/execute-graph и возвращает SSE
    return _runViaSse(request);
  }

  Stream<GraphRunEvent> _runViaSse(GraphRunRequest request) async* {
    final client = http.Client();
    try {
      final uri = Uri.parse('$baseUrl/api/execute-graph');
      final httpRequest = http.Request('POST', uri);
      httpRequest.headers['Content-Type'] = 'application/json';
      httpRequest.headers['Accept'] = 'text/event-stream';
      if (defaultHeaders != null) {
        httpRequest.headers.addAll(defaultHeaders!);
      }
      httpRequest.body = jsonEncode({
        'runId': request.runId,
        'blueprintId': request.blueprintId,
        'projectId': request.projectId,
        'projectPath': request.projectPath,
        if (request.initialVariables.isNotEmpty)
          'initialVariables': request.initialVariables,
      });

      final response = await client.send(httpRequest);

      if (response.statusCode != 200) {
        final body = await response.stream.bytesToString();
        yield GraphRunEvent.error(
          runId: request.runId,
          message: 'Server error ${response.statusCode}: $body',
        );
        return;
      }

      // Читаем SSE stream
      final buffer = StringBuffer();
      await for (final chunk in response.stream.transform(utf8.decoder)) {
        buffer.write(chunk);
        final content = buffer.toString();
        final lines = content.split('\n');

        // Оставляем последнюю неполную строку в буфере
        buffer.clear();
        if (!content.endsWith('\n')) {
          buffer.write(lines.removeLast());
        }

        for (final line in lines) {
          if (line.startsWith('data: ')) {
            final data = line.substring(6).trim();
            if (data.isEmpty) continue;

            try {
              final json = jsonDecode(data) as Map<String, dynamic>;
              final typeStr = json['type'] as String?;
              final type = GraphRunEventType.values.firstWhere(
                (e) => e.name == typeStr,
                orElse: () => GraphRunEventType.log,
              );

              final event = GraphRunEvent(
                runId: json['runId'] as String? ?? request.runId,
                type: type,
                timestamp: json['timestamp'] != null
                    ? DateTime.parse(json['timestamp'] as String)
                    : DateTime.now(),
                message: json['message'] as String?,
                logType: json['logType'] as String?,
                branch: json['branch'] as String?,
                depth: json['depth'] as int? ?? 0,
                newStatus: json['newStatus'] != null
                    ? GraphRunStatus.fromJson(json['newStatus'] as String)
                    : null,
                inputRequiredPayload:
                    json['inputRequiredPayload'] as Map<String, dynamic>?,
                errorMessage: json['errorMessage'] as String?,
              );

              yield event;

              // Завершаем при финальных событиях
              if (event.type == GraphRunEventType.completed ||
                  event.type == GraphRunEventType.error) {
                return;
              }
            } catch (e) {
              // Не удалось распарсить — пропускаем
            }
          }
        }
      }
    } catch (e) {
      yield GraphRunEvent.error(
        runId: request.runId,
        message: 'Connection error: $e',
      );
    } finally {
      client.close();
    }
  }

  @override
  Future<void> resume(UserInputResponse response) async {
    await _client.resumeRun(response.runId, response.values);
  }

  @override
  Future<void> cancel(String runId) async {
    await _client.cancelRun(runId);
  }

  @override
  Future<Map<String, dynamic>?> getRun(String runId) async {
    final client = http.Client();
    try {
      final uri = Uri.parse('$baseUrl/api/runs/$runId');
      final response = await client.get(uri).timeout(timeout);
      if (response.statusCode == 404) return null;
      if (response.statusCode != 200) return null;
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  @override
  Future<bool> isAvailable() async {
    final client = http.Client();
    try {
      final response = await client
          .get(Uri.parse('$baseUrl/health'))
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    } finally {
      client.close();
    }
  }

  @override
  void dispose() => _client.close();
}
