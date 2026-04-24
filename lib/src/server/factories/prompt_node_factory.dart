// Фабрика для создания узлов PromptGraph из JSON

import 'package:aq_schema/graph/nodes/base/i_prompt_node.dart';
import 'package:aq_schema/graph/nodes/prompt/text_block_node.dart';
import 'package:aq_schema/graph/nodes/prompt/variable_insert_node.dart';
import 'package:aq_schema/graph/nodes/prompt/conditional_block_node.dart';

/// Фабрика для создания узлов PromptGraph из JSON
class PromptNodeFactory {
  /// Создать узел из JSON
  ///
  /// [json] должен содержать поле 'type' с типом узла
  static IPromptNode fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String?;
    if (type == null || type.isEmpty) {
      throw Exception('PromptNodeFactory: missing "type" field in JSON');
    }

    switch (type) {
      case 'textBlock':
        return TextBlockNode.fromJson(json);
      case 'variableInsert':
        return VariableInsertNode.fromJson(json);
      case 'conditionalBlock':
        return ConditionalBlockNode.fromJson(json);

      default:
        throw Exception('PromptNodeFactory: unknown node type "$type"');
    }
  }

  /// Получить список всех поддерживаемых типов узлов
  static List<String> getSupportedTypes() => [
        'textBlock',
        'variableInsert',
        'conditionalBlock',
      ];

  /// Проверить, поддерживается ли тип узла
  static bool isSupported(String type) => getSupportedTypes().contains(type);
}
