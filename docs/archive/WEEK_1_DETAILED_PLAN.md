# Неделя 1: Детальный план разработки

## 🎯 Цель недели

Создать модульную, расширяемую архитектуру для клиент-серверного взаимодействия Graph Engine с акцентом на SOLID принципы и pluggable компоненты.

**Результат:** HTTP сервер с WebSocket поддержкой, готовый к расширению новыми транспортами и стратегиями выполнения.

---

## 📋 Содержание

- [День 1: Архитектура и структура проекта](#день-1-архитектура-и-структура-проекта)
- [День 2: HTTP сервер (модульный подход)](#день-2-http-сервер-модульный-подход)
- [День 3: WebSocket транспорт (расширяемый)](#день-3-websocket-транспорт-расширяемый)
- [День 4: HttpEngineTransport (серверная сторона)](#день-4-httpenginetransport-серверная-сторона)
- [День 5: Интеграция и рефакторинг](#день-5-интеграция-и-рефакторинг)
- [Ключевые принципы](#ключевые-принципы)
- [Примеры расширения](#примеры-расширения)
- [Чек-лист готовности](#чек-лист-готовности)

---

## Ключевые принципы

### 1. Dependency Injection
Все зависимости через конструктор. Никаких синглтонов или глобального состояния.

### 2. Interface Segregation
Маленькие, специфичные интерфейсы вместо больших универсальных.

### 3. Open/Closed Principle
Открыто для расширения (новые транспорты, middleware, стратегии), закрыто для модификации.

### 4. Single Responsibility
Один класс = одна ответственность. Router только маршрутизирует, Handler только обрабатывает.

### 5. Pluggable Architecture
Любой компонент можно заменить без изменения остального кода.

---

## День 1: Архитектура и структура проекта

### Цель дня
Создать модульную структуру с четким разделением ответственности и dependency injection.

### Утро (09:00 - 13:00): Архитектура слоёв

#### 09:00 - 10:30: Создание структуры проекта

**Задача:** Создать модульную структуру пакета с четким разделением слоёв.

**Структура директорий:**
```
server_apps/graph_engine_server/
├── bin/
│   └── main.dart                    # Точка входа
├── lib/
│   ├── server.dart                  # Публичный API сервера
│   ├── core/
│   │   ├── interfaces/              # Контракты (DI boundaries)
│   │   │   ├── i_router.dart
│   │   │   ├── i_handler.dart
│   │   │   ├── i_middleware.dart
│   │   │   └── i_execution_strategy.dart
│   │   ├── di/                      # Dependency Injection
│   │   │   ├── service_locator.dart
│   │   │   └── server_module.dart
│   │   └── types/                   # Общие типы
│   │       ├── request_context.dart
│   │       └── response_builder.dart
│   ├── routing/                     # Слой маршрутизации
│   │   ├── router.dart
│   │   └── route_registry.dart
│   ├── handlers/                    # Слой обработчиков
│   │   ├── run_handler.dart
│   │   ├── resume_handler.dart
│   │   ├── cancel_handler.dart
│   │   └── status_handler.dart
│   ├── middleware/                  # Слой middleware
│   │   ├── auth_middleware.dart
│   │   ├── logging_middleware.dart
│   │   ├── cors_middleware.dart
│   │   └── error_middleware.dart
│   ├── transport/                   # Слой транспорта
│   │   ├── http_engine_transport.dart
│   │   └── websocket_manager.dart
│   └── strategies/                  # Стратегии выполнения
│       ├── sync_execution_strategy.dart
│       ├── async_execution_strategy.dart
│       └── queue_execution_strategy.dart
└── test/
    ├── unit/
    ├── integration/
    └── fixtures/
```

**Команды:**
```bash
cd server_apps
mkdir -p graph_engine_server/{bin,lib/{core/{interfaces,di,types},routing,handlers,middleware,transport,strategies},test/{unit,integration,fixtures}}
```

**Принципы:**
- **Слой interfaces** — контракты, не зависят ни от чего
- **Слой routing** — зависит только от interfaces
- **Слой handlers** — зависит от interfaces и GraphEngine
- **Слой middleware** — зависит только от interfaces
- **Слой transport** — зависит от interfaces и GraphEngine

---

#### 10:30 - 11:30: Определение интерфейсов

**Задача:** Создать маленькие, специфичные интерфейсы (Interface Segregation Principle).

**1. IRouter — Маршрутизация запросов**

```dart
// lib/core/interfaces/i_router.dart

import 'package:shelf/shelf.dart';

/// Контракт для маршрутизатора HTTP запросов
abstract class IRouter {
  /// Зарегистрировать маршрут
  void register(String method, String path, Handler handler);

  /// Получить Shelf Handler для интеграции с сервером
  Handler get handler;
}
```

**2. IHandler — Обработка запросов**

```dart
// lib/core/interfaces/i_handler.dart

import 'package:shelf/shelf.dart';
import '../types/request_context.dart';

/// Контракт для обработчика HTTP запроса
abstract class IHandler {
  /// Обработать запрос
  Future<Response> handle(RequestContext context);
}
```

**3. IMiddleware — Промежуточная обработка**

```dart
// lib/core/interfaces/i_middleware.dart

import 'package:shelf/shelf.dart';

/// Контракт для middleware
abstract class IMiddleware {
  /// Обработать запрос перед передачей в handler
  Middleware get middleware;
}
```

**4. IExecutionStrategy — Стратегия выполнения**

```dart
// lib/core/interfaces/i_execution_strategy.dart

import 'package:aq_graph_engine/aq_graph_engine.dart';

/// Контракт для стратегии выполнения графа
abstract class IExecutionStrategy {
  /// Выполнить граф с заданной стратегией
  Stream<GraphRunEvent> execute(
    GraphEngine engine,
    GraphRunRequest request,
  );

  /// Название стратегии (для логирования)
  String get name;
}
```

**Почему маленькие интерфейсы?**
- Легче тестировать (меньше методов для мока)
- Легче реализовывать (не нужно реализовывать ненужные методы)
- Легче понимать (одна ответственность)

---

#### 11:30 - 13:00: Типы данных и контексты

**Задача:** Создать типы для передачи данных между слоями.

**1. RequestContext — Контекст запроса**

```dart
// lib/core/types/request_context.dart

import 'package:shelf/shelf.dart';

/// Контекст HTTP запроса с дополнительными данными
class RequestContext {
  final Request request;
  final Map<String, dynamic> params;
  final Map<String, dynamic> metadata;

  RequestContext({
    required this.request,
    this.params = const {},
    this.metadata = const {},
  });

  /// Получить параметр из URL
  String? param(String key) => params[key] as String?;

  /// Получить метаданные (например, userId из JWT)
  T? meta<T>(String key) => metadata[key] as T?;

  /// Создать копию с дополнительными метаданными
  RequestContext withMeta(String key, dynamic value) {
    return RequestContext(
      request: request,
      params: params,
      metadata: {...metadata, key: value},
    );
  }
}
```

**2. ResponseBuilder — Построение ответов**

```dart
// lib/core/types/response_builder.dart

import 'dart:convert';
import 'package:shelf/shelf.dart';

/// Утилита для построения HTTP ответов
class ResponseBuilder {
  /// JSON ответ с кодом 200
  static Response ok(Map<String, dynamic> data) {
    return Response.ok(
      jsonEncode(data),
      headers: {'Content-Type': 'application/json'},
    );
  }

  /// JSON ответ с кодом 201
  static Response created(Map<String, dynamic> data) {
    return Response(
      201,
      body: jsonEncode(data),
      headers: {'Content-Type': 'application/json'},
    );
  }

  /// Ошибка с кодом 400
  static Response badRequest(String message) {
    return Response(
      400,
      body: jsonEncode({'error': message}),
      headers: {'Content-Type': 'application/json'},
    );
  }

  /// Ошибка с кодом 404
  static Response notFound(String message) {
    return Response(
      404,
      body: jsonEncode({'error': message}),
      headers: {'Content-Type': 'application/json'},
    );
  }

  /// Ошибка с кодом 500
  static Response internalError(String message) {
    return Response(
      500,
      body: jsonEncode({'error': message}),
      headers: {'Content-Type': 'application/json'},
    );
  }
}
```

---

### День (14:00 - 18:00): Dependency Injection

#### 14:00 - 15:30: Service Locator

**Задача:** Создать простой DI контейнер для управления зависимостями.

**Реализация:**

```dart
// lib/core/di/service_locator.dart

/// Простой Service Locator для DI
class ServiceLocator {
  final Map<Type, dynamic> _services = {};
  final Map<Type, dynamic Function()> _factories = {};

  /// Зарегистрировать синглтон
  void registerSingleton<T>(T instance) {
    _services[T] = instance;
  }

  /// Зарегистрировать фабрику (создаёт новый инстанс каждый раз)
  void registerFactory<T>(T Function() factory) {
    _factories[T] = factory;
  }

  /// Получить сервис
  T get<T>() {
    // Сначала проверяем синглтоны
    if (_services.containsKey(T)) {
      return _services[T] as T;
    }

    // Затем фабрики
    if (_factories.containsKey(T)) {
      return _factories[T]!() as T;
    }

    throw Exception('Service of type $T not registered');
  }

  /// Проверить, зарегистрирован ли сервис
  bool isRegistered<T>() {
    return _services.containsKey(T) || _factories.containsKey(T);
  }

  /// Очистить все регистрации (для тестов)
  void clear() {
    _services.clear();
    _factories.clear();
  }
}
```

**Почему Service Locator, а не get_it?**
- Простота (нет внешних зависимостей)
- Контроль (понимаем как работает)
- Достаточно для наших нужд

---

#### 15:30 - 17:00: Server Module

**Задача:** Создать модуль для регистрации всех зависимостей сервера.

**Реализация:**

```dart
// lib/core/di/server_module.dart

import 'package:aq_graph_engine/aq_graph_engine.dart';
import '../interfaces/i_router.dart';
import '../interfaces/i_execution_strategy.dart';
import '../../routing/router.dart';
import '../../handlers/run_handler.dart';
import '../../handlers/resume_handler.dart';
import '../../handlers/cancel_handler.dart';
import '../../handlers/status_handler.dart';
import '../../middleware/auth_middleware.dart';
import '../../middleware/logging_middleware.dart';
import '../../middleware/cors_middleware.dart';
import '../../middleware/error_middleware.dart';
import '../../strategies/sync_execution_strategy.dart';
import 'service_locator.dart';

/// Модуль для регистрации зависимостей сервера
class ServerModule {
  final ServiceLocator locator;
  final GraphEngine engine;

  ServerModule({
    required this.locator,
    required this.engine,
  });

  /// Зарегистрировать все зависимости
  void register() {
    // 1. Регистрируем GraphEngine (синглтон)
    locator.registerSingleton<GraphEngine>(engine);

    // 2. Регистрируем стратегию выполнения (синглтон)
    locator.registerSingleton<IExecutionStrategy>(
      SyncExecutionStrategy(),
    );

    // 3. Регистрируем Router (синглтон)
    locator.registerSingleton<IRouter>(
      ShelfRouter(),
    );

    // 4. Регистрируем Handlers (фабрики, создаются для каждого запроса)
    locator.registerFactory<RunHandler>(
      () => RunHandler(
        engine: locator.get<GraphEngine>(),
        strategy: locator.get<IExecutionStrategy>(),
      ),
    );

    locator.registerFactory<ResumeHandler>(
      () => ResumeHandler(
        engine: locator.get<GraphEngine>(),
      ),
    );

    locator.registerFactory<CancelHandler>(
      () => CancelHandler(
        engine: locator.get<GraphEngine>(),
      ),
    );

    locator.registerFactory<StatusHandler>(
      () => StatusHandler(
        engine: locator.get<GraphEngine>(),
      ),
    );

    // 5. Регистрируем Middleware (синглтоны)
    locator.registerSingleton<AuthMiddleware>(
      AuthMiddleware(),
    );

    locator.registerSingleton<LoggingMiddleware>(
      LoggingMiddleware(),
    );

    locator.registerSingleton<CorsMiddleware>(
      CorsMiddleware(),
    );

    locator.registerSingleton<ErrorMiddleware>(
      ErrorMiddleware(),
    );
  }

  /// Настроить маршруты
  void setupRoutes() {
    final router = locator.get<IRouter>();

    // POST /api/v1/runs - запуск графа
    router.register(
      'POST',
      '/api/v1/runs',
      (request) => locator.get<RunHandler>().handle(
        RequestContext(request: request),
      ),
    );

    // POST /api/v1/runs/:id/resume - возобновление
    router.register(
      'POST',
      '/api/v1/runs/<id>/resume',
      (request) => locator.get<ResumeHandler>().handle(
        RequestContext(
          request: request,
          params: {'id': request.url.pathSegments[3]},
        ),
      ),
    );

    // DELETE /api/v1/runs/:id - отмена
    router.register(
      'DELETE',
      '/api/v1/runs/<id>',
      (request) => locator.get<CancelHandler>().handle(
        RequestContext(
          request: request,
          params: {'id': request.url.pathSegments[3]},
        ),
      ),
    );

    // GET /api/v1/runs/:id/status - статус
    router.register(
      'GET',
      '/api/v1/runs/<id>/status',
      (request) => locator.get<StatusHandler>().handle(
        RequestContext(
          request: request,
          params: {'id': request.url.pathSegments[3]},
        ),
      ),
    );
  }
}
```

**Преимущества модульного подхода:**
- Все зависимости в одном месте
- Легко тестировать (можно подменить модуль)
- Легко расширять (добавить новый handler = 2 строки кода)

---

#### 17:00 - 18:00: Точка входа (main.dart)

**Задача:** Создать точку входа с инициализацией DI.

**Реализация:**

```dart
// bin/main.dart

import 'dart:io';
import 'package:aq_graph_engine/aq_graph_engine.dart';
import 'package:graph_engine_server/server.dart';
import 'package:graph_engine_server/core/di/service_locator.dart';
import 'package:graph_engine_server/core/di/server_module.dart';

void main() async {
  // 1. Создаём GraphEngine (с реальными зависимостями)
  final engine = GraphEngine(
    tools: buildToolRegistry(),
    runRepo: await createRunRepository(),
    graphRepo: await createGraphRepository(),
  );

  // 2. Создаём DI контейнер
  final locator = ServiceLocator();

  // 3. Регистрируем зависимости
  final module = ServerModule(
    locator: locator,
    engine: engine,
  );
  module.register();
  module.setupRoutes();

  // 4. Создаём и запускаем сервер
  final server = GraphEngineServer(locator: locator);
  await server.start(port: 8080);

  print('✅ Server running on http://localhost:8080');
  print('   Health: http://localhost:8080/health');
  print('   API: http://localhost:8080/api/v1/runs');

  // 5. Graceful shutdown
  ProcessSignal.sigint.watch().listen((_) async {
    print('\n🛑 Shutting down...');
    await server.stop();
    exit(0);
  });
}

// Вспомогательные функции (заглушки на День 1)
ToolRegistry buildToolRegistry() {
  return ToolRegistry(); // TODO: реализовать
}

Future<IRunRepository> createRunRepository() async {
  return LocalRunRepository(); // TODO: подключить к Data Layer
}

Future<IGraphRepository> createGraphRepository() async {
  return LocalGraphRepository(); // TODO: подключить к Data Layer
}
```

---

### Результат дня

✅ **Модульная структура проекта** — четкое разделение на слои
✅ **DI контейнер настроен** — ServiceLocator + ServerModule
✅ **Интерфейсы определены** — IRouter, IHandler, IMiddleware, IExecutionStrategy
✅ **Типы данных созданы** — RequestContext, ResponseBuilder
✅ **Точка входа готова** — main.dart с инициализацией

### Диаграмма зависимостей

```
┌─────────────────────────────────────────────────────────┐
│                      main.dart                          │
│                   (точка входа)                         │
└────────────────────┬────────────────────────────────────┘
                     │
                     ↓
┌─────────────────────────────────────────────────────────┐
│                  ServerModule                           │
│              (регистрация зависимостей)                 │
└────────────────────┬────────────────────────────────────┘
                     │
        ┌────────────┼────────────┐
        ↓            ↓            ↓
   ┌────────┐  ┌─────────┐  ┌──────────┐
   │ Router │  │ Handlers│  │Middleware│
   └────────┘  └─────────┘  └──────────┘
        │            │            │
        └────────────┼────────────┘
                     ↓
              ┌─────────────┐
              │ Interfaces  │
              │ (контракты) │
              └─────────────┘
```

### Проверка SOLID

- ✅ **S**ingle Responsibility — каждый класс имеет одну ответственность
- ✅ **O**pen/Closed — можно добавить новый Handler без изменения Router
- ✅ **L**iskov Substitution — все реализации IHandler взаимозаменяемы
- ✅ **I**nterface Segregation — маленькие, специфичные интерфейсы
- ✅ **D**ependency Inversion — зависимости через интерфейсы, не конкретные классы

---

## День 2: HTTP сервер (модульный подход)

### Цель дня
Создать HTTP сервер с четким разделением на Router, Handlers и Middleware.

### Утро (09:00 - 13:00): Router и Handlers

#### 09:00 - 10:30: Реализация Router

**Задача:** Создать Router с поддержкой динамических параметров.

**Реализация:**

```dart
// lib/routing/router.dart

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart' as shelf;
import '../core/interfaces/i_router.dart';

/// Реализация IRouter на основе shelf_router
class ShelfRouter implements IRouter {
  final shelf.Router _router = shelf.Router();
  final List<Middleware> _middleware = [];

  @override
  void register(String method, String path, Handler handler) {
    switch (method.toUpperCase()) {
      case 'GET':
        _router.get(path, handler);
        break;
      case 'POST':
        _router.post(path, handler);
        break;
      case 'PUT':
        _router.put(path, handler);
        break;
      case 'DELETE':
        _router.delete(path, handler);
        break;
      case 'PATCH':
        _router.patch(path, handler);
        break;
      default:
        throw ArgumentError('Unsupported HTTP method: $method');
    }
  }

  /// Добавить middleware (будет применён ко всем маршрутам)
  void use(Middleware middleware) {
    _middleware.add(middleware);
  }

  @override
  Handler get handler {
    // Применяем middleware в порядке регистрации
    Handler result = _router;
    for (final mw in _middleware.reversed) {
      result = mw(result);
    }
    return result;
  }
}
```

**Почему shelf_router?**
- Поддержка параметров в URL (`/runs/<id>`)
- Проверенное решение
- Легко тестировать

---

#### 10:30 - 11:30: RunHandler — запуск графа

**Задача:** Создать handler для запуска графа через HTTP.

**Реализация:**

```dart
// lib/handlers/run_handler.dart

import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:aq_graph_engine/aq_graph_engine.dart';
import '../core/interfaces/i_handler.dart';
import '../core/interfaces/i_execution_strategy.dart';
import '../core/types/request_context.dart';
import '../core/types/response_builder.dart';

/// Handler для запуска графа
class RunHandler implements IHandler {
  final GraphEngine engine;
  final IExecutionStrategy strategy;

  RunHandler({
    required this.engine,
    required this.strategy,
  });

  @override
  Future<Response> handle(RequestContext context) async {
    try {
      // 1. Парсим тело запроса
      final body = await context.request.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;

      // 2. Валидируем запрос
      if (!json.containsKey('blueprintId')) {
        return ResponseBuilder.badRequest('Missing blueprintId');
      }

      if (!json.containsKey('projectId')) {
        return ResponseBuilder.badRequest('Missing projectId');
      }

      // 3. Создаём GraphRunRequest
      final request = GraphRunRequest(
        runId: json['runId'] as String? ?? _generateRunId(),
        blueprintId: json['blueprintId'] as String,
        projectId: json['projectId'] as String,
        projectPath: json['projectPath'] as String?,
        initialContext: json['initialContext'] as Map<String, dynamic>?,
      );

      // 4. Запускаем через стратегию (не блокируем HTTP запрос)
      final events = strategy.execute(engine, request);

      // 5. Подписываемся на первое событие (подтверждение запуска)
      await events.first;

      // 6. Возвращаем runId
      return ResponseBuilder.created({
        'runId': request.runId,
        'status': 'started',
        'eventsUrl': '/api/v1/runs/${request.runId}/events',
      });
    } on FormatException catch (e) {
      return ResponseBuilder.badRequest('Invalid JSON: ${e.message}');
    } catch (e) {
      return ResponseBuilder.internalError('Failed to start run: $e');
    }
  }

  String _generateRunId() {
    return DateTime.now().millisecondsSinceEpoch.toString();
  }
}
```

**Ключевые моменты:**
- Handler НЕ блокирует HTTP запрос (возвращает сразу после запуска)
- Валидация на уровне handler
- Использует IExecutionStrategy (можно подменить)

---

#### 11:30 - 12:30: ResumeHandler и CancelHandler

**ResumeHandler:**

```dart
// lib/handlers/resume_handler.dart

import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:aq_graph_engine/aq_graph_engine.dart';
import '../core/interfaces/i_handler.dart';
import '../core/types/request_context.dart';
import '../core/types/response_builder.dart';

/// Handler для возобновления выполнения
class ResumeHandler implements IHandler {
  final GraphEngine engine;

  ResumeHandler({required this.engine});

  @override
  Future<Response> handle(RequestContext context) async {
    try {
      // 1. Получаем runId из URL
      final runId = context.param('id');
      if (runId == null) {
        return ResponseBuilder.badRequest('Missing runId');
      }

      // 2. Парсим тело запроса
      final body = await context.request.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;

      // 3. Создаём UserInputResponse
      final response = UserInputResponse(
        runId: runId,
        data: json['data'] as Map<String, dynamic>,
      );

      // 4. Возобновляем выполнение
      await engine.resumeWithInput(response);

      // 5. Возвращаем успех
      return ResponseBuilder.ok({
        'runId': runId,
        'status': 'resumed',
      });
    } on FormatException catch (e) {
      return ResponseBuilder.badRequest('Invalid JSON: ${e.message}');
    } catch (e) {
      return ResponseBuilder.internalError('Failed to resume: $e');
    }
  }
}
```

**CancelHandler:**

```dart
// lib/handlers/cancel_handler.dart

import 'package:shelf/shelf.dart';
import 'package:aq_graph_engine/aq_graph_engine.dart';
import '../core/interfaces/i_handler.dart';
import '../core/types/request_context.dart';
import '../core/types/response_builder.dart';

/// Handler для отмены выполнения
class CancelHandler implements IHandler {
  final GraphEngine engine;

  CancelHandler({required this.engine});

  @override
  Future<Response> handle(RequestContext context) async {
    try {
      // 1. Получаем runId из URL
      final runId = context.param('id');
      if (runId == null) {
        return ResponseBuilder.badRequest('Missing runId');
      }

      // 2. Отменяем выполнение
      await engine.cancel(runId);

      // 3. Возвращаем успех
      return ResponseBuilder.ok({
        'runId': runId,
        'status': 'cancelled',
      });
    } catch (e) {
      return ResponseBuilder.internalError('Failed to cancel: $e');
    }
  }
}
```

---

#### 12:30 - 13:00: StatusHandler

**Задача:** Handler для получения статуса выполнения.

```dart
// lib/handlers/status_handler.dart

import 'package:shelf/shelf.dart';
import 'package:aq_graph_engine/aq_graph_engine.dart';
import '../core/interfaces/i_handler.dart';
import '../core/types/request_context.dart';
import '../core/types/response_builder.dart';

/// Handler для получения статуса выполнения
class StatusHandler implements IHandler {
  final GraphEngine engine;

  StatusHandler({required this.engine});

  @override
  Future<Response> handle(RequestContext context) async {
    try {
      // 1. Получаем runId из URL
      final runId = context.param('id');
      if (runId == null) {
        return ResponseBuilder.badRequest('Missing runId');
      }

      // 2. Получаем статус из репозитория
      final run = await engine.runRepo.getRun(runId);
      if (run == null) {
        return ResponseBuilder.notFound('Run not found');
      }

      // 3. Возвращаем статус
      return ResponseBuilder.ok({
        'runId': runId,
        'status': run['status'],
        'currentNode': run['currentNode'],
        'logs': run['logs'],
      });
    } catch (e) {
      return ResponseBuilder.internalError('Failed to get status: $e');
    }
  }
}
```

---

### День (14:00 - 18:00): Middleware система

#### 14:00 - 15:00: LoggingMiddleware

**Задача:** Middleware для логирования всех запросов.

```dart
// lib/middleware/logging_middleware.dart

import 'package:shelf/shelf.dart';
import '../core/interfaces/i_middleware.dart';

/// Middleware для логирования HTTP запросов
class LoggingMiddleware implements IMiddleware {
  @override
  Middleware get middleware {
    return (Handler innerHandler) {
      return (Request request) async {
        final startTime = DateTime.now();

        print('→ ${request.method} ${request.url}');

        final response = await innerHandler(request);

        final duration = DateTime.now().difference(startTime);
        print('← ${response.statusCode} (${duration.inMilliseconds}ms)');

        return response;
      };
    };
  }
}
```

---

#### 15:00 - 16:00: CorsMiddleware

**Задача:** Middleware для CORS (Cross-Origin Resource Sharing).

```dart
// lib/middleware/cors_middleware.dart

import 'package:shelf/shelf.dart';
import '../core/interfaces/i_middleware.dart';

/// Middleware для CORS
class CorsMiddleware implements IMiddleware {
  final String allowOrigin;
  final String allowMethods;
  final String allowHeaders;

  CorsMiddleware({
    this.allowOrigin = '*',
    this.allowMethods = 'GET, POST, PUT, DELETE, PATCH, OPTIONS',
    this.allowHeaders = 'Content-Type, Authorization',
  });

  @override
  Middleware get middleware {
    return (Handler innerHandler) {
      return (Request request) async {
        // Обрабатываем preflight запросы
        if (request.method == 'OPTIONS') {
          return Response.ok('', headers: _corsHeaders);
        }

        // Добавляем CORS заголовки к ответу
        final response = await innerHandler(request);
        return response.change(headers: _corsHeaders);
      };
    };
  }

  Map<String, String> get _corsHeaders => {
        'Access-Control-Allow-Origin': allowOrigin,
        'Access-Control-Allow-Methods': allowMethods,
        'Access-Control-Allow-Headers': allowHeaders,
      };
}
```

---

#### 16:00 - 17:00: AuthMiddleware

**Задача:** Middleware для проверки JWT токена.

```dart
// lib/middleware/auth_middleware.dart

import 'package:shelf/shelf.dart';
import '../core/interfaces/i_middleware.dart';
import '../core/types/response_builder.dart';

/// Middleware для аутентификации через JWT
class AuthMiddleware implements IMiddleware {
  final List<String> publicPaths;

  AuthMiddleware({
    this.publicPaths = const ['/health', '/metrics'],
  });

  @override
  Middleware get middleware {
    return (Handler innerHandler) {
      return (Request request) async {
        // Пропускаем публичные пути
        if (_isPublicPath(request.url.path)) {
          return innerHandler(request);
        }

        // Проверяем наличие токена
        final authHeader = request.headers['authorization'];
        if (authHeader == null) {
          return Response(
            401,
            body: 'Missing Authorization header',
          );
        }

        // Извлекаем токен
        final token = authHeader.replaceFirst('Bearer ', '');

        // Валидируем токен (заглушка на День 2)
        final userId = await _validateToken(token);
        if (userId == null) {
          return Response(
            401,
            body: 'Invalid token',
          );
        }

        // Добавляем userId в request context
        final newRequest = request.change(context: {
          ...request.context,
          'userId': userId,
        });

        return innerHandler(newRequest);
      };
    };
  }

  bool _isPublicPath(String path) {
    return publicPaths.any((p) => path.startsWith(p));
  }

  Future<String?> _validateToken(String token) async {
    // TODO: интеграция с Security Layer
    // Пока возвращаем заглушку
    return 'user-123';
  }
}
```

---

#### 17:00 - 18:00: ErrorMiddleware

**Задача:** Middleware для обработки необработанных ошибок.

```dart
// lib/middleware/error_middleware.dart

import 'package:shelf/shelf.dart';
import '../core/interfaces/i_middleware.dart';
import '../core/types/response_builder.dart';

/// Middleware для обработки ошибок
class ErrorMiddleware implements IMiddleware {
  @override
  Middleware get middleware {
    return (Handler innerHandler) {
      return (Request request) async {
        try {
          return await innerHandler(request);
        } catch (error, stackTrace) {
          // Логируем ошибку
          print('❌ Unhandled error: $error');
          print(stackTrace);

          // Возвращаем 500
          return ResponseBuilder.internalError(
            'Internal server error',
          );
        }
      };
    };
  }
}
```

---

### Интеграция: GraphEngineServer

**Задача:** Собрать всё вместе в один сервер.

```dart
// lib/server.dart

import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'core/di/service_locator.dart';
import 'core/interfaces/i_router.dart';
import 'middleware/logging_middleware.dart';
import 'middleware/cors_middleware.dart';
import 'middleware/auth_middleware.dart';
import 'middleware/error_middleware.dart';

/// HTTP сервер для Graph Engine
class GraphEngineServer {
  final ServiceLocator locator;
  HttpServer? _server;

  GraphEngineServer({required this.locator});

  /// Запустить сервер
  Future<void> start({int port = 8080}) async {
    // 1. Получаем router из DI
    final router = locator.get<IRouter>();

    // 2. Получаем middleware из DI
    final errorMw = locator.get<ErrorMiddleware>();
    final loggingMw = locator.get<LoggingMiddleware>();
    final corsMw = locator.get<CorsMiddleware>();
    final authMw = locator.get<AuthMiddleware>();

    // 3. Создаём pipeline (порядок важен!)
    final pipeline = Pipeline()
        .addMiddleware(errorMw.middleware)      // Первым ловит все ошибки
        .addMiddleware(loggingMw.middleware)    // Логирует запросы
        .addMiddleware(corsMw.middleware)       // Добавляет CORS
        .addMiddleware(authMw.middleware)       // Проверяет авторизацию
        .addHandler(router.handler);            // Обрабатывает запрос

    // 4. Запускаем HTTP сервер
    _server = await io.serve(pipeline, 'localhost', port);
    print('✅ Server started on http://localhost:$port');
  }

  /// Остановить сервер
  Future<void> stop() async {
    await _server?.close(force: true);
    print('🛑 Server stopped');
  }
}
```

---

### Результат дня

✅ **HTTP сервер с модульной архитектурой** — Router + Handlers + Middleware
✅ **Pluggable middleware** — можно добавить новый middleware без изменения кода
✅ **Handlers с DI** — все зависимости через конструктор
✅ **CORS поддержка** — готово для фронтенда
✅ **Логирование** — все запросы логируются
✅ **Обработка ошибок** — необработанные ошибки не роняют сервер

### Диаграмма обработки запроса

```
HTTP Request
     ↓
ErrorMiddleware (ловит все ошибки)
     ↓
LoggingMiddleware (логирует запрос)
     ↓
CorsMiddleware (добавляет CORS заголовки)
     ↓
AuthMiddleware (проверяет JWT токен)
     ↓
Router (определяет handler)
     ↓
Handler (обрабатывает запрос)
     ↓
Response
```

### Проверка модульности

**Можно ли добавить новый Handler без изменения Router?**
✅ Да! Регистрируем в ServerModule:
```dart
locator.registerFactory<MyNewHandler>(
  () => MyNewHandler(engine: locator.get<GraphEngine>()),
);

router.register('GET', '/api/v1/my-endpoint',
  (req) => locator.get<MyNewHandler>().handle(RequestContext(request: req))
);
```

**Можно ли добавить новый Middleware без изменения существующих?**
✅ Да! Создаём класс, реализуем IMiddleware, регистрируем в DI, добавляем в pipeline.

**Можно ли заменить Router на другую реализацию?**
✅ Да! Создаём класс, реализуем IRouter, регистрируем в DI вместо ShelfRouter.

---

## День 3: WebSocket транспорт (расширяемый)

### Цель дня
Создать WebSocket менеджер с поддержкой разных протоколов и reconnect стратегий.

### Утро (09:00 - 13:00): WebSocketManager

#### 09:00 - 10:00: Интерфейсы для WebSocket

**Задача:** Определить контракты для расширяемой WebSocket архитектуры.

**1. IWebSocketProtocol — Протокол сериализации**

```dart
// lib/core/interfaces/i_websocket_protocol.dart

/// Контракт для протокола сериализации WebSocket сообщений
abstract class IWebSocketProtocol {
  /// Сериализовать объект в формат для передачи
  dynamic encode(Map<String, dynamic> data);

  /// Десериализовать полученные данные
  Map<String, dynamic> decode(dynamic data);

  /// Название протокола (для логирования)
  String get name;

  /// Content-Type для HTTP заголовков
  String get contentType;
}
```

**2. IReconnectStrategy — Стратегия переподключения**

```dart
// lib/core/interfaces/i_reconnect_strategy.dart

/// Контракт для стратегии переподключения
abstract class IReconnectStrategy {
  /// Получить задержку перед следующей попыткой
  Duration getDelay(int attemptNumber);

  /// Нужно ли пытаться переподключиться
  bool shouldRetry(int attemptNumber);

  /// Сбросить счётчик попыток
  void reset();

  /// Название стратегии
  String get name;
}
```

**3. IWebSocketConnection — Абстракция соединения**

```dart
// lib/core/interfaces/i_websocket_connection.dart

/// Контракт для WebSocket соединения
abstract class IWebSocketConnection {
  /// Подключиться к серверу
  Future<void> connect(String url);

  /// Отключиться от сервера
  Future<void> disconnect();

  /// Отправить сообщение
  void send(Map<String, dynamic> data);

  /// Поток входящих сообщений
  Stream<Map<String, dynamic>> get messages;

  /// Поток событий соединения
  Stream<ConnectionEvent> get events;

  /// Текущее состояние соединения
  ConnectionState get state;
}

/// События соединения
enum ConnectionEvent {
  connecting,
  connected,
  disconnected,
  error,
}

/// Состояние соединения
enum ConnectionState {
  disconnected,
  connecting,
  connected,
}
```

---

#### 10:00 - 11:30: Реализация протоколов

**JsonProtocol — JSON сериализация**

```dart
// lib/transport/protocols/json_protocol.dart

import 'dart:convert';
import '../../core/interfaces/i_websocket_protocol.dart';

/// Протокол JSON для WebSocket
class JsonProtocol implements IWebSocketProtocol {
  @override
  String encode(Map<String, dynamic> data) {
    return jsonEncode(data);
  }

  @override
  Map<String, dynamic> decode(dynamic data) {
    if (data is String) {
      return jsonDecode(data) as Map<String, dynamic>;
    }
    throw FormatException('Expected String, got ${data.runtimeType}');
  }

  @override
  String get name => 'json';

  @override
  String get contentType => 'application/json';
}
```

**MessagePackProtocol — MessagePack сериализация (опционально)**

```dart
// lib/transport/protocols/messagepack_protocol.dart

import 'package:messagepack/messagepack.dart';
import '../../core/interfaces/i_websocket_protocol.dart';

/// Протокол MessagePack для WebSocket (более компактный чем JSON)
class MessagePackProtocol implements IWebSocketProtocol {
  final _packer = Packer();
  final _unpacker = Unpacker();

  @override
  List<int> encode(Map<String, dynamic> data) {
    _packer.packMap(data);
    return _packer.takeBytes();
  }

  @override
  Map<String, dynamic> decode(dynamic data) {
    if (data is List<int>) {
      _unpacker.unpack(data);
      return _unpacker.unpackMap() as Map<String, dynamic>;
    }
    throw FormatException('Expected List<int>, got ${data.runtimeType}');
  }

  @override
  String get name => 'messagepack';

  @override
  String get contentType => 'application/msgpack';
}
```

**Преимущества pluggable протоколов:**
- JSON для дебаггинга (читаемый)
- MessagePack для production (компактный)
- Можно добавить Protobuf, CBOR и т.д.

---

#### 11:30 - 13:00: WebSocketManager

**Задача:** Создать менеджер для управления WebSocket соединениями.

```dart
// lib/transport/websocket_manager.dart

import 'dart:async';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../core/interfaces/i_websocket_protocol.dart';
import '../core/interfaces/i_reconnect_strategy.dart';
import '../core/interfaces/i_websocket_connection.dart';

/// Менеджер WebSocket соединений
class WebSocketManager implements IWebSocketConnection {
  final IWebSocketProtocol protocol;
  final IReconnectStrategy reconnectStrategy;

  WebSocketChannel? _channel;
  ConnectionState _state = ConnectionState.disconnected;
  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;

  final _messagesController = StreamController<Map<String, dynamic>>.broadcast();
  final _eventsController = StreamController<ConnectionEvent>.broadcast();

  WebSocketManager({
    required this.protocol,
    required this.reconnectStrategy,
  });

  @override
  ConnectionState get state => _state;

  @override
  Stream<Map<String, dynamic>> get messages => _messagesController.stream;

  @override
  Stream<ConnectionEvent> get events => _eventsController.stream;

  @override
  Future<void> connect(String url) async {
    if (_state == ConnectionState.connected) {
      return; // Уже подключены
    }

    _setState(ConnectionState.connecting);
    _eventsController.add(ConnectionEvent.connecting);

    try {
      _channel = WebSocketChannel.connect(Uri.parse(url));

      // Слушаем входящие сообщения
      _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDisconnect,
      );

      _setState(ConnectionState.connected);
      _eventsController.add(ConnectionEvent.connected);
      _reconnectAttempts = 0;
      reconnectStrategy.reset();

      print('✅ WebSocket connected: $url (protocol: ${protocol.name})');
    } catch (e) {
      print('❌ WebSocket connection failed: $e');
      _setState(ConnectionState.disconnected);
      _eventsController.add(ConnectionEvent.error);
      _scheduleReconnect(url);
    }
  }

  @override
  Future<void> disconnect() async {
    _reconnectTimer?.cancel();
    await _channel?.sink.close();
    _channel = null;
    _setState(ConnectionState.disconnected);
    _eventsController.add(ConnectionEvent.disconnected);
    print('🛑 WebSocket disconnected');
  }

  @override
  void send(Map<String, dynamic> data) {
    if (_state != ConnectionState.connected) {
      throw StateError('Cannot send: not connected');
    }

    final encoded = protocol.encode(data);
    _channel!.sink.add(encoded);
  }

  void _onMessage(dynamic data) {
    try {
      final decoded = protocol.decode(data);
      _messagesController.add(decoded);
    } catch (e) {
      print('❌ Failed to decode message: $e');
    }
  }

  void _onError(dynamic error) {
    print('❌ WebSocket error: $error');
    _eventsController.add(ConnectionEvent.error);
  }

  void _onDisconnect() {
    print('⚠️ WebSocket disconnected');
    _setState(ConnectionState.disconnected);
    _eventsController.add(ConnectionEvent.disconnected);

    // Пытаемся переподключиться
    final url = _channel?.closeCode != null ? null : 'reconnect';
    if (url != null) {
      _scheduleReconnect(url);
    }
  }

  void _scheduleReconnect(String url) {
    _reconnectAttempts++;

    if (!reconnectStrategy.shouldRetry(_reconnectAttempts)) {
      print('❌ Max reconnect attempts reached');
      return;
    }

    final delay = reconnectStrategy.getDelay(_reconnectAttempts);
    print('🔄 Reconnecting in ${delay.inSeconds}s (attempt $_reconnectAttempts)');

    _reconnectTimer = Timer(delay, () {
      connect(url);
    });
  }

  void _setState(ConnectionState newState) {
    _state = newState;
  }

  void dispose() {
    _reconnectTimer?.cancel();
    _messagesController.close();
    _eventsController.close();
    _channel?.sink.close();
  }
}
```

---

### День (14:00 - 18:00): Reconnect стратегии

#### 14:00 - 15:00: ExponentialBackoffStrategy

**Задача:** Стратегия с экспоненциальной задержкой.

```dart
// lib/transport/strategies/exponential_backoff_strategy.dart

import 'dart:math';
import '../../core/interfaces/i_reconnect_strategy.dart';

/// Стратегия переподключения с экспоненциальной задержкой
class ExponentialBackoffStrategy implements IReconnectStrategy {
  final Duration initialDelay;
  final Duration maxDelay;
  final int maxAttempts;
  final double multiplier;

  ExponentialBackoffStrategy({
    this.initialDelay = const Duration(seconds: 1),
    this.maxDelay = const Duration(seconds: 60),
    this.maxAttempts = 10,
    this.multiplier = 2.0,
  });

  @override
  Duration getDelay(int attemptNumber) {
    final delayMs = initialDelay.inMilliseconds * pow(multiplier, attemptNumber - 1);
    final cappedMs = min(delayMs, maxDelay.inMilliseconds.toDouble());
    return Duration(milliseconds: cappedMs.toInt());
  }

  @override
  bool shouldRetry(int attemptNumber) {
    return attemptNumber <= maxAttempts;
  }

  @override
  void reset() {
    // Нет состояния для сброса
  }

  @override
  String get name => 'exponential_backoff';
}
```

**Пример задержек:**
- Попытка 1: 1 сек
- Попытка 2: 2 сек
- Попытка 3: 4 сек
- Попытка 4: 8 сек
- Попытка 5: 16 сек
- Попытка 6: 32 сек
- Попытка 7+: 60 сек (max)

---

#### 15:00 - 16:00: FixedDelayStrategy и LinearBackoffStrategy

**FixedDelayStrategy — фиксированная задержка**

```dart
// lib/transport/strategies/fixed_delay_strategy.dart

import '../../core/interfaces/i_reconnect_strategy.dart';

/// Стратегия с фиксированной задержкой между попытками
class FixedDelayStrategy implements IReconnectStrategy {
  final Duration delay;
  final int maxAttempts;

  FixedDelayStrategy({
    this.delay = const Duration(seconds: 5),
    this.maxAttempts = 5,
  });

  @override
  Duration getDelay(int attemptNumber) => delay;

  @override
  bool shouldRetry(int attemptNumber) => attemptNumber <= maxAttempts;

  @override
  void reset() {}

  @override
  String get name => 'fixed_delay';
}
```

**LinearBackoffStrategy — линейная задержка**

```dart
// lib/transport/strategies/linear_backoff_strategy.dart

import 'dart:math';
import '../../core/interfaces/i_reconnect_strategy.dart';

/// Стратегия с линейным увеличением задержки
class LinearBackoffStrategy implements IReconnectStrategy {
  final Duration initialDelay;
  final Duration increment;
  final Duration maxDelay;
  final int maxAttempts;

  LinearBackoffStrategy({
    this.initialDelay = const Duration(seconds: 1),
    this.increment = const Duration(seconds: 2),
    this.maxDelay = const Duration(seconds: 30),
    this.maxAttempts = 10,
  });

  @override
  Duration getDelay(int attemptNumber) {
    final delayMs = initialDelay.inMilliseconds +
                    (increment.inMilliseconds * (attemptNumber - 1));
    final cappedMs = min(delayMs, maxDelay.inMilliseconds);
    return Duration(milliseconds: cappedMs);
  }

  @override
  bool shouldRetry(int attemptNumber) => attemptNumber <= maxAttempts;

  @override
  void reset() {}

  @override
  String get name => 'linear_backoff';
}
```

**Пример задержек (increment = 2s):**
- Попытка 1: 1 сек
- Попытка 2: 3 сек
- Попытка 3: 5 сек
- Попытка 4: 7 сек
- ...

---

#### 16:00 - 17:30: EventsHandler — WebSocket endpoint

**Задача:** Handler для WebSocket соединений.

```dart
// lib/handlers/events_handler.dart

import 'dart:async';
import 'package:shelf/shelf.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:aq_graph_engine/aq_graph_engine.dart';
import '../core/interfaces/i_websocket_protocol.dart';

/// Handler для WebSocket соединений (стриминг событий)
class EventsHandler {
  final GraphEngine engine;
  final IWebSocketProtocol protocol;

  EventsHandler({
    required this.engine,
    required this.protocol,
  });

  /// Создать WebSocket handler
  Handler get handler {
    return webSocketHandler((WebSocketChannel channel) {
      _handleConnection(channel);
    });
  }

  void _handleConnection(WebSocketChannel channel) async {
    String? runId;
    StreamSubscription<GraphRunEvent>? subscription;

    try {
      // Ждём первое сообщение с runId
      final firstMessage = await channel.stream.first;
      final data = protocol.decode(firstMessage);
      runId = data['runId'] as String?;

      if (runId == null) {
        channel.sink.add(protocol.encode({
          'error': 'Missing runId',
        }));
        await channel.sink.close();
        return;
      }

      print('📡 WebSocket client connected for run: $runId');

      // Подписываемся на события выполнения
      final events = engine.getEvents(runId);
      subscription = events.listen(
        (event) {
          // Отправляем событие клиенту
          channel.sink.add(protocol.encode(event.toJson()));
        },
        onError: (error) {
          channel.sink.add(protocol.encode({
            'type': 'error',
            'message': error.toString(),
          }));
        },
        onDone: () {
          channel.sink.close();
        },
      );

      // Ждём отключения клиента
      await channel.stream.drain();
    } catch (e) {
      print('❌ WebSocket error: $e');
    } finally {
      await subscription?.cancel();
      print('📡 WebSocket client disconnected for run: $runId');
    }
  }
}
```

---

#### 17:30 - 18:00: Интеграция в ServerModule

**Задача:** Добавить WebSocket в DI и маршруты.

```dart
// Обновление lib/core/di/server_module.dart

void register() {
  // ... существующие регистрации ...

  // Регистрируем WebSocket протокол
  locator.registerSingleton<IWebSocketProtocol>(
    JsonProtocol(),
  );

  // Регистрируем EventsHandler
  locator.registerFactory<EventsHandler>(
    () => EventsHandler(
      engine: locator.get<GraphEngine>(),
      protocol: locator.get<IWebSocketProtocol>(),
    ),
  );
}

void setupRoutes() {
  final router = locator.get<IRouter>();

  // ... существующие маршруты ...

  // WebSocket endpoint для событий
  router.register(
    'GET',
    '/api/v1/runs/<id>/events',
    locator.get<EventsHandler>().handler,
  );
}
```

---

### Результат дня

✅ **WebSocket с pluggable протоколами** — JSON, MessagePack
✅ **Reconnect стратегии** — Exponential, Fixed, Linear
✅ **Event broadcasting** — события в реальном времени
✅ **Автоматическое переподключение** — клиент не теряет события
✅ **Расширяемая архитектура** — легко добавить новый протокол или стратегию

### Диаграмма WebSocket архитектуры

```
┌─────────────────────────────────────────────────────────┐
│                  WebSocketManager                       │
│  (управление соединением, reconnect)                    │
└────────────────────┬────────────────────────────────────┘
                     │
        ┌────────────┼────────────┐
        ↓            ↓            ↓
┌──────────────┐ ┌──────────────┐ ┌──────────────┐
│  IProtocol   │ │ IReconnect   │ │ IConnection  │
│              │ │  Strategy    │ │              │
└──────────────┘ └──────────────┘ └──────────────┘
        │                │                │
   ┌────┴────┐      ┌────┴────┐      ┌────┴────┐
   │  JSON   │      │  Expo   │      │ Channel │
   │ MsgPack │      │  Fixed  │      │         │
   └─────────┘      │ Linear  │      └─────────┘
                    └─────────┘
```

### Примеры использования

**Клиент подключается к WebSocket:**

```dart
// Клиентская сторона
final manager = WebSocketManager(
  protocol: JsonProtocol(),
  reconnectStrategy: ExponentialBackoffStrategy(),
);

await manager.connect('ws://localhost:8080/api/v1/runs/123/events');

// Отправляем runId
manager.send({'runId': '123'});

// Слушаем события
manager.messages.listen((event) {
  print('Event: ${event['type']}');
});

// Слушаем состояние соединения
manager.events.listen((event) {
  switch (event) {
    case ConnectionEvent.connected:
      print('✅ Connected');
    case ConnectionEvent.disconnected:
      print('⚠️ Disconnected, reconnecting...');
    case ConnectionEvent.error:
      print('❌ Error');
  }
});
```

### Проверка расширяемости

**Можно ли добавить новый протокол?**
✅ Да! Создаём класс, реализуем IWebSocketProtocol, регистрируем в DI.

**Можно ли добавить новую reconnect стратегию?**
✅ Да! Создаём класс, реализуем IReconnectStrategy, передаём в WebSocketManager.

**Можно ли использовать разные протоколы для разных клиентов?**
✅ Да! Создаём несколько WebSocketManager с разными протоколами.

---

## День 4: HttpEngineTransport (серверная сторона)

### Цель дня
Создать адаптер между HTTP и GraphEngine с pluggable стратегиями выполнения.

### Утро (09:00 - 13:00): Transport адаптер

#### 09:00 - 10:30: Стратегии выполнения

**Задача:** Создать pluggable стратегии для разных режимов выполнения.

**1. SyncExecutionStrategy — синхронное выполнение**

```dart
// lib/strategies/sync_execution_strategy.dart

import 'package:aq_graph_engine/aq_graph_engine.dart';
import '../core/interfaces/i_execution_strategy.dart';

/// Синхронная стратегия выполнения (блокирует до завершения)
class SyncExecutionStrategy implements IExecutionStrategy {
  @override
  Stream<GraphRunEvent> execute(
    GraphEngine engine,
    GraphRunRequest request,
  ) {
    // Просто делегируем в engine
    return engine.run(request);
  }

  @override
  String get name => 'sync';
}
```

**2. AsyncExecutionStrategy — асинхронное выполнение**

```dart
// lib/strategies/async_execution_strategy.dart

import 'dart:async';
import 'package:aq_graph_engine/aq_graph_engine.dart';
import '../core/interfaces/i_execution_strategy.dart';

/// Асинхронная стратегия выполнения (не блокирует HTTP запрос)
class AsyncExecutionStrategy implements IExecutionStrategy {
  final Map<String, StreamController<GraphRunEvent>> _activeRuns = {};

  @override
  Stream<GraphRunEvent> execute(
    GraphEngine engine,
    GraphRunRequest request,
  ) {
    // Создаём контроллер для этого запуска
    final controller = StreamController<GraphRunEvent>.broadcast();
    _activeRuns[request.runId] = controller;

    // Запускаем выполнение в фоне
    _executeInBackground(engine, request, controller);

    // Возвращаем поток событий
    return controller.stream;
  }

  Future<void> _executeInBackground(
    GraphEngine engine,
    GraphRunRequest request,
    StreamController<GraphRunEvent> controller,
  ) async {
    try {
      final events = engine.run(request);
      await for (final event in events) {
        controller.add(event);
      }
      controller.close();
    } catch (e) {
      controller.addError(e);
      controller.close();
    } finally {
      _activeRuns.remove(request.runId);
    }
  }

  /// Получить поток событий для активного запуска
  Stream<GraphRunEvent>? getEvents(String runId) {
    return _activeRuns[runId]?.stream;
  }

  @override
  String get name => 'async';
}
```

**3. QueueExecutionStrategy — выполнение через очередь**

```dart
// lib/strategies/queue_execution_strategy.dart

import 'package:aq_graph_engine/aq_graph_engine.dart';
import 'package:aq_queue/aq_queue.dart';
import '../core/interfaces/i_execution_strategy.dart';

/// Стратегия выполнения через очередь (Redis)
class QueueExecutionStrategy implements IExecutionStrategy {
  final IJobQueue queue;

  QueueExecutionStrategy({required this.queue});

  @override
  Stream<GraphRunEvent> execute(
    GraphEngine engine,
    GraphRunRequest request,
  ) async* {
    // Отправляем задание в очередь
    await queue.enqueue(WorkerJobImpl(
      jobId: request.runId,
      tool: 'run_graph',
      payload: request.toJson(),
    ));

    // Возвращаем событие о постановке в очередь
    yield GraphRunEvent(
      runId: request.runId,
      type: GraphRunEventType.log,
      message: 'Job queued for execution',
    );

    // Клиент должен подписаться на WebSocket для получения событий
  }

  @override
  String get name => 'queue';
}
```

**Преимущества pluggable стратегий:**
- **Sync** — для тестов и простых случаев
- **Async** — для production (не блокирует HTTP)
- **Queue** — для масштабирования (воркеры)

---

#### 10:30 - 12:00: HttpEngineTransport

**Задача:** Создать транспорт, который связывает HTTP и GraphEngine.

```dart
// lib/transport/http_engine_transport.dart

import 'package:aq_graph_engine/aq_graph_engine.dart';
import '../core/interfaces/i_execution_strategy.dart';

/// HTTP транспорт для GraphEngine (серверная сторона)
class HttpEngineTransport implements IEngineTransport {
  final GraphEngine engine;
  final IExecutionStrategy strategy;
  final List<LifecycleHook> hooks;

  HttpEngineTransport({
    required this.engine,
    required this.strategy,
    this.hooks = const [],
  });

  @override
  Stream<GraphRunEvent> run(GraphRunRequest request) async* {
    // 1. Вызываем onStart hooks
    await _callHooks('onStart', request);

    try {
      // 2. Выполняем через стратегию
      final events = strategy.execute(engine, request);

      // 3. Проксируем события с вызовом hooks
      await for (final event in events) {
        // Вызываем hooks для специфичных событий
        if (event.type == GraphRunEventType.suspended) {
          await _callHooks('onSuspend', request, event);
        }

        yield event;

        if (event.type == GraphRunEventType.completed) {
          await _callHooks('onComplete', request, event);
        }

        if (event.type == GraphRunEventType.error) {
          await _callHooks('onError', request, event);
        }
      }
    } catch (e) {
      // 4. Вызываем onError hooks
      await _callHooks('onError', request, e);
      rethrow;
    }
  }

  @override
  Future<void> respondToInput(UserInputResponse response) async {
    await engine.resumeWithInput(response);
  }

  @override
  Future<void> cancel(String runId) async {
    await engine.cancel(runId);
  }

  @override
  Future<bool> isAvailable() async {
    // Проверяем доступность зависимостей
    try {
      // Проверяем GraphEngine
      if (engine == null) return false;

      // Проверяем репозитории
      await engine.runRepo.getRun('health-check');

      return true;
    } catch (e) {
      return false;
    }
  }

  @override
  void dispose() {
    // Очистка ресурсов
  }

  Future<void> _callHooks(
    String hookName,
    GraphRunRequest request, [
    dynamic data,
  ]) async {
    for (final hook in hooks) {
      try {
        await hook.call(hookName, request, data);
      } catch (e) {
        print('❌ Hook $hookName failed: $e');
      }
    }
  }
}
```

---

#### 12:00 - 13:00: LifecycleHook интерфейс

**Задача:** Создать систему hooks для расширения поведения.

```dart
// lib/core/interfaces/i_lifecycle_hook.dart

import 'package:aq_graph_engine/aq_graph_engine.dart';

/// Контракт для lifecycle hook
abstract class LifecycleHook {
  /// Вызывается при событии жизненного цикла
  Future<void> call(
    String hookName,
    GraphRunRequest request,
    dynamic data,
  );

  /// Название hook (для логирования)
  String get name;
}
```

**Пример: MetricsHook**

```dart
// lib/hooks/metrics_hook.dart

import 'package:aq_graph_engine/aq_graph_engine.dart';
import '../core/interfaces/i_lifecycle_hook.dart';

/// Hook для сбора метрик
class MetricsHook implements LifecycleHook {
  final Map<String, int> _counters = {};
  final Map<String, DateTime> _startTimes = {};

  @override
  Future<void> call(
    String hookName,
    GraphRunRequest request,
    dynamic data,
  ) async {
    switch (hookName) {
      case 'onStart':
        _counters['runs_started'] = (_counters['runs_started'] ?? 0) + 1;
        _startTimes[request.runId] = DateTime.now();
        break;

      case 'onComplete':
        _counters['runs_completed'] = (_counters['runs_completed'] ?? 0) + 1;
        _recordDuration(request.runId);
        break;

      case 'onError':
        _counters['runs_failed'] = (_counters['runs_failed'] ?? 0) + 1;
        _recordDuration(request.runId);
        break;

      case 'onSuspend':
        _counters['runs_suspended'] = (_counters['runs_suspended'] ?? 0) + 1;
        break;
    }
  }

  void _recordDuration(String runId) {
    final startTime = _startTimes[runId];
    if (startTime != null) {
      final duration = DateTime.now().difference(startTime);
      print('⏱️ Run $runId took ${duration.inSeconds}s');
      _startTimes.remove(runId);
    }
  }

  Map<String, int> get metrics => Map.unmodifiable(_counters);

  @override
  String get name => 'metrics';
}
```

---

### День (14:00 - 18:00): Lifecycle hooks

#### 14:00 - 15:00: LoggingHook

**Задача:** Hook для детального логирования.

```dart
// lib/hooks/logging_hook.dart

import 'package:aq_graph_engine/aq_graph_engine.dart';
import '../core/interfaces/i_lifecycle_hook.dart';

/// Hook для логирования событий жизненного цикла
class LoggingHook implements LifecycleHook {
  final bool verbose;

  LoggingHook({this.verbose = false});

  @override
  Future<void> call(
    String hookName,
    GraphRunRequest request,
    dynamic data,
  ) async {
    final timestamp = DateTime.now().toIso8601String();

    switch (hookName) {
      case 'onStart':
        print('[$timestamp] 🚀 Run started: ${request.runId}');
        if (verbose) {
          print('  Blueprint: ${request.blueprintId}');
          print('  Project: ${request.projectId}');
        }
        break;

      case 'onSuspend':
        print('[$timestamp] ⏸️ Run suspended: ${request.runId}');
        if (verbose && data is GraphRunEvent) {
          print('  Node: ${data.nodeId}');
          print('  Reason: ${data.message}');
        }
        break;

      case 'onComplete':
        print('[$timestamp] ✅ Run completed: ${request.runId}');
        break;

      case 'onError':
        print('[$timestamp] ❌ Run failed: ${request.runId}');
        if (data is GraphRunEvent) {
          print('  Error: ${data.errorMessage}');
        } else if (data is Exception) {
          print('  Error: $data');
        }
        break;
    }
  }

  @override
  String get name => 'logging';
}
```

---

#### 15:00 - 16:00: NotificationHook

**Задача:** Hook для отправки уведомлений.

```dart
// lib/hooks/notification_hook.dart

import 'package:aq_graph_engine/aq_graph_engine.dart';
import '../core/interfaces/i_lifecycle_hook.dart';

/// Hook для отправки уведомлений (Slack, Email, etc.)
class NotificationHook implements LifecycleHook {
  final NotificationService service;
  final List<String> notifyOn;

  NotificationHook({
    required this.service,
    this.notifyOn = const ['onComplete', 'onError'],
  });

  @override
  Future<void> call(
    String hookName,
    GraphRunRequest request,
    dynamic data,
  ) async {
    if (!notifyOn.contains(hookName)) {
      return; // Не уведомляем для этого события
    }

    switch (hookName) {
      case 'onComplete':
        await service.send(
          title: 'Run Completed',
          message: 'Run ${request.runId} completed successfully',
          level: NotificationLevel.success,
        );
        break;

      case 'onError':
        await service.send(
          title: 'Run Failed',
          message: 'Run ${request.runId} failed: ${_extractError(data)}',
          level: NotificationLevel.error,
        );
        break;
    }
  }

  String _extractError(dynamic data) {
    if (data is GraphRunEvent) {
      return data.errorMessage ?? 'Unknown error';
    }
    return data.toString();
  }

  @override
  String get name => 'notification';
}

/// Абстракция для сервиса уведомлений
abstract class NotificationService {
  Future<void> send({
    required String title,
    required String message,
    required NotificationLevel level,
  });
}

enum NotificationLevel { info, success, warning, error }
```

---

#### 16:00 - 17:00: PersistenceHook

**Задача:** Hook для сохранения состояния после каждого события.

```dart
// lib/hooks/persistence_hook.dart

import 'package:aq_graph_engine/aq_graph_engine.dart';
import '../core/interfaces/i_lifecycle_hook.dart';

/// Hook для автоматического сохранения состояния
class PersistenceHook implements LifecycleHook {
  final IRunRepository repository;

  PersistenceHook({required this.repository});

  @override
  Future<void> call(
    String hookName,
    GraphRunRequest request,
    dynamic data,
  ) async {
    // Сохраняем состояние после ключевых событий
    switch (hookName) {
      case 'onStart':
        await repository.updateRunLog(
          request.runId,
          ['Run started'],
          status: 'running',
        );
        break;

      case 'onSuspend':
        if (data is GraphRunEvent) {
          await repository.suspendRun(
            runId: request.runId,
            contextJson: data.contextJson ?? '{}',
            nodeId: data.nodeId ?? '',
            logs: [data.message ?? 'Suspended'],
          );
        }
        break;

      case 'onComplete':
        await repository.updateRunLog(
          request.runId,
          ['Run completed'],
          status: 'completed',
        );
        break;

      case 'onError':
        final errorMsg = _extractError(data);
        await repository.updateRunLog(
          request.runId,
          ['Run failed: $errorMsg'],
          status: 'failed',
        );
        break;
    }
  }

  String _extractError(dynamic data) {
    if (data is GraphRunEvent) {
      return data.errorMessage ?? 'Unknown error';
    }
    return data.toString();
  }

  @override
  String get name => 'persistence';
}
```

---

#### 17:00 - 18:00: Интеграция hooks в ServerModule

**Задача:** Зарегистрировать hooks в DI и подключить к транспорту.

```dart
// Обновление lib/core/di/server_module.dart

void register() {
  // ... существующие регистрации ...

  // Регистрируем hooks
  locator.registerSingleton<MetricsHook>(
    MetricsHook(),
  );

  locator.registerSingleton<LoggingHook>(
    LoggingHook(verbose: true),
  );

  locator.registerSingleton<PersistenceHook>(
    PersistenceHook(
      repository: engine.runRepo,
    ),
  );

  // Регистрируем стратегию выполнения
  locator.registerSingleton<IExecutionStrategy>(
    AsyncExecutionStrategy(),
  );

  // Регистрируем HttpEngineTransport с hooks
  locator.registerSingleton<HttpEngineTransport>(
    HttpEngineTransport(
      engine: engine,
      strategy: locator.get<IExecutionStrategy>(),
      hooks: [
        locator.get<MetricsHook>(),
        locator.get<LoggingHook>(),
        locator.get<PersistenceHook>(),
      ],
    ),
  );
}
```

---

### Результат дня

✅ **HttpEngineTransport с lifecycle hooks** — расширяемая система событий
✅ **Pluggable execution strategies** — Sync, Async, Queue
✅ **Error handling strategies** — hooks для обработки ошибок
✅ **Метрики** — автоматический сбор через MetricsHook
✅ **Логирование** — детальное логирование через LoggingHook
✅ **Персистентность** — автоматическое сохранение через PersistenceHook

### Диаграмма lifecycle hooks

```
GraphRunRequest
     ↓
HttpEngineTransport
     ↓
onStart hooks → [MetricsHook, LoggingHook, PersistenceHook]
     ↓
IExecutionStrategy (Async/Sync/Queue)
     ↓
GraphEngine.run()
     ↓
Events stream
     ↓
onSuspend hooks (если suspended)
onError hooks (если error)
onComplete hooks (если completed)
     ↓
Response
```

### Sequence diagram для HTTP запроса

```
Client          RunHandler      HttpEngineTransport    GraphEngine
  │                 │                    │                  │
  ├─POST /runs─────>│                    │                  │
  │                 ├─handle()───────────>│                  │
  │                 │                    ├─onStart hooks────>│
  │                 │                    ├─strategy.execute()>│
  │                 │                    │                  ├─run()
  │                 │                    │                  │
  │                 │<──201 Created──────┤                  │
  │<────runId───────┤                    │                  │
  │                 │                    │                  │
  │                 │                    │<──events stream──┤
  │                 │                    ├─onComplete hooks─>│
  │                 │                    │                  │
```

### Проверка расширяемости

**Можно ли добавить новую стратегию выполнения?**
✅ Да! Создаём класс, реализуем IExecutionStrategy, регистрируем в DI.

**Можно ли добавить новый hook?**
✅ Да! Создаём класс, реализуем LifecycleHook, добавляем в список hooks.

**Можно ли использовать разные стратегии для разных запросов?**
✅ Да! Можно передавать стратегию в параметрах запроса и выбирать динамически.

---

## День 5: Интеграция и рефакторинг

### Цель дня
Связать все компоненты и проверить модульность/расширяемость.

### Утро (09:00 - 13:00): Интеграция компонентов

#### 09:00 - 10:30: Полная интеграция в main.dart

**Задача:** Собрать все компоненты в единое приложение.

```dart
// bin/main.dart (финальная версия)

import 'dart:io';
import 'package:aq_graph_engine/aq_graph_engine.dart';
import 'package:graph_engine_server/server.dart';
import 'package:graph_engine_server/core/di/service_locator.dart';
import 'package:graph_engine_server/core/di/server_module.dart';

void main() async {
  print('🚀 Starting Graph Engine Server...\n');

  // 1. Загружаем конфигурацию из окружения
  final config = ServerConfig.fromEnv();
  print('📋 Configuration:');
  print('   Port: ${config.port}');
  print('   Data Service: ${config.dataServiceUrl}');
  print('   Auth Service: ${config.authServiceUrl}');
  print('   Strategy: ${config.executionStrategy}\n');

  // 2. Инициализируем зависимости
  print('🔧 Initializing dependencies...');
  final dependencies = await initializeDependencies(config);
  print('✅ Dependencies initialized\n');

  // 3. Создаём DI контейнер
  final locator = ServiceLocator();

  // 4. Регистрируем зависимости
  print('📦 Registering services...');
  final module = ServerModule(
    locator: locator,
    engine: dependencies.engine,
    config: config,
  );
  module.register();
  module.setupRoutes();
  print('✅ Services registered\n');

  // 5. Создаём и запускаем сервер
  print('🌐 Starting HTTP server...');
  final server = GraphEngineServer(locator: locator);
  await server.start(port: config.port);

  print('\n✅ Server is running!');
  print('   Health: http://localhost:${config.port}/health');
  print('   API: http://localhost:${config.port}/api/v1/runs');
  print('   Metrics: http://localhost:${config.port}/metrics');
  print('\n📊 Press Ctrl+C to stop\n');

  // 6. Graceful shutdown
  ProcessSignal.sigint.watch().listen((_) async {
    print('\n🛑 Shutting down gracefully...');
    await server.stop();
    await dependencies.dispose();
    print('✅ Server stopped');
    exit(0);
  });
}

/// Конфигурация сервера
class ServerConfig {
  final int port;
  final String dataServiceUrl;
  final String authServiceUrl;
  final String executionStrategy;
  final bool verboseLogging;

  ServerConfig({
    required this.port,
    required this.dataServiceUrl,
    required this.authServiceUrl,
    required this.executionStrategy,
    required this.verboseLogging,
  });

  factory ServerConfig.fromEnv() {
    return ServerConfig(
      port: int.parse(Platform.environment['PORT'] ?? '8080'),
      dataServiceUrl: Platform.environment['DATA_SERVICE_URL'] ?? 'http://localhost:8765',
      authServiceUrl: Platform.environment['AUTH_SERVICE_URL'] ?? 'http://localhost:8080',
      executionStrategy: Platform.environment['EXECUTION_STRATEGY'] ?? 'async',
      verboseLogging: Platform.environment['VERBOSE'] == 'true',
    );
  }
}

/// Инициализация зависимостей
class Dependencies {
  final GraphEngine engine;
  final RemoteVaultStorage storage;

  Dependencies({
    required this.engine,
    required this.storage,
  });

  Future<void> dispose() async {
    await storage.disconnect();
  }
}

Future<Dependencies> initializeDependencies(ServerConfig config) async {
  // 1. Подключаемся к Data Layer
  final storage = RemoteVaultStorage(
    endpoint: config.dataServiceUrl,
    tenantId: 'default',
  );
  await storage.connect();

  // 2. Создаём репозитории
  final runRepo = RemoteRunRepository(storage);
  final graphRepo = RemoteGraphRepository(storage);

  // 3. Создаём GraphEngine
  final engine = GraphEngine(
    tools: buildToolRegistry(),
    runRepo: runRepo,
    graphRepo: graphRepo,
  );

  return Dependencies(
    engine: engine,
    storage: storage,
  );
}

ToolRegistry buildToolRegistry() {
  // TODO: реализовать регистрацию инструментов
  return ToolRegistry();
}
```

---

#### 10:30 - 11:30: Health check endpoint

**Задача:** Добавить endpoint для проверки здоровья сервера.

```dart
// lib/handlers/health_handler.dart

import 'package:shelf/shelf.dart';
import 'package:aq_graph_engine/aq_graph_engine.dart';
import '../core/interfaces/i_handler.dart';
import '../core/types/request_context.dart';
import '../core/types/response_builder.dart';
import '../transport/http_engine_transport.dart';

/// Handler для health check
class HealthHandler implements IHandler {
  final GraphEngine engine;
  final HttpEngineTransport? transport;

  HealthHandler({
    required this.engine,
    this.transport,
  });

  @override
  Future<Response> handle(RequestContext context) async {
    final checks = <String, dynamic>{};

    // 1. Проверяем GraphEngine
    checks['engine'] = await _checkEngine();

    // 2. Проверяем Transport
    if (transport != null) {
      checks['transport'] = await _checkTransport();
    }

    // 3. Проверяем репозитории
    checks['repositories'] = await _checkRepositories();

    // 4. Общий статус
    final allHealthy = checks.values.every((v) => v['status'] == 'ok');
    final status = allHealthy ? 'ok' : 'degraded';

    return Response(
      allHealthy ? 200 : 503,
      body: jsonEncode({
        'status': status,
        'timestamp': DateTime.now().toIso8601String(),
        'checks': checks,
      }),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Future<Map<String, dynamic>> _checkEngine() async {
    try {
      // Проверяем что engine не null
      if (engine == null) {
        return {'status': 'error', 'message': 'Engine is null'};
      }
      return {'status': 'ok'};
    } catch (e) {
      return {'status': 'error', 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> _checkTransport() async {
    try {
      final available = await transport!.isAvailable();
      return {
        'status': available ? 'ok' : 'error',
        'message': available ? null : 'Transport unavailable',
      };
    } catch (e) {
      return {'status': 'error', 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> _checkRepositories() async {
    try {
      // Пытаемся прочитать несуществующий run (не должно падать)
      await engine.runRepo.getRun('health-check-test');
      return {'status': 'ok'};
    } catch (e) {
      return {'status': 'error', 'message': e.toString()};
    }
  }
}
```

---

#### 11:30 - 12:30: Metrics endpoint

**Задача:** Добавить endpoint для метрик (Prometheus формат).

```dart
// lib/handlers/metrics_handler.dart

import 'package:shelf/shelf.dart';
import '../core/interfaces/i_handler.dart';
import '../core/types/request_context.dart';
import '../hooks/metrics_hook.dart';

/// Handler для метрик (Prometheus формат)
class MetricsHandler implements IHandler {
  final MetricsHook metricsHook;

  MetricsHandler({required this.metricsHook});

  @override
  Future<Response> handle(RequestContext context) async {
    final metrics = metricsHook.metrics;

    // Формат Prometheus
    final lines = <String>[];

    // HELP и TYPE для каждой метрики
    lines.add('# HELP graph_runs_started_total Total number of runs started');
    lines.add('# TYPE graph_runs_started_total counter');
    lines.add('graph_runs_started_total ${metrics['runs_started'] ?? 0}');
    lines.add('');

    lines.add('# HELP graph_runs_completed_total Total number of runs completed');
    lines.add('# TYPE graph_runs_completed_total counter');
    lines.add('graph_runs_completed_total ${metrics['runs_completed'] ?? 0}');
    lines.add('');

    lines.add('# HELP graph_runs_failed_total Total number of runs failed');
    lines.add('# TYPE graph_runs_failed_total counter');
    lines.add('graph_runs_failed_total ${metrics['runs_failed'] ?? 0}');
    lines.add('');

    lines.add('# HELP graph_runs_suspended_total Total number of runs suspended');
    lines.add('# TYPE graph_runs_suspended_total counter');
    lines.add('graph_runs_suspended_total ${metrics['runs_suspended'] ?? 0}');
    lines.add('');

    return Response.ok(
      lines.join('\n'),
      headers: {'Content-Type': 'text/plain; version=0.0.4'},
    );
  }
}
```

---

#### 12:30 - 13:00: Обновление ServerModule

**Задача:** Добавить новые handlers в DI.

```dart
// Обновление lib/core/di/server_module.dart

void register() {
  // ... существующие регистрации ...

  // Регистрируем HealthHandler
  locator.registerFactory<HealthHandler>(
    () => HealthHandler(
      engine: locator.get<GraphEngine>(),
      transport: locator.get<HttpEngineTransport>(),
    ),
  );

  // Регистрируем MetricsHandler
  locator.registerFactory<MetricsHandler>(
    () => MetricsHandler(
      metricsHook: locator.get<MetricsHook>(),
    ),
  );
}

void setupRoutes() {
  final router = locator.get<IRouter>();

  // ... существующие маршруты ...

  // GET /health - health check
  router.register(
    'GET',
    '/health',
    (request) => locator.get<HealthHandler>().handle(
      RequestContext(request: request),
    ),
  );

  // GET /metrics - Prometheus метрики
  router.register(
    'GET',
    '/metrics',
    (request) => locator.get<MetricsHandler>().handle(
      RequestContext(request: request),
    ),
  );
}
```

---

### День (14:00 - 18:00): Проверка архитектуры

#### 14:00 - 15:30: Проверка модульности

**Задача:** Убедиться, что компоненты можно заменять без изменения кода.

**Тест 1: Замена Router**

```dart
// test/integration/router_replacement_test.dart

import 'package:test/test.dart';
import 'package:graph_engine_server/core/interfaces/i_router.dart';
import 'package:graph_engine_server/routing/router.dart';

void main() {
  test('Can replace Router implementation', () {
    // Создаём кастомный Router
    final customRouter = CustomRouter();

    // Регистрируем маршрут
    customRouter.register('GET', '/test', (req) async {
      return Response.ok('Custom router works!');
    });

    // Проверяем что работает
    expect(customRouter, isA<IRouter>());
  });
}

/// Кастомная реализация Router (для примера)
class CustomRouter implements IRouter {
  final Map<String, Handler> _routes = {};

  @override
  void register(String method, String path, Handler handler) {
    _routes['$method:$path'] = handler;
  }

  @override
  Handler get handler {
    return (Request request) async {
      final key = '${request.method}:${request.url.path}';
      final handler = _routes[key];
      if (handler == null) {
        return Response.notFound('Not found');
      }
      return handler(request);
    };
  }
}
```

**Результат:** ✅ Router можно заменить без изменения Handlers

---

**Тест 2: Замена Execution Strategy**

```dart
// test/integration/strategy_replacement_test.dart

import 'package:test/test.dart';
import 'package:graph_engine_server/core/interfaces/i_execution_strategy.dart';
import 'package:graph_engine_server/strategies/sync_execution_strategy.dart';

void main() {
  test('Can replace Execution Strategy', () {
    // Создаём кастомную стратегию
    final customStrategy = LoggingExecutionStrategy();

    // Проверяем что реализует интерфейс
    expect(customStrategy, isA<IExecutionStrategy>());

    // Можем использовать вместо SyncExecutionStrategy
    final transport = HttpEngineTransport(
      engine: mockEngine,
      strategy: customStrategy, // ← Подменили стратегию
    );

    expect(transport, isNotNull);
  });
}

/// Кастомная стратегия с логированием
class LoggingExecutionStrategy implements IExecutionStrategy {
  @override
  Stream<GraphRunEvent> execute(
    GraphEngine engine,
    GraphRunRequest request,
  ) async* {
    print('🔍 Executing with logging strategy: ${request.runId}');
    yield* engine.run(request);
  }

  @override
  String get name => 'logging';
}
```

**Результат:** ✅ Execution Strategy можно заменить без изменения Transport

---

#### 15:30 - 17:00: Проверка расширяемости

**Задача:** Убедиться, что можно добавлять новые компоненты без изменения существующих.

**Тест 3: Добавление нового Middleware**

```dart
// Создаём новый Middleware
class RateLimitMiddleware implements IMiddleware {
  final int maxRequestsPerMinute;
  final Map<String, List<DateTime>> _requests = {};

  RateLimitMiddleware({this.maxRequestsPerMinute = 60});

  @override
  Middleware get middleware {
    return (Handler innerHandler) {
      return (Request request) async {
        final ip = request.headers['x-forwarded-for'] ?? 'unknown';

        // Проверяем rate limit
        if (_isRateLimited(ip)) {
          return Response(
            429,
            body: 'Too many requests',
          );
        }

        // Записываем запрос
        _recordRequest(ip);

        return innerHandler(request);
      };
    };
  }

  bool _isRateLimited(String ip) {
    final requests = _requests[ip] ?? [];
    final now = DateTime.now();
    final recentRequests = requests.where(
      (t) => now.difference(t).inMinutes < 1,
    ).length;
    return recentRequests >= maxRequestsPerMinute;
  }

  void _recordRequest(String ip) {
    _requests[ip] = [...(_requests[ip] ?? []), DateTime.now()];
  }
}

// Добавляем в ServerModule (2 строки!)
locator.registerSingleton<RateLimitMiddleware>(
  RateLimitMiddleware(maxRequestsPerMinute: 100),
);

// Добавляем в pipeline
final pipeline = Pipeline()
    .addMiddleware(errorMw.middleware)
    .addMiddleware(loggingMw.middleware)
    .addMiddleware(rateLimitMw.middleware)  // ← Новый middleware
    .addMiddleware(corsMw.middleware)
    .addMiddleware(authMw.middleware)
    .addHandler(router.handler);
```

**Результат:** ✅ Новый Middleware добавлен без изменения существующих

---

**Тест 4: Добавление нового Handler**

```dart
// Создаём новый Handler
class GraphListHandler implements IHandler {
  final GraphEngine engine;

  GraphListHandler({required this.engine});

  @override
  Future<Response> handle(RequestContext context) async {
    // Получаем список всех графов
    final graphs = await engine.graphRepo.listGraphs();

    return ResponseBuilder.ok({
      'graphs': graphs.map((g) => g.toJson()).toList(),
    });
  }
}

// Регистрируем в ServerModule (3 строки!)
locator.registerFactory<GraphListHandler>(
  () => GraphListHandler(engine: locator.get<GraphEngine>()),
);

router.register('GET', '/api/v1/graphs',
  (req) => locator.get<GraphListHandler>().handle(RequestContext(request: req))
);
```

**Результат:** ✅ Новый Handler добавлен без изменения Router

---

#### 17:00 - 18:00: Code review по SOLID

**Задача:** Проверить соответствие SOLID принципам.

**Чек-лист:**

**1. Single Responsibility Principle**
- ✅ Router только маршрутизирует
- ✅ Handler только обрабатывает запрос
- ✅ Middleware только модифицирует request/response
- ✅ Strategy только определяет способ выполнения
- ✅ Hook только реагирует на события

**2. Open/Closed Principle**
- ✅ Можно добавить новый Handler без изменения Router
- ✅ Можно добавить новый Middleware без изменения Pipeline
- ✅ Можно добавить новый Hook без изменения Transport
- ✅ Можно добавить новую Strategy без изменения Engine

**3. Liskov Substitution Principle**
- ✅ Все реализации IRouter взаимозаменяемы
- ✅ Все реализации IHandler взаимозаменяемы
- ✅ Все реализации IExecutionStrategy взаимозаменяемы
- ✅ Все реализации IWebSocketProtocol взаимозаменяемы

**4. Interface Segregation Principle**
- ✅ IRouter — только маршрутизация (2 метода)
- ✅ IHandler — только обработка (1 метод)
- ✅ IMiddleware — только middleware (1 метод)
- ✅ IExecutionStrategy — только выполнение (2 метода)
- ✅ Нет "толстых" интерфейсов с ненужными методами

**5. Dependency Inversion Principle**
- ✅ Handlers зависят от IExecutionStrategy, не от конкретной реализации
- ✅ Transport зависит от IExecutionStrategy, не от конкретной реализации
- ✅ Server зависит от IRouter, не от ShelfRouter
- ✅ Все зависимости через интерфейсы

---

### Результат дня

✅ **Все компоненты интегрированы** — сервер работает end-to-end
✅ **Модульность проверена** — компоненты можно заменять
✅ **Расширяемость подтверждена** — можно добавлять новые компоненты
✅ **SOLID принципы соблюдены** — код чистый и поддерживаемый
✅ **Health check работает** — можно мониторить состояние
✅ **Метрики собираются** — готово для Prometheus

### Финальная архитектура

```
┌─────────────────────────────────────────────────────────┐
│                      main.dart                          │
│              (инициализация + DI setup)                 │
└────────────────────┬────────────────────────────────────┘
                     │
                     ↓
┌─────────────────────────────────────────────────────────┐
│                  ServerModule                           │
│         (регистрация всех зависимостей)                 │
└────────────────────┬────────────────────────────────────┘
                     │
        ┌────────────┼────────────┐
        ↓            ↓            ↓
┌──────────────┐ ┌──────────────┐ ┌──────────────┐
│   Router     │ │   Handlers   │ │  Middleware  │
│ (pluggable)  │ │ (pluggable)  │ │ (pluggable)  │
└──────────────┘ └──────────────┘ └──────────────┘
        │            │            │
        └────────────┼────────────┘
                     ↓
┌─────────────────────────────────────────────────────────┐
│              HttpEngineTransport                        │
│         (адаптер с lifecycle hooks)                     │
└────────────────────┬────────────────────────────────────┘
                     │
        ┌────────────┼────────────┐
        ↓            ↓            ↓
┌──────────────┐ ┌──────────────┐ ┌──────────────┐
│  Strategy    │ │    Hooks     │ │  WebSocket   │
│ (pluggable)  │ │ (pluggable)  │ │ (pluggable)  │
└──────────────┘ └──────────────┘ └──────────────┘
        │            │            │
        └────────────┼────────────┘
                     ↓
┌─────────────────────────────────────────────────────────┐
│                  GraphEngine                            │
│              (бизнес-логика выполнения)                 │
└─────────────────────────────────────────────────────────┘
```

### Итоговая проверка

**Можно ли заменить компонент без изменения кода?**
✅ Да! Все компоненты за интерфейсами.

**Можно ли добавить новый компонент без изменения существующих?**
✅ Да! Регистрируем в DI, добавляем в конфигурацию.

**Можно ли тестировать компоненты изолированно?**
✅ Да! Все зависимости через конструктор, легко мокировать.

**Соблюдены ли SOLID принципы?**
✅ Да! Все 5 принципов проверены и соблюдены.

---

## Примеры расширения

### Как добавить кастомный Handler

**Сценарий:** Нужен endpoint для получения статистики по всем запускам.

**Шаг 1: Создать Handler**

```dart
// lib/handlers/stats_handler.dart

import 'package:shelf/shelf.dart';
import 'package:aq_graph_engine/aq_graph_engine.dart';
import '../core/interfaces/i_handler.dart';
import '../core/types/request_context.dart';
import '../core/types/response_builder.dart';

class StatsHandler implements IHandler {
  final IRunRepository repository;

  StatsHandler({required this.repository});

  @override
  Future<Response> handle(RequestContext context) async {
    try {
      // Получаем все запуски
      final runs = await repository.listRuns();

      // Считаем статистику
      final stats = {
        'total': runs.length,
        'completed': runs.where((r) => r['status'] == 'completed').length,
        'failed': runs.where((r) => r['status'] == 'failed').length,
        'running': runs.where((r) => r['status'] == 'running').length,
      };

      return ResponseBuilder.ok(stats);
    } catch (e) {
      return ResponseBuilder.internalError('Failed to get stats: $e');
    }
  }
}
```

**Шаг 2: Зарегистрировать в DI**

```dart
// lib/core/di/server_module.dart

void register() {
  // ... существующие регистрации ...

  locator.registerFactory<StatsHandler>(
    () => StatsHandler(
      repository: locator.get<GraphEngine>().runRepo,
    ),
  );
}
```

**Шаг 3: Добавить маршрут**

```dart
void setupRoutes() {
  final router = locator.get<IRouter>();

  // ... существующие маршруты ...

  router.register(
    'GET',
    '/api/v1/stats',
    (request) => locator.get<StatsHandler>().handle(
      RequestContext(request: request),
    ),
  );
}
```

**Результат:** Новый endpoint `/api/v1/stats` работает без изменения существующего кода!

---

### Как добавить новый Middleware

**Сценарий:** Нужно добавить кеширование ответов для GET запросов.

**Шаг 1: Создать Middleware**

```dart
// lib/middleware/cache_middleware.dart

import 'package:shelf/shelf.dart';
import '../core/interfaces/i_middleware.dart';

class CacheMiddleware implements IMiddleware {
  final Duration cacheDuration;
  final Map<String, CacheEntry> _cache = {};

  CacheMiddleware({this.cacheDuration = const Duration(minutes: 5)});

  @override
  Middleware get middleware {
    return (Handler innerHandler) {
      return (Request request) async {
        // Кешируем только GET запросы
        if (request.method != 'GET') {
          return innerHandler(request);
        }

        final key = request.url.toString();

        // Проверяем кеш
        final cached = _cache[key];
        if (cached != null && !cached.isExpired) {
          print('💾 Cache HIT: $key');
          return cached.response;
        }

        // Выполняем запрос
        final response = await innerHandler(request);

        // Кешируем ответ (только 200)
        if (response.statusCode == 200) {
          _cache[key] = CacheEntry(
            response: response,
            expiresAt: DateTime.now().add(cacheDuration),
          );
          print('💾 Cache MISS: $key (cached)');
        }

        return response;
      };
    };
  }
}

class CacheEntry {
  final Response response;
  final DateTime expiresAt;

  CacheEntry({required this.response, required this.expiresAt});

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}
```

**Шаг 2: Зарегистрировать в DI**

```dart
locator.registerSingleton<CacheMiddleware>(
  CacheMiddleware(cacheDuration: Duration(minutes: 10)),
);
```

**Шаг 3: Добавить в pipeline**

```dart
final cacheMw = locator.get<CacheMiddleware>();

final pipeline = Pipeline()
    .addMiddleware(errorMw.middleware)
    .addMiddleware(loggingMw.middleware)
    .addMiddleware(cacheMw.middleware)  // ← Новый middleware
    .addMiddleware(corsMw.middleware)
    .addMiddleware(authMw.middleware)
    .addHandler(router.handler);
```

**Результат:** Кеширование работает для всех GET запросов!

---

### Как реализовать кастомный Transport

**Сценарий:** Нужен Transport для выполнения графов через gRPC вместо HTTP.

**Шаг 1: Создать Transport**

```dart
// lib/transport/grpc_engine_transport.dart

import 'package:aq_graph_engine/aq_graph_engine.dart';
import 'package:grpc/grpc.dart';

class GrpcEngineTransport implements IEngineTransport {
  final GraphEngine engine;
  final IExecutionStrategy strategy;
  final String host;
  final int port;

  ClientChannel? _channel;

  GrpcEngineTransport({
    required this.engine,
    required this.strategy,
    required this.host,
    required this.port,
  });

  Future<void> connect() async {
    _channel = ClientChannel(
      host,
      port: port,
      options: ChannelOptions(
        credentials: ChannelCredentials.insecure(),
      ),
    );
  }

  @override
  Stream<GraphRunEvent> run(GraphRunRequest request) {
    // Выполняем через стратегию (та же логика что у HTTP)
    return strategy.execute(engine, request);
  }

  @override
  Future<void> respondToInput(UserInputResponse response) async {
    await engine.resumeWithInput(response);
  }

  @override
  Future<void> cancel(String runId) async {
    await engine.cancel(runId);
  }

  @override
  Future<bool> isAvailable() async {
    return _channel != null;
  }

  @override
  void dispose() {
    _channel?.shutdown();
  }
}
```

**Шаг 2: Зарегистрировать в DI**

```dart
locator.registerSingleton<GrpcEngineTransport>(
  GrpcEngineTransport(
    engine: engine,
    strategy: locator.get<IExecutionStrategy>(),
    host: 'localhost',
    port: 50051,
  ),
);
```

**Результат:** Теперь можно использовать gRPC вместо HTTP!

---

### Как добавить новую стратегию выполнения

**Сценарий:** Нужна стратегия с приоритетами (high/normal/low).

**Шаг 1: Создать стратегию**

```dart
// lib/strategies/priority_execution_strategy.dart

import 'dart:async';
import 'dart:collection';
import 'package:aq_graph_engine/aq_graph_engine.dart';
import '../core/interfaces/i_execution_strategy.dart';

class PriorityExecutionStrategy implements IExecutionStrategy {
  final Map<Priority, Queue<_PendingRun>> _queues = {
    Priority.high: Queue(),
    Priority.normal: Queue(),
    Priority.low: Queue(),
  };

  bool _isProcessing = false;

  @override
  Stream<GraphRunEvent> execute(
    GraphEngine engine,
    GraphRunRequest request,
  ) {
    final controller = StreamController<GraphRunEvent>.broadcast();

    // Определяем приоритет из метаданных
    final priority = _getPriority(request);

    // Добавляем в очередь
    _queues[priority]!.add(_PendingRun(
      request: request,
      controller: controller,
      engine: engine,
    ));

    // Запускаем обработку
    _processQueue();

    return controller.stream;
  }

  Priority _getPriority(GraphRunRequest request) {
    final priorityStr = request.initialContext?['priority'] as String?;
    switch (priorityStr) {
      case 'high':
        return Priority.high;
      case 'low':
        return Priority.low;
      default:
        return Priority.normal;
    }
  }

  Future<void> _processQueue() async {
    if (_isProcessing) return;
    _isProcessing = true;

    while (_hasWork()) {
      // Берём задание с наивысшим приоритетом
      final run = _getNextRun();
      if (run == null) break;

      // Выполняем
      try {
        final events = run.engine.run(run.request);
        await for (final event in events) {
          run.controller.add(event);
        }
        run.controller.close();
      } catch (e) {
        run.controller.addError(e);
        run.controller.close();
      }
    }

    _isProcessing = false;
  }

  bool _hasWork() {
    return _queues.values.any((q) => q.isNotEmpty);
  }

  _PendingRun? _getNextRun() {
    // Сначала high, потом normal, потом low
    for (final priority in [Priority.high, Priority.normal, Priority.low]) {
      final queue = _queues[priority]!;
      if (queue.isNotEmpty) {
        return queue.removeFirst();
      }
    }
    return null;
  }

  @override
  String get name => 'priority';
}

enum Priority { high, normal, low }

class _PendingRun {
  final GraphRunRequest request;
  final StreamController<GraphRunEvent> controller;
  final GraphEngine engine;

  _PendingRun({
    required this.request,
    required this.controller,
    required this.engine,
  });
}
```

**Шаг 2: Зарегистрировать в DI**

```dart
locator.registerSingleton<IExecutionStrategy>(
  PriorityExecutionStrategy(),
);
```

**Шаг 3: Использовать**

```dart
// Клиент отправляет запрос с приоритетом
POST /api/v1/runs
{
  "blueprintId": "...",
  "projectId": "...",
  "initialContext": {
    "priority": "high"  // ← Приоритет
  }
}
```

**Результат:** Запросы с `priority: high` выполняются первыми!

---

## Чек-лист готовности

### Архитектура
- [ ] Все зависимости через конструктор
- [ ] Нет синглтонов или глобального состояния
- [ ] Интерфейсы маленькие и специфичные
- [ ] Каждый класс имеет одну ответственность

### Модульность
- [ ] Можно заменить Router без изменения Handlers
- [ ] Можно заменить Transport без изменения Engine
- [ ] Можно добавить Middleware без изменения Router
- [ ] Можно добавить новый Handler без изменения существующих

### Расширяемость
- [ ] Можно добавить новый протокол для WebSocket
- [ ] Можно добавить новую reconnect стратегию
- [ ] Можно добавить новую execution strategy
- [ ] Можно добавить новый тип Transport

### Тестируемость
- [ ] Все компоненты можно тестировать изолированно
- [ ] Зависимости можно мокировать
- [ ] Нет скрытых зависимостей

---

## Следующие шаги

После завершения Недели 1:
- Неделя 2: Клиентская часть (GraphEngineClient, RemoteEngineTransport)
- Неделя 3: Тестирование и документация
