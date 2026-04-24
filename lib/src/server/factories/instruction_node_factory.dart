// Фабрика для создания узлов InstructionGraph из JSON

import 'package:aq_schema/graph/nodes/base/i_instruction_node.dart';
import 'package:aq_schema/graph/nodes/instruction/tool_call_node.dart';
import 'package:aq_schema/graph/nodes/instruction/llm_query_node.dart';
import 'package:aq_schema/graph/nodes/instruction/condition_node.dart';
import 'package:aq_schema/graph/nodes/instruction/transform_node.dart';

/// Фабрика для создания узлов InstructionGraph из JSON
class InstructionNodeFactory {
  /// Создать узел из JSON
  ///
  /// [json] должен содержать поле 'type' с типом узла
  static IInstructionNode fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String?;
    if (type == null || type.isEmpty) {
      throw Exception('InstructionNodeFactory: missing "type" field in JSON');
    }

    switch (type) {
      case 'toolCall':
        return ToolCallNode.fromJson(json);
      case 'llmQuery':
        return LlmQueryNode.fromJson(json);
      case 'condition':
        return ConditionNode.fromJson(json);
      case 'transform':
        return TransformNode.fromJson(json);

      default:
        throw Exception('InstructionNodeFactory: unknown node type "$type"');
    }
  }

  /// Получить список всех поддерживаемых типов узлов
  static List<String> getSupportedTypes() => [
        'toolCall',
        'llmQuery',
        'condition',
        'transform',
      ];

  /// Проверить, поддерживается ли тип узла
  static bool isSupported(String type) => getSupportedTypes().contains(type);
}
