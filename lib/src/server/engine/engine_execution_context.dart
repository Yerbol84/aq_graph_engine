// Внутренний контекст выполнения для движка.
// Создаётся из GraphRunRequest после загрузки всех данных.

import 'package:aq_schema/aq_schema.dart';

/// Внутренний контекст для выполнения графа в движке.
/// Содержит все загруженные данные, необходимые для выполнения.
class EngineExecutionContext {
  final String runId;
  final String projectId;
  final String projectPath;
  final TypedWorkflowGraph graph;
  final Map<String, dynamic> initialVariables;
  final String? resumeStateJson;
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
