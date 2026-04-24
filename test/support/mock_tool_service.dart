// Mock реализация AQToolService для тестов

import 'package:aq_schema/aq_schema.dart';

/// Mock реализация AQToolService для unit тестов
class MockToolService implements AQToolService {
  final MockLlmService _llm;
  final MockVaultService _vault;
  final Map<String, Future<dynamic> Function(Map<String, dynamic>, RunContext)> _tools = {};

  MockToolService({
    MockLlmService? llm,
    MockVaultService? vault,
  })  : _llm = llm ?? MockLlmService(),
        _vault = vault ?? MockVaultService();

  @override
  IAQLlmService get llm => _llm;

  @override
  IAQVaultService get vault => _vault;

  @override
  Future<dynamic> callTool(String toolName, Map<String, dynamic> args, RunContext ctx) async {
    if (!_tools.containsKey(toolName)) {
      throw AQToolNotFoundException(toolName, _tools.keys.toList());
    }
    return await _tools[toolName]!(args, ctx);
  }

  @override
  bool hasTool(String toolName) => _tools.containsKey(toolName);

  @override
  List<AQToolDescriptor> get availableTools => _tools.keys
      .map((name) => AQToolDescriptor(
            name: name,
            description: 'Mock tool: $name',
            inputSchema: {'type': 'object'},
          ))
      .toList();

  @override
  Future<bool> isAvailable() async => true;

  /// Зарегистрировать mock инструмент
  void registerTool(
    String name,
    Future<dynamic> Function(Map<String, dynamic>, RunContext) handler,
  ) {
    _tools[name] = handler;
  }
}

/// Mock реализация IAQLlmService
class MockLlmService implements IAQLlmService {
  final List<AQLlmResponse> _responses = [];
  int _callCount = 0;

  /// Добавить ответ в очередь
  void addResponse(AQLlmResponse response) {
    _responses.add(response);
  }

  /// Количество вызовов complete()
  int get completeCallCount => _callCount;

  /// Последние переданные сообщения
  List<AQLlmMessage>? lastMessages;

  @override
  Future<AQLlmResponse> complete({
    required List<AQLlmMessage> messages,
    String? model,
    double? temperature,
    int? maxTokens,
    List<AQToolDescriptor>? tools,
  }) async {
    _callCount++;
    lastMessages = messages;

    if (_responses.isEmpty) {
      return AQLlmResponse(
        text: 'Mock response',
        stopReason: 'end_turn',
      );
    }

    return _responses.removeAt(0);
  }

  @override
  Stream<AQLlmChunk> stream({
    required List<AQLlmMessage> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async* {
    lastMessages = messages;
    yield AQLlmChunk(delta: 'Mock ', isDone: false);
    yield AQLlmChunk(delta: 'stream', isDone: false);
    yield AQLlmChunk(delta: '', isDone: true);
  }

  @override
  Future<List<String>> getAvailableModels() async => ['mock-model'];

  @override
  Future<bool> isAvailable() async => true;

  /// Сбросить состояние
  void reset() {
    _responses.clear();
    _callCount = 0;
    lastMessages = null;
  }
}

/// Mock реализация IAQVaultService
class MockVaultService implements IAQVaultService {
  final Map<String, dynamic> _store = {};
  final List<String> _readPaths = [];
  final List<String> _writePaths = [];
  final List<String> _deletePaths = [];

  /// Пути которые были прочитаны
  List<String> get readPaths => List.unmodifiable(_readPaths);

  /// Пути которые были записаны
  List<String> get writePaths => List.unmodifiable(_writePaths);

  /// Пути которые были удалены
  List<String> get deletePaths => List.unmodifiable(_deletePaths);

  @override
  Future<AQVaultItem?> read(String path, RunContext ctx) async {
    _readPaths.add(path);
    _checkPermission(ctx, 'fs:read');

    if (!_store.containsKey(path)) {
      return null;
    }

    return AQVaultItem(
      path: path,
      content: _store[path],
      contentType: 'json',
    );
  }

  @override
  Future<void> write(String path, dynamic content, RunContext ctx) async {
    _writePaths.add(path);
    _checkPermission(ctx, 'fs:write');
    _store[path] = content;
  }

  @override
  Future<List<AQVaultItem>> query(AQVaultQuery query, RunContext ctx) async {
    _checkPermission(ctx, 'fs:read');
    return _store.entries
        .map((e) => AQVaultItem(
              path: e.key,
              content: e.value,
              contentType: 'json',
            ))
        .toList();
  }

  @override
  Future<void> delete(String path, RunContext ctx) async {
    _deletePaths.add(path);
    _checkPermission(ctx, 'fs:write');
    _store.remove(path);
  }

  @override
  Future<bool> exists(String path, RunContext ctx) async {
    _checkPermission(ctx, 'fs:read');
    return _store.containsKey(path);
  }

  @override
  Future<Map<String, dynamic>?> getMetadata(String path, RunContext ctx) async {
    _checkPermission(ctx, 'fs:read');
    if (!_store.containsKey(path)) {
      return null;
    }
    return {'path': path, 'size': _store[path].toString().length};
  }

  void _checkPermission(RunContext ctx, String requiredScope) {
    // Для тестов можно пропустить проверку если apiKeyClaims == null
    if (ctx.apiKeyClaims == null) return;

    final scopes = ctx.apiKeyClaims!.scope;
    if (!scopes.contains(requiredScope) && !scopes.contains('*')) {
      throw AQPermissionDeniedException(
        'Нет прав для операции',
        requiredScope: requiredScope,
        availableScopes: scopes,
      );
    }
  }

  /// Сбросить состояние
  void reset() {
    _store.clear();
    _readPaths.clear();
    _writePaths.clear();
    _deletePaths.clear();
  }
}
