# AQ Graph Engine — План полной production-готовности

> Документ охватывает: архитектуру пакета, два режима работы (client/server),  
> auth-модуль, абстракцию инструментов (AQToolService), иерархию узлов,  
> механизм conditional edges и фазированный план реализации.

---

## Часть I. Целевая архитектура пакета

### 1.1 Два режима — один пакет

Пакет `aq_graph_engine` должен уметь работать в двух режимах, которые выбираются при инициализации:

```
┌────────────────────────────────────────────────────────────────────┐
│                    aq_graph_engine                                  │
│                                                                     │
│  GraphEngineService.local(...)   GraphEngineService.remote(...)     │
│         │                                   │                       │
│   LocalEngineTransport              HttpEngineTransport             │
│   (выполняет граф здесь же)         (делегирует на сервер)          │
│         │                                   │                       │
│   PolymorphicWorkflowRunner         GraphEngineClient               │
│   InstructionRunner                 (SSE / HTTP polling)            │
│   PromptRunner                                                      │
└────────────────────────────────────────────────────────────────────┘
```

**Local mode** — движок работает в том же процессе (десктоп-приложение, CLI, тест).  
**Remote mode** — движок работает на сервере, клиент получает только `GraphEngineService` с теми же методами и стримами событий.

**Публичный API одинаков в обоих режимах:**

```dart
// Инициализация — выбор режима один раз при старте приложения
final engine = GraphEngineService.local(
  tools: myToolService,       // AQToolService
  runRepo: myRunRepo,
  graphRepo: myGraphRepo,
  auth: myAuthClient,         // AQAuthClient
);

// — или —

final engine = GraphEngineService.remote(
  baseUrl: 'https://engine.aq.io',
  auth: myAuthClient,
);

// Использование — одинаково в обоих режимах
final stream = engine.run(GraphRunRequest(...));
await engine.resume(runId, userInput);
await engine.cancel(runId);
```

Клиентская часть приложения работает **только** через `GraphEngineService` — она не знает, где физически выполняется граф.

---

### 1.2 Структура модулей (пакеты монорепо)

```
pkgs/
├── aq_schema/              # Доменные модели, графы, узлы, контракты
├── aq_graph_engine/        # Движок (runner + transport + client)
├── aq_auth/                # Auth-модуль (отдельный пакет, см. Часть II)
├── aq_tool_service/        # Абстракция инструментов (см. Часть III)
├── aq_queue/               # Redis job queue
└── dart_vault/             # Data storage

server_apps/
├── graph_engine_server/    # HTTP сервер движка
└── aq_graph_worker/        # Stateless worker (Redis consumer)
```

---

## Часть II. Модуль авторизации (aq_auth)

### 2.1 Концепция: API-ключ несёт в себе права

Движок работает с двумя типами учётных данных:

| Тип | Кто использует | Что содержит | Как валидируется |
|-----|----------------|--------------|-----------------|
| **JWT-токен** | Команды от клиента → сервер | userId, projectId, роли, exp | Сервером по подписи |
| **API-ключ** | Движок → внешние ресурсы | scope (llm/fs/mcp), projectId, rateLimit, выдавший | Самим ресурсом по хешу |

**Важно:** API-ключ — это не просто строка. В него зашито: что ключ может делать (`scope`), к какому проекту он привязан, кто его выдал и когда. Сервис авторизации выдаёт API-ключи и хранит их метаданные.

### 2.2 Публичный API модуля aq_auth

