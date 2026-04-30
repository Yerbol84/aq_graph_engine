// Полиморфный WorkflowRunner - единственная реализация
// Поддерживает все типы узлов включая интерактивные (suspend/resume)

import 'dart:async';
import 'dart:convert';
import 'package:aq_schema/aq_schema.dart';
import 'package:aq_schema/tools.dart';
import 'package:aq_schema/graph/nodes/base/i_workflow_node.dart';
import 'package:aq_schema/graph/nodes/base/composite_node.dart';
import 'package:aq_schema/graph/nodes/base/interactive_node.dart';
import '../../interfaces/i_run_repository.dart';
import '../../interfaces/i_graph_repository.dart';
import '../engine/condition_evaluator.dart';
import '../monitoring/metrics.dart';
/// WorkflowRunner — исполнитель WorkflowGraph.
///
/// Поддерживает:
/// - Автоматические узлы (execute без пауз)
/// - Интерактивные узлы (suspend/resume)
/// - Композитные узлы (SubGraph, RunInstruction)
class WorkflowRunner {
  final String runId;
  final String projectId;
  final String projectPath;
  final TypedWorkflowGraph graph;
  final IRunRepository _repo;
  // Будут использоваться при реализации выполнения узлов (LLM, FileRead и т.д.)
  // ignore: unused_field
  final IGraphRepository _graphRepo;
  // ignore: unused_field
  final IToolService _tools;

  final List<String> _logs = [];
  final Set<String> _visitedEdges = {};

  /// Отслеживание прибытия рёбер к узлам для joinStrategy.waitAll
  final Map<String, Set<String>> _arrivedEdges = {};

  WorkflowRunner({
    required this.runId,
    required this.projectId,
    required this.projectPath,
    required this.graph,
    required IRunRepository repo,
    required IGraphRepository graphRepo,
    required IToolService tools,
  })  : _repo = repo,
        _graphRepo = graphRepo,
        _tools = tools;

