# План улучшения Graph Engine

## Дата: 2026-04-09

## Текущее состояние

### Что работает ✅
- Последовательное выполнение узлов
- Простые цепочки (A → B → C)
- Diamond pattern (разветвление и слияние)
- Suspend/Resume для интерактивных узлов
- Полиморфные узлы через IWorkflowNode

### Что НЕ работает ❌
1. **Условное ветвление** - типы рёбер (onSuccess/onError) игнорируются
2. **Параллельное выполнение** - все рёбра выполняются параллельно через `Future.wait()`
3. **Приоритеты рёбер** - нет механизма выбора порядка
4. **Логика слияния** - узел не может ждать все входящие рёбра
5. **Явные стартовые узлы** - определяются автоматически (узлы без входящих рёбер)

### Текущая логика выполнения

```dart
// polymorphic_workflow_runner.dart:196-222
final outgoingEdges = graph.edges.values.where((e) => e.sourceId == node.id).toList();

// Выполнить ВСЕ исходящие рёбра параллельно
final branchFutures = <Future<void>>[];
for (final edge in outgoingEdges) {
  final nextNode = WorkflowNodeFactory.fromJson(nextNodeData.toJson());
  branchFutures.add(_processNode(nextNode, depth + 1, nextContext));
}
await Future.wait(branchFutures);  // ← Всегда параллельно!
```

**Проблемы:**
- Игнорируется `edge.type` (onSuccess/onError)
- Нет проверки результата выполнения узла
- Нет приоритетов
- Нет контроля параллельности

## Требования к улучшениям

### 1. Корневые узлы (Root Nodes)

**Текущее:** Автоматически находятся узлы без входящих рёбер
**Требуется:** Явное указание стартовых узлов

**Решение:**
```dart
// В WorkflowGraph добавить:
final List<String> rootNodeIds;  // Явные стартовые узлы

// Если пусто - использовать текущую логику (узлы без входящих)
```

### 2. Типизация рёбер (Edge Types)

**Текущее:** `WorkflowEdgeType { onSuccess, onError, conditional }`
**Требуется:** Расширенная типизация с контролем выполнения

**Новые свойства ребра:**

```dart
class WorkflowEdge extends $Edge {
  // Существующие
  final WorkflowEdgeType type;  // onSuccess, onError, conditional
  final String? conditionExpression;

  // НОВЫЕ свойства

  /// Приоритет ребра (0-100, по умолчанию 50)
  /// Чем выше - тем раньше выполняется
  final int priority;

  /// Режим выполнения
  final EdgeExecutionMode executionMode;

  /// Ревнивое ребро - блокирует другие исходящие рёбра
  /// По умолчанию true для onSuccess/onError
  final bool isExclusive;
}

enum EdgeExecutionMode {
  /// Последовательное выполнение - ждёт завершения предыдущего
  sequential,

  /// Параллельное выполнение - запускается в отдельном потоке
  parallel,

  /// Отложенное выполнение - ждёт сигнала от других рёбер
  deferred,
}
```

### 3. Логика узла (Node Behavior)

**Требуется:** Узел должен контролировать обработку входящих/исходящих рёбер

**Новые методы в IWorkflowNode:**

```dart
abstract class IWorkflowNode extends $Node {
  // Существующие
  Future<dynamic> execute(RunContext context, ToolRegistry tools);

  // НОВЫЕ методы

  /// Выбор исходящих рёбер после выполнения
  /// Если null - движок использует стандартную логику
  /// Если List<String> - выполняются только указанные рёбра
  List<String>? selectOutgoingEdges(
    List<WorkflowEdge> availableEdges,
    dynamic executionResult,
    RunContext context,
  ) => null;  // По умолчанию - стандартная логика

  /// Стратегия обработки входящих рёбер
  NodeJoinStrategy get joinStrategy => NodeJoinStrategy.firstCome;

  /// Приоритет входящих рёбер (если задан)
  /// Узел будет ждать приоритетное ребро даже если пришли другие
  Map<String, int>? get incomingEdgePriorities => null;
}

enum NodeJoinStrategy {
  /// Первый пришёл - первый обслужился
  firstCome,

  /// Ждать все входящие рёбра (join/merge)
  waitAll,

  /// Ждать любое из приоритетных рёбер
  waitPriority,
}
```

### 4. Механизм выполнения (Execution Logic)

**Новая логика в PolymorphicWorkflowRunner:**

