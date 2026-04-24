import 'package:test/test.dart';
import 'package:aq_graph_engine/aq_graph_engine.dart';
import 'package:aq_graph_engine/server.dart';
import 'package:aq_tool_service/aq_tool_service.dart';
import 'package:aq_schema/aq_schema.dart';

void main() {
  late MockToolService mockTools;

  setUp(() {
    // Инициализировать mock tool service
    mockTools = MockToolService();
    AQToolService.init(mockTools);
  });

  tearDown(() {
    AQToolService.reset();
  });

  group('Client-Server Integration', () {
    test('должен выполнить простой workflow через LocalEngineTransport', () async {
      // Настроить mock ответы
      mockTools.setResponse('llm', {
        'content': 'Hello from LLM',
        'model': 'claude-sonnet-4',
      });

      // Создать in-memory репозитории
      final runRepo = InMemoryRunRepository();
      final graphRepo = InMemoryGraphRepository();

      // Создать простой workflow
      final workflow = WorkflowGraph(
        id: 'test-workflow',
        name: 'Test Workflow',
        nodes: [
          WorkflowNode(
            id: 'start',
            type: WorkflowNodeType.start,
            label: 'Start',
          ),
          WorkflowNode(
            id: 'llm-node',
            type: WorkflowNodeType.llmAction,
            label: 'LLM Action',
            config: {
              'prompt': 'Say hello',
            },
          ),
          WorkflowNode(
            id: 'end',
            type: WorkflowNodeType.end,
            label: 'End',
          ),
        ],
        edges: [
          WorkflowEdge(
            id: 'e1',
            from: 'start',
            to: 'llm-node',
            type: WorkflowEdgeType.always,
          ),
          WorkflowEdge(
            id: 'e2',
            from: 'llm-node',
            to: 'end',
            type: WorkflowEdgeType.onSuccess,
          ),
        ],
      );

      await graphRepo.save(workflow);

      // Создать серверный движок
      final engine = GraphEngine(
        runRepo: runRepo,
        graphRepo: graphRepo,
        nodeRegistry: NodeTypeRegistry(),
      );

      // Создать локальный транспорт
      final transport = LocalEngineTransport(engine: engine);

      // Создать клиента
      final client = GraphEngineClient(transport: transport);

      // Запустить workflow
      final request = GraphRunRequest(
        runId: 'test-run-1',
        blueprintId: 'test-workflow',
        userId: 'test-user',
      );

      final events = <GraphRunEvent>[];
      final stream = client.run(request);

      await for (final event in stream) {
        events.add(event);
        if (event.type == GraphRunEventType.completed ||
            event.type == GraphRunEventType.failed) {
          break;
        }
      }

      // Проверить результаты
      expect(events, isNotEmpty);
      expect(events.last.type, equals(GraphRunEventType.completed));
    });

    test('должен обработать ошибку выполнения', () async {
      // Настроить mock для возврата ошибки
      mockTools.setResponse('llm', null); // Нет ответа

      final runRepo = InMemoryRunRepository();
      final graphRepo = InMemoryGraphRepository();

      final workflow = WorkflowGraph(
        id: 'error-workflow',
        name: 'Error Workflow',
        nodes: [
          WorkflowNode(
            id: 'start',
            type: WorkflowNodeType.start,
            label: 'Start',
          ),
          WorkflowNode(
            id: 'llm-node',
            type: WorkflowNodeType.llmAction,
            label: 'LLM Action',
            config: {'prompt': 'Test'},
          ),
        ],
        edges: [
          WorkflowEdge(
            id: 'e1',
            from: 'start',
            to: 'llm-node',
            type: WorkflowEdgeType.always,
          ),
        ],
      );

      await graphRepo.save(workflow);

      final engine = GraphEngine(
        runRepo: runRepo,
        graphRepo: graphRepo,
        nodeRegistry: NodeTypeRegistry(),
      );

      final transport = LocalEngineTransport(engine: engine);
      final client = GraphEngineClient(transport: transport);

      final request = GraphRunRequest(
        runId: 'test-run-2',
        blueprintId: 'error-workflow',
        userId: 'test-user',
      );

      final events = <GraphRunEvent>[];
      final stream = client.run(request);

      await for (final event in stream) {
        events.add(event);
        if (event.type == GraphRunEventType.failed) {
          break;
        }
      }

      // Проверить что получили событие ошибки
      expect(events.any((e) => e.type == GraphRunEventType.failed), isTrue);
    });

    test('должен поддерживать suspend/resume', () async {
      mockTools.setResponse('llm', {'content': 'Response'});

      final runRepo = InMemoryRunRepository();
      final graphRepo = InMemoryGraphRepository();

      final workflow = WorkflowGraph(
        id: 'suspend-workflow',
        name: 'Suspend Workflow',
        nodes: [
          WorkflowNode(
            id: 'start',
            type: WorkflowNodeType.start,
            label: 'Start',
          ),
          WorkflowNode(
            id: 'input',
            type: WorkflowNodeType.userInput,
            label: 'User Input',
            config: {
              'prompt': 'Enter your name',
            },
          ),
          WorkflowNode(
            id: 'end',
            type: WorkflowNodeType.end,
            label: 'End',
          ),
        ],
        edges: [
          WorkflowEdge(
            id: 'e1',
            from: 'start',
            to: 'input',
            type: WorkflowEdgeType.always,
          ),
          WorkflowEdge(
            id: 'e2',
            from: 'input',
            to: 'end',
            type: WorkflowEdgeType.always,
          ),
        ],
      );

      await graphRepo.save(workflow);

      final engine = GraphEngine(
        runRepo: runRepo,
        graphRepo: graphRepo,
        nodeRegistry: NodeTypeRegistry(),
      );

      final transport = LocalEngineTransport(engine: engine);
      final client = GraphEngineClient(transport: transport);

      // Запустить workflow
      final request = GraphRunRequest(
        runId: 'test-run-3',
        blueprintId: 'suspend-workflow',
        userId: 'test-user',
      );

      final events = <GraphRunEvent>[];
      final stream = client.run(request);

      await for (final event in stream) {
        events.add(event);
        if (event.type == GraphRunEventType.suspended) {
          // Отправить ответ пользователя
          await client.resume(
            'test-run-3',
            UserInputResponse(
              nodeId: 'input',
              value: 'John Doe',
            ),
          );
        }
        if (event.type == GraphRunEventType.completed) {
          break;
        }
      }

      // Проверить что workflow завершился
      expect(events.any((e) => e.type == GraphRunEventType.suspended), isTrue);
      expect(events.last.type, equals(GraphRunEventType.completed));
    });
  });
}

/// In-memory реализация IRunRepository для тестов
class InMemoryRunRepository implements IRunRepository {
  final Map<String, GraphRun> _runs = {};

  @override
  Future<GraphRun?> get(String runId) async => _runs[runId];

  @override
  Future<void> save(GraphRun run) async {
    _runs[run.id] = run;
  }

  @override
  Future<void> delete(String runId) async {
    _runs.remove(runId);
  }

  @override
  Future<List<GraphRun>> list({int? limit, int? offset}) async {
    return _runs.values.toList();
  }
}

/// In-memory реализация IGraphRepository для тестов
class InMemoryGraphRepository implements IGraphRepository {
  final Map<String, WorkflowGraph> _graphs = {};

  @override
  Future<WorkflowGraph?> get(String id) async => _graphs[id];

  @override
  Future<void> save(WorkflowGraph graph) async {
    _graphs[graph.id] = graph;
  }

  @override
  Future<void> delete(String id) async {
    _graphs.remove(id);
  }

  @override
  Future<List<WorkflowGraph>> list({int? limit, int? offset}) async {
    return _graphs.values.toList();
  }
}
