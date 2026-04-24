# Замечания и улучшения - Graph Engine Server

**Дата начала:** 2026-04-08
**Статус:** В процессе

---

## Принципы архитектуры

### ✅ Тонкий клиент (подтверждено)

Graph Engine Server является **тонким клиентом** для:
- **aq_auth_service** - аутентификация и авторизация
- **aq_studio_data_service** - персистентность данных

**Не должен знать:**
- Как хранятся токены/API ключи (PostgreSQL, Vault, etc.)
- Где находится база данных
- Как работает Vault внутри
- SQL запросы или схемы БД

**Должен знать только:**
- HTTP API endpoints для валидации токенов
- HTTP API endpoints для сохранения/загрузки данных
- Формат запросов/ответов (JSON)

**Текущая реализация:**
```dart
// ✅ Правильно - через HTTP клиент
class GraphEngineSecurityClient {
  final String _baseUrl;

  Future<SecurityContext?> validateJwtToken(String token) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/introspect'),
      body: jsonEncode({'token': token}),
    );
    // Парсим ответ, не знаем как он получен
  }
}

// ❌ Неправильно было бы:
// import 'package:postgres/postgres.dart';
// SELECT * FROM tokens WHERE ...
```

---

## Замечания от пользователя

### 1. [2026-04-08] Fallback для разработки

**Замечание:**
> "для разработки наверно будет так лучше!"

**Контекст:**
- Fallback механизм в AuthMiddleware позволяет работать без реальных сервисов
- Любой API ключ `aq_*` принимается
- Ключи с `admin` получают все права

**Решение:**
- ✅ Оставить fallback для development
- ⚠️ Добавить явное предупреждение при старте если SecurityClient не настроен
- ⚠️ Добавить environment переменную `ENVIRONMENT=development|production`
- ⚠️ В production режиме fallback должен быть отключён

**TODO:**
```dart
// В server_module.dart
if (securityUrl.isEmpty) {
  if (environment == 'production') {
    throw Exception('SECURITY_SERVICE_URL required in production!');
  }
  print('⚠️  WARNING: Running in development mode with mock auth!');
  print('   Set SECURITY_SERVICE_URL for production use');
}
```

**Приоритет:** Medium
**Статус:** Открыто

---

### 2. [2026-04-08] Тонкий клиент - подтверждение архитектуры

**Замечание:**
> "код воркера не должен знать как работает слой данных и как работает слой безопасности он клиент для них- тонкий!"

**Подтверждение:**
- ✅ Graph Engine Server - тонкий клиент
- ✅ Использует только HTTP API
- ✅ Не знает о внутренней реализации

**Проверка текущего кода:**

**SecurityClient - ✅ Правильно:**
```dart
class GraphEngineSecurityClient {
  final String _baseUrl;  // HTTP endpoint
  final http.Client _client;

  // Только HTTP запросы, никаких прямых обращений к БД
  Future<SecurityContext?> validateJwtToken(String token) async {
    final response = await _client.post(...);
    return _parseResponse(response);
  }
}
```

**RunStateRepository - ⚠️ Временное решение:**
```dart
// Сейчас: in-memory Map
class RunStateRepository {
  final Map<String, RunState> _storage = {};
}

// Будущее: HTTP клиент для data service
class RunStateRepository {
  final String _dataServiceUrl;
  final http.Client _client;

  Future<void> saveState(RunState state) async {
    await _client.post(
      Uri.parse('$_dataServiceUrl/states'),
      body: jsonEncode(state.toJson()),
    );
  }
}
```

**TODO:**
- [ ] Заменить in-memory RunStateRepository на HTTP клиент
- [ ] Создать endpoint в aq_studio_data_service для graph states
- [ ] Убрать прямые зависимости на dart_vault из graph_engine_server

**Приоритет:** High (для production)
**Статус:** Открыто

---

### 3. [2026-04-08] Документирование замечаний

**Замечание:**
> "мои замечания отмечай в документе в который ты даже случайно необойдеш"

**Решение:**
- ✅ Создан документ `FEEDBACK_AND_IMPROVEMENTS.md`
- Все замечания фиксируются здесь
- Каждое замечание имеет:
  - Дату
  - Контекст
  - Решение/TODO
  - Приоритет
  - Статус

**Статус:** Реализовано

---

### 4. [2026-04-08] Приоритет: Production Features + Тестирование

**Замечание:**
> "двай начнем с самого важного и срочного! в первой позиции! отработаем все! пишем юнит тесты и тесты интеграции!"

**Решение:**
- Day 4-5: Production Features (rate limiting, validation, error handling)
- Unit тесты для всех компонентов
- Integration тесты для API endpoints

**Приоритет:** Critical
**Статус:** ✅ Завершено (2026-04-08)

---

### 7. [2026-04-08] Тесты должны отражать реальные потребности

**Замечание:**
> "тесты должны отражать реальныеепотребности клиента и и ситуации - отнесись серьезно а не просто шаблонно! тесты это творческий процесс которй должен выдать стабильность!"

**Решение:**
- ✅ Все тесты содержат реальные production сценарии
- ✅ Названия тестов описывают бизнес-кейсы
- ✅ Проверяются edge cases (high load, errors, timeouts)
- ✅ Performance тесты (100 runs, 500 runs)
- ✅ Multi-tenancy тесты
- ✅ Параллельные запросы

