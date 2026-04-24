// Тесты для PromptRunner

import 'package:test/test.dart';
import 'package:aq_schema/aq_schema.dart';
import 'package:aq_graph_engine/server.dart';
import 'dart:async';

class MockSandbox implements ISandbox {
  @override
  String get sandboxId => 'mock-sandbox';

  @override
  String get displayName => 'Mock Sandbox';

  @override
  Stream<ISandboxEvent> get events => Stream.empty();

  @override
  SandboxPolicy get policy => const SandboxPolicy(
        available: ['*'],
        allowed: ['*'],
      );

  @override
  Future<void> dispose() async {}
}

class MockGraphRepository implements IGraphRepository {
  final Map<String, dynamic> _graphs = {};

  void addGraph(String id, dynamic graph) {
    _graphs[id] = graph;
  }

  @override
  Future<$Graph?> loadGraph(String blueprintId) async {
    return _graphs[blueprintId] as $Graph?;
  }

  @override
  Future<void> saveGraph($Graph graph) async {
    // Not needed for tests
  }

  @override
  Future<void> deleteGraph(String blueprintId) async {
    _graphs.remove(blueprintId);
  }

  @override
  Future<List<$Graph>> listGraphs() async {
    return _graphs.values.whereType<$Graph>().toList();
  }
}

