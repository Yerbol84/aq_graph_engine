// ============================================================================
// DEPRECATED! РУДИМЕНТ!
// Эта фабрика нужна только для конвертации старых enum-based узлов
// TODO: Удалить после полного перехода на IWorkflowNode
// Новый код должен работать напрямую с IWorkflowNode без конвертации
// ============================================================================

// Фабрика для создания узлов WorkflowGraph из JSON

import 'package:aq_schema/graph/nodes/base/i_workflow_node.dart';
import 'package:aq_schema/graph/nodes/workflow/automatic/llm_action_node.dart';
import 'package:aq_schema/graph/nodes/workflow/automatic/file_read_node.dart';
import 'package:aq_schema/graph/nodes/workflow/automatic/file_write_node.dart';
import 'package:aq_schema/graph/nodes/workflow/automatic/git_commit_node.dart';
import 'package:aq_schema/graph/nodes/workflow/interactive/user_input_node.dart';
import 'package:aq_schema/graph/nodes/workflow/interactive/manual_review_node.dart';
import 'package:aq_schema/graph/nodes/workflow/interactive/file_upload_node.dart';
import 'package:aq_schema/graph/nodes/workflow/interactive/co_creation_chat_node.dart';
import 'package:aq_schema/graph/nodes/workflow/composite/sub_graph_node.dart';
import 'package:aq_schema/graph/nodes/workflow/composite/run_instruction_node.dart';

/// Фабрика для создания узлов WorkflowGraph из JSON
@Deprecated('РУДИМЕНТ! Удалить после миграции на IWorkflowNode')
class WorkflowNodeFactory {
  /// Создать узел из JSON
  ///
  /// [json] должен содержать поле 'type' с типом узла
  static IWorkflowNode fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String?;
    if (type == null || type.isEmpty) {
      throw Exception('WorkflowNodeFactory: missing "type" field in JSON');
    }

    switch (type) {
      // Automatic nodes
      case 'llmAction':
        return LlmActionNode.fromJson(json);
      case 'fileRead':
        return FileReadNode.fromJson(json);
      case 'fileWrite':
        return FileWriteNode.fromJson(json);
      case 'gitCommit':
        return GitCommitNode.fromJson(json);

      // Interactive nodes
      case 'userInput':
        return UserInputNode.fromJson(json);
      case 'manualReview':
        return ManualReviewNode.fromJson(json);
      case 'fileUpload':
        return FileUploadNode.fromJson(json);
      case 'coCreationChat':
        return CoCreationChatNode.fromJson(json);

      // Composite nodes
      case 'subGraph':
        return SubGraphNode.fromJson(json);
      case 'runInstruction':
        return RunInstructionNode.fromJson(json);

      default:
        throw Exception('WorkflowNodeFactory: unknown node type "$type"');
    }
  }

  /// Получить список всех поддерживаемых типов узлов
  static List<String> getSupportedTypes() => [
        'llmAction',
        'fileRead',
        'fileWrite',
        'gitCommit',
        'userInput',
        'manualReview',
        'fileUpload',
        'coCreationChat',
        'subGraph',
        'runInstruction',
      ];

  /// Проверить, поддерживается ли тип узла
  static bool isSupported(String type) => getSupportedTypes().contains(type);
}