```dart
// ── Клиент-часть (используется везде — в приложении, воркере) ──

abstract interface class AQAuthClient {
  /// Аутентификация по логину/паролю → JWT токен
  Future<AQToken> loginWithCredentials(String email, String password);

  /// Аутентификация воркера по API-ключу → service JWT
  Future<AQToken> loginWithApiKey(String apiKey);

  /// Текущий действующий токен (автоматически обновляется)
  Future<AQToken> get currentToken;

  /// Проверить токен локально (без сети, по jwtSecret)
  AQTokenClaims? validateLocally(String rawToken);

  /// Получить / создать API-ключ для проекта
  Future<AQApiKey> getProjectApiKey(String projectId, {List<String> scope});

  /// Выйти
  Future<void> logout();

  /// Стрим событий (tokenRefreshed, expired, loggedOut)
  Stream<AQAuthEvent> get events;
}

// ── Инициализация ──

// В приложении (Flutter/Dart)
final auth = await AQAuth.init(
  serverUrl: 'https://auth.aq.io',
  jwtSecret: optionalLocalSecret,   // для offline validation
);

// Движок получает уже инициализированный клиент
final engine = GraphEngineService.remote(
  baseUrl: '...',
  auth: auth,   // AQAuthClient — движок сам обновляет токен через него
);
```

### 2.3 Жизненный цикл токена в движке

```
[Клиент] ──JWT──► [GraphEngineServer] ──валидирует JWT──► [запускает граф]
                                              │
                             граф получает API-ключ из JWT claims
                                              │
                   [Узел в графе] ──API-key──► [AQToolService / AQVault]
```

Движок при запуске графа извлекает из `AQTokenClaims.apiKeyRef` → загружает API-ключ → передаёт в `RunContext`. Каждый инструмент получает API-ключ через контекст — он не хранится в самом графе.

### 2.4 Интерфейсы в aq_schema (контракт)

```dart
// pkgs/aq_schema/lib/auth/api_key_claims.dart

/// Права зашитые в API-ключ
class AQApiKeyClaims {
  final String projectId;
  final String keyId;
  final List<String> scope;       // ['llm', 'fs:read', 'vault:write', 'mcp:*']
  final String issuedBy;          // auth service instance
  final DateTime issuedAt;
  final DateTime? expiresAt;
  final Map<String, dynamic> rateLimit;   // { 'llm_rpm': 60, 'fs_ops': 1000 }

  bool allows(String permission) => scope.any((s) =>
    s == permission || s == '${permission.split(':').first}:*' || s == '*');
}
```

---

## Часть III. Абстракция инструментов (AQToolService)

### 3.1 Философия: движок — это "пользователь" сервисов

Граф организует логику. Узлы исполняют команды. Но узел **не знает**, как именно выполнена команда — локально, через HTTP, через MCP, через subprocess. Это задача `AQToolService`.

```
[WorkflowRunner]
      │
      ▼
[LlmActionNode].execute(context, toolService)
      │
      ▼
toolService.llm.complete(messages, model: 'claude-3-5')
      │
      ├─ если local: прямой HTTP в Anthropic API
      ├─ если remote MCP: MCP transport → Anthropic
      └─ если mock (тест): возвращает заглушку
```

### 3.2 Интерфейс AQToolService (в aq_schema)

```dart
// pkgs/aq_schema/lib/tools/aq_tool_service.dart

/// Главный фасад для доступа к инструментам из узлов графа.
/// Движок получает его при инициализации — не знает о реализации.
abstract interface class AQToolService {

  /// LLM-интерфейс
  IAQLlmService get llm;

  /// Файловая система / хранилище артефактов
  IAQVaultService get vault;

  /// Произвольный инструмент по имени (для ToolCallNode)
  Future<dynamic> callTool(String toolName, Map<String, dynamic> args, RunContext ctx);

  /// Проверить доступность инструмента
  bool hasTool(String toolName);

  /// Список всех зарегистрированных инструментов
  List<AQToolDescriptor> get availableTools;
}

// ── LLM ────────────────────────────────────────────────────────────

abstract interface class IAQLlmService {
  /// Запрос к LLM. Узел не знает: это Claude, GPT или локальная модель.
  Future<AQLlmResponse> complete({
    required List<AQLlmMessage> messages,
    String? model,
    double? temperature,
    int? maxTokens,
    List<AQToolDescriptor>? tools,   // для tool-use (function calling)
  });

  /// Стриминг ответа
  Stream<AQLlmChunk> stream({
    required List<AQLlmMessage> messages,
    String? model,
  });
}

abstract interface class IAQVaultService {
  /// Прочитать артефакт / файл
  Future<AQVaultItem?> read(String path, RunContext ctx);

  /// Записать артефакт
  Future<void> write(String path, dynamic content, RunContext ctx);

  /// Найти артефакты по запросу
  Future<List<AQVaultItem>> query(AQVaultQuery q, RunContext ctx);

  /// Удалить
  Future<void> delete(String path, RunContext ctx);
}

// ── Модели ─────────────────────────────────────────────────────────

class AQLlmMessage {
  final String role;    // 'system' | 'user' | 'assistant'
  final String content;
  final List<AQToolCall>? toolCalls;     // для ответа ассистента с tool use
  final AQToolResult? toolResult;        // для результата вызова
  const AQLlmMessage({required this.role, required this.content,
    this.toolCalls, this.toolResult});
}

class AQLlmResponse {
  final String text;
  final String? stopReason;
  final List<AQToolCall>? toolCalls;    // если LLM хочет вызвать инструмент
  final AQUsage usage;
}

class AQToolDescriptor {
  final String name;
  final String description;
  final Map<String, dynamic> inputSchema;   // JSON Schema
  const AQToolDescriptor({required this.name, required this.description,
    required this.inputSchema});
}
```

