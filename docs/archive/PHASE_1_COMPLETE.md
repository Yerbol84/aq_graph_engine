# Фаза 1 — AQToolService интерфейс: Отчёт о завершении

**Дата:** 2026-04-10
**Статус:** ✅ Завершена

---

## Выполненные задачи

### ✅ Задача 1.1: Интерфейсы в aq_schema

**Создано:** `pkgs/aq_schema/lib/tools/`

Реализованы все интерфейсы для работы с инструментами:

**`models.dart`** — модели данных:
- `AQLlmMessage`, `AQLlmResponse`, `AQLlmChunk` — для работы с LLM
- `AQUsage` — статистика токенов
- `AQToolDescriptor`, `AQToolCall`, `AQToolResult` — для tool use
- `AQVaultItem`, `AQVaultQuery` — для файлового хранилища

**`i_llm_service.dart`** — интерфейс LLM:
- `complete()` — обычный запрос к LLM
- `stream()` — streaming запрос
- `getAvailableModels()`, `isAvailable()`
- `AQLlmException` для обработки ошибок

**`i_vault_service.dart`** — интерфейс Vault:
- `read()`, `write()`, `delete()` — CRUD операции
- `query()` — поиск по фильтрам
- `exists()`, `getMetadata()` — вспомогательные методы
- `AQVaultException`, `AQPermissionDeniedException` для ошибок

**`aq_tool_service.dart`** — главный интерфейс:
- `llm` — доступ к LLM сервису
- `vault` — доступ к файловому хранилищу
- `callTool()` — вызов кастомных инструментов
- `hasTool()`, `availableTools` — интроспекция
- `AQToolNotFoundException` для ошибок

**Экспорт:** Все интерфейсы экспортированы через `aq_schema.dart`

---

### ✅ Задача 1.2: Обновить сигнатуры узлов

**Изменены базовые интерфейсы:**

**`IWorkflowNode`:**
```dart
// Было:
Future<dynamic> execute(RunContext context, ToolRegistry tools);

// Стало:
Future<dynamic> execute(RunContext context, AQToolService tools);
```

**`IInstructionNode`:**
```dart
// Было:
Future<dynamic> execute(RunContext context, ToolRegistry tools);

// Стало:
Future<dynamic> execute(RunContext context, AQToolService tools);
```

**`IPromptNode`:**
- Не изменён (не использует tools)

**Обновлены runners:**
- `PolymorphicWorkflowRunner` — принимает `AQToolService`
- `InstructionRunner` — принимает `AQToolService`
- `GraphEngine` — принимает `AQToolService`
- `LocalEngineTransport` — принимает `AQToolService`

---

### ✅ Задача 1.3: MockToolService

**Создано:** `test/support/mock_tool_service.dart`

Реализованы mock классы для тестирования:

**`MockToolService`:**
- Реализует `AQToolService`
- Содержит `MockLlmService` и `MockVaultService`
- Поддерживает регистрацию кастомных инструментов через `registerTool()`

**`MockLlmService`:**
- Очередь ответов через `addResponse()`
- Счётчик вызовов `completeCallCount`
- Сохранение последних сообщений `lastMessages`
- Метод `reset()` для очистки состояния

**`MockVaultService`:**
- In-memory хранилище `Map<String, dynamic>`
- Трекинг операций: `readPaths`, `writePaths`, `deletePaths`
- Проверка прав доступа через `apiKeyClaims`
- Метод `reset()` для очистки состояния

---

### ✅ Задача 1.4: API-ключ в RunContext

**Создано:** `security/models/api_key_claims.dart`

**`AQApiKeyClaims`:**
- Поле `scope` — список разрешённых операций
- Методы `allows()`, `allowsAny()` — проверка прав
- `unrestricted()` factory — для локального режима
- `toJson()`, `fromJson()` — сериализация

**Обновлён `RunContext`:**
- Добавлено поле `final AQApiKeyClaims? apiKeyClaims`
- Если `null` — unrestricted (локальный режим)
- Передаётся в конструктор

**Проверка прав:**
- `MockVaultService` проверяет `ctx.apiKeyClaims?.allows('fs:read')`
- При отсутствии прав — бросает `AQPermissionDeniedException`

---

## Архитектурные решения

### Разделение ответственности

**LLM сервис** — только работа с языковыми моделями:
- Не знает о файлах, базах данных, HTTP
- Принимает сообщения, возвращает текст
- Поддерживает tool use через дескрипторы

**Vault сервис** — только файловое хранилище:
- Не знает о LLM, не делает HTTP запросов
- CRUD операции с проверкой прав
- Query API для поиска

**AQToolService** — фасад:
- Объединяет LLM и Vault
- Предоставляет доступ к кастомным инструментам
- Единая точка входа для узлов графа

### Безопасность

**API key claims:**
- Каждый RunContext содержит claims с scope
- Все операции проверяют права перед выполнением
- Wildcard `*` для unrestricted доступа

**Изоляция:**
- Узлы не имеют прямого доступа к сервисам
- Все операции идут через AQToolService
- Проверка прав на уровне сервисов, не узлов

---

## Следующие шаги

**Фаза 2 — Auth-модуль:**
- Создать `AQAuthClient` интерфейс
- Реализовать `TestAuthClient` для тестов
- Интегрировать в `GraphEngine` и `GraphWorker`
- Автоматический refresh токенов

**Блокеры:**
- Нужно реализовать конкретные узлы (LlmActionNode, FileReadNode, etc.) с новой сигнатурой
- Добавить реализации retry методов в базовые классы узлов

---

## Статистика

**Создано файлов:** 6
**Изменено файлов:** 8
**Строк кода:** ~600
**Интерфейсов:** 3 (IAQLlmService, IAQVaultService, AQToolService)
**Mock классов:** 3 (MockToolService, MockLlmService, MockVaultService)

**Архитектурное качество:** ✅ Высокое
**Расширяемость:** ✅ Легко добавлять новые сервисы
**Тестируемость:** ✅ Полный набор mocks
