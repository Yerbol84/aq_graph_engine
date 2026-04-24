# Архитектура клиент-сервер для AQ Graph Engine

## 🎯 Философия "Тонкий клиент"

### Ключевой принцип

**Клиент НЕ реализует бизнес-логику сервиса. Клиент ИСПОЛЬЗУЕТ то, что дано.**

Если клиенту чего-то не хватает → это задача для сервиса, а не для клиента.

---

## 🏗️ Трёхслойная архитектура

```
┌─────────────────────────────────────────────────────────────┐
│                    Flutter Application                      │
│              (UI + вызовы готовых сервисов)                 │
│                   НИКАКОЙ БИЗНЕС-ЛОГИКИ!                    │
└─────────────────────────────────────────────────────────────┘
                              │
                              │ HTTP/WebSocket
                              ↓
┌─────────────────────────────────────────────────────────────┐
│                  Graph Engine Server                        │
│           (выполнение графов, оркестрация)                  │
│                                                             │
│  GraphEngine → WorkflowRunner → InstructionRunner           │
│                                                             │
│  Тонкий клиент для:                                         │
│    - Data Layer (репозитории)                               │
│    - Security Layer (авторизация)                           │
│    - Queue Layer (Redis)                                    │
└─────────────────────────────────────────────────────────────┘
                              │
                ┌─────────────┼─────────────┐
                │             │             │
                ↓             ↓             ↓
        ┌──────────┐  ┌──────────┐  ┌──────────┐
        │   Data   │  │ Security │  │  Queue   │
        │  Layer   │  │  Layer   │  │  Layer   │
        └──────────┘  └──────────┘  └──────────┘
```

---

## 📦 Структура пакета `aq_graph_engine`

### Две части пазла

```
aq_graph_engine/
├── lib/
│   ├── aq_graph_engine.dart          # Публичный API
│   │
│   ├── src/
│   │   ├── engine/                   # СЕРВЕРНАЯ ЧАСТЬ
│   │   │   └── graph_engine.dart     # Движок выполнения
│   │   │
│   │   ├── runners/                  # СЕРВЕРНАЯ ЧАСТЬ
│   │   │   ├── workflow_runner.dart
│   │   │   ├── instruction_runner.dart
│   │   │   └── prompt_runner.dart
│   │   │
│   │   ├── transport/                # СЕРВЕРНАЯ + КЛИЕНТСКАЯ
│   │   │   ├── local_engine_transport.dart    # Локальное выполнение
│   │   │   └── http_engine_transport.dart     # Удалённое выполнение
│   │   │
│   │   ├── interfaces/               # КОНТРАКТЫ (обе стороны)
│   │   │   ├── i_engine_transport.dart
│   │   │   ├── i_run_repository.dart
│   │   │   └── i_graph_repository.dart
│   │   │
│   │   └── client/                   # КЛИЕНТСКАЯ ЧАСТЬ
│   │       ├── graph_engine_client.dart
│   │       └── remote_transport.dart
│   │
│   └── server/                       # СЕРВЕРНОЕ ПРИЛОЖЕНИЕ
│       ├── graph_engine_server.dart
│       └── handlers/
│           ├── run_handler.dart
│           └── resume_handler.dart
```

---

## 🔌 Принцип "Тонкий клиент"

### Что такое "тонкий клиент"

**Тонкий клиент** — это клиент, который:
- ✅ Использует готовые интерфейсы
- ✅ Отправляет запросы
- ✅ Получает ответы
- ❌ НЕ реализует бизнес-логику
- ❌ НЕ дублирует серверную логику
- ❌ НЕ содержит сложных алгоритмов

### Пример: ПРАВИЛЬНО ✅

**Клиент (Flutter приложение):**
```dart
// Только вызов готового сервиса
final client = GraphEngineClient(serverUrl);
final events = client.run(GraphRunRequest(...));

await for (final event in events) {
  if (event.type == GraphRunEventType.userInputRequired) {
    final input = await showDialog(...);
    await client.resumeWithInput(input);
  }
}
```