### 3.3 Использование в узлах

```dart
// В LlmActionNode.execute():
@override
Future<dynamic> execute(RunContext context, AQToolService tools) async {
  final prompt = context.getVar(promptVar) as String;

  final response = await tools.llm.complete(
    messages: [
      AQLlmMessage(role: 'system', content: systemPrompt),
      AQLlmMessage(role: 'user', content: prompt),
    ],
    model: modelName,
  );

  context.setVar(outputVar, response.text);
  return response.text;
}

// В FileReadNode.execute():
@override
Future<dynamic> execute(RunContext context, AQToolService tools) async {
  final path = substituteVariables(filePath, context);
  final item = await tools.vault.read(path, context);
  context.setVar(outputVar, item?.content);
  return item?.content;
}
```

**Ключевое решение:** `IWorkflowNode.execute()` принимает `AQToolService`, а не `ToolRegistry`. `ToolRegistry` — внутренняя деталь реализации `AQToolService`, снаружи невидима.

---

## Часть IV. Иерархия узлов — финальная версия

### 4.1 Проблема: WorkflowNodeFactory и устаревший enum

Сейчас в `PolymorphicWorkflowRunner` в четырёх местах вызывается `WorkflowNodeFactory.fromJson()`, помеченная как `@Deprecated`. Причина — граф хранится со старыми `WorkflowNode` (enum-based), и runner делает конвертацию на лету.

**Решение:** Отделить **хранение** графа от **выполнения**. Граф в базе продолжает использовать `WorkflowNode` (для обратной совместимости), но при загрузке из репозитория он **компилируется** в типобезопасное представление. Runner работает только с `IWorkflowNode` — без фабрик, без конвертаций.

### 4.2 Финальная иерархия узлов (aq_schema)

```
INode (базовый интерфейс для всех типов узлов)
├── IWorkflowNode              — узел WorkflowGraph
│   │   execute(ctx, tools) → dynamic
│   │   selectBranch(edges, result) → String?   ← новый метод
│   │   joinStrategy, maxRetries, retryDelayMs
│   │
│   ├── AutomaticNode (абстрактный)
│   │   ├── LlmActionNode          — вызов LLM через tools.llm
│   │   ├── FileReadNode           — чтение через tools.vault
│   │   ├── FileWriteNode          — запись через tools.vault
│   │   ├── GitCommitNode          — git через tools.callTool('git_commit')
│   │   └── [расширяется проектами]
│   │
│   ├── InteractiveNode (абстрактный)
│   │   ├── UserInputNode          — suspend → ждёт ввода
│   │   ├── ManualReviewNode       — suspend → ждёт одобрения
│   │   ├── FileUploadNode         — suspend → ждёт файла
│   │   └── CoCreationChatNode     — suspend → многоходовый диалог
│   │
│   └── CompositeNode (абстрактный)
│       ├── SubGraphNode           — запускает дочерний WorkflowGraph
│       └── RunInstructionNode     — запускает InstructionGraph как функцию
│
├── IInstructionNode           — узел InstructionGraph
│   │   execute(ctx, tools) → dynamic
│   │
│   ├── ToolCallNode               — вызов tools.callTool(name, args)
│   ├── LlmQueryNode               — вызов tools.llm.complete(...)
│   ├── ConditionNode              — вычисляет булево выражение
│   └── TransformNode              — преобразование данных
│
└── IPromptNode                — узел PromptGraph
    ├── TextBlockNode              — статический текст с {{vars}}
    ├── VariableInsertNode         — вставка переменной с форматированием
    └── ConditionalBlockNode       — условный текстовый блок
```

