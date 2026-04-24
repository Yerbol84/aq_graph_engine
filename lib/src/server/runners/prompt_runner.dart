// PromptRunner — компилятор PromptGraph в текстовый промпт

import 'package:aq_schema/aq_schema.dart';
import '../../interfaces/i_graph_repository.dart';
import '../../shared/logger.dart';

// Импорт узлов PromptGraph из aq_schema
import 'package:aq_schema/graph/nodes/prompt/text_block_node.dart';
import 'package:aq_schema/graph/nodes/prompt/conditional_block_node.dart';
import 'package:aq_schema/graph/nodes/prompt/variable_insert_node.dart';

/// Runner для компиляции PromptGraph в текстовый промпт
///
/// PromptGraph содержит узлы (textBlock, conditionalBlock, variableInsert),
/// которые компилируются в финальный текст промпта с подстановкой переменных.
class PromptRunner {
  final IGraphRepository graphRepo;

  PromptRunner({required this.graphRepo});

  /// Скомпилировать PromptGraph в текстовый промпт
  ///
  /// [promptGraphId] - ID PromptGraph для компиляции
  /// [context] - контекст с переменными для подстановки
  ///
  /// Возвращает скомпилированный текст промпта
  Future<String> compile(String promptGraphId, RunContext context) async {
    graphEngineServerLogger.fine('Compiling PromptGraph: $promptGraphId');

    // 1. Загрузить граф
    final graph = await graphRepo.loadGraph(promptGraphId);
    if (graph == null) {
      graphEngineServerLogger.warning('PromptGraph not found: $promptGraphId');
      throw Exception('PromptGraph not found: $promptGraphId');
    }

    if (graph is! PromptGraph) {
      graphEngineServerLogger.warning(
        'Graph $promptGraphId is not a PromptGraph (type: ${graph.runtimeType})',
      );
      throw Exception('Graph $promptGraphId is not a PromptGraph');
    }

    // 2. Получить узлы в порядке выполнения
    final orderedNodes = _getExecutionOrder(graph);

    graphEngineServerLogger.fine(
      'Compiling ${orderedNodes.length} nodes in PromptGraph $promptGraphId',
    );

    // 3. Выполнить каждый узел и собрать результаты
    final parts = <String>[];
    for (final nodeId in orderedNodes) {
      final node = graph.nodes[nodeId];
      if (node == null) continue;

      try {
        // Получить IPromptNode из PromptNode
        final promptNode = _createPromptNode(node);
        if (promptNode == null) {
          graphEngineServerLogger.warning(
            'Unknown prompt node type: ${node.type}',
          );
          continue;
        }

        // Выполнить узел - получить часть промпта
        final part = await promptNode.execute(context);
        if (part.isNotEmpty) {
          parts.add(part);
        }
      } catch (e, stack) {
        graphEngineServerLogger.severe(
          'Error executing prompt node $nodeId: $e',
          e,
          stack,
        );
        // Продолжаем компиляцию, пропуская проблемный узел
      }
    }

    // 4. Склеить части с двойным переносом строки
    final compiledPrompt = parts.join('\n\n').trim();

    graphEngineServerLogger.info(
      'PromptGraph $promptGraphId compiled: ${compiledPrompt.length} chars',
    );

    return compiledPrompt;
  }

  /// Получить порядок выполнения узлов
  ///
  /// Если есть рёбра - топологическая сортировка
  /// Если нет рёбер - порядок добавления узлов
  List<String> _getExecutionOrder(PromptGraph graph) {
    if (graph.edges.isEmpty) {
      // Нет рёбер - возвращаем узлы в порядке добавления
      return graph.nodes.keys.toList();
    }

    // Есть рёбра - топологическая сортировка
    return _topologicalSort(graph);
  }

  /// Топологическая сортировка узлов графа
  List<String> _topologicalSort(PromptGraph graph) {
    final result = <String>[];
    final visited = <String>{};
    final visiting = <String>{};

    void visit(String nodeId) {
      if (visited.contains(nodeId)) return;
      if (visiting.contains(nodeId)) {
        // Цикл обнаружен - игнорируем
        graphEngineServerLogger.warning(
          'Cycle detected in PromptGraph at node $nodeId',
        );
        return;
      }

      visiting.add(nodeId);

      // Посетить все исходящие рёбра
      for (final edge in graph.edges.values) {
        if (edge.sourceId == nodeId) {
          visit(edge.targetId);
        }
      }

      visiting.remove(nodeId);
      visited.add(nodeId);
      result.add(nodeId);
    }

    // Найти корневые узлы (без входящих рёбер)
    final hasIncoming = <String>{};
    for (final edge in graph.edges.values) {
      hasIncoming.add(edge.targetId);
    }

    final roots = graph.nodes.keys.where((id) => !hasIncoming.contains(id));

    // Обойти от корней
    for (final root in roots) {
      visit(root);
    }

    // Добавить узлы без рёбер
    for (final nodeId in graph.nodes.keys) {
      if (!visited.contains(nodeId)) {
        result.add(nodeId);
      }
    }

    return result.reversed.toList(); // Обратный порядок для топологической сортировки
  }

  /// Создать IPromptNode из PromptNode
  TextBlockNode? _createPromptNode(PromptNode node) {
    final data = node.data;

    switch (node.type) {
      case PromptNodeType.textBlock:
        return TextBlockNode(
          id: node.id,
          text: data['content'] as String? ?? data['text'] as String? ?? '',
        );

      case PromptNodeType.variable:
        // Узел variable только документирует переменные, не влияет на компиляцию
        return null;

      case PromptNodeType.fileContext:
        // TODO: Реализовать когда понадобится
        graphEngineServerLogger.warning(
          'fileContext node type not yet implemented',
        );
        return null;

      default:
        return null;
    }
  }
}
