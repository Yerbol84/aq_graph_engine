// Mock узел для unit тестирования логики движка
//
// Позволяет:
// - Считать количество выполнений
// - Контролировать успех/ошибку
// - Задавать joinStrategy
// - Отслеживать порядок выполнения

import 'package:aq_schema/aq_schema.dart';

/// Mock узел с счётчиком выполнений для unit тестов
class MockNode {
  final String id;
  final JoinStrategy joinStrategy;
  final bool shouldFail;
  final Duration? delay;
  final Function()? onExecute;

  int executionCount = 0;
  final List<DateTime> executionTimestamps = [];
  String? lastError;

  MockNode({
    required this.id,
    this.joinStrategy = JoinStrategy.firstCome,
    this.shouldFail = false,
    this.delay,
    this.onExecute,
  });

  /// Выполнить узел
  Future<void> execute() async {
    executionCount++;
    executionTimestamps.add(DateTime.now());

    if (delay != null) {
      await Future.delayed(delay!);
    }

    if (shouldFail) {
      lastError = 'Mock node $id failed intentionally';
      throw Exception(lastError);
    }

    onExecute?.call();
  }

  /// Сбросить счётчики
  void reset() {
    executionCount = 0;
    executionTimestamps.clear();
    lastError = null;
  }

  /// Получить среднее время между выполнениями
  Duration? getAverageExecutionInterval() {
    if (executionTimestamps.length < 2) return null;

    var totalDuration = Duration.zero;
    for (var i = 1; i < executionTimestamps.length; i++) {
      totalDuration += executionTimestamps[i].difference(executionTimestamps[i - 1]);
    }

    return totalDuration ~/ (executionTimestamps.length - 1);
  }

  @override
  String toString() => 'MockNode($id, executions: $executionCount, joinStrategy: $joinStrategy)';
}

/// Фабрика для создания типовых mock узлов
class MockNodeFactory {
  /// Узел который всегда успешен
  static MockNode success(String id, {JoinStrategy? joinStrategy}) {
    return MockNode(
      id: id,
      joinStrategy: joinStrategy ?? JoinStrategy.firstCome,
      shouldFail: false,
    );
  }

  /// Узел который всегда падает
  static MockNode failing(String id, {JoinStrategy? joinStrategy}) {
    return MockNode(
      id: id,
      joinStrategy: joinStrategy ?? JoinStrategy.firstCome,
      shouldFail: true,
    );
  }

  /// Узел с задержкой (для проверки параллельности)
  static MockNode delayed(String id, Duration delay, {JoinStrategy? joinStrategy}) {
    return MockNode(
      id: id,
      joinStrategy: joinStrategy ?? JoinStrategy.firstCome,
      delay: delay,
    );
  }

  /// Узел с waitAll стратегией
  static MockNode waitAll(String id) {
    return MockNode(
      id: id,
      joinStrategy: JoinStrategy.waitAll,
    );
  }

  /// Узел с firstCome стратегией
  static MockNode firstCome(String id) {
    return MockNode(
      id: id,
      joinStrategy: JoinStrategy.firstCome,
    );
  }

  /// Узел с exclusive стратегией
  static MockNode exclusive(String id) {
    return MockNode(
      id: id,
      joinStrategy: JoinStrategy.exclusive,
    );
  }
}