### 4.3 Регистрация типов без фабрик (NodeRegistry)

Вместо `WorkflowNodeFactory` (статический switch) — `NodeTypeRegistry` с регистрацией через конструкторы:

```dart
// pkgs/aq_graph_engine/lib/src/registry/node_type_registry.dart

class NodeTypeRegistry {
  final _workflow = <String, IWorkflowNode Function(Map<String, dynamic>)>{};
  final _instruction = <String, IInstructionNode Function(Map<String, dynamic>)>{};
  final _prompt = <String, IPromptNode Function(Map<String, dynamic>)>{};

  /// Зарегистрировать тип WorkflowNode
  void registerWorkflow<T extends IWorkflowNode>(
    String typeKey,
    T Function(Map<String, dynamic>) fromJson,
  ) => _workflow[typeKey] = fromJson;

  /// Создать узел из JSON
  IWorkflowNode workflowFromJson(Map<String, dynamic> json) {
    final type = json['type'] as String;
    final factory = _workflow[type];
    if (factory == null) throw UnknownNodeTypeException(type, 'workflow');
    return factory(json);
  }

  // ... аналогично для instruction и prompt
}

// ── Стандартная регистрация ──────────────────────────────────────────

NodeTypeRegistry buildDefaultRegistry() {
  final r = NodeTypeRegistry();
  // Workflow
  r.registerWorkflow('llmAction', LlmActionNode.fromJson);
  r.registerWorkflow('fileRead', FileReadNode.fromJson);
  r.registerWorkflow('fileWrite', FileWriteNode.fromJson);
  r.registerWorkflow('gitCommit', GitCommitNode.fromJson);
  r.registerWorkflow('userInput', UserInputNode.fromJson);
  r.registerWorkflow('manualReview', ManualReviewNode.fromJson);
  r.registerWorkflow('fileUpload', FileUploadNode.fromJson);
  r.registerWorkflow('coCreationChat', CoCreationChatNode.fromJson);
  r.registerWorkflow('subGraph', SubGraphNode.fromJson);
  r.registerWorkflow('runInstruction', RunInstructionNode.fromJson);
  // Instruction
  r.registerInstruction('toolCall', ToolCallNode.fromJson);
  r.registerInstruction('llmQuery', LlmQueryNode.fromJson);
  r.registerInstruction('condition', ConditionNode.fromJson);
  r.registerInstruction('transform', TransformNode.fromJson);
  // Prompt
  r.registerPrompt('textBlock', TextBlockNode.fromJson);
  r.registerPrompt('variableInsert', VariableInsertNode.fromJson);
  r.registerPrompt('conditionalBlock', ConditionalBlockNode.fromJson);
  return r;
}
```

Добавить новый тип — одна строка регистрации. Никаких правок в runner.

---

## Часть V. Conditional edges — правильная реализация

### 5.1 Механизм: два уровня выбора ветки

```
Узел завершился → результат R
       │
       ▼
[Уровень 1] node.selectBranch(edges, R)
       │
       ├─ вернул String (ключ ветки)
       │     └─ runner выбирает ребро с branchName == ключ
       │
       └─ вернул null (узел не выбирает сам)
             │
             ▼
       [Уровень 2] runner сортирует рёбра:
             ├─ фильтр по onSuccess / onError
             ├─ фильтр по conditionExpression (evaluator)
             ├─ сортировка по priority (DESC)
             └─ если isExclusive — берём только первое
```

### 5.2 Метод selectBranch в базовом классе

