// Runner для выполнения InstructionGraph с полиморфными узлами

import 'dart:async';
import 'package:aq_schema/aq_schema.dart';
import 'package:aq_schema/graph/nodes/base/i_instruction_node.dart';
import 'package:aq_schema/graph/engine/i_graph_repository.dart';
import '../factories/instruction_node_factory.dart';

/// Исключение при превышении максимального количества шагов в инструкции
class InstructionMaxStepsException implements Exception {
  final String instructionId;
  final int maxSteps;

  InstructionMaxStepsException(this.instructionId, this.maxSteps);

  @override
  String toString() =>
      'InstructionMaxStepsException: инструкция $instructionId превысила лимит $maxSteps шагов. '
      'Возможно, в графе есть бесконечный цикл.';
}

/// Runner для выполнения InstructionGraph
///
/// InstructionGraph выполняется как функция:
/// - Полностью без пауз (нет suspend/resume)
/// - В изолированном контексте
/// - Принимает входные данные через context
/// - Возвращает результат через context
class InstructionRunner {
  final IGraphRepository graphRepo;
  final int maxSteps;

  InstructionRunner({
    required this.graphRepo,
    this.maxSteps = 50,
  });

  /// Выполнить инструкцию
  ///
  /// [instructionId] - ID InstructionGraph для загрузки
  /// [context] - изолированный контекст с входными данными
  ///
  /// Возвращает контекст с результатами выполнения
  Future<RunContext> execute(
    String instructionId,
    RunContext context,
  ) async {
    context.log(
      'Starting instruction: $instructionId',
      branch: context.currentBranch,
    );

    // Загрузить InstructionGraph
    final graph = await graphRepo.loadGraph(instructionId);
    if (graph == null) {
      throw Exception('InstructionRunner: graph $instructionId not found');
    }

    if (graph is! InstructionGraph) {
      throw Exception(
        'InstructionRunner: graph $instructionId is not an InstructionGraph',
      );
    }

    // Проверить project isolation
    if (graph.ownerId != context.projectId) {
      throw Exception(
        'InstructionRunner: graph $instructionId does not belong to project ${context.projectId}',
      );
    }

    // Найти стартовый узел
    final allTargetIds = graph.edges.values.map((e) => e.targetId).toSet();
    final startNodes =
        graph.nodes.values.where((n) => !allTargetIds.contains(n.id)).toList();

    if (startNodes.isEmpty) {
      throw Exception(
          'InstructionRunner: no start node found in graph $instructionId');
    }

    final firstNode = startNodes.first;
    context.log(
      'Instruction start node: ${firstNode.id}',
      branch: context.currentBranch,
    );

    // Конвертировать в полиморфный узел
    final polymorphicNode = InstructionNodeFactory.fromJson(firstNode.toJson());

    // Выполнить граф с начальным шагом 0
    await _processNode(polymorphicNode, graph, context, 0);

    context.log(
      'Instruction completed: $instructionId',
      branch: context.currentBranch,
    );

    return context;
  }

  Future<void> _processNode(
    IInstructionNode node,
    InstructionGraph graph,
    RunContext context,
    int step,
  ) async {
    // Проверка на превышение максимального количества шагов
    if (step >= maxSteps) {
      throw InstructionMaxStepsException(graph.id, maxSteps);
    }

    context.log(
      'Executing instruction node: ${node.nodeType} [${node.id}] (step $step)',
      branch: context.currentBranch,
    );

    // Выполнить узел - полиморфизм вместо switch
    await node.execute(context);

    // Найти следующие узлы
    final outgoingEdges =
        graph.edges.values.where((e) => e.sourceId == node.id).toList();

    if (outgoingEdges.isEmpty) {
      // Конечный узел
      return;
    }

    // Выполнить следующие узлы
    for (final edge in outgoingEdges) {
      final nextNodeData = graph.nodes[edge.targetId];
      if (nextNodeData != null) {
        // Конвертировать в полиморфный узел
        final nextNode = InstructionNodeFactory.fromJson(nextNodeData.toJson());
        await _processNode(nextNode, graph, context, step + 1);
      }
    }
  }
}
