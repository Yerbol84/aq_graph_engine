# Week 2 Detailed Plan - Graph Engine Server

**Период:** Week 2
**Цель:** Интеграция с реальными сервисами (Security, Vault), персистентность, production-ready features

---

## Обзор Week 2

### Основные задачи

1. **Интеграция с aq_security** - реальная валидация JWT и API ключей
2. **Интеграция с dart_vault** - персистентность состояния графов
3. **Advanced Monitoring** - расширенные метрики и alerting
4. **Production Readiness** - graceful shutdown, rate limiting, validation

### Архитектурные принципы

- Сохраняем модульность и SOLID принципы
- Все интеграции через интерфейсы
- Конфигурация через environment variables
- Backward compatibility с Week 1

---

## День 1 (Понедельник): Интеграция с aq_security

### Утро (09:00 - 13:00): Security Client

#### 09:00 - 10:30: Создание SecurityClient wrapper

**Задача:** Обернуть aq_security в удобный клиент для сервера.

**Файл:** `lib/integrations/security_client.dart`

```dart
// Клиент для интеграции с aq_security

import 'package:aq_security/aq_security_client.dart';

/// Wrapper для aq_security с кэшированием
class GraphEngineSecurityClient {
  final AqSecurityClient _client;
  final Duration _cacheTtl;
  final Map<String, _CacheEntry> _cache = {};

  GraphEngineSecurityClient({
    required String securityServiceUrl,
    Duration cacheTtl = const Duration(minutes: 5),
  })  : _client = AqSecurityClient(baseUrl: securityServiceUrl),
        _cacheTtl = cacheTtl;

  /// Валидация JWT токена
  Future<SecurityContext?> validateJwtToken(String token) async {
    final cached = _getFromCache('jwt:$token');
    if (cached != null) return cached;

    try {
      final result = await _client.introspectToken(token);
      if (!result.active) return null;

      final context = SecurityContext(
        type: AuthType.jwt,
        userId: result.userId!,
        permissions: result.permissions ?? [],
      );

      _putInCache('jwt:$token', context);
      return context;
    } catch (e) {
      print('❌ JWT validation failed: $e');
      return null;
    }
  }

  /// Валидация API ключа
  Future<SecurityContext?> validateApiKey(String apiKey) async {
    final cached = _getFromCache('api:$apiKey');
    if (cached != null) return cached;

    try {
      final result = await _client.validateApiKey(apiKey);
      if (!result.valid) return null;

      final context = SecurityContext(
        type: AuthType.apiKey,
        serviceId: result.serviceId!,
        permissions: result.permissions ?? [],
      );

      _putInCache('api:$apiKey', context);
      return context;
    } catch (e) {
      print('❌ API key validation failed: $e');
      return null;
    }
  }

  SecurityContext? _getFromCache(String key) {
    final entry = _cache[key];
    if (entry == null) return null;

    if (DateTime.now().isAfter(entry.expiresAt)) {
      _cache.remove(key);
      return null;
    }

    return entry.context;
  }

  void _putInCache(String key, SecurityContext context) {
    _cache[key] = _CacheEntry(
      context: context,
      expiresAt: DateTime.now().add(_cacheTtl),
    );
  }

  /// Очистка кэша
  void clearCache() {
    _cache.clear();
  }
}

class _CacheEntry {
  final SecurityContext context;
  final DateTime expiresAt;

  _CacheEntry({required this.context, required this.expiresAt});
}

/// Контекст безопасности
class SecurityContext {
  final AuthType type;
  final String? userId;
  final String? serviceId;
  final List<String> permissions;

  SecurityContext({
    required this.type,
    this.userId,
    this.serviceId,
    this.permissions = const [],
  });

  bool hasPermission(String permission) {
    return permissions.contains(permission);
  }
}

enum AuthType { jwt, apiKey }
```

---

#### 10:30 - 12:00: Обновление AuthMiddleware

**Задача:** Интегрировать SecurityClient в AuthMiddleware.

**Обновление:** `lib/middleware/auth_middleware.dart`