```dart
// pkgs/aq_schema/lib/graph/nodes/base/i_workflow_node.dart

abstract interface class IWorkflowNode {

  /// Узел может сам выбрать ветку по результату выполнения.
  ///
  /// Возвращает branchName ребра, по которому надо пройти.
  /// Возвращает null — runner сам выбирает по приоритету и conditionExpression.
  ///
  /// По умолчанию: null (большинство узлов не выбирают сами).
  String? selectBranch(List<WorkflowEdge> outgoingEdges, dynamic result) => null;

  // ... остальные методы
}
```

**Базовая реализация возвращает null.** Узлы, которым нужна кастомная логика ветвления, переопределяют метод:

```dart
// Пример: ConditionBranchNode — узел с явным ветвлением
class ConditionBranchNode extends AutomaticNode {
  final String checkVar;
  final String operator;
  final dynamic compareValue;

  @override
  Future<dynamic> execute(RunContext context, AQToolService tools) async {
    final val = context.getVar(checkVar);
    final passed = _evaluate(val, operator, compareValue);
    return passed; // bool
  }

  @override
  String? selectBranch(List<WorkflowEdge> edges, dynamic result) {
    // result — это bool от execute
    final passed = result as bool;
    // Ищем ребро с branchName 'true' или 'false'
    final branchKey = passed ? 'true' : 'false';
    final edge = edges.firstWhereOrNull((e) => e.branchName == branchKey);
    return edge?.branchName;
  }
}
```

### 5.3 Evaluator для conditionExpression

Для рёбер с `conditionExpression` (строка выражения) runner использует `ConditionEvaluator`:

```dart
// pkgs/aq_graph_engine/lib/src/engine/condition_evaluator.dart

class ConditionEvaluator {
  /// Оценить выражение в контексте состояния.
  ///
  /// Поддерживаемый синтаксис:
  ///   "status == 'success'"
  ///   "count > 5"
  ///   "errors isEmpty"
  ///   "name contains 'error'"
  ///   "result != null"
  ///
  /// Возвращает true/false или throws ConditionEvalException.
  static bool evaluate(String expression, Map<String, dynamic> state) { ... }
}
```

---

## Часть VI. Бизнес-логика проекта: Workflow → Instruction → Prompt

### 6.1 Модель проекта

Проект в AQ Studio — это контейнер, который может быть агентом, программой или веб-сайтом. Внутри:

```
AQProject
├── mainWorkflowId         — главный workflow (точка входа)
├── workflows[]            — все workflow (в т.ч. не-главные, дочерние)
├── instructions[]         — переиспользуемые инструкции
├── prompts[]              — шаблоны промптов
└── metadata               — название, тип (agent/app/website), версия
```

**Точка входа** — всегда `mainWorkflowId`. Запустить проект = запустить главный workflow. Остальные workflow вызываются через `SubGraphNode`.

### 6.2 Логика вызовов (стек выполнения)

```
[GraphEngine.run(projectId)]
        │
        ▼
[MainWorkflowRunner]
  ├── [AutomaticNode: LlmActionNode]
  │       └── compiles prompt: PromptRunner.run(promptId, ctx)
  │                               └── [TextBlockNode, VariableInsertNode...]
  │                               └── returns: "Ты агент. Задача: {{task}}"
  │       └── calls: tools.llm.complete(messages)
  │       └── saves result to ctx.outputVar
  │
  ├── [CompositeNode: RunInstructionNode]
  │       └── InstructionRunner.execute(instructionId, isolatedCtx)
  │               ├── [ToolCallNode: tools.callTool('code_analyze', ...)]
  │               ├── [LlmQueryNode: tools.llm.complete(...)]
  │               └── [ConditionNode] → branch 'retry' или 'done'
  │
  ├── [InteractiveNode: UserInputNode]
  │       └── suspend → GraphRunEvent.userInputRequired
  │               → клиент показывает UI
  │               → engine.resume(runId, input)
  │
  └── [CompositeNode: SubGraphNode]
          └── WorkflowRunner.start(subWorkflowId, mappedCtx)
```