void main() {
  group('PromptRunner', () {
    late MockGraphRepository graphRepo;
    late PromptRunner runner;

    setUp(() {
      graphRepo = MockGraphRepository();
      runner = PromptRunner(graphRepo: graphRepo);
    });

    test('should compile simple text block', () async {
      // Создать простой PromptGraph с одним textBlock
      final graph = PromptGraph(
        id: 'prompt1',
        tenantId: 'tenant1',
        ownerId: 'project1',
        name: 'Test Prompt',
        nodes: {
          'node1': PromptNode(
            id: 'node1',
            type: PromptNodeType.textBlock,
            data: {'content': 'Hello World'},
          ),
        },
      );

      graphRepo.addGraph('prompt1', graph);

      final context = RunContext(
        runId: 'run1',
        projectId: 'project1',
        projectPath: '/test',
        log: (msg, {type = 'info', depth = 0, required branch, details}) {},
        currentBranch: 'main',
        sandbox: MockSandbox(),
      );
      final result = await runner.compile('prompt1', context);

      expect(result, 'Hello World');
    });

    test('should compile text block with variable substitution', () async {
      final graph = PromptGraph(
        id: 'prompt2',
        tenantId: 'tenant1',
        ownerId: 'project1',
        name: 'Test Prompt',
        nodes: {
          'node1': PromptNode(
            id: 'node1',
            type: PromptNodeType.textBlock,
            data: {'content': 'Hello {{name}}!'},
          ),
        },
      );

      graphRepo.addGraph('prompt2', graph);

      final context = RunContext(
        runId: 'run1',
        projectId: 'project1',
        projectPath: '/test',
        log: (msg, {type = 'info', depth = 0, required branch, details}) {},
        currentBranch: 'main',
        sandbox: MockSandbox(),
      );
      context.setVar('name', 'Alice');

      final result = await runner.compile('prompt2', context);

      expect(result, 'Hello Alice!');
    });

    test('should compile multiple text blocks', () async {
      final graph = PromptGraph(
        id: 'prompt3',
        tenantId: 'tenant1',
        ownerId: 'project1',
        name: 'Test Prompt',
        nodes: {
          'node1': PromptNode(
            id: 'node1',
            type: PromptNodeType.textBlock,
            data: {'content': 'First block'},
          ),
          'node2': PromptNode(
            id: 'node2',
            type: PromptNodeType.textBlock,
            data: {'content': 'Second block'},
          ),
        },
      );

      graphRepo.addGraph('prompt3', graph);

      final context = RunContext(
        runId: 'run1',
        projectId: 'project1',
        projectPath: '/test',
        log: (msg, {type = 'info', depth = 0, required branch, details}) {},
        currentBranch: 'main',
        sandbox: MockSandbox(),
      );
      final result = await runner.compile('prompt3', context);

      // Блоки склеиваются с двойным переносом строки
      expect(result, contains('First block'));
      expect(result, contains('Second block'));
    });

    test('should skip variable nodes', () async {
      final graph = PromptGraph(
        id: 'prompt4',
        tenantId: 'tenant1',
        ownerId: 'project1',
        name: 'Test Prompt',
        nodes: {
          'var1': PromptNode(
            id: 'var1',
            type: PromptNodeType.variable,
            data: {'name': 'userName', 'description': 'User name'},
          ),
          'text1': PromptNode(
            id: 'text1',
            type: PromptNodeType.textBlock,
            data: {'content': 'Hello {{userName}}'},
          ),
        },
      );

      graphRepo.addGraph('prompt4', graph);

      final context = RunContext(
        runId: 'run1',
        projectId: 'project1',
        projectPath: '/test',
        log: (msg, {type = 'info', depth = 0, required branch, details}) {},
        currentBranch: 'main',
        sandbox: MockSandbox(),
      );
      context.setVar('userName', 'Bob');

      final result = await runner.compile('prompt4', context);

      // Узел variable не влияет на результат
      expect(result, 'Hello Bob');
    });

    test('should throw if graph not found', () async {
      final context = RunContext(
        runId: 'run1',
        projectId: 'project1',
        projectPath: '/test',
        log: (msg, {type = 'info', depth = 0, required branch, details}) {},
        currentBranch: 'main',
        sandbox: MockSandbox(),
      );

      expect(
        () => runner.compile('nonexistent', context),
        throwsA(isA<Exception>()),
      );
    });

    test('should throw if graph is not PromptGraph', () async {
      // Добавить WorkflowGraph вместо PromptGraph
      final graph = WorkflowGraph(
        id: 'workflow1',
        tenantId: 'tenant1',
        ownerId: 'project1',
        name: 'Test Workflow',
      );

      graphRepo.addGraph('workflow1', graph);

      final context = RunContext(
        runId: 'run1',
        projectId: 'project1',
        projectPath: '/test',
        log: (msg, {type = 'info', depth = 0, required branch, details}) {},
        currentBranch: 'main',
        sandbox: MockSandbox(),
      );

      expect(
        () => runner.compile('workflow1', context),
        throwsA(isA<Exception>()),
      );
    });

    test('should handle empty graph', () async {
      final graph = PromptGraph(
        id: 'prompt5',
        tenantId: 'tenant1',
        ownerId: 'project1',
        name: 'Empty Prompt',
      );

      graphRepo.addGraph('prompt5', graph);

      final context = RunContext(
        runId: 'run1',
        projectId: 'project1',
        projectPath: '/test',
        log: (msg, {type = 'info', depth = 0, required branch, details}) {},
        currentBranch: 'main',
        sandbox: MockSandbox(),
      );
      final result = await runner.compile('prompt5', context);

      expect(result, '');
    });

    test('should compile with edges in correct order', () async {
      final graph = PromptGraph(
        id: 'prompt6',
        tenantId: 'tenant1',
        ownerId: 'project1',
        name: 'Ordered Prompt',
        nodes: {
          'intro': PromptNode(
            id: 'intro',
            type: PromptNodeType.textBlock,
            data: {'content': 'Introduction'},
          ),
          'body': PromptNode(
            id: 'body',
            type: PromptNodeType.textBlock,
            data: {'content': 'Body'},
          ),
          'conclusion': PromptNode(
            id: 'conclusion',
            type: PromptNodeType.textBlock,
            data: {'content': 'Conclusion'},
          ),
        },
        edges: {
          'e1': PromptEdge(
            id: 'e1',
            sourceId: 'intro',
            targetId: 'body',
          ),
          'e2': PromptEdge(
            id: 'e2',
            sourceId: 'body',
            targetId: 'conclusion',
          ),
        },
      );

      graphRepo.addGraph('prompt6', graph);

      final context = RunContext(
        runId: 'run1',
        projectId: 'project1',
        projectPath: '/test',
        log: (msg, {type = 'info', depth = 0, required branch, details}) {},
        currentBranch: 'main',
        sandbox: MockSandbox(),
      );
      final result = await runner.compile('prompt6', context);

      // Проверяем что порядок правильный
      final introIndex = result.indexOf('Introduction');
      final bodyIndex = result.indexOf('Body');
      final conclusionIndex = result.indexOf('Conclusion');

      expect(introIndex, lessThan(bodyIndex));
      expect(bodyIndex, lessThan(conclusionIndex));
    });
  });
}