```dart
class AuthMiddleware implements IMiddleware {
  final List<String> publicPaths;
  final GraphEngineSecurityClient? securityClient;

  AuthMiddleware({
    this.publicPaths = const ['/health', '/metrics'],
    this.securityClient,
  });

  @override
  Middleware get middleware {
    return (Handler innerHandler) {
      return (Request request) async {
        if (_isPublicPath(request.url.path)) {
          return innerHandler(request);
        }

        // Проверяем API ключ
        final apiKey = request.headers['x-api-key'];
        if (apiKey != null) {
          final context = await _validateApiKey(apiKey);
          if (context == null) {
            return Response(401,
              body: '{"error":"Invalid API key"}',
              headers: {'Content-Type': 'application/json'},
            );
          }

          final newRequest = request.change(context: {
            ...request.context,
            'authType': 'api_key',
            'serviceId': context.serviceId,
            'permissions': context.permissions,
          });

          return innerHandler(newRequest);
        }

        // Проверяем JWT токен
        final authHeader = request.headers['authorization'];
        if (authHeader == null) {
          return Response(401,
            body: '{"error":"Missing Authorization header or X-API-Key"}',
            headers: {'Content-Type': 'application/json'},
          );
        }

        final token = authHeader.replaceFirst('Bearer ', '');
        final context = await _validateJwtToken(token);
        if (context == null) {
          return Response(401,
            body: '{"error":"Invalid JWT token"}',
            headers: {'Content-Type': 'application/json'},
          );
        }

        final newRequest = request.change(context: {
          ...request.context,
          'authType': 'jwt',
          'userId': context.userId,
          'permissions': context.permissions,
        });

        return innerHandler(newRequest);
      };
    };
  }

  Future<SecurityContext?> _validateApiKey(String apiKey) async {
    if (securityClient != null) {
      return await securityClient!.validateApiKey(apiKey);
    }

    // Fallback для тестирования
    if (apiKey.startsWith('aq_')) {
      return SecurityContext(
        type: AuthType.apiKey,
        serviceId: 'service-${apiKey.substring(3, 8)}',
        permissions: ['graph:run', 'graph:cancel'],
      );
    }
    return null;
  }

  Future<SecurityContext?> _validateJwtToken(String token) async {
    if (securityClient != null) {
      return await securityClient!.validateJwtToken(token);
    }

    // Fallback для тестирования
    return SecurityContext(
      type: AuthType.jwt,
      userId: 'user-123',
      permissions: ['graph:run', 'graph:cancel', 'graph:view'],
    );
  }

  bool _isPublicPath(String path) {
    final fullPath = '/$path';
    return publicPaths.any((p) => fullPath.startsWith(p));
  }
}
```

---

#### 12:00 - 13:00: Обновление ServerModule

**Задача:** Добавить SecurityClient в DI.

```dart
void register() {
  // ... существующие регистрации ...

  // Регистрируем SecurityClient (если URL указан)
  final securityUrl = Platform.environment['SECURITY_SERVICE_URL'];
  if (securityUrl != null) {
    locator.registerSingleton<GraphEngineSecurityClient>(
      GraphEngineSecurityClient(
        securityServiceUrl: securityUrl,
        cacheTtl: Duration(minutes: 5),
      ),
    );
  }

  // Обновляем AuthMiddleware с SecurityClient
  locator.registerSingleton<AuthMiddleware>(
    AuthMiddleware(
      securityClient: locator.getOptional<GraphEngineSecurityClient>(),
    ),
  );
}
```

---

### День (14:00 - 18:00): RBAC и Permissions

#### 14:00 - 16:00: Permission Middleware

**Задача:** Создать middleware для проверки прав доступа.

**Файл:** `lib/middleware/permission_middleware.dart`