  Future<void> start({
    String? startNodeId,
    String? restoredStateJson,
    Map<String, dynamic>? injectedVariables,
  }) async {
    // Метрики: запуск начат
    GraphEngineMetrics.runStarted.inc(attributes: {
      'project_id': projectId,
      'blueprint_id': graph.id,
    });
    GraphEngineMetrics.activeRuns.inc();
    final runTimer = GraphEngineMetrics.runDuration.start(attributes: {
      'project_id': projectId,
      'blueprint_id': graph.id,
    });

    _visitedEdges.clear();

    if (restoredStateJson == null) {
      _log('🚀 Run Started (ID: ${runId.substring(0, 6)})');
    } else {
      _log('⚡ Run Resumed from node [${startNodeId?.substring(0, 4)}]');
      // Восстановить логи из сохранённого состояния
      final savedRun = await _repo.getRun(runId);
      if (savedRun != null) {
        _logs.clear();
        final rawLogs = jsonDecode(savedRun['logsJson'] as String? ?? '[]') as List;
        _logs.addAll(rawLogs.map((e) => e.toString()));
      }
    }

    try {
      // Найти стартовый узел
      final allTargetIds = graph.edges.values.map((e) => e.targetId).toSet();
      final startNodes = graph.nodes.values
          .where((n) => !allTargetIds.contains(n.id))
          .toList();

      _log('📊 Graph has ${graph.nodes.length} nodes, ${graph.edges.length} edges');
      _log('🎯 Start nodes found: ${startNodes.length}');

      // Создать или восстановить контекст
      RunContext context;
      if (restoredStateJson != null) {
        final parsedState = jsonDecode(restoredStateJson) as Map<String, dynamic>;
        if (parsedState.containsKey('user_context')) {
          context = RunContext.fromJson(
            parsedState['user_context'] as Map<String, dynamic>,
            (String message, {String type = 'info', int depth = 0, required String branch, String? details}) {
              _log(message);
            },
          );
          final engineState = parsedState['engine_state'] as Map<String, dynamic>?;
          if (engineState?['visited_edges'] != null) {
            _visitedEdges.addAll(List<String>.from(engineState!['visited_edges'] as List));
          }
        } else {
          context = RunContext.fromJson(
            parsedState,
            (String message, {String type = 'info', int depth = 0, required String branch, String? details}) {
              _log(message);
            },
          );
        }
        if (injectedVariables != null) {
          context.state.addAll(injectedVariables);
          _log('💉 User Input received and injected.');
        }
      } else {
        context = RunContext(
          runId: runId,
          projectId: projectId,
          projectPath: projectPath,
          log: (String message, {String type = 'info', int depth = 0, required String branch, String? details}) {
            _log(message);
          },
          currentBranch: 'main',
        );
        if (injectedVariables != null) {
          _log('💉 Injecting ${injectedVariables.length} variables');
          for (final entry in injectedVariables.entries) {
            context.setVar(entry.key, entry.value);
          }
        }
      }

      // Выполнить стартовые узлы
      if (startNodeId != null) {
        // Resume - выполнить конкретный узел
        final resumeNode = graph.nodes[startNodeId];
        if (resumeNode == null) {
          _log('⚠️ Warning: Resume node not found: $startNodeId');
          await _repo.updateRunLog(runId, _logs, status: 'failed');
          return;
        }

        _log('✅ Resuming from node: ${resumeNode.id} (type: ${resumeNode.nodeType})');
        await _processNode(resumeNode, 0, context);
      } else {
        // Новый запуск - выполнить все стартовые узлы
        if (startNodes.isEmpty) {
          _log('⚠️ Warning: No valid starting nodes found.');
          await _repo.updateRunLog(runId, _logs, status: 'failed');
          return;
        }

        if (startNodes.length == 1) {
          final node = startNodes.first;
          _log('✅ Starting from node: ${node.id} (type: ${node.nodeType})');
          await _processNode(node, 0, context);
        } else {
          _log('⚡ Starting ${startNodes.length} nodes in parallel');
          await Future.wait(
            startNodes.map((node) async {
              _log('✅ Starting node: ${node.id} (type: ${node.nodeType})');
              await _processNode(node, 0, context);
            }),
          );
        }
      }

      _log('🏁 Run Completed!');
      await _repo.updateRunLog(runId, _logs, status: 'completed');

      // Метрики: успешное завершение
      runTimer.stop(attributes: {'status': 'completed'});
      GraphEngineMetrics.runCompleted.inc(attributes: {
        'project_id': projectId,
        'blueprint_id': graph.id,
      });
      GraphEngineMetrics.activeRuns.dec();
    } catch (e, stack) {
      _log('❌ CRITICAL ERROR: $e');
      _log('Stack trace: $stack');
      print('Stack trace: $stack');
      await _repo.updateRunLog(runId, _logs, status: 'failed');

      // Метрики: ошибка
      runTimer.stop(attributes: {'status': 'failed'});
      GraphEngineMetrics.runFailed.inc(attributes: {
        'project_id': projectId,
        'blueprint_id': graph.id,
        'error_type': e.runtimeType.toString(),
      });
      GraphEngineMetrics.activeRuns.dec();
    }
  }

