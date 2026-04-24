# API Keys Implementation Summary

**Дата:** 2026-04-08
**Статус:** ✅ Реализовано и протестировано

## Что реализовано

### 1. Двойная авторизация в AuthMiddleware

**JWT токены** (для пользователей):
```bash
Authorization: Bearer <token>
```

**API ключи** (для воркеров):
```bash
X-API-Key: aq_<type>_<random>
```

### 2. Приоритет авторизации

API ключ проверяется **первым**. Если присутствует валидный API ключ, JWT токен игнорируется.

### 3. Context для handlers

**JWT:**
```dart
{
  'authType': 'jwt',
  'userId': 'user-123',
  'serviceId': null
}
```

**API Key:**
```dart
{
  'authType': 'api_key',
  'userId': null,
  'serviceId': 'service-worke'
}
```

### 4. Валидация (заглушка)

Текущая реализация принимает любые ключи с префиксом `aq_`:

```dart
Future<String?> _validateApiKey(String apiKey) async {
  if (apiKey.startsWith('aq_')) {
    return 'service-${apiKey.substring(3, 8)}';
  }
  return null;
}
```

### 5. Новый endpoint для отладки

`GET /auth/info` - возвращает информацию о текущей авторизации

## Тестирование

✅ JWT токен работает
✅ API ключ работает
✅ Приоритет API ключа над JWT
✅ Невалидные ключи отклоняются
✅ Context корректно передаётся в handlers

## Файлы

- `lib/middleware/auth_middleware.dart` - обновлён с поддержкой API ключей
- `lib/handlers/auth_info_handler.dart` - новый handler для отладки
- `docs/API_KEYS.md` - полная документация

## Интеграция с aq_security

В будущем валидация будет делегирована в `aq_security`:

```dart
final service = await securityClient.validateApiKey(apiKey);
```

## Use Cases

**Воркер запускает граф:**
```bash
curl -X POST http://localhost:8080/api/v1/runs \
  -H "X-API-Key: aq_worker_12345" \
  -d '{"blueprintId":"bp","projectId":"proj"}'
```

**Пользователь запускает граф:**
```bash
curl -X POST http://localhost:8080/api/v1/runs \
  -H "Authorization: Bearer token" \
  -d '{"blueprintId":"bp","projectId":"proj"}'
```

## Следующие шаги

1. Интеграция с `aq_security` для реальной валидации
2. Управление API ключами (создание, ротация, отзыв)
3. Rate limiting по API ключам
4. Аудит действий воркеров