```dart
// Middleware для проверки прав доступа

import 'package:shelf/shelf.dart';
import '../core/interfaces/i_middleware.dart';

/// Middleware для проверки permissions
class PermissionMiddleware implements IMiddleware {
  final Map<String, List<String>> _routePermissions;

  PermissionMiddleware({
    Map<String, List<String>>? routePermissions,
  }) : _routePermissions = routePermissions ?? _defaultPermissions;

  static final Map<String, List<String>> _defaultPermissions = {
    'POST:/api/v1/runs': ['graph:run'],
    'POST:/api/v1/runs/*/resume': ['graph:resume'],
    'DELETE:/api/v1/runs/*': ['graph:cancel'],
    'GET:/api/v1/runs/*/status': ['graph:view'],
    'GET:/api/v1/runs/*/events': ['graph:view'],
  };

  @override
  Middleware get middleware {
    return (Handler innerHandler) {
      return (Request request) async {
        final permissions = request.context['permissions'] as List<String>?;
        if (permissions == null) {
          // Нет permissions в context - пропускаем
          return innerHandler(request);
        }

        final required = _getRequiredPermissions(request);
        if (required.isEmpty) {
          // Для этого маршрута не требуются permissions
          return innerHandler(request);
        }

        // Проверяем наличие хотя бы одного требуемого permission
        final hasPermission = required.any((p) => permissions.contains(p));
        if (!hasPermission) {
          return Response(
            403,
            body: '{"error":"Insufficient permissions","required":${required}}',
            headers: {'Content-Type': 'application/json'},
          );
        }

        return innerHandler(request);
      };
    };
  }

  List<String> _getRequiredPermissions(Request request) {
    final method = request.method;
    final path = '/${request.url.path}';

    // Точное совпадение
    final exact = _routePermissions['$method:$path'];
    if (exact != null) return exact;

    // Совпадение с wildcard
    for (final entry in _routePermissions.entries) {
      final pattern = entry.key.replaceAll('*', '[^/]+');
      final regex = RegExp('^$pattern\$');
      if (regex.hasMatch('$method:$path')) {
        return entry.value;
      }
    }

    return [];
  }
}
```

---

## День 2 (Вторник): Интеграция с dart_vault

### Утро (09:00 - 13:00): Vault Storage для Run State

#### 09:00 - 11:00: Run State Repository

**Задача:** Создать репозиторий для сохранения состояния графов.

**Файл:** `lib/storage/run_state_repository.dart`

```dart
// Репозиторий для персистентности состояния графов

import 'package:dart_vault_package/dart_vault_package.dart';
import 'package:aq_schema/aq_schema.dart';

/// Репозиторий для сохранения состояния выполнения графов
class RunStateRepository {
  final Vault vault;
  late final DirectRepository<RunState> _repo;

  RunStateRepository({required this.vault}) {
    _repo = vault.direct<RunState>(
      collection: 'graph_run_states',
      fromMap: RunState.fromMap,
    );
  }

  /// Сохранить состояние
  Future<void> saveState(RunState state) async {
    await _repo.save(state);
  }

  /// Получить состояние
  Future<RunState?> getState(String runId) async {
    try {
      return await _repo.get(runId);
    } catch (e) {
      return null;
    }
  }

  /// Удалить состояние
  Future<void> deleteState(String runId) async {
    await _repo.delete(runId);
  }

  /// Получить все активные runs
  Future<List<RunState>> getActiveRuns() async {
    final all = await _repo.list();
    return all.where((s) => s.status == RunStatus.running).toList();
  }
}

/// Модель состояния run
class RunState implements DirectStorable {
  final String runId;
  final String blueprintId;
  final String projectId;
  final RunStatus status;
  final String? currentNodeId;
  final Map<String, dynamic> variables;
  final DateTime startedAt;
  final DateTime? completedAt;
  final String? error;

  RunState({
    required this.runId,
    required this.blueprintId,
    required this.projectId,
    required this.status,
    this.currentNodeId,
    this.variables = const {},
    required this.startedAt,
    this.completedAt,
    this.error,
  });

  @override
  String get id => runId;

  @override
  Map<String, dynamic> toMap() {
    return {
      'runId': runId,
      'blueprintId': blueprintId,
      'projectId': projectId,
      'status': status.name,
      'currentNodeId': currentNodeId,
      'variables': variables,
      'startedAt': startedAt.toIso8601String(),
      'completedAt': completedAt?.toIso8601String(),
      'error': error,
    };
  }

  static RunState fromMap(Map<String, dynamic> map) {
    return RunState(
      runId: map['runId'] as String,
      blueprintId: map['blueprintId'] as String,
      projectId: map['projectId'] as String,
      status: RunStatus.values.byName(map['status'] as String),
      currentNodeId: map['currentNodeId'] as String?,
      variables: map['variables'] as Map<String, dynamic>? ?? {},
      startedAt: DateTime.parse(map['startedAt'] as String),
      completedAt: map['completedAt'] != null
          ? DateTime.parse(map['completedAt'] as String)
          : null,
      error: map['error'] as String?,
    );
  }
}

enum RunStatus {
  running,
  suspended,
  completed,
  failed,
  cancelled,
}
```

---

Продолжить с остальными днями Week 2?
