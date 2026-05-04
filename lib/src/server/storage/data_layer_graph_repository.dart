// Реализация IGraphRepository через IDataLayer.instance (из aq_schema).
// Конвертирует deprecated WorkflowGraph → TypedWorkflowGraph при загрузке.

import 'package:aq_schema/aq_schema.dart';
import 'package:aq_schema/graph/nodes/base/i_workflow_node.dart';
import 'package:aq_schema/graph/engine/i_graph_repository.dart';
import '../registry/node_type_registry.dart';

final class DataLayerGraphRepository implements IGraphRepository {
  DataLayerGraphRepository();

  // Lazy singleton — создаётся один раз при первом обращении
  static NodeTypeRegistry? _registry;
  static NodeTypeRegistry get _defaultRegistry =>
      _registry ??= buildDefaultRegistry();

  VersionedRepository<InstructionGraph> get _instructions =>
      IDataLayer.instance.versioned<InstructionGraph>(
        collection: InstructionGraph.kCollection,
        fromMap: InstructionGraph.fromMap,
      );

  VersionedRepository<PromptGraph> get _prompts =>
      IDataLayer.instance.versioned<PromptGraph>(
        collection: PromptGraph.kCollection,
        fromMap: PromptGraph.fromMap,
      );

  @override
  Future<$Graph?> loadGraph(String blueprintId) async {
    // TypedWorkflowGraph — приоритет (новый формат)
    final typed = IDataLayer.instance.versioned<TypedWorkflowGraph>(
      collection: TypedWorkflowGraph.kCollection,
      fromMap: (m) => TypedWorkflowGraph.fromMap(m, _defaultRegistry),
    );
    $Graph? graph = await typed.getCurrent(blueprintId);
    graph ??= await typed.getVersion(blueprintId);
    if (graph != null) return graph;

    // WorkflowGraph (deprecated) — конвертируем при загрузке
    final legacy = IDataLayer.instance.versioned<WorkflowGraph>( // ignore: deprecated_member_use
      collection: WorkflowGraph.kCollection, // ignore: deprecated_member_use
      fromMap: WorkflowGraph.fromMap, // ignore: deprecated_member_use
    );
    final legacyGraph = await legacy.getCurrent(blueprintId) // ignore: deprecated_member_use
        ?? await legacy.getVersion(blueprintId); // ignore: deprecated_member_use
    if (legacyGraph != null) {
      return _convertToTyped(legacyGraph as WorkflowGraph); // ignore: deprecated_member_use
    }

    graph = await _instructions.getCurrent(blueprintId);
    graph ??= await _instructions.getVersion(blueprintId);
    if (graph != null) return graph;

    graph = await _prompts.getCurrent(blueprintId);
    graph ??= await _prompts.getVersion(blueprintId);
    return graph;
  }

  TypedWorkflowGraph _convertToTyped(WorkflowGraph graph) { // ignore: deprecated_member_use
    final nodes = <String, IWorkflowNode>{};
    for (final entry in graph.nodes.entries) {
      try {
        nodes[entry.key] = _defaultRegistry.workflowFromJson(entry.value.toJson());
      } catch (_) {
        // Пропускаем узлы неизвестного типа
      }
    }
    return TypedWorkflowGraph(
      id: graph.id,
      tenantId: graph.tenantId,
      ownerId: graph.ownerId,
      name: graph.name,
      nodes: nodes,
      edges: graph.edges,
    );
  }
}