**Правило изоляции:** `InstructionGraph` выполняется в изолированном контексте (копия, не оригинал). Результат передаётся через `outputMapping`. Это позволяет безопасно использовать инструкции из разных workflow.

### 6.3 PromptGraph — компилятор промптов

PromptGraph компилируется _до_ вызова LLM и возвращает строку. Это важно сделать явной операцией:

```dart
// В LlmActionNode.execute():
final promptText = await tools.callTool('compile_prompt', {
  'promptId': promptBlueprintId,
  'context': context.state,
});
// promptText — готовая строка для LLM
```

Или напрямую через `PromptRunner` если движок работает локально. В обоих случаях узел не знает, как собирается промпт.

---

## Часть VII. Фазированный план реализации

### Фаза 0: Фундаментные исправления (1 неделя)

> Цель: движок запускается и проходит граф без крашей

**День 1-2: Очистка иерархии узлов**
- Создать `NodeTypeRegistry` (заменяет `WorkflowNodeFactory`)
- Обновить `PolymorphicWorkflowRunner` — убрать все вызовы `WorkflowNodeFactory`, использовать `NodeTypeRegistry`
- Добавить `selectBranch()` в `IWorkflowNode` (default: `null`)
- Убрать `@Deprecated WorkflowNodeFactory` из runner (оставить для совместимости в schema пока)

**День 3-4: Conditional edges**
- Реализовать `ConditionEvaluator` (базовые операторы: `==`, `!=`, `>`, `<`, `>=`, `<=`, `contains`, `isEmpty`, `isNotEmpty`, `exists`)
- Вставить в `PolymorphicWorkflowRunner._processNode()` — заменить `return true` на реальный evaluator
- Добавить `ConditionBranchNode` в workflow узлы

**День 5: Базовый тест всего стека**
- InstructionRunner: добавить счётчик шагов `maxSteps = 50` защита от цикла
- Убрать `test_api_key` backdoor из `GraphWorker` (использовать `TestAuthClient` в тестах)
- Заменить `print()` на `package:logging`

---

### Фаза 1: Интерфейс инструментов (1.5 недели)

> Цель: движок получает чистый контракт с инструментами

**День 1-3: AQToolService интерфейс**
- Добавить в `aq_schema`:
  - `AQToolService` (абстрактный интерфейс)
  - `IAQLlmService` с `complete()` и `stream()`
  - `IAQVaultService` с `read()`, `write()`, `query()`, `delete()`
  - Модели: `AQLlmMessage`, `AQLlmResponse`, `AQToolDescriptor`, `AQVaultItem`
- Обновить сигнатуры `IWorkflowNode.execute()` и `IInstructionNode.execute()`:
  - было: `execute(RunContext context, ToolRegistry tools)`
  - стало: `execute(RunContext context, AQToolService tools)`
- Обновить все существующие узлы

**День 4-6: MockToolService для тестов**
- `MockToolService` — реализация `AQToolService` с заглушками
- `MockLlmService` — возвращает сконфигурированные ответы
- `MockVaultService` — in-memory хранилище
- Написать unit-тесты для всех типов узлов с Mock

**День 7: API ключ в RunContext**
- Добавить `apiKeyClaims` в `RunContext`
- Инструменты получают claims через контекст — могут проверить scope
- `AQToolService` при вызове `complete()` проверяет `ctx.apiKeyClaims.allows('llm')`

---

### Фаза 2: Auth-модуль (1 неделя)

> Цель: движок работает по API-ключам, команды валидируются по JWT

**День 1-3: Пакет aq_auth**
- Интерфейс `AQAuthClient` (см. Часть II)
- `AQToken` — обёртка над JWT с автообновлением
- `AQApiKey` с `AQApiKeyClaims`
- `AQAuthClient.remote(serverUrl)` — HTTP-реализация
- `AQAuthClient.test(...)` — mock для тестов

**День 4-5: Интеграция в движок**
- `GraphEngineService` принимает `AQAuthClient` в конструкторе
- Валидация JWT в `graph_engine_server` middleware
- Воркер: убрать ручной token lifecycle, делегировать `AQAuthClient`
- `AQAuthClient` автоматически обновляет токен фоновым таймером (за 2 минуты до expiry)

