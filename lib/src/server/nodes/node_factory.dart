// Фабрика для создания узлов из JSON

import 'i_workflow_node.dart';
import 'workflow/run_instruction_node.dart';

/// Фабрика для создания IWorkflowNode из JSON
///
/// Поддерживает только новую архитектуру:
/// - runInstruction: универсальный узел для запуска инструкций
/// - userInput: интерактивный узел (TODO: Day 2)
/// - manualReview: интерактивный узел (TODO: Day 2)
/// - subGraph: композитный узел (TODO: Day 3)
class WorkflowNodeFactory {
  /// Создать узел из JSON
  ///
  /// Формат: { "id": "...", "type": "runInstruction", "config": {...} }
  static IWorkflowNode fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String?;

    if (type == null) {
      throw Exception('Node type is required');
    }

    switch (type) {
      case 'runInstruction':
        return RunInstructionNode.fromJson(json);

      // TODO: Day 2 - Интерактивные узлы
      // case 'userInput': return UserInputNode.fromJson(json);
      // case 'manualReview': return ManualReviewNode.fromJson(json);

      // TODO: Day 3 - Композитные узлы
      // case 'subGraph': return SubGraphNode.fromJson(json);

      default:
        throw Exception('Unknown node type: $type');
    }
  }

  /// Список поддерживаемых типов узлов
  static const supportedTypes = [
    'runInstruction',
    // TODO: добавить остальные после реализации
  ];
}
