// Stream событий от запущенного графа через WebSocket

import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:aq_schema/aq_schema.dart';
import '../shared/logger.dart';
import 'exceptions.dart';

/// Stream событий от запущенного графа
class GraphRunStream {
  final String runId;
  final String wsUrl;
  final Duration connectionTimeout;
  final bool enableKeepAlive;
  final Duration keepAliveInterval;

  WebSocketChannel? _channel;
  StreamController<GraphRunEvent>? _controller;
  StreamSubscription? _subscription;
  Timer? _keepAliveTimer;
  bool _isConnected = false;

  GraphRunStream({
    required this.runId,
    required this.wsUrl,
    this.connectionTimeout = const Duration(seconds: 10),
    this.enableKeepAlive = true,
    this.keepAliveInterval = const Duration(seconds: 30),
  });

  /// Stream событий
  Stream<GraphRunEvent> get events {
    if (_controller == null) {
      _controller = StreamController<GraphRunEvent>(
        onListen: _onListen,
        onCancel: _onCancel,
      );
    }
    return _controller!.stream;
  }

  /// Подключён ли к WebSocket
  bool get isConnected => _isConnected;

  /// Подключиться к WebSocket
  Future<void> connect() async {
    if (_isConnected) {
      return;
    }

    try {
      graphEngineClientLogger.info('Connecting to WebSocket: $wsUrl');

      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _isConnected = true;

      // Слушаем сообщения
      _subscription = _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
        cancelOnError: false,
      );

      // Запускаем keep-alive если включён
      if (enableKeepAlive) {
        _startKeepAlive();
      }

      graphEngineClientLogger.info('Connected to WebSocket');
    } catch (e) {
      _isConnected = false;
      throw GraphEngineConnectionException(
        'Failed to connect to WebSocket: $e',
      );
    }
  }

  /// Отключиться от WebSocket
  Future<void> disconnect() async {
    if (!_isConnected) {
      return;
    }

    graphEngineClientLogger.info('Disconnecting from WebSocket');

    // Останавливаем keep-alive
    _stopKeepAlive();

    await _subscription?.cancel();
    await _channel?.sink.close();

    _subscription = null;
    _channel = null;
    _isConnected = false;

    graphEngineClientLogger.info('Disconnected from WebSocket');
  }

  /// Отправить ping
  Future<void> ping() async {
    if (!_isConnected) {
      throw GraphEngineConnectionException('Not connected to WebSocket');
    }

    _channel!.sink.add(jsonEncode({'type': 'ping'}));
  }

  /// Запустить keep-alive таймер
  void _startKeepAlive() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer.periodic(keepAliveInterval, (_) {
      if (_isConnected) {
        try {
          ping();
        } catch (e) {
          graphEngineClientLogger.warning('Keep-alive ping failed: $e');
        }
      }
    });
    graphEngineClientLogger.fine('Keep-alive started (interval: ${keepAliveInterval.inSeconds}s)');
  }

  /// Остановить keep-alive таймер
  void _stopKeepAlive() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
    if (enableKeepAlive) {
      graphEngineClientLogger.fine('Keep-alive stopped');
    }
  }

  void _onListen() {
    // Автоматически подключаемся при первом listen
    if (!_isConnected) {
      connect();
    }
  }

  Future<void> _onCancel() async {
    // Отключаемся при отмене подписки
    await disconnect();
    await _controller?.close();
    _controller = null;
  }

  void _onMessage(dynamic message) {
    try {
      final data = jsonDecode(message as String) as Map<String, dynamic>;
      final type = data['type'] as String?;

      switch (type) {
        case 'welcome':
          graphEngineClientLogger.fine('Welcome: ${data['message']}');
          break;

        case 'pong':
          graphEngineClientLogger.finest('Pong received');
          break;

        case 'ack':
          graphEngineClientLogger.fine('Ack: ${data['action']}');
          break;

        case 'error':
          final error = GraphEngineException(
            data['message'] as String? ?? 'Unknown error',
            code: data['code'] as String?,
          );
          _controller?.addError(error);
          break;

        default:
          // Пытаемся распарсить как GraphRunEvent
          try {
            final event = GraphRunEvent(
              runId: data['runId'] as String,
              type: GraphRunEventType.values.firstWhere(
                (e) => e.toString().split('.').last == data['type'],
              ),
              timestamp: DateTime.parse(data['timestamp'] as String),
              message: data['message'] as String?,
              logType: data['logType'] as String?,
              branch: data['branch'] as String?,
              depth: data['depth'] as int? ?? 0,
              newStatus: data['newStatus'] != null
                  ? GraphRunStatus.values.firstWhere(
                      (e) => e.toString().split('.').last == data['newStatus'],
                    )
                  : null,
              inputRequiredPayload: data['inputRequiredPayload'] as Map<String, dynamic>?,
              errorMessage: data['errorMessage'] as String?,
            );
            _controller?.add(event);
          } catch (e) {
            graphEngineClientLogger.warning('Failed to parse event: $e');
          }
      }
    } catch (e) {
      graphEngineClientLogger.warning('Failed to parse message: $e');
      _controller?.addError(
        GraphEngineException('Failed to parse message: $e'),
      );
    }
  }

  void _onError(dynamic error) {
    graphEngineClientLogger.severe('WebSocket error: $error');
    _controller?.addError(
      GraphEngineConnectionException('WebSocket error: $error'),
    );
  }

  void _onDone() {
    graphEngineClientLogger.info('WebSocket connection closed');
    _isConnected = false;
    _controller?.close();
  }
}