**День 6-7: API-ключ → RunContext**
- При старте графа: server извлекает `apiKeyRef` из JWT → загружает `AQApiKeyClaims` → кладёт в `RunContext`
- Написать тесты: граф без нужного scope → отказ в нужном инструменте

---

### Фаза 3: Два режима Client/Server (1.5 недели)

> Цель: публичный API одинаков в обоих режимах, можно переключать

**День 1-3: GraphEngineService фасад**
```dart
abstract interface class GraphEngineService {
  factory GraphEngineService.local({...}) = _LocalGraphEngineService;
  factory GraphEngineService.remote({...}) = _RemoteGraphEngineService;

  Stream<GraphRunEvent> run(GraphRunRequest request);
  Future<void> resume(String runId, UserInputResponse input);
  Future<void> cancel(String runId);
  Future<GraphRunStatus> getStatus(String runId);
  Future<bool> isAvailable();
  void dispose();
}
```

**День 4-5: Remote mode (HttpEngineTransport)**
- SSE (Server-Sent Events) для стрима событий
- Graceful reconnect при обрыве
- `GraphRunStream` — обёртка, скрывающая HTTP детали
- Таймаут и retry для отдельных запросов

**День 6-7: Тесты integration**
- Тест: local mode, полный workflow с MockToolService
- Тест: remote mode, мок HTTP сервер, проверка SSE стрима
- Тест: suspend/resume через оба режима

---

### Фаза 4: Production hardening (1 неделя)

> Цель: стабильность под нагрузкой

**День 1-2: Параллельность и race conditions**
- Защитить `_logs` и `_visitedEdges` в runner (использовать `ListQueue` или `SynchronizedList`)
- Правильный `cloneForBranch` — глубокое копирование состояния
- Изолировать `InstructionGraph` выполнение (`RunContext.isolatedCopy()`)

**День 3-4: Token и session lifecycle**
- Фоновый refresh в `AQAuthClient` (уже в Фазе 2)
- Circuit breaker для data service вызовов (3 failed → open circuit → 503)
- Dead Letter Queue в Redis для failed jobs

**День 5: Метрики и алертинг**
- Заполнить `graph_queued_runs` из Redis
- Добавить метрику `auth_token_refresh_total`
- Добавить health check endpoint с детальным статусом: `{redis: ok, dataService: ok, auth: ok}`
- Grafana alert rules: failed_rate > 5%, active_runs > concurrency * 0.9

---

### Фаза 5: Тестирование (1 неделя)

> Согласно GRAPH_ENGINE_MASTER_PLAN.md (Неделя 3)

**День 1-2: Unit тесты**
- `MockRunRepository`, `MockGraphRepository`, `MockToolService`
- `PolymorphicWorkflowRunner` с 5+ сценариями: happy path, suspend, retry, conditional, parallel
- `InstructionRunner` с cycle detection
- `ConditionEvaluator` — все операторы

**День 3-4: Integration тесты**
- Реальный PostgreSQL через docker-compose (или SQLite для скорости)
- Сохранение/восстановление run state
- Suspend → resume через очередь событий
- Join strategies (waitAll с 3 параллельными ветками)

**День 5: E2E тест**
- Полный граф: `UserInput` → `LlmAction` → `ConditionBranch` → `FileWrite`
- Prometheus метрики после прогона — проверить счётчики
- Load test: 10 параллельных графов, concurrency=4

---

## Часть VIII. Совет по архитектуре ToolService

### Как организовать пакет aq_tool_service

Это отдельная интересная задача. Вот рекомендуемая структура:

