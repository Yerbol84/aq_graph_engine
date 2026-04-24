# API Keys Authentication

## Обзор

Graph Engine Server поддерживает два типа авторизации:

1. **JWT токены** (`Authorization: Bearer <token>`) - для действий пользователей
2. **API ключи** (`X-API-Key: <key>`) - для воркеров и сервисов

## Типы авторизации

### 1. JWT токены (для пользователей)

Используются для действий, инициированных пользователем через UI.

**Заголовок:**
```
Authorization: Bearer <jwt_token>
```

**Context:**
```dart
{
  'authType': 'jwt',
  'userId': 'user-123',
  'serviceId': null
}
```

**Пример:**
```bash
curl -X POST http://localhost:8080/api/v1/runs \
  -H "Authorization: Bearer eyJhbGc..." \
  -H "Content-Type: application/json" \
  -d '{"blueprintId":"bp-1","projectId":"proj-1"}'
```

### 2. API ключи (для воркеров)

Используются для автоматических действий воркеров и сервисов.

**Заголовок:**
```
X-API-Key: <api_key>
```

**Context:**
```dart
{
  'authType': 'api_key',
  'userId': null,
  'serviceId': 'service-worke'
}
```

**Пример:**
```bash
curl -X POST http://localhost:8080/api/v1/runs \
  -H "X-API-Key: aq_worker_12345" \
  -H "Content-Type: application/json" \
  -d '{"blueprintId":"bp-1","projectId":"proj-1"}'
```

## Приоритет авторизации

Если в запросе присутствуют оба заголовка, **API ключ имеет приоритет**:

```bash
# API ключ будет использован, JWT токен проигнорирован
curl -X POST http://localhost:8080/api/v1/runs \
  -H "X-API-Key: aq_worker_12345" \
  -H "Authorization: Bearer token" \
  -d '...'
```

## Публичные эндпоинты

Следующие эндпоинты доступны без авторизации:

- `GET /health` - health check
- `GET /metrics` - Prometheus метрики

## Валидация API ключей

### Текущая реализация (заглушка)

```dart
Future<String?> _validateApiKey(String apiKey) async {
  // Принимаем ключи с префиксом 'aq_'
  if (apiKey.startsWith('aq_')) {
    return 'service-${apiKey.substring(3, 8)}';
  }
  return null;
}
```

### Будущая интеграция с aq_security

```dart
Future<String?> _validateApiKey(String apiKey) async {
  try {
    // Интеграция с aq_security
    final service = await securityClient.validateApiKey(apiKey);
    return service.id;
  } catch (e) {
    return null;
  }
}
```

## Формат API ключей

API ключи должны иметь префикс `aq_` для идентификации:

```
aq_worker_<random>     - для воркеров
aq_service_<random>    - для сервисов
aq_integration_<random> - для интеграций
```

**Примеры валидных ключей:**
- `aq_worker_abc123def456`
- `aq_service_xyz789ghi012`
- `aq_integration_mno345pqr678`

## Использование в handlers

Handlers могут проверять тип авторизации через context:

```dart
@override
Future<Response> handle(RequestContext context) async {
  final authType = context.request.context['authType'] as String?;

  if (authType == 'api_key') {
    // Запрос от воркера
    final serviceId = context.request.context['serviceId'] as String;
    print('Request from service: $serviceId');
  } else if (authType == 'jwt') {
    // Запрос от пользователя
    final userId = context.request.context['userId'] as String;
    print('Request from user: $userId');
  }

  // ...
}
```

## Примеры использования

### Воркер запускает граф

```bash
curl -X POST http://localhost:8080/api/v1/runs \
  -H "X-API-Key: aq_worker_12345" \
  -H "Content-Type: application/json" \
  -d '{
    "blueprintId": "code-generation-v1",
    "projectId": "proj-123",
    "initialVariables": {
      "task": "Generate REST API"
    }
  }'
```

### Пользователь запускает граф

```bash
curl -X POST http://localhost:8080/api/v1/runs \
  -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIs..." \
  -H "Content-Type: application/json" \
  -d '{
    "blueprintId": "code-generation-v1",
    "projectId": "proj-123",
    "initialVariables": {
      "task": "Generate REST API"
    }
  }'
```

### Проверка типа авторизации

```bash
# С JWT токеном
curl http://localhost:8080/auth/info \
  -H "Authorization: Bearer token"

# Ответ:
# {
#   "authType": "jwt",
#   "userId": "user-123",
#   "serviceId": null
# }

# С API ключом
curl http://localhost:8080/auth/info \
  -H "X-API-Key: aq_worker_12345"

# Ответ:
# {
#   "authType": "api_key",
#   "userId": null,
#   "serviceId": "service-worke"
# }
```

## Ошибки авторизации

### Отсутствует авторизация

```bash
curl -X POST http://localhost:8080/api/v1/runs -d '{}'

# 401 Unauthorized
# {"error":"Missing Authorization header or X-API-Key"}
```

### Невалидный API ключ

```bash
curl -X POST http://localhost:8080/api/v1/runs \
  -H "X-API-Key: invalid_key" \
  -d '{}'

# 401 Unauthorized
# {"error":"Invalid API key"}
```

### Невалидный JWT токен

```bash
curl -X POST http://localhost:8080/api/v1/runs \
  -H "Authorization: Bearer invalid_token" \
  -d '{}'

# 401 Unauthorized
# {"error":"Invalid JWT token"}
```

## Интеграция с aq_security

В будущем AuthMiddleware будет интегрирован с пакетом `aq_security`:

```dart
import 'package:aq_security/aq_security_client.dart';

class AuthMiddleware implements IMiddleware {
  final AqSecurityClient securityClient;

  AuthMiddleware({required this.securityClient});

  Future<String?> _validateApiKey(String apiKey) async {
    return await securityClient.validateApiKey(apiKey);
  }

  Future<String?> _validateJwtToken(String token) async {
    return await securityClient.validateJwtToken(token);
  }
}
```

## Best Practices

1. **Воркеры всегда используют API ключи** - никогда не используйте JWT токены для автоматических процессов
2. **Пользовательские действия используют JWT** - для аудита и RBAC
3. **Храните API ключи в переменных окружения** - никогда не коммитьте в git
4. **Ротация ключей** - регулярно обновляйте API ключи
5. **Минимальные права** - каждый воркер должен иметь только необходимые права

## Переменные окружения

```bash
# Для воркеров
export GRAPH_ENGINE_API_KEY=aq_worker_abc123def456
export GRAPH_ENGINE_URL=http://localhost:8080

# Использование в коде воркера
final client = GraphEngineClient(
  baseUrl: Platform.environment['GRAPH_ENGINE_URL']!,
  apiKey: Platform.environment['GRAPH_ENGINE_API_KEY']!,
);
```
