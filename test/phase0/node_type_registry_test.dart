// Тесты для NodeTypeRegistry

import 'package:test/test.dart';
import 'package:aq_graph_engine/server.dart';
import 'package:aq_schema/graph/nodes/workflow/automatic/llm_action_node.dart';
import 'package:aq_schema/graph/nodes/workflow/interactive/user_input_node.dart';
import 'package:aq_schema/graph/nodes/instruction/condition_node.dart';
import 'package:aq_schema/graph/nodes/prompt/text_block_node.dart';

void main() {
  group('NodeTypeRegistry', () {
    late NodeTypeRegistry registry;

    setUp(() {
      registry = buildDefaultRegistry();
    });

    group('Workflow nodes', () {
      test('создаёт LlmActionNode из JSON', () {
        final json = {
          'id': 'test-node',
          'type': 'llmAction',
          'prompt': 'Test prompt',
          'outputVar': 'result',
        };

        final node = registry.workflowFromJson(json);

        expect(node, isA<LlmActionNode>());
        expect(node.id, equals('test-node'));
        expect(node.nodeType, equals('llmAction'));
      });

      test('создаёт UserInputNode из JSON', () {
        final json = {
          'id': 'input-node',
          'type': 'userInput',
          'prompt': 'Enter value',
          'outputVar': 'userValue',
        };

        final node = registry.workflowFromJson(json);

        expect(node, isA<UserInputNode>());
        expect(node.id, equals('input-node'));
      });

      test('бросает UnknownNodeTypeException для неизвестного типа', () {
        final json = {
          'id': 'unknown',
          'type': 'unknownType',
        };

        expect(
          () => registry.workflowFromJson(json),
          throwsA(isA<UnknownNodeTypeException>()),
        );
      });

      test('бросает ArgumentError если нет поля type', () {
        final json = {
          'id': 'no-type',
        };

        expect(
          () => registry.workflowFromJson(json),
          throwsA(isA<ArgumentError>()),
        );
      });
    });

    group('Instruction nodes', () {
      test('создаёт ConditionNode из JSON', () {
        final json = {
          'id': 'cond-node',
          'type': 'condition',
          'expression': 'status == "ok"',
        };

        final node = registry.instructionFromJson(json);

        expect(node, isA<ConditionNode>());
        expect(node.id, equals('cond-node'));
      });

      test('бросает UnknownNodeTypeException для неизвестного instruction типа', () {
        final json = {
          'id': 'unknown',
          'type': 'unknownInstruction',
        };

        expect(
          () => registry.instructionFromJson(json),
          throwsA(isA<UnknownNodeTypeException>()),
        );
      });
    });

    group('Prompt nodes', () {
      test('создаёт TextBlockNode из JSON', () {
        final json = {
          'id': 'text-node',
          'type': 'textBlock',
          'text': 'Hello world',
        };

        final node = registry.promptFromJson(json);

        expect(node, isA<TextBlockNode>());
        expect(node.id, equals('text-node'));
      });
    });

    group('Независимость реестров', () {
      test('workflow и instruction реестры независимы', () {
        // Регистрируем тип только в workflow
        final customRegistry = NodeTypeRegistry();
        customRegistry.registerWorkflow('custom', (json) {
          return LlmActionNode.fromJson(json);
        });

        // Проверяем что тип есть в workflow
        expect(customRegistry.hasWorkflowType('custom'), isTrue);

        // Но нет в instruction
        expect(customRegistry.hasInstructionType('custom'), isFalse);
      });

      test('возвращает список зарегистрированных типов', () {
        final workflowTypes = registry.workflowTypes;
        final instructionTypes = registry.instructionTypes;
        final promptTypes = registry.promptTypes;

        expect(workflowTypes, contains('llmAction'));
        expect(workflowTypes, contains('userInput'));
        expect(instructionTypes, contains('condition'));
        expect(promptTypes, contains('textBlock'));
      });
    });

    group('UnknownNodeTypeException', () {
      test('содержит правильное сообщение об ошибке', () {
        final exception = UnknownNodeTypeException('badType', 'workflow');

        expect(
          exception.toString(),
          contains('badType'),
        );
        expect(
          exception.toString(),
          contains('workflow'),
        );
        expect(exception.typeKey, equals('badType'));
        expect(exception.graphKind, equals('workflow'));
      });
    });
  });
}
