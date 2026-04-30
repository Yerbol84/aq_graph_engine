// Тесты для RunInstructionNode через NodeTypeRegistry

import 'package:test/test.dart';
import 'package:aq_graph_engine/server.dart';
import 'package:aq_schema/graph/nodes/workflow/composite/run_instruction_node.dart';

void main() {
  late NodeTypeRegistry registry;

  setUp(() {
    registry = buildDefaultRegistry();
  });

  group('RunInstructionNode', () {
    test('создаётся из JSON с правильными полями', () {
      final json = {
        'id': 'node1',
        'type': 'runInstruction',
        'config': {
          'instruction_id': 'instruction_llm_ask',
          'input_mapping': {'prompt': 'user_prompt'},
          'output_mapping': {'result': 'llm_response'},
        },
      };

      final node = registry.workflowFromJson(json);

      expect(node, isA<RunInstructionNode>());
      expect(node.id, 'node1');
      expect(node.nodeType, 'runInstruction');

      final runNode = node as RunInstructionNode;
      expect(runNode.subGraphId, 'instruction_llm_ask');
      expect(runNode.inputMapping, {'prompt': 'user_prompt'});
      expect(runNode.outputMapping, {'result': 'llm_response'});
    });

    test('сериализуется в JSON корректно', () {
      final json = {
        'id': 'node1',
        'type': 'runInstruction',
        'config': {
          'instruction_id': 'instruction_file_read',
          'input_mapping': {'file_path': 'target_file'},
          'output_mapping': {'content': 'file_content'},
        },
      };

      final node = registry.workflowFromJson(json);
      final serialized = node.toJson();

      expect(serialized['id'], 'node1');
      expect(serialized['type'], 'runInstruction');
      expect(serialized['config']['instruction_id'], 'instruction_file_read');
    });

    test('NodeTypeRegistry бросает UnknownNodeTypeException для неизвестного типа', () {
      final json = {'id': 'node1', 'type': 'unknownType'};
      expect(
        () => registry.workflowFromJson(json),
        throwsA(isA<UnknownNodeTypeException>()),
      );
    });

    test('NodeTypeRegistry бросает ArgumentError если type отсутствует', () {
      final json = {'id': 'node1'};
      expect(
        () => registry.workflowFromJson(json),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