**Сервер (Graph Engine):**
```dart
// Вся логика выполнения
class GraphEngine {
  Stream<GraphRunEvent> run(GraphRunRequest request) {
    final runner = WorkflowRunner(...);
    return runner.start();
  }
}
```

### Пример: НЕПРАВИЛЬНО ❌

**Клиент (Flutter приложение):**
```dart
// ❌ ПЛОХО: Клиент реализует логику выполнения
class ClientSideWorkflowRunner {
  Future<void> executeNode(WorkflowNode node) {
    if (node.type == WorkflowNodeType.llmAction) {
      // ❌ Клиент не должен знать как выполнять узлы!
      final prompt = await compilePrompt(...);
      final result = await llm.ask(prompt);
      return result;
    }
  }
}
```

**Правильно:** Вся логика выполнения узлов — на сервере. Клиент только отправляет запрос "запусти граф".

---

## 🎯 Правило для каждого слоя

### 1. Flutter Application (UI слой)

**Разрешено:**
- ✅ Отображать UI
- ✅ Вызывать готовые сервисы
- ✅ Обрабатывать события
- ✅ Показывать формы для ввода

**Запрещено:**
- ❌ Реализовывать логику выполнения графов
- ❌ Реализовывать логику хранения данных
- ❌ Реализовывать логику авторизации
- ❌ Дублировать серверную логику

**Если чего-то не хватает:**
→ Задача для `aq_graph_engine` (серверная часть)

---

### 2. Graph Engine Server (бизнес-логика)

**Разрешено:**
- ✅ Выполнять графы (WorkflowRunner, InstructionRunner)
- ✅ Компилировать промпты (PromptRunner)
- ✅ Управлять жизненным циклом (suspend/resume)
- ✅ Использовать готовые репозитории от Data Layer
- ✅ Использовать готовые сервисы от Security Layer

**Запрещено:**
- ❌ Реализовывать логику хранения данных (это Data Layer)
- ❌ Реализовывать логику авторизации (это Security Layer)
- ❌ Реализовывать логику очередей (это Queue Layer)

**Если чего-то не хватает:**
→ Задача для Data Layer / Security Layer / Queue Layer

---

### 3. Data Layer / Security Layer / Queue Layer

**Разрешено:**
- ✅ Реализовывать свою бизнес-логику
- ✅ Предоставлять готовые интерфейсы (IRunRepository, IGraphRepository)
- ✅ Предоставлять готовые сервисы (AQSecurityService)

**Запрещено:**
- ❌ Знать о логике выполнения графов
- ❌ Зависеть от Graph Engine

---

## 🔗 Взаимодействие слоёв

### Инициализация сервера

```dart
// server_apps/graph_engine_server/bin/main.dart

void main() async {
  // 1. Подключаемся к Data Layer
  final dataServiceUrl = env['DATA_SERVICE_URL'];
  final storage = RemoteVaultStorage(
    endpoint: dataServiceUrl,
    tenantId: 'default',
    authToken: token,
  );
  await storage.connect();

  // 2. Получаем готовые репозитории от Data Layer
  final runRepo = RemoteRunRepository(storage);
  final graphRepo = RemoteGraphRepository(storage);

  // 3. Подключаемся к Security Layer
  final security = await AQSecurityClient.init(authServiceUrl);
  await security.loginWithApiKey(apiKey);

  // 4. Создаём движок с готовыми зависимостями
  final engine = GraphEngine(
    tools: buildToolRegistry(),
    runRepo: runRepo,      // ← от Data Layer
    graphRepo: graphRepo,  // ← от Data Layer
  );

  // 5. Запускаем HTTP сервер
  final server = GraphEngineServer(engine);
  await server.start(port: 8080);
}
```

**Ключевой момент:** Сервер НЕ реализует репозитории. Он получает их готовыми от Data Layer.

---