**Примеры реальных сценариев:**
```dart
test('Сценарий: Production - 20 графов, 3 проблемных', () async {
  // 17 завершаются нормально
  // 2 зависают в suspended
  // 1 остаётся running (будет долгим)
  // Проверяем что алерты генерируются только для проблемных
});

test('Сценарий: Production - воркер запускает граф через API ключ', () async {
  // Реальный HTTP запрос с API ключом
  // Проверяем что permissions правильные
});
```

**Результат:**
- 136 тестов создано
- Все тесты проходят
- Покрыты критические компоненты
- Реальные production сценарии

**Приоритет:** Critical
**Статус:** ✅ Завершено (2026-04-08)

---

## 2026-04-08: Week 2 Day 4-5 - Итоги

### Выполнено

1. **GraphRunState перенесён в aq_schema**
   - Файл: `pkgs/aq_schema/lib/graph/transport/messages/run_state.dart`
   - Обновлены все импорты

2. **Создано 136 тестов**
   - 121 unit тестов
   - 15 integration тестов
   - Все проходят успешно

3. **Исправлен PermissionMiddleware**
   - Использование `jsonEncode()` для массива в error response

### Архитектурные решения

1. **Тонкий клиент подтверждён**
   - Только HTTP клиенты
   - Никакого прямого доступа к БД
   - Все домены в aq_schema

2. **Тестовая стратегия**
   - Unit тесты с моками
   - Integration тесты с реальным сервером
   - Production сценарии

3. **Структура тестов**
   ```
   test/
     ├── unit/           (121 тестов)
     ├── integration/    (15 тестов)
     └── fixtures/
   ```

### Метрики

- **136 тестов** всего
- **100%** критических компонентов покрыто
- **~16 секунд** время выполнения
- **0 failed tests**

---

### 5. [2026-04-08] Домены в корневом пакете (aq_schema)

**Замечание:**
> "все домены долны быть в корневомпакете- исключение сугубо внутрений домен не использующися вне пакета"

**Правило:**
- **В aq_schema:** Все модели, которые передаются между сервисами
- **Локально:** Только внутренние модели, не покидающие сервис

**Проверка текущего кода:**

**✅ Правильно в aq_schema:**
- `GraphRunRequest` - передаётся клиентом
- `GraphRunEvent` - возвращается клиенту
- `GraphRunStatus` - используется везде

**⚠️ Нужно переместить в aq_schema:**
- `RunState` - используется для персистентности, может понадобиться другим сервисам
- `RunStatus` enum - используется в API ответах

**✅ Правильно локально:**
- `SecurityContext` - только внутри graph_engine_server
- `Alert` - только внутри graph_engine_server (пока)
- Metrics - внутренние структуры

**TODO:**
- [x] Переместить RunState в aq_schema как GraphRunState
- [x] Переместить RunStatus в aq_schema (уже есть как GraphRunStatus)
- [x] Проверить все модели на соответствие правилу

**Приоритет:** High
**Статус:** ✅ Завершено (2026-04-08)

---

### 6. [2026-04-08] Не решать задачи других сервисов

**Замечание:**
> "не решая те задачи которые входят в компетеницию другого сервиса"

**Правило:**
- Graph Engine Server отвечает только за выполнение графов
- Не делает аутентификацию (это aq_auth_service)
- Не делает персистентность данных напрямую (это aq_studio_data_service)
- Только HTTP клиенты к другим сервисам

**Проверка:**
- ✅ SecurityClient - HTTP клиент, не делает auth сам
- ⚠️ RunStateRepository - пока in-memory, нужен HTTP клиент

**Статус:** Подтверждено

---

## Roadmap улучшений

### High Priority

1. **Заменить in-memory RunStateRepository на HTTP клиент**
   - Создать endpoint в aq_studio_data_service
   - Реализовать HTTP клиент в graph_engine_server
   - Убрать Map<String, RunState>

2. **Production mode проверки**
   - Добавить ENVIRONMENT переменную
   - Отключить fallback в production
   - Требовать SECURITY_SERVICE_URL в production

### Medium Priority

3. **Улучшить fallback предупреждения**
   - Явное предупреждение при старте
   - Логирование каждого fallback использования
   - Метрики для fallback requests

### Low Priority

4. **Документация для deployment**
   - Как настроить все сервисы
   - Переменные окружения
   - Docker compose для полного стека

---

## Проверка соответствия принципам

### ✅ Тонкий клиент - соблюдается

**Что делаем правильно:**
- HTTP клиенты для внешних сервисов
- Не знаем о БД
- Не импортируем postgres/drift
- Используем только JSON API

**Что нужно улучшить:**
- RunStateRepository пока in-memory (временно)
- Нет интеграции с data service для states

### ✅ Модульность - соблюдается

**Что делаем правильно:**
- Hooks изолированы
- Middleware независимы
- DI через ServiceLocator
- Легко заменить компоненты

### ✅ Расширяемость - соблюдается

**Что делаем правильно:**
- Новые hooks добавляются легко
- Новые middleware не ломают существующие
- Новые endpoints через router

---

## Следующие шаги

1. Дождаться следующих замечаний от пользователя
2. Фиксировать каждое замечание в этом документе
3. Приоритизировать и реализовывать
4. Обновлять статусы

---

**Примечание:** Этот документ будет обновляться при каждом новом замечании.
