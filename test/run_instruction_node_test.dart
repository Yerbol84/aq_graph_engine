import 'package:test/test.dart';
import 'package:aq_schema/aq_schema.dart';
import 'package:aq_graph_engine/aq_graph_engine.dart';

void main() {
  group('RunInstructionNode', () {
    test('создаётся из JSON с правильными полями', () {
      final json = {
        'id': 'node1',
        'type': 'runInstruction',
        'instructionBlueprintId': 'instruction_llm_ask',
        'inputMapping': {
          'prompt': 'user_prompt',
        },
        'outputMapping': {
          'result': 'llm_response',
        },
      };

      final node = RunInstructionNode.fromJson(json);

      expect(node.id, 'node1');
      expect(node.nodeType, 'runInstruction');
      expect(node.instructionBlueprintId, 'instruction_llm_ask');
      expect(node.inputMapping, {'prompt': 'user_prompt'});
      expect(node.outputMapping, {'result': 'llm_response'});
    });

    test('сериализуется в JSON корректно', () {
      final node = RunInstructionNode(
        id: 'node1',
        instructionBlueprintId: 'instruction_file_read',
        inputMapping: {'file_path': 'target_file'},
        outputMapping: {'content': 'file_content'},
      );

      final json = node.toJson();

      expect(json['id'], 'node1');
      expect(json['nodeType'], 'runInstruction');
      expect(json['instructionBlueprintId'], 'instruction_file_read');
      expect(json['inputMapping'], {'file_path': 'target_file'});
      expect(json['outputMapping'], {'content': 'file_content'});
    });

    test('NodeFactory создаёт RunInstructionNode из JSON', () {
      final json = {
        'id': 'node1',
        'type': 'runInstruction',
        'instructionBlueprintId': 'instruction_code_analyzer',
        'inputMapping': {
          'source_code': 'code',
          'analysis_type': 'security',
        },
        'outputMapping': {
          'analysis': 'result',
          'score': 'quality',
        },
      };

      final node = WorkflowNodeFactory.fromJson(json);

      expect(node, isA<RunInstructionNode>());
      expect(node.id, 'node1');

      final runNode = node as RunInstructionNode;
      expect(runNode.instructionBlueprintId, 'instruction_code_analyzer');
      expect(runNode.inputMapping.length, 2);
      expect(runNode.outputMapping.length, 2);
    });

    test('NodeFactory выбрасывает исключение для неизвестного типа', () {
      final json = {
        'id': 'node1',
        'type': 'unknownType',
      };

      expect(
        () => WorkflowNodeFactory.fromJson(json),
        throwsA(isA<Exception>()),
      );
    });

    test('NodeFactory выбрасывает исключение если type отсутствует', () {
      final json = {
        'id': 'node1',
      };

      expect(
        () => WorkflowNodeFactory.fromJson(json),
        throwsA(isA<Exception>()),
      );
    });
  });
}