### Инициализация клиента

```dart
// Flutter приложение

void main() async {
  // 1. Создаём клиент для Graph Engine
  final graphClient = GraphEngineClient(
    serverUrl: 'http://localhost:8080',
  );

  // 2. Используем готовый интерфейс
  final events = graphClient.run(GraphRunRequest(
    runId: uuid,
    blueprintId: workflowId,
    projectId: projectId,
  ));

  // 3. Обрабатываем события
  await for (final event in events) {
    // UI логика
  }
}
```

**Ключевой момент:** Клиент НЕ реализует логику выполнения. Он только отправляет запросы.

---

## 📋 Контракты (интерфейсы)

### IEngineTransport — Транспорт для выполнения

```dart
abstract class IEngineTransport {
  /// Запустить граф
  Stream<GraphRunEvent> run(GraphRunRequest request);

  /// Продолжить выполнение после ввода
  Future<void> respondToInput(UserInputResponse response);

  /// Отменить выполнение
  Future<void> cancel(String runId);

  /// Проверить доступность
  Future<bool> isAvailable();

  void dispose();
}
```

**Реализации:**
- `LocalEngineTransport` — локальное выполнение (desktop)
- `HttpEngineTransport` — удалённое выполнение (клиент → сервер)

---

### IRunRepository — Хранилище запусков

```dart
abstract class IRunRepository {
  /// Получить запуск по ID
  Future<Map<String, dynamic>?> getRun(String runId);

  /// Обновить логи запуска
  Future<void> updateRunLog(String runId, List<String> logs, {String? status});

  /// Приостановить запуск
  Future<void> suspendRun({
    required String runId,
    required String contextJson,
    required String nodeId,
    required List<String> logs,
  });
}
```

**Реализации:**
- `LocalRunRepository` — локальное хранилище (in-memory или SQLite)
- `RemoteRunRepository` — удалённое хранилище (через Data Layer)

---

### IGraphRepository — Хранилище графов

```dart
abstract class IGraphRepository {
  /// Загрузить граф по ID
  Future<$Graph?> loadGraph(String graphId);
}
```

**Реализации:**
- `LocalGraphRepository` — локальное хранилище
- `RemoteGraphRepository` — удалённое хранилище (через Data Layer)

---

## 🚫 Антипаттерны (чего НЕ делать)

### ❌ Антипаттерн 1: Дублирование логики

**ПЛОХО:**
```dart
// Flutter приложение
class WorkflowExecutor {
  Future<void> executeWorkflow(WorkflowGraph graph) {
    // ❌ Клиент дублирует серверную логику
    for (final node in graph.nodes.values) {
      await executeNode(node);
    }
  }
}
```

**ХОРОШО:**
```dart
// Flutter приложение
final events = graphClient.run(request);
// Сервер выполняет, клиент только получает события
```

---

### ❌ Антипаттерн 2: Реализация репозиториев в приложении

**ПЛОХО:**
```dart
// Flutter приложение
class AppRunRepository implements IRunRepository {
  // ❌ Приложение реализует логику хранения
  @override
  Future<void> updateRunLog(String runId, List<String> logs) {
    await database.insert('runs', {'id': runId, 'logs': logs});
  }
}
```

**ХОРОШО:**
```dart
// Flutter приложение
final runRepo = RemoteRunRepository(dataServiceUrl);
// Используем готовый репозиторий от Data Layer
```

---

### ❌ Антипаттерн 3: Бизнес-логика в UI

**ПЛОХО:**
```dart
// Flutter приложение
class WorkflowScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: () async {
        // ❌ UI содержит бизнес-логику
        final graph = await loadGraph(graphId);
        final runner = WorkflowRunner(graph);
        await runner.start();
      },
    );
  }
}
```

**ХОРОШО:**
```dart
// Flutter приложение
class WorkflowScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: () async {
        // ✅ UI только вызывает готовый сервис
        await ref.read(graphEngineProvider).run(request);
      },
    );
  }
}
```

