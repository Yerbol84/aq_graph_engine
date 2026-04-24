// Реестр типов узлов для полиморфной десериализации
// Заменяет WorkflowNodeFactory на расширяемую систему регистрации

import 'package:aq_schema/graph/nodes/base/i_workflow_node.dart';
import 'package:aq_schema/graph/nodes/base/i_instruction_node.dart';
import 'package:aq_schema/graph/nodes/base/i_prompt_node.dart';
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
import 'package:aq_schema/graph/nodes/instruction/condition_node.dart';
import 'package:aq_schema/graph/nodes/instruction/llm_query_node.dart';
import 'package:aq_schema/graph/nodes/instruction/tool_call_node.dart';
import 'package:aq_schema/graph/nodes/instruction/transform_node.dart';
import 'package:aq_schema/graph/nodes/prompt/text_block_node.dart';
import 'package:aq_schema/graph/nodes/prompt/conditional_block_node.dart';
import 'package:aq_schema/graph/nodes/prompt/variable_insert_node.dart';

/// Исключение при попытке создать узел неизвестного типа
class UnknownNodeTypeException implements Exception {
  final String typeKey;
  final String graphKind;

  UnknownNodeTypeException(this.typeKey, this.graphKind);

  @override
  String toString() =>
      'UnknownNodeTypeException: тип "$typeKey" не зарегистрирован в реестре $graphKind узлов. '
      'Проверьте правильность типа или зарегистрируйте его через NodeTypeRegistry.register${graphKind.substring(0, 1).toUpperCase()}${graphKind.substring(1)}()';
}

/// Реестр типов узлов с раздельными namespace для workflow/instruction/prompt
///
/// Использование:
/// ```dart
/// final registry = buildDefaultRegistry();
/// final node = registry.workflowFromJson({'type': 'llmAction', ...});
/// ```
class NodeTypeRegistry {
  final Map<String, IWorkflowNode Function(Map<String, dynamic>)> _workflowFactories = {};
  final Map<String, IInstructionNode Function(Map<String, dynamic>)> _instructionFactories = {};
  final Map<String, IPromptNode Function(Map<String, dynamic>)> _promptFactories = {};

  /// Зарегистрировать тип workflow узла
  void registerWorkflow<T extends IWorkflowNode>(
    String typeKey,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    _workflowFactories[typeKey] = fromJson;
  }

  /// Зарегистрировать тип instruction узла
  void registerInstruction<T extends IInstructionNode>(
    String typeKey,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    _instructionFactories[typeKey] = fromJson;
  }

  /// Зарегистрировать тип prompt узла
  void registerPrompt<T extends IPromptNode>(
    String typeKey,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    _promptFactories[typeKey] = fromJson;
  }

  /// Создать workflow узел из JSON
  IWorkflowNode workflowFromJson(Map<String, dynamic> json) {
    final type = json['type'] as String?;
    if (type == null || type.isEmpty) {
      throw ArgumentError('NodeTypeRegistry: отсутствует поле "type" в JSON');
    }

    final factory = _workflowFactories[type];
    if (factory == null) {
      throw UnknownNodeTypeException(type, 'workflow');
    }

    return factory(json);
  }

  /// Создать instruction узел из JSON
  IInstructionNode instructionFromJson(Map<String, dynamic> json) {
    final type = json['type'] as String?;
    if (type == null || type.isEmpty) {
      throw ArgumentError('NodeTypeRegistry: отсутствует поле "type" в JSON');
    }

    final factory = _instructionFactories[type];
    if (factory == null) {
      throw UnknownNodeTypeException(type, 'instruction');
    }

    return factory(json);
  }

  /// Создать prompt узел из JSON
  IPromptNode promptFromJson(Map<String, dynamic> json) {
    final type = json['type'] as String?;
    if (type == null || type.isEmpty) {
      throw ArgumentError('NodeTypeRegistry: отсутствует поле "type" в JSON');
    }

    final factory = _promptFactories[type];
    if (factory == null) {
      throw UnknownNodeTypeException(type, 'prompt');
    }

    return factory(json);
  }

  /// Проверить, зарегистрирован ли workflow тип
  bool hasWorkflowType(String typeKey) => _workflowFactories.containsKey(typeKey);

  /// Проверить, зарегистрирован ли instruction тип
  bool hasInstructionType(String typeKey) => _instructionFactories.containsKey(typeKey);

  /// Проверить, зарегистрирован ли prompt тип
  bool hasPromptType(String typeKey) => _promptFactories.containsKey(typeKey);

  /// Получить список зарегистрированных workflow типов
  List<String> get workflowTypes => _workflowFactories.keys.toList();

  /// Получить список зарегистрированных instruction типов
  List<String> get instructionTypes => _instructionFactories.keys.toList();

  /// Получить список зарегистрированных prompt типов
  List<String> get promptTypes => _promptFactories.keys.toList();
}

/// Создать реестр со всеми стандартными типами узлов
NodeTypeRegistry buildDefaultRegistry() {
  final registry = NodeTypeRegistry();

  // ── Workflow nodes ──────────────────────────────────────────────────────────

  // Automatic nodes
  registry.registerWorkflow('llmAction', (json) => LlmActionNode.fromJson(json));
  registry.registerWorkflow('fileRead', (json) => FileReadNode.fromJson(json));
  registry.registerWorkflow('fileWrite', (json) => FileWriteNode.fromJson(json));
  registry.registerWorkflow('gitCommit', (json) => GitCommitNode.fromJson(json));

  // Interactive nodes
  registry.registerWorkflow('userInput', (json) => UserInputNode.fromJson(json));
  registry.registerWorkflow('manualReview', (json) => ManualReviewNode.fromJson(json));
  registry.registerWorkflow('fileUpload', (json) => FileUploadNode.fromJson(json));
  registry.registerWorkflow('coCreationChat', (json) => CoCreationChatNode.fromJson(json));

  // Composite nodes
  registry.registerWorkflow('subGraph', (json) => SubGraphNode.fromJson(json));
  registry.registerWorkflow('runInstruction', (json) => RunInstructionNode.fromJson(json));

  // ── Instruction nodes ───────────────────────────────────────────────────────

  registry.registerInstruction('condition', (json) => ConditionNode.fromJson(json));
  registry.registerInstruction('llmQuery', (json) => LlmQueryNode.fromJson(json));
  registry.registerInstruction('toolCall', (json) => ToolCallNode.fromJson(json));
  registry.registerInstruction('transform', (json) => TransformNode.fromJson(json));

  // ── Prompt nodes ────────────────────────────────────────────────────────────

  registry.registerPrompt('textBlock', (json) => TextBlockNode.fromJson(json));
  registry.registerPrompt('conditionalBlock', (json) => ConditionalBlockNode.fromJson(json));
  registry.registerPrompt('variableInsert', (json) => VariableInsertNode.fromJson(json));

  return registry;
}