  Future<void> _processNode(
    IWorkflowNode node,
    int depth,
    RunContext context,
  ) async {
    _log('▶ Executing: ${node.nodeType} [${node.id.substring(0, 4)}]');

    // Метрики: начало выполнения узла
    final nodeTimer = GraphEngineMetrics.nodeDuration.start(attributes: {
      'node_type': node.nodeType,
      'project_id': projectId,
    });
    GraphEngineMetrics.nodeExecuted.inc(attributes: {
      'node_type': node.nodeType,
      'project_id': projectId,
    });

    dynamic result;
    bool success = true;

    try {
      // Выполняем узел с retry механизмом
      result = await _executeNodeWithRetry(node, context);

      // Метрики: узел выполнен успешно
      nodeTimer.stop(attributes: {'status': 'ok'});

      // Обработка CompositeNode (SubGraph, RunInstruction)
      if (node is CompositeNode && result is RunContext) {
        _log('🔄 Composite node executed, applying output mapping');
        node.applyOutputMapping(result, context);
      }

      await _repo.updateRunLog(runId, _logs);
    } on SuspendExecutionException catch (e) {
      // Интерактивный узел требует ввода пользователя
      _log('⏸️ Execution suspended: ${e.reason}');

      // Метрика suspended
      GraphEngineMetrics.runSuspended.inc(attributes: {
        'project_id': projectId,
        'blueprint_id': graph.id,
      });

      // Сохранить состояние для resume
      final snapshotPayload = {
        'user_context': context.toJson(),
        'engine_state': {
          'visited_edges': _visitedEdges.toList(),
          'suspended_node_id': node.id,
        }
      };

      await _repo.suspendRun(
        runId: runId,
        contextJson: jsonEncode(snapshotPayload),
        nodeId: node.id,
        logs: _logs,
      );
      await _repo.updateRunLog(runId, _logs, status: 'suspended');
      return;
    } catch (e) {
      _log('❌ Node Error: $e');
      success = false;
      await _repo.updateRunLog(runId, _logs, status: 'failed');
      // НЕ возвращаемся - продолжаем обработку onError рёбер
    }

    // Проверить не suspended ли run (может быть изменён извне)
    final currentRun = await _repo.getRun(runId);
    if (currentRun?['status'] == 'suspended') return;

    // ═══════════════════════════════════════════════════════════════════════════
    // НОВАЯ ЛОГИКА: Фильтрация и выполнение рёбер
    // ═══════════════════════════════════════════════════════════════════════════

    // 1. Получить все исходящие рёбра
    final allOutgoingEdges =
        graph.edges.values.where((e) => e.sourceId == node.id).toList();

    if (allOutgoingEdges.isEmpty) {
      // Конечный узел - завершаем
      return;
    }

    // 2. Фильтрация по типу ребра (onSuccess/onError/conditional)
    final candidateEdges = allOutgoingEdges.where((edge) {
      switch (edge.type) {
        case WorkflowEdgeType.onSuccess:
          return success;
        case WorkflowEdgeType.onError:
          return !success;
        case WorkflowEdgeType.conditional:
          // Вычислить условное выражение
          if (edge.conditionExpression != null && edge.conditionExpression!.isNotEmpty) {
            try {
              return ConditionEvaluator.evaluate(edge.conditionExpression!, context.state);
            } catch (e) {
              _log('⚠️ Condition evaluation error for edge ${edge.id}: $e');
              return false; // При ошибке вычисления — ребро не проходит
            }
          }
          return true; // Если нет выражения — пропускаем
      }
    }).toList();

    if (candidateEdges.isEmpty) {
      _log('⚠️ No matching edges for node result (success=$success)');
      return;
    }

    // 3. Дать узлу возможность выбрать рёбра
    final selectedEdgeIds = node.selectOutgoingEdges(candidateEdges, result);
    final edgesToExecute = selectedEdgeIds != null
        ? candidateEdges.where((e) => selectedEdgeIds.contains(e.id)).toList()
        : candidateEdges;

    if (edgesToExecute.isEmpty) {
      _log('⚠️ Node selected no edges to execute');
      return;
    }

    // 4. Сортировка по приоритету (выше приоритет = раньше выполняется)
    edgesToExecute.sort((a, b) => b.priority.compareTo(a.priority));

    // 5. Выполнение с учётом exclusive и executionMode
    await _executeEdges(edgesToExecute, depth, context);

    // Проверить статус после выполнения веток
    final checkRun = await _repo.getRun(runId);
    if (checkRun?['status'] != 'suspended') {
      await _repo.updateRunLog(runId, _logs, status: 'running');
    }
  }

  /// Выполнить список рёбер с учётом приоритетов, exclusive и executionMode
  Future<void> _executeEdges(
    List<WorkflowEdge> edges,
    int depth,
    RunContext context,
  ) async {
    if (edges.isEmpty) return;

    final sequentialEdges = <WorkflowEdge>[];
    final parallelEdges = <WorkflowEdge>[];

    for (final edge in edges) {
      // Проверка exclusive - ревнивое ребро блокирует остальные
      if (edge.isExclusive && sequentialEdges.isNotEmpty) {
        _log('🚫 Exclusive edge ${edge.id.substring(0, 4)} blocks remaining edges');
        break;
      }

      // Группировка по режиму выполнения
      if (edge.executionMode == EdgeExecutionMode.parallel) {
        parallelEdges.add(edge);
      } else {
        sequentialEdges.add(edge);
      }

      // Если встретили exclusive - больше не добавляем
      if (edge.isExclusive) {
        _log('🔒 Exclusive edge ${edge.id.substring(0, 4)} - stopping edge processing');
        break;
      }
    }

    // Выполнить последовательные рёбра
    for (final edge in sequentialEdges) {
      await _executeEdge(edge, depth, context);
    }

    // Выполнить параллельные рёбра
    if (parallelEdges.isNotEmpty) {
      _log('⚡ Executing ${parallelEdges.length} edges in parallel');
      await Future.wait(
        parallelEdges.map((edge) => _executeEdge(edge, depth, context)),
      );
    }
  }

