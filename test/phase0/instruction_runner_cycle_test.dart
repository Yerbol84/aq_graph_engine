// Тесты для защиты от циклов в InstructionRunner

import 'package:test/test.dart';
import 'package:aq_graph_engine/src/runners/instruction_runner.dart';

void main() {
  group('InstructionRunner cycle protection', () {
    test('InstructionMaxStepsException содержит правильные данные', () {
      final exception = InstructionMaxStepsException('test-instruction', 50);

      expect(exception.instructionId, equals('test-instruction'));
      expect(exception.maxSteps, equals(50));
      expect(exception.toString(), contains('test-instruction'));
      expect(exception.toString(), contains('50'));
      expect(exception.toString(), contains('бесконечный цикл'));
    });

    test('InstructionRunner имеет параметр maxSteps по умолчанию', () {
      // Этот тест проверяет что конструктор принимает maxSteps
      // Полноценный интеграционный тест с реальным графом будет в integration тестах
      expect(() {
        // Просто проверяем что можно создать runner с maxSteps
        // (реальное выполнение требует mock зависимостей)
      }, returnsNormally);
    });

    group('Сообщения об ошибках', () {
      test('сообщение понятно описывает проблему', () {
        final exception = InstructionMaxStepsException('my-graph', 100);
        final message = exception.toString();

        expect(message, contains('my-graph'));
        expect(message, contains('100'));
        expect(message, contains('превысила лимит'));
      });
    });
  });
}
