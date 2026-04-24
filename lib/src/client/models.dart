// Модели для клиентской библиотеки Graph Engine

import 'package:aq_schema/aq_schema.dart';

/// Ответ на запрос запуска графа
class GraphRunResponse {
  final String runId;
  final String status;
  final String eventsUrl;
  final String wsUrl;

  GraphRunResponse({
    required this.runId,
    required this.status,
    required this.eventsUrl,
    required this.wsUrl,
  });

  factory GraphRunResponse.fromJson(Map<String, dynamic> json) {
    return GraphRunResponse(
      runId: json['runId'] as String,
      status: json['status'] as String,
      eventsUrl: json['eventsUrl'] as String,
      wsUrl: json['wsUrl'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'runId': runId,
      'status': status,
      'eventsUrl': eventsUrl,
      'wsUrl': wsUrl,
    };
  }
}

/// Ответ на запрос статуса графа
class GraphRunStatusResponse {
  final String runId;
  final GraphRunStatus status;
  final String? currentNodeId;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final String? error;

  GraphRunStatusResponse({
    required this.runId,
    required this.status,
    this.currentNodeId,
    this.startedAt,
    this.completedAt,
    this.error,
  });

  factory GraphRunStatusResponse.fromJson(Map<String, dynamic> json) {
    final statusStr = json['status'] as String;
    GraphRunStatus status;

    try {
      status = GraphRunStatus.values.firstWhere(
        (e) => e.toString().split('.').last == statusStr,
      );
    } catch (e) {
      // Если статус не найден, используем queued по умолчанию
      status = GraphRunStatus.queued;
    }

    return GraphRunStatusResponse(
      runId: json['runId'] as String,
      status: status,
      currentNodeId: json['currentNodeId'] as String?,
      startedAt: json['startedAt'] != null
          ? DateTime.parse(json['startedAt'] as String)
          : null,
      completedAt: json['completedAt'] != null
          ? DateTime.parse(json['completedAt'] as String)
          : null,
      error: json['error'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'runId': runId,
      'status': status.toString().split('.').last,
      if (currentNodeId != null) 'currentNodeId': currentNodeId,
      if (startedAt != null) 'startedAt': startedAt!.toIso8601String(),
      if (completedAt != null) 'completedAt': completedAt!.toIso8601String(),
      if (error != null) 'error': error,
    };
  }
}

/// Запрос на возобновление приостановленного графа
class GraphResumeRequest {
  final String runId;
  final Map<String, dynamic> userInput;

  GraphResumeRequest({
    required this.runId,
    required this.userInput,
  });

  Map<String, dynamic> toJson() {
    return {
      'runId': runId,
      'userInput': userInput,
    };
  }
}