  /// Выполнить одно ребро
  Future<void> _executeEdge(
    WorkflowEdge edge,
    int depth,
    RunContext context,
  ) async {
    _visitedEdges.add(edge.id);
    final nextNodeData = graph.nodes[edge.targetId];
    if (nextNodeData == null) {
      _log('⚠️ Target node ${edge.targetId} not found');
      return;
    }

    final nextBranchName = edge.branchName;
    final nextContext = context.cloneForBranch(nextBranchName);

    _log('→ Transmitting to [$nextBranchName]...');

    // Узел уже IWorkflowNode — конвертация не нужна
    final nextNode = nextNodeData;

    // Отметить прибытие ребра к целевому узлу
    _arrivedEdges.putIfAbsent(edge.targetId, () => {}).add(edge.id);

    // Проверить joinStrategy целевого узла
    if (nextNode.joinStrategy == NodeJoinStrategy.waitAll) {
      // Получить все входящие рёбра для этого узла
      final incomingEdges = graph.edges.values
          .where((e) => e.targetId == edge.targetId)
          .toList();

      // Проверить пришли ли все рёбра
      final arrivedSet = _arrivedEdges[edge.targetId] ?? {};
      final allArrived = incomingEdges.every((e) => arrivedSet.contains(e.id));

      if (!allArrived) {
        final remaining = incomingEdges.length - arrivedSet.length;
        _log('⏳ Node [${edge.targetId.substring(0, 4)}] waiting for $remaining more edge(s)');
        return; // Не выполняем узел пока не пришли все рёбра
      }

      _log('✅ All ${incomingEdges.length} edges arrived at [${edge.targetId.substring(0, 4)}]');
    }

    await _processNode(nextNode, depth + 1, nextContext);
  }

  /// Выполнить узел с retry механизмом
  Future<dynamic> _executeNodeWithRetry(
    IWorkflowNode node,
    RunContext context,
  ) async {
    final maxRetries = node.maxRetries;
    var attempt = 0;
    var delayMs = node.retryDelayMs;

    while (true) {
      try {
        // Попытка выполнения
        return await node.execute(context);
      } catch (e) {
        attempt++;

        // Проверить нужно ли делать retry для этой ошибки
        final shouldRetry = _shouldRetryError(node, e);

        if (!shouldRetry || attempt > maxRetries) {
          // Больше не пытаемся - пробрасываем ошибку
          if (attempt > 1) {
            _log('❌ Failed after $attempt attempts: $e');
          }
          rethrow;
        }

        // Логируем retry
        _log('⚠️  Attempt $attempt failed: $e');
        _log('🔄 Retrying in ${delayMs}ms... (${maxRetries - attempt} attempts left)');

        // Метрика retry
        GraphEngineMetrics.nodeRetried.inc(attributes: {
          'node_type': node.nodeType,
          'project_id': projectId,
          'attempt': attempt.toString(),
        });

        // Ждём перед следующей попыткой
        await Future.delayed(Duration(milliseconds: delayMs));

        // Экспоненциальный backoff
        if (node.useExponentialBackoff) {
          delayMs *= 2;
        }
      }
    }
  }

  /// Проверить нужно ли делать retry для данной ошибки
  bool _shouldRetryError(IWorkflowNode node, Object error) {
    // Если список retryableExceptions не задан - retry для всех ошибок
    final retryableTypes = node.retryableExceptions;
    if (retryableTypes == null) return true;

    // Проверить входит ли тип ошибки в список
    return retryableTypes.any((type) => error.runtimeType == type);
  }

  void _log(String message) {
    final timestamp = DateTime.now().toString().substring(11, 19);
    final entry = '[$timestamp] $message';
    _logs.add(entry);
    print(entry);
  }
}
