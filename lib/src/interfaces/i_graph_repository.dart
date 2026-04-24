// Абстракция хранилища графов.
// Движок запрашивает граф по ID — откуда он берётся (SQLite, API, файл), его не касается.

import 'package:aq_schema/aq_schema.dart';

abstract class IGraphRepository {
  /// Загрузить граф по ID blueprint.
  /// Возвращает WorkflowGraph, InstructionGraph или PromptGraph.
  /// Возвращает null если граф не найден.
  Future<$Graph?> loadGraph(String blueprintId);
}
