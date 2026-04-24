// Тесты для ConditionEvaluator

import 'package:test/test.dart';
import 'package:aq_graph_engine/server.dart';

void main() {
  group('ConditionEvaluator', () {
    group('Операторы сравнения', () {
      test('== для строк', () {
        final state = {'status': 'success'};
        expect(ConditionEvaluator.evaluate("status == 'success'", state), isTrue);
        expect(ConditionEvaluator.evaluate("status == 'failed'", state), isFalse);
      });

      test('== для чисел', () {
        final state = {'count': 5};
        expect(ConditionEvaluator.evaluate('count == 5', state), isTrue);
        expect(ConditionEvaluator.evaluate('count == 10', state), isFalse);
      });

      test('!= для строк и чисел', () {
        final state = {'status': 'ok', 'count': 3};
        expect(ConditionEvaluator.evaluate("status != 'failed'", state), isTrue);
        expect(ConditionEvaluator.evaluate('count != 5', state), isTrue);
        expect(ConditionEvaluator.evaluate('count != 3', state), isFalse);
      });

      test('> и < для чисел', () {
        final state = {'count': 10};
        expect(ConditionEvaluator.evaluate('count > 5', state), isTrue);
        expect(ConditionEvaluator.evaluate('count > 15', state), isFalse);
        expect(ConditionEvaluator.evaluate('count < 15', state), isTrue);
        expect(ConditionEvaluator.evaluate('count < 5', state), isFalse);
      });

      test('>= и <= для чисел', () {
        final state = {'count': 10};
        expect(ConditionEvaluator.evaluate('count >= 10', state), isTrue);
        expect(ConditionEvaluator.evaluate('count >= 5', state), isTrue);
        expect(ConditionEvaluator.evaluate('count >= 15', state), isFalse);
        expect(ConditionEvaluator.evaluate('count <= 10', state), isTrue);
        expect(ConditionEvaluator.evaluate('count <= 15', state), isTrue);
        expect(ConditionEvaluator.evaluate('count <= 5', state), isFalse);
      });

      test('> и < для строк (лексикографическое сравнение)', () {
        final state = {'name': 'bob'};
        expect(ConditionEvaluator.evaluate("name > 'alice'", state), isTrue);
        expect(ConditionEvaluator.evaluate("name < 'charlie'", state), isTrue);
      });
    });

    group('Строковые операторы', () {
      test('contains для строк', () {
        final state = {'message': 'Error: file not found'};
        expect(ConditionEvaluator.evaluate("message contains 'Error'", state), isTrue);
        expect(ConditionEvaluator.evaluate("message contains 'Success'", state), isFalse);
      });

      test('contains для списков', () {
        final state = {
          'tags': ['urgent', 'bug', 'frontend']
        };
        expect(ConditionEvaluator.evaluate("tags contains 'bug'", state), isTrue);
        expect(ConditionEvaluator.evaluate("tags contains 'backend'", state), isFalse);
      });
    });

    group('Унарные операторы', () {
      test('isEmpty для строк', () {
        final state = {'empty': '', 'full': 'text'};
        expect(ConditionEvaluator.evaluate('empty isEmpty', state), isTrue);
        expect(ConditionEvaluator.evaluate('full isEmpty', state), isFalse);
      });

      test('isEmpty для списков', () {
        final state = {
          'emptyList': [],
          'fullList': [1, 2, 3]
        };
        expect(ConditionEvaluator.evaluate('emptyList isEmpty', state), isTrue);
        expect(ConditionEvaluator.evaluate('fullList isEmpty', state), isFalse);
      });

      test('isEmpty для null', () {
        final state = {'nullValue': null};
        expect(ConditionEvaluator.evaluate('nullValue isEmpty', state), isTrue);
      });

      test('isNotEmpty', () {
        final state = {'text': 'hello', 'empty': ''};
        expect(ConditionEvaluator.evaluate('text isNotEmpty', state), isTrue);
        expect(ConditionEvaluator.evaluate('empty isNotEmpty', state), isFalse);
      });

      test('exists и notExists', () {
        final state = {'present': 'value', 'absent': null};
        expect(ConditionEvaluator.evaluate('present exists', state), isTrue);
        expect(ConditionEvaluator.evaluate('absent exists', state), isFalse);
        expect(ConditionEvaluator.evaluate('absent notExists', state), isTrue);
        expect(ConditionEvaluator.evaluate('present notExists', state), isFalse);
      });
    });

    group('Dot-notation переменные', () {
      test('вложенные объекты', () {
        final state = {
          'user': {
            'name': 'Alice',
            'age': 30,
          }
        };
        expect(ConditionEvaluator.evaluate("user.name == 'Alice'", state), isTrue);
        expect(ConditionEvaluator.evaluate('user.age > 25', state), isTrue);
      });

      test('глубокая вложенность', () {
        final state = {
          'config': {
            'api': {
              'key': 'secret123',
            }
          }
        };
        expect(
          ConditionEvaluator.evaluate("config.api.key == 'secret123'", state),
          isTrue,
        );
      });

      test('несуществующий путь возвращает null', () {
        final state = {'user': {}};
        expect(ConditionEvaluator.evaluate('user.missing == null', state), isTrue);
      });
    });

    group('Граничные случаи', () {
      test('null значения', () {
        final state = {'value': null};
        expect(ConditionEvaluator.evaluate('value == null', state), isTrue);
        expect(ConditionEvaluator.evaluate('value != null', state), isFalse);
      });

      test('boolean значения', () {
        final state = {'flag': true};
        expect(ConditionEvaluator.evaluate('flag == true', state), isTrue);
        expect(ConditionEvaluator.evaluate('flag == false', state), isFalse);
      });

      test('пустая строка', () {
        final state = {'text': ''};
        expect(ConditionEvaluator.evaluate("text == ''", state), isTrue);
        expect(ConditionEvaluator.evaluate('text isEmpty', state), isTrue);
      });

      test('числа с плавающей точкой', () {
        final state = {'pi': 3.14};
        expect(ConditionEvaluator.evaluate('pi > 3', state), isTrue);
        expect(ConditionEvaluator.evaluate('pi < 4', state), isTrue);
      });
    });

    group('Ошибки', () {
      test('пустое выражение', () {
        expect(
          () => ConditionEvaluator.evaluate('', {}),
          throwsA(isA<ConditionEvalException>()),
        );
      });

      test('неизвестный оператор', () {
        final state = {'x': 5};
        expect(
          () => ConditionEvaluator.evaluate('x === 5', state),
          throwsA(isA<ConditionEvalException>()),
        );
      });

      test('некорректный литерал', () {
        final state = {'x': 5};
        expect(
          () => ConditionEvaluator.evaluate('x == notALiteral', state),
          throwsA(isA<ConditionEvalException>()),
        );
      });

      test('сравнение несовместимых типов', () {
        final state = {'text': 'hello', 'number': 5};
        expect(
          () => ConditionEvaluator.evaluate('text > number', state),
          throwsA(isA<ConditionEvalException>()),
        );
      });

      test('contains на несовместимом типе', () {
        final state = {'number': 42};
        expect(
          () => ConditionEvaluator.evaluate('number contains 4', state),
          throwsA(isA<ConditionEvalException>()),
        );
      });
    });

    group('ConditionEvalException', () {
      test('содержит выражение и сообщение', () {
        final exception = ConditionEvalException('bad expr', 'test error');
        expect(exception.expression, equals('bad expr'));
        expect(exception.message, equals('test error'));
        expect(exception.toString(), contains('bad expr'));
        expect(exception.toString(), contains('test error'));
      });
    });
  });
}