```
pkgs/aq_tool_service/
├── lib/
│   ├── aq_tool_service.dart          # публичный экспорт
│   ├── src/
│   │   ├── service/
│   │   │   ├── tool_service_impl.dart    # конкретная реализация AQToolService
│   │   │   └── tool_service_builder.dart # builder pattern для конфигурации
│   │   ├── llm/
│   │   │   ├── anthropic_llm.dart        # Anthropic API
│   │   │   ├── openai_llm.dart           # OpenAI API
│   │   │   └── mcp_llm_proxy.dart        # LLM через MCP транспорт
│   │   ├── vault/
│   │   │   ├── remote_vault.dart         # через dart_vault (HTTP)
│   │   │   └── local_vault.dart          # локальная FS (десктоп)
│   │   ├── mcp/
│   │   │   ├── mcp_transport.dart        # MCP JSON-RPC транспорт
│   │   │   ├── mcp_tool_adapter.dart     # MCP tool → AQToolDescriptor
│   │   │   └── mcp_server_registry.dart  # список подключённых MCP серверов
│   │   └── tools/
│   │       ├── git_tool.dart
│   │       ├── code_exec_tool.dart
│   │       └── web_search_tool.dart
```

**Ключевой принцип:** `aq_tool_service` **реализует** интерфейсы из `aq_schema`. Движок `aq_graph_engine` зависит только от `aq_schema`. Так движок никогда не узнает о конкретных реализациях:

```
aq_graph_engine  →  aq_schema (interfaces)  ←  aq_tool_service (implementations)
```

**Builder для конфигурации:**

```dart
final toolService = AQToolServiceBuilder()
  .withLlm(AnthropicLlmService(apiKey: key))
  .withVault(RemoteVaultService(endpoint: vaultUrl, auth: auth))
  .withMcpServer('filesystem', 'stdio', 'npx @modelcontextprotocol/server-filesystem /data')
  .withMcpServer('github', 'http', 'https://github.mcp.example.com')
  .withTool('git_commit', GitCommitTool(workDir: projectPath))
  .build();

// Передаём в движок
final engine = GraphEngineService.local(
  tools: toolService,
  ...
);
```

**MCP инструменты** регистрируются как обычные tools через `callTool()` — движок не знает, что это MCP. `mcp_tool_adapter.dart` транслирует MCP JSON-RPC в `AQToolService.callTool()` интерфейс.

---

## Часть IX. Сводная таблица готовности по фазам

| Компонент | Сейчас | После Фаза 0 | После Фаза 1 | После Фаза 2 | После Фаза 3 | После Фаза 4-5 |
|-----------|:---:|:---:|:---:|:---:|:---:|:---:|
| WorkflowRunner (без крашей) | ⚠️ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Conditional edges | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ |
| NodeTypeRegistry | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ |
| AQToolService interface | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ |
| Auth / API-ключи | ⚠️ | ⚠️ | ⚠️ | ✅ | ✅ | ✅ |
| Token auto-refresh | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ |
| Client/Server два режима | ⚠️ | ⚠️ | ⚠️ | ⚠️ | ✅ | ✅ |
| Race conditions (параллель) | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ |
| Unit + Integration тесты | ❌ | ❌ | ⚠️ | ⚠️ | ⚠️ | ✅ |
| MCP интеграция | ❌ | ❌ | ❌ | ❌ | ❌ | aq_tool_service |
| LLM реализация | ❌ | ❌ | ❌ | ❌ | ❌ | aq_tool_service |
| Production стабильность | ❌ | ⚠️ | ⚠️ | ⚠️ | ⚠️ | ✅ |

**Итого: 7 недель до полной production-готовности движка.**  
(aq_tool_service — отдельный параллельный трек, не блокирует движок)

---

## Приложение: минимальный интерфейс для первого реального запуска

Если нужно запустить граф с реальным LLM как можно быстрее (параллельно с Фазами), минимально необходимо:

1. **Фаза 0, День 1-2** — убрать deprecated factory и крашащий `isSystemTool`
2. Создать **минимальный `SimpleToolService`** прямо в `aq_graph_worker`:
   ```dart
   class SimpleAnthropicToolService implements AQToolService {
     final String apiKey;
     @override
     IAQLlmService get llm => _AnthropicDirectService(apiKey);
     // vault — заглушка, остальное — не нужно для базового графа
   }
   ```
3. Зарегистрировать его в `GraphWorker.start()`

Это даст первый работающий граф `UserInput → LlmAction → FileWrite` примерно за **3-4 дня** от сегодня, параллельно с полноценной реализацией по плану выше.