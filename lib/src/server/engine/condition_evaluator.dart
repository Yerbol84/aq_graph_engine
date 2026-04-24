// Evaluator для условных выражений в WorkflowEdge
// Поддерживает операторы сравнения и проверки существования

/// Исключение при ошибке вычисления условия
class ConditionEvalException implements Exception {
  final String expression;
  final String message;

  ConditionEvalException(this.expression, this.message);

  @override
  String toString() =>
      'ConditionEvalException: не удалось вычислить "$expression" — $message';
}

/// Evaluator условных выражений
///
/// Поддерживаемые операторы:
/// - Сравнение: ==, !=, >, <, >=, <=
/// - Строковые: contains
/// - Проверки: isEmpty, isNotEmpty, exists, notExists
///
/// Примеры:
/// - "status == 'success'"
/// - "count > 5"
/// - "errors isEmpty"
/// - "result != null"
/// - "message contains 'error'"
class ConditionEvaluator {
  /// Вычислить условное выражение
  ///
  /// [expression] — строка вида "variable operator value"
  /// [state] — карта переменных контекста
  ///
  /// Возвращает true/false
  /// Бросает ConditionEvalException при синтаксической ошибке
  static bool evaluate(String expression, Map<String, dynamic> state) {
    final trimmed = expression.trim();
    if (trimmed.isEmpty) {
      throw ConditionEvalException(expression, 'пустое выражение');
    }

    // Унарные операторы (без правой части)
    if (trimmed.contains(' isEmpty')) {
      return _evaluateUnary(trimmed, 'isEmpty', state, (val) => _isEmpty(val));
    }
    if (trimmed.contains(' isNotEmpty')) {
      return _evaluateUnary(
          trimmed, 'isNotEmpty', state, (val) => !_isEmpty(val));
    }
    if (trimmed.contains(' exists')) {
      return _evaluateUnary(trimmed, 'exists', state, (val) => val != null);
    }
    if (trimmed.contains(' notExists')) {
      return _evaluateUnary(trimmed, 'notExists', state, (val) => val == null);
    }

    // Бинарные операторы (с правой частью)
    if (trimmed.contains(' contains ')) {
      return _evaluateBinary(
          trimmed, 'contains', state, (left, right) => _contains(left, right));
    }
    if (trimmed.contains(' >= ')) {
      return _evaluateBinary(
          trimmed, '>=', state, (left, right) => _compare(left, right) >= 0);
    }
    if (trimmed.contains(' <= ')) {
      return _evaluateBinary(
          trimmed, '<=', state, (left, right) => _compare(left, right) <= 0);
    }
    if (trimmed.contains(' > ')) {
      return _evaluateBinary(
          trimmed, '>', state, (left, right) => _compare(left, right) > 0);
    }
    if (trimmed.contains(' < ')) {
      return _evaluateBinary(
          trimmed, '<', state, (left, right) => _compare(left, right) < 0);
    }
    if (trimmed.contains(' == ')) {
      return _evaluateBinary(
          trimmed, '==', state, (left, right) => _equals(left, right));
    }
    if (trimmed.contains(' != ')) {
      return _evaluateBinary(
          trimmed, '!=', state, (left, right) => !_equals(left, right));
    }

    throw ConditionEvalException(
        expression, 'неизвестный оператор или неверный синтаксис');
  }

  // ── Унарные операторы ──────────────────────────────────────────────────────

  static bool _evaluateUnary(
    String expression,
    String operator,
    Map<String, dynamic> state,
    bool Function(dynamic) check,
  ) {
    final parts = expression.split(' $operator');
    if (parts.length != 2 || parts[1].trim().isNotEmpty) {
      throw ConditionEvalException(
          expression, 'оператор $operator должен быть в конце выражения');
    }

    final varName = parts[0].trim();
    final value = _resolveVariable(varName, state);
    return check(value);
  }

  // ── Бинарные операторы ─────────────────────────────────────────────────────

  static bool _evaluateBinary(
    String expression,
    String operator,
    Map<String, dynamic> state,
    bool Function(dynamic, dynamic) compare,
  ) {
    final parts = expression.split(' $operator ');
    if (parts.length != 2) {
      throw ConditionEvalException(
          expression, 'оператор $operator требует левую и правую часть');
    }

    final leftVar = parts[0].trim();
    final rightLiteral = parts[1].trim();

    final leftValue = _resolveVariable(leftVar, state);
    final rightValue = _parseLiteral(rightLiteral);

    return compare(leftValue, rightValue);
  }

  // ── Разрешение переменных ──────────────────────────────────────────────────

  /// Разрешить переменную из state с поддержкой dot-notation
  /// Примеры: "status", "user.name", "config.api.key"
  static dynamic _resolveVariable(String varName, Map<String, dynamic> state) {
    if (!varName.contains('.')) {
      return state[varName];
    }

    // Dot-notation: user.name → state['user']['name']
    final parts = varName.split('.');
    dynamic current = state;

    for (final part in parts) {
      if (current is Map) {
        current = current[part];
      } else {
        return null; // Путь не существует
      }
    }

    return current;
  }

  // ── Парсинг литералов ──────────────────────────────────────────────────────

  /// Распарсить литерал из правой части выражения
  /// Поддерживает: строки в кавычках, числа, true/false, null
  static dynamic _parseLiteral(String literal) {
    // Строка в одинарных кавычках
    if (literal.startsWith("'") && literal.endsWith("'")) {
      return literal.substring(1, literal.length - 1);
    }

    // Строка в двойных кавычках
    if (literal.startsWith('"') && literal.endsWith('"')) {
      return literal.substring(1, literal.length - 1);
    }

    // Boolean
    if (literal == 'true') return true;
    if (literal == 'false') return false;

    // Null
    if (literal == 'null') return null;

    // Число (int или double)
    final numValue = num.tryParse(literal);
    if (numValue != null) return numValue;

    throw ConditionEvalException(
        literal, 'не удалось распарсить литерал (используйте кавычки для строк)');
  }

  // ── Операции сравнения ─────────────────────────────────────────────────────

  static bool _equals(dynamic left, dynamic right) {
    return left == right;
  }

  static int _compare(dynamic left, dynamic right) {
    if (left is num && right is num) {
      return left.compareTo(right);
    }
    if (left is String && right is String) {
      return left.compareTo(right);
    }
    throw ConditionEvalException(
        '$left <=> $right', 'сравнение возможно только для чисел или строк');
  }

  static bool _contains(dynamic left, dynamic right) {
    if (left is String && right is String) {
      return left.contains(right);
    }
    if (left is List) {
      return left.contains(right);
    }
    throw ConditionEvalException(
        '$left contains $right', 'contains работает только для строк и списков');
  }

  static bool _isEmpty(dynamic value) {
    if (value == null) return true;
    if (value is String) return value.isEmpty;
    if (value is List) return value.isEmpty;
    if (value is Map) return value.isEmpty;
    return false;
  }
}
