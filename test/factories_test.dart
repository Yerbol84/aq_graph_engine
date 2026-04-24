// Тесты для фабрик узлов

import 'package:test/test.dart';
import 'package:aq_graph_engine/src/factories/workflow_node_factory.dart';
import 'package:aq_graph_engine/src/factories/instruction_node_factory.dart';
import 'package:aq_graph_engine/src/factories/prompt_node_factory.dart';
import 'package:aq_schema/graph/nodes/base/i_workflow_node.dart';
import 'package:aq_schema/graph/nodes/base/i_instruction_node.dart';
import 'package:aq_schema/graph/nodes/base/i_prompt_node.dart';
import 'package:aq_schema/graph/nodes/workflow/automatic/llm_action_node.dart';
import 'package:aq_schema/graph/nodes/workflow/interactive/user_input_node.dart';
import 'package:aq_schema/graph/nodes/workflow/composite/sub_graph_node.dart';
import 'package:aq_schema/graph/nodes/instruction/tool_call_node.dart';
import 'package:aq_schema/graph/nodes/prompt/text_block_node.dart';

void main() {
  group('WorkflowNodeFactory', () {
    test('should create LlmActionNode from JSON', () {
      final json = {
        'id': 'llm1',
        'type': 'llmAction',
        'config': {
          'prompt_blueprint_id': 'prompt123',
          'output_var': 'result',
          'model_name': 'gpt-4',
        },
      };

      final node = WorkflowNodeFactory.fromJson(json);

      expect(node, isA<LlmActionNode>());
      expect(node.id, 'llm1');
      expect(node.nodeType, 'llmAction');

      final llmNode = node as LlmActionNode;
      expect(llmNode.promptBlueprintId, 'prompt123');
      expect(llmNode.outputVar, 'result');
      expect(llmNode.modelName, 'gpt-4');
    });

    test('should create UserInputNode from JSON', () {
      final json = {
        'id': 'input1',
        'type': 'userInput',
        'config': {
          'title': 'Enter name',
          'message': 'Please enter your name',
          'output_var': 'user_name',
          'input_type': 'text',
        },
      };

      final node = WorkflowNodeFactory.fromJson(json);

      expect(node, isA<UserInputNode>());
      expect(node.nodeType, 'userInput');

      final inputNode = node as UserInputNode;
      expect(inputNode.title, 'Enter name');
      expect(inputNode.message, 'Please enter your name');
    });

    test('should create SubGraphNode from JSON', () {
      final json = {
        'id': 'sub1',
        'type': 'subGraph',
        'config': {
          'sub_graph_id': 'graph123',
          'input_mapping': {'input': 'data'},
          'output_mapping': {'result': 'output'},
        },
      };

      final node = WorkflowNodeFactory.fromJson(json);

      expect(node, isA<SubGraphNode>());

      final subNode = node as SubGraphNode;
      expect(subNode.subGraphId, 'graph123');
      expect(subNode.inputMapping, {'input': 'data'});
      expect(subNode.outputMapping, {'result': 'output'});
    });

    test('should throw on unknown node type', () {
      final json = {
        'id': 'unknown1',
        'type': 'unknownType',
        'config': {},
      };

      expect(
        () => WorkflowNodeFactory.fromJson(json),
        throwsA(isA<Exception>()),
      );
    });

    test('should throw on missing type field', () {
      final json = {
        'id': 'node1',
        'config': {},
      };

      expect(
        () => WorkflowNodeFactory.fromJson(json),
        throwsA(isA<Exception>()),
      );
    });

    test('should return all supported types', () {
      final types = WorkflowNodeFactory.getSupportedTypes();

      expect(types, contains('llmAction'));
      expect(types, contains('fileRead'));
      expect(types, contains('fileWrite'));
      expect(types, contains('gitCommit'));
      expect(types, contains('userInput'));
      expect(types, contains('manualReview'));
      expect(types, contains('fileUpload'));
      expect(types, contains('coCreationChat'));
      expect(types, contains('subGraph'));
      expect(types, contains('runInstruction'));
      expect(types.length, 10);
    });

    test('should check if type is supported', () {
      expect(WorkflowNodeFactory.isSupported('llmAction'), true);
      expect(WorkflowNodeFactory.isSupported('userInput'), true);
      expect(WorkflowNodeFactory.isSupported('unknownType'), false);
    });

    test('should handle round-trip serialization', () {
      final original = {
        'id': 'test1',
        'type': 'fileRead',
        'config': {
          'file_path': '/test/file.txt',
          'output_var': 'content',
        },
      };

      final node = WorkflowNodeFactory.fromJson(original);
      final serialized = node.toJson();

      expect(serialized['id'], original['id']);
      expect(serialized['type'], original['type']);
      expect(serialized['config']['file_path'], original['config']['file_path']);
      expect(serialized['config']['output_var'], original['config']['output_var']);
    });
  });

  group('InstructionNodeFactory', () {
    test('should create ToolCallNode from JSON', () {
      final json = {
        'id': 'tool1',
        'type': 'toolCall',
        'config': {
          'tool_name': 'test_tool',
          'params': {'param1': 'value1'},
          'output_var': 'result',
        },
      };

      final node = InstructionNodeFactory.fromJson(json);

      expect(node, isA<ToolCallNode>());
      expect(node.nodeType, 'toolCall');

      final toolNode = node as ToolCallNode;
      expect(toolNode.toolName, 'test_tool');
      expect(toolNode.params, {'param1': 'value1'});
    });

    test('should create all instruction node types', () {
      final types = ['toolCall', 'llmQuery', 'condition', 'transform'];

      for (final type in types) {
        final json = {
          'id': 'node1',
          'type': type,
          'config': {},
        };

        final node = InstructionNodeFactory.fromJson(json);
        expect(node.nodeType, type);
      }
    });

    test('should return all supported types', () {
      final types = InstructionNodeFactory.getSupportedTypes();

      expect(types, contains('toolCall'));
      expect(types, contains('llmQuery'));
      expect(types, contains('condition'));
      expect(types, contains('transform'));
      expect(types.length, 4);
    });

    test('should throw on unknown type', () {
      final json = {
        'id': 'node1',
        'type': 'unknownType',
        'config': {},
      };

      expect(
        () => InstructionNodeFactory.fromJson(json),
        throwsA(isA<Exception>()),
      );
    });

    test('should handle round-trip serialization', () {
      final original = {
        'id': 'cond1',
        'type': 'condition',
        'config': {
          'check_var': 'status',
          'operator': '==',
          'compare_value': 'success',
          'output_var': 'is_success',
        },
      };

      final node = InstructionNodeFactory.fromJson(original);
      final serialized = node.toJson();

      expect(serialized['id'], original['id']);
      expect(serialized['type'], original['type']);
      expect(serialized['config']['check_var'], original['config']['check_var']);
    });
  });

  group('PromptNodeFactory', () {
    test('should create TextBlockNode from JSON', () {
      final json = {
        'id': 'text1',
        'type': 'textBlock',
        'config': {
          'text': 'Hello {{name}}!',
        },
      };

      final node = PromptNodeFactory.fromJson(json);

      expect(node, isA<TextBlockNode>());
      expect(node.nodeType, 'textBlock');

      final textNode = node as TextBlockNode;
      expect(textNode.text, 'Hello {{name}}!');
    });

    test('should create all prompt node types', () {
      final types = ['textBlock', 'variableInsert', 'conditionalBlock'];

      for (final type in types) {
        final json = {
          'id': 'node1',
          'type': type,
          'config': {},
        };

        final node = PromptNodeFactory.fromJson(json);
        expect(node.nodeType, type);
      }
    });

    test('should return all supported types', () {
      final types = PromptNodeFactory.getSupportedTypes();

      expect(types, contains('textBlock'));
      expect(types, contains('variableInsert'));
      expect(types, contains('conditionalBlock'));
      expect(types.length, 3);
    });

    test('should throw on unknown type', () {
      final json = {
        'id': 'node1',
        'type': 'unknownType',
        'config': {},
      };

      expect(
        () => PromptNodeFactory.fromJson(json),
        throwsA(isA<Exception>()),
      );
    });

    test('should handle round-trip serialization', () {
      final original = {
        'id': 'var1',
        'type': 'variableInsert',
        'config': {
          'var_name': 'username',
          'prefix': 'User: ',
          'suffix': '',
          'default_value': 'Guest',
        },
      };

      final node = PromptNodeFactory.fromJson(original);
      final serialized = node.toJson();

      expect(serialized['id'], original['id']);
      expect(serialized['type'], original['type']);
      expect(serialized['config']['var_name'], original['config']['var_name']);
    });
  });
}
