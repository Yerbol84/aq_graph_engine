// Внутренний контекст выполнения для движка.
// Создаётся из GraphRunRequest после загрузки всех данных.

import 'package:aq_schema/aq_schema.dart';

/// Внутренний контекст для выполнения графа в движке.
/// Содержит все загруженные данные, необходимые для выполнения.
class EngineExecutionContext {
  /// ID запуска
  final String runId;

  /// ID проекта
  final String projectId;

  /// Путь к проекту на диске
  final String projectPath;

  /// Загруженный граф для выполнения
  final WorkflowGraph graph;

  /// Начальные переменные
  final Map<String, dynamic> initialVariables;

  /// Сохранённое состояние для Resume
  final String? resumeStateJson;

  /// ID узла для Resume
  final String? resumeFromNodeId;

  const EngineExecutionContext({
    required this.runId,
    required this.projectId,
    required this.projectPath,
    required this.graph,
    this.initialVariables = const {},
    this.resumeStateJson,
    this.resumeFromNodeId,
  });

  bool get isResume => resumeStateJson != null;
}