---

## 🎨 Обёртки и кастомизация

### Где разрешены обёртки

**Разрешено в целевых пакетах:**

```
pkgs/
├── aq_graph_client/          # ✅ Клиентские обёртки
│   ├── graph_engine_client.dart
│   └── cached_graph_repository.dart
│
├── aq_graph_worker/          # ✅ Воркер
│   └── graph_worker.dart
│
└── aq_graph_ui/              # ✅ UI компоненты
    └── graph_viewer_widget.dart
```

**Запрещено в приложении:**

```
lib/
├── ui/
│   └── workflow_screen.dart  # ❌ НЕ должен содержать обёртки
│
└── data/
    └── custom_run_repo.dart  # ❌ НЕ должен реализовывать репозитории
```

---

### Пример правильной обёртки

**Пакет `aq_graph_client`:**
```dart
// pkgs/aq_graph_client/lib/cached_graph_repository.dart

class CachedGraphRepository implements IGraphRepository {
  final IGraphRepository _remote;
  final Map<String, $Graph> _cache = {};

  CachedGraphRepository(this._remote);

  @override
  Future<$Graph?> loadGraph(String graphId) async {
    // Кеширование — это кастомизация, но не бизнес-логика
    if (_cache.containsKey(graphId)) {
      return _cache[graphId];
    }
    final graph = await _remote.loadGraph(graphId);
    if (graph != null) {
      _cache[graphId] = graph;
    }
    return graph;
  }
}
```

**Использование в приложении:**
```dart
// Flutter приложение
final remoteRepo = RemoteGraphRepository(dataServiceUrl);
final cachedRepo = CachedGraphRepository(remoteRepo); // ✅ Обёртка из пакета
final client = GraphEngineClient(serverUrl, graphRepo: cachedRepo);
```

---

## 📝 Чек-лист для разработчика

### Перед добавлением кода в приложение, спроси себя:

1. ❓ **Это бизнес-логика?**
   - Если да → код должен быть в сервисе, не в приложении

2. ❓ **Это дублирует серверную логику?**
   - Если да → используй готовый API сервиса

3. ❓ **Это реализация репозитория?**
   - Если да → репозиторий должен быть в Data Layer

4. ❓ **Это обёртка/кастомизация?**
   - Если да → создай целевой пакет (например, `aq_graph_client`)

5. ❓ **Это UI логика?**
   - Если да → можно в приложении, но только UI

---

## 🎯 Итоговое правило

### Золотое правило тонкого клиента

**Если клиенту чего-то не хватает — это задача для сервиса, а не для клиента.**

**Примеры:**

| Проблема | ❌ Неправильно | ✅ Правильно |
|----------|---------------|-------------|
| Нет кеширования графов | Реализовать кеш в приложении | Создать пакет `aq_graph_client` с `CachedGraphRepository` |
| Нет retry при ошибке | Реализовать retry в UI | Добавить retry в `GraphEngine` на сервере |
| Нет валидации входов | Валидировать в UI | Добавить валидацию в `InstructionRunner` |
| Нет метрик | Собирать метрики в приложении | Добавить метрики в `GraphEngine` |

---

## 🚀 Преимущества подхода

### Почему "тонкий клиент" лучше

1. **Единая точка истины** — вся логика на сервере
2. **Легче тестировать** — тестируешь сервер, а не каждый клиент
3. **Легче обновлять** — обновил сервер, все клиенты получили новую логику
4. **Меньше дублирования** — логика написана один раз
5. **Безопаснее** — бизнес-логика не утекает в клиентский код

---

## 📚 Следующие шаги

Читайте:
- [DEVELOPMENT_PLAN.md](./DEVELOPMENT_PLAN.md) — план разработки
- [OVERVIEW.md](./OVERVIEW.md) — обзор системы
- [WORKFLOW_GRAPH.md](./WORKFLOW_GRAPH.md) — WorkflowGraph в деталях