```dart
Future<void> _processNode(IWorkflowNode node, int depth, RunContext context) async {
  // 1. Выполнить узел
  final result = await node.execute(context, _tools);
  final success = result != null && result != false;  // Определить успех

  // 2. Получить исходящие рёбра
  final outgoingEdges = graph.edges.values
      .where((e) => e.sourceId == node.id)
      .toList();

  // 3. Фильтрация по типу ребра (onSuccess/onError)
  final candidateEdges = outgoingEdges.where((edge) {
    switch (edge.type) {
      case WorkflowEdgeType.onSuccess:
        return success;
      case WorkflowEdgeType.onError:
        return !success;
      case WorkflowEdgeType.conditional:
        return _evaluateCondition(edge.conditionExpression, context);
    }
  }).toList();

  // 4. Дать узлу возможность выбрать рёбра
  final selectedEdgeIds = node.selectOutgoingEdges(candidateEdges, result, context);
  final edgesToExecute = selectedEdgeIds != null
      ? candidateEdges.where((e) => selectedEdgeIds.contains(e.id)).toList()
      : candidateEdges;

  // 5. Сортировка по приоритету
  edgesToExecute.sort((a, b) => b.priority.compareTo(a.priority));

  // 6. Выполнение с учётом exclusive и executionMode
  await _executeEdges(edgesToExecute, depth, context);
}

Future<void> _executeEdges(
  List<WorkflowEdge> edges,
  int depth,
  RunContext context,
) async {
  if (edges.isEmpty) return;

  // Группировка по режиму выполнения
  final sequentialEdges = <WorkflowEdge>[];
  final parallelEdges = <WorkflowEdge>[];

  for (final edge in edges) {
    // Проверка exclusive
    if (edge.isExclusive && sequentialEdges.isNotEmpty) {
      // Ревнивое ребро - останавливаем обработку остальных
      break;
    }

    if (edge.executionMode == EdgeExecutionMode.parallel) {
      parallelEdges.add(edge);
    } else {
      sequentialEdges.add(edge);
    }

    // Если встретили exclusive - больше не добавляем
    if (edge.isExclusive) break;
  }

  // Выполнить последовательные рёбра
  for (final edge in sequentialEdges) {
    await _executeEdge(edge, depth, context);
  }

  // Выполнить параллельные рёбра
  if (parallelEdges.isNotEmpty) {
    await Future.wait(
      parallelEdges.map((edge) => _executeEdge(edge, depth, context))
    );
  }
}

Future<void> _executeEdge(
  WorkflowEdge edge,
  int depth,
  RunContext context,
) async {
  final targetNode = graph.nodes[edge.targetId];
  if (targetNode == null) return;

  // Проверить стратегию слияния целевого узла
  final polymorphicTarget = WorkflowNodeFactory.fromJson(targetNode.toJson());

  if (polymorphicTarget.joinStrategy == NodeJoinStrategy.waitAll) {
    // Узел ждёт все входящие рёбра
    final incomingEdges = graph.edges.values
        .where((e) => e.targetId == targetNode.id)
        .toList();

    // Отметить что это ребро пришло
    _markEdgeArrived(edge.id);

    // Проверить все ли рёбра пришли
    final allArrived = incomingEdges.every((e) => _isEdgeArrived(e.id));
    if (!allArrived) {
      _log('⏳ Node ${targetNode.id} waiting for other edges...');
      return;  // Ждём остальные
    }
  }

  // Выполнить целевой узел
  final nextContext = context.cloneForBranch(edge.branchName);
  await _processNode(polymorphicTarget, depth + 1, nextContext as RunContext);
}
```

## План реализации

### Этап 1: Расширение моделей (1-2 часа)

1. **WorkflowEdge** - добавить новые поля:
   - `priority: int` (по умолчанию 50)
   - `executionMode: EdgeExecutionMode` (по умолчанию sequential)
   - `isExclusive: bool` (по умолчанию true для onSuccess/onError)

2. **IWorkflowNode** - добавить новые методы:
   - `selectOutgoingEdges()` - выбор рёбер
   - `joinStrategy` - стратегия слияния
   - `incomingEdgePriorities` - приоритеты входящих

3. **WorkflowGraph** - добавить:
   - `rootNodeIds: List<String>` - явные стартовые узлы

### Этап 2: Обновление движка (2-3 часа)

1. **PolymorphicWorkflowRunner** - переписать `_processNode()`:
   - Определение успеха выполнения узла
   - Фильтрация рёбер по типу (onSuccess/onError)
   - Вызов `node.selectOutgoingEdges()`
   - Сортировка по приоритету
   - Обработка exclusive рёбер
   - Разделение на sequential/parallel

2. Добавить `_executeEdges()` и `_executeEdge()`

3. Добавить механизм отслеживания прибытия рёбер для `waitAll`

### Этап 3: Обновление тестов (1-2 часа)

1. Обновить стресс-тесты:
   - Тест на onSuccess/onError ветвление
   - Тест на приоритеты рёбер
   - Тест на exclusive рёбра
   - Тест на waitAll стратегию

2. Создать новые тесты:
   - Параллельное vs последовательное выполнение
   - Выбор рёбер узлом
   - Приоритеты входящих рёбер

### Этап 4: Документация (30 минут)

1. Обновить GRAPH_ENGINE_GUIDE.md
2. Добавить примеры использования новых возможностей
3. Обновить STRESS_TEST_REPORT.md

## Оценка сложности

**Общее время:** 5-8 часов

**Риски:**
- Обратная совместимость - старые графы должны работать
- Производительность - не замедлить выполнение
- Тестирование - нужно покрыть все комбинации

**Приоритеты:**
1. **Высокий:** onSuccess/onError ветвление (критично для production)
2. **Высокий:** Приоритеты рёбер (нужно для сложных сценариев)
3. **Средний:** Exclusive рёбра (можно эмулировать через приоритеты)
4. **Средний:** waitAll стратегия (нужно для join паттернов)
5. **Низкий:** Явные root узлы (текущая логика работает)

## Следующие шаги

1. **Обсудить с пользователем** - согласовать приоритеты и подход
2. **Начать с Этапа 1** - расширить модели
3. **Написать тесты** - TDD подход для новой логики
4. **Реализовать Этап 2** - обновить движок
5. **Проверить обратную совместимость** - старые тесты должны проходить

## Вопросы для обсуждения

1. Нужны ли явные `rootNodeIds` или текущая логика достаточна?
2. Какие приоритеты: onSuccess/onError, приоритеты, exclusive, waitAll?
3. Начинать с TDD (тесты → реализация) или сразу реализовывать?
4. Нужна ли обратная совместимость со старыми графами?
