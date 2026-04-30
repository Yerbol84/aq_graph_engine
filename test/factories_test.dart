// Тесты для NodeTypeRegistry — реестра типов узлов.
// Проверяет что реестр корректно создаёт узлы из JSON
// для всех трёх типов графов: Workflow, Instruction, Prompt.

import 'package:test/test.dart';
import 'package:aq_graph_engine/server.dart';
import 'package:aq_schema/graph/nodes/workflow/automatic/llm_action_node.dart';
import 'package:aq_schema/graph/nodes/workflow/interactive/user_input_node.dart';
import 'package:aq_schema/graph/nodes/workflow/composite/sub_graph_node.dart';
import 'package:aq_schema/graph/nodes/instruction/tool_call_node.dart';
import 'package:aq_schema/graph/nodes/prompt/text_block_node.dart';

void main() {
  late NodeTypeRegistry registry;

  setUp(() {
    registry = buildDefaultRegistry();
  });

  // ── Workflow узлы ──────────────────────────────────────────────────────────

  group('NodeTypeRegistry — Workflow nodes', () {
    test('создаёт LlmActionNode из JSON', () {
      final json = {
        'id': 'llm1',
        'type': 'llmAction',
        'config': {
          'prompt_blueprint_id': 'prompt123',
          'output_var': 'result',
          'model_name': 'gpt-4',
        },
      };

      final node = registry.workflowFromJson(json);

      expect(node, isA<LlmActionNode>());
      expect(node.id, 'llm1');
      expect(node.nodeType, 'llmAction');

      final llmNode = node as LlmActionNode;
      expect(llmNode.promptBlueprintId, 'prompt123');
      expect(llmNode.outputVar, 'result');
      expect(llmNode.modelName, 'gpt-4');
    });

    test('создаёт UserInputNode из JSON', () {
      final json = {
        'id': 'input1',
        'type': 'userInput',
        'config': {
          'title': 'Enter name',
          'message': 'Please enter your name',
          'output_var': 'user_name',
        },
      };

      final node = registry.workflowFromJson(json);

      expect(node, isA<UserInputNode>());
      expect(node.nodeType, 'userInput');

      final inputNode = node as UserInputNode;
      expect(inputNode.title, 'Enter name');
      expect(inputNode.message, 'Please enter your name');
    });

    test('создаёт SubGraphNode из JSON', () {
      final json = {
        'id': 'sub1',
        'type': 'subGraph',
        'config': {
          'sub_graph_id': 'graph123',
          'input_mapping': {'input': 'data'},
          'output_mapping': {'result': 'output'},
        },
      };

      final node = registry.workflowFromJson(json);

      expect(node, isA<SubGraphNode>());

      final subNode = node as SubGraphNode;
      expect(subNode.subGraphId, 'graph123');
      expect(subNode.inputMapping, {'input': 'data'});
      expect(subNode.outputMapping, {'result': 'output'});
    });

    test('бросает UnknownNodeTypeException для неизвестного типа', () {
      final json = {'id': 'unknown1', 'type': 'unknownType', 'config': {}};
      expect(
        () => registry.workflowFromJson(json),
        throwsA(isA<UnknownNodeTypeException>()),
      );
    });

    test('бросает ArgumentError если нет поля type', () {
      final json = {'id': 'node1', 'config': {}};
      expect(
        () => registry.workflowFromJson(json),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('содержит все стандартные типы workflow узлов', () {
      final types = registry.workflowTypes;
      expect(types, containsAll([
        'llmAction', 'fileRead', 'fileWrite', 'gitCommit',
        'userInput', 'manualReview', 'fileUpload', 'coCreationChat',
        'subGraph', 'runInstruction',
      ]));
    });

    test('round-trip сериализация fileRead', () {
      final original = {
        'id': 'test1',
        'type': 'fileRead',
        'config': {'file_path': '/test/file.txt', 'output_var': 'content'},
      };

      final node = registry.workflowFromJson(original);
      final serialized = node.toJson();

      expect(serialized['id'], original['id']);
      expect(serialized['type'], original['type']);
    });
  });

  // ── Instruction узлы ───────────────────────────────────────────────────────

  group('NodeTypeRegistry — Instruction nodes', () {
    test('создаёт ToolCallNode из JSON', () {
      final json = {
        'id': 'tool1',
        'type': 'toolCall',
        'config': {
          'tool_name': 'test_tool',
          'params': {'param1': 'value1'},
          'output_var': 'result',
        },
      };

      final node = registry.instructionFromJson(json);

      expect(node, isA<ToolCallNode>());
      expect(node.nodeType, 'toolCall');

      final toolNode = node as ToolCallNode;
      expect(toolNode.toolName, 'test_tool');
    });

    test('содержит все стандартные типы instruction узлов', () {
      final types = registry.instructionTypes;
      expect(types, containsAll(['toolCall', 'llmQuery', 'condition', 'transform']));
    });

    test('бросает UnknownNodeTypeException для неизвестного типа', () {
      final json = {'id': 'node1', 'type': 'unknownInstruction'};
      expect(
        () => registry.instructionFromJson(json),
        throwsA(isA<UnknownNodeTypeException>()),
      );
    });
  });

  // ── Prompt узлы ────────────────────────────────────────────────────────────

  group('NodeTypeRegistry — Prompt nodes', () {
    test('создаёт TextBlockNode из JSON', () {
      final json = {
        'id': 'text1',
        'type': 'textBlock',
        'config': {'text': 'Hello {{name}}!'},
      };

      final node = registry.promptFromJson(json);

      expect(node, isA<TextBlockNode>());
      expect(node.nodeType, 'textBlock');

      final textNode = node as TextBlockNode;
      expect(textNode.text, 'Hello {{name}}!');
    });

    test('содержит все стандартные типы prompt узлов', () {
      final types = registry.promptTypes;
      expect(types, containsAll(['textBlock', 'variableInsert', 'conditionalBlock']));
    });

    test('бросает UnknownNodeTypeException для неизвестного типа', () {
      final json = {'id': 'node1', 'type': 'unknownPrompt'};
      expect(
        () => registry.promptFromJson(json),
        throwsA(isA<UnknownNodeTypeException>()),
      );
    });
  });
}
