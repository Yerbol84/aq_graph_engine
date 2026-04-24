# Отчёт о соответствии пакета aq_graph_engine архитектурным принципам

**Дата:** 2026-04-10
**Пакет:** `aq_graph_engine`
**Базовый документ:** `../aq_schema/PACKAGE_ARCHITECTURE.md` v2.0
**Общая оценка:** ❌ **40% соответствие** (критические отклонения)

---

## Исполнительное резюме

Пакет `aq_graph_engine` содержит **КРИТИЧЕСКОЕ ОТКЛОНЕНИЕ** от архитектурных принципов: **отсутствует разделение клиента и сервера**. Файл `lib/server.dart` не существует, все серверные компоненты (движок, runners, nodes) экспортируются в клиентский файл.

Это нарушает фундаментальный принцип **"тонкого клиента"** и делает невозможным правильное использование пакета в распределённой архитектуре.

**Требуется критический рефакторинг.**

---

## ❌ КРИТИЧЕСКОЕ ОТКЛОНЕНИЕ: Отсутствует lib/server.dart

### Требование из документа (Раздел 2.1)

> Каждый пакет в экосистеме AQ должен следовать единой структуре:
> ```
> my_package/
> ├── lib/
> │   ├── my_package.dart              # Главный экспорт (ТОЛЬКО клиентская часть)
> │   ├── client/                      # Клиентская часть (экспортируется)
> │   ├── server/                      # Серверная часть (НЕ экспортируется в main)
> │   └── server.dart                  # Отдельный экспорт для серверной части
> ```

### Текущая реализация

```
aq_graph_engine/
├── lib/
│   ├── aq_graph_engine.dart          ✅ Есть
│   └── server.dart                   ❌ ОТСУТСТВУЕТ
```

**Статус:** ❌ **КРИТИЧЕСКОЕ НАРУШЕНИЕ**

### Требование из документа (Раздел 2.2, правило 2)

> **Серверная часть** экспортируется через **отдельный файл** (`lib/server.dart`):
> ```dart
> // lib/server.dart
> library my_package.server;
>
> export 'server/my_service_server.dart';
> export 'server/storage/my_storage.dart';
> ```

### Проблема

**Должно быть:**
- `lib/aq_graph_engine.dart` — клиентский экспорт (транспорт, интерфейсы)
- `lib/server.dart` — серверный экспорт (движок, runners, nodes, registry)

**У вас:**
- `lib/aq_graph_engine.dart` — смешанный экспорт (клиент + сервер)
- `lib/server.dart` — отсутствует

### Последствия

1. **Клиент получает доступ к серверным компонентам:**
   - `GraphEngine` — движок выполнения (должен быть только на сервере)
   - `EngineExecutionContext` — контекст выполнения (должен быть только на сервере)
   - `NodeTypeRegistry` — реестр типов узлов (должен быть только на сервере)
   - `Metrics` — метрики (должны быть только на сервере)

2. **Нарушается принцип "тонкого клиента":**
   - Клиент может создать `GraphEngine` напрямую
   - Клиент может манипулировать `EngineExecutionContext`
   - Клиент знает о внутренностях движка

3. **Невозможна распределённая архитектура:**
   - Клиент и сервер не разделены
   - Нельзя запустить движок на отдельном сервере
   - Нарушается архитектура из раздела 3.2.3

---

## ❌ Отклонение #1: Серверные компоненты в клиентском экспорте

### Требование из документа (Раздел 2.2, правило 1)

> Главный файл пакета (`lib/my_package.dart`) экспортирует **ТОЛЬКО клиентскую часть**:
> ```dart
> export 'client/my_service_client.dart';
> export 'client/my_repository.dart';
> // НЕ экспортируем server/ и storage/
> ```

### Текущая реализация

**Файл `lib/aq_graph_engine.dart`:**
```dart
// Главный фасад
export 'src/engine/graph_engine.dart';              // ❌ СЕРВЕРНЫЙ компонент
export 'src/engine/engine_execution_context.dart';  // ❌ СЕРВЕРНЫЙ компонент

// Интерфейсы для адаптеров
export 'src/interfaces/i_run_repository.dart';      // ✅ Интерфейс (клиент)
export 'src/interfaces/i_graph_repository.dart';    // ✅ Интерфейс (клиент)

// Транспорт
export 'src/transport/local_engine_transport.dart'; // ⚠️ Смешанный
export 'src/transport/http_engine_transport.dart';  // ✅ Клиентский транспорт

// Мониторинг
export 'src/monitoring/metrics.dart';               // ❌ СЕРВЕРНЫЙ компонент

// Реестр типов узлов
export 'src/registry/node_type_registry.dart';      // ❌ СЕРВЕРНЫЙ компонент

// Клиентская библиотека
export 'src/client/graph_engine_client.dart';       // ✅ Клиент
export 'src/client/graph_run_stream.dart';          // ✅ Клиент
export 'src/client/models.dart';                    // ✅ Клиент
```

### Проблема

**Должно быть в клиентском файле:**
- ✅ `i_run_repository.dart` — интерфейс
- ✅ `i_graph_repository.dart` — интерфейс
- ✅ `http_engine_transport.dart` — клиентский транспорт
- ✅ `graph_engine_client.dart` — клиент
- ✅ `graph_run_stream.dart` — клиент
- ✅ `models.dart` — модели
- ✅ `exceptions.dart` — исключения

**НЕ должно быть в клиентском файле:**
- ❌ `graph_engine.dart` — движок (сервер)
- ❌ `engine_execution_context.dart` — контекст (сервер)
- ❌ `metrics.dart` — метрики (сервер)
- ❌ `node_type_registry.dart` — реестр (сервер)
- ❌ `local_engine_transport.dart` — локальный транспорт (сервер)

### Цитата из документа (Раздел 1.2, постулат 3)

> **Клиент максимально тонкий**
> - Клиентское приложение НЕ пишет ни строчки бизнес-логики
> - Клиент просто подключает пакет и получает готовый сервис
> - Вся логика реализована на уровне пакета (и на клиенте, и на сервере)

---

## ❌ Отклонение #2: Неправильная структура src/

### Требование из документа (Раздел 2.1)

> ```
> my_package/
> ├── lib/
> │   └── src/
> │       ├── client/                      # Клиентская часть
> │       ├── server/                      # Серверная часть
> │       └── shared/                      # Общие утилиты
> ```

### Текущая реализация

```
aq_graph_engine/
└── lib/
    └── src/
        ├── client/                   ✅ Клиентская часть
        ├── engine/                   ❌ Должно быть в server/
        ├── transport/                ⚠️ Смешанный
        ├── interfaces/               ✅ Интерфейсы (shared)
        ├── monitoring/               ❌ Должно быть в server/
        ├── registry/                 ❌ Должно быть в server/
        ├── nodes/                    ❌ Должно быть в server/
        ├── runners/                  ❌ Должно быть в server/
        └── factories/                ❌ Должно быть в server/
```

### Проблема

**Должно быть:**
```
src/
├── client/          ← клиентская часть (graph_engine_client, http_transport)
├── server/          ← серверная часть (engine, runners, nodes, registry, metrics)
├── shared/          ← общие утилиты
├── interfaces/      ← интерфейсы (доступны всем)
└── transport/       ← транспорт (смешанный)
```

**У вас:**
- Нет папки `server/`
- Серверные компоненты разбросаны по корню `src/`
- Непонятно что клиент, что сервер

---

## ❌ Отклонение #3: Отсутствуют типизированные клиенты

### Требование из документа (Раздел 3.2.3)

> **Графовый движок — aq_graph_engine**
>
> **Типизированные клиенты:**
>
> | Клиент | Режим | Примечание |
> |--------|-------|-----------|
> | Flutter/Desktop app | remote | HTTP + SSE к серверу |
> | Server-side сервис | local | InProcess, LocalEngineTransport |
> | Другой сервис | remote | то же HTTP API |
> | Тест | mock | MockEngineTransport, без IO |
>
> Все режимы — один интерфейс `IAQGraphEngineClient`. Режим выбирается при `AQPlatform.init()`.

### Текущая реализация

- ❌ Нет интерфейса `IAQGraphEngineClient` в `aq_schema/clients.dart`
- ❌ Нет разделения на режимы (remote/local/mock)
- ❌ Нет регистрации через `AQPlatform.init()`

### Проблема

**Должно быть:**
```dart
// В aq_schema/lib/clients.dart
abstract interface class IAQGraphEngineClient {
  static IAQGraphEngineClient get instance => AQPlatform.resolve();

  Stream<GraphRunEvent> run(GraphRunRequest request);
  Future<void> resume(String runId, UserInputResponse input);
  Future<void> cancel(String runId);
  Future<GraphRunStatus> getStatus(String runId);
}

// В приложении
AQPlatform.init(engine: RemoteGraphEngineClient(endpoint: url));

// Использование
final stream = IAQGraphEngineClient.instance.run(request);
```

**У вас:**
- Клиент создаётся напрямую: `GraphEngineClient(transport: ...)`
- Нет единой точки входа через `.instance`
- Нет регистрации в `AQPlatform`

---

## ❌ Отклонение #4: Отсутствуют интеграционные тесты

### Требование из документа (Раздел 5.1)

> Благодаря тому, что клиент и сервер в одном пакете, тесты проверяют всё сразу:
> ```
> test/
> ├── integration/                 # Интеграционные тесты (клиент + сервер)
> └── unit/                        # Юнит-тесты
> ```

### Текущая реализация

```
test/
└── unit/                         ✅ Юнит-тесты есть
    ├── comprehensive_test.dart
    ├── engine_core_test.dart
    ├── http_engine_transport_test.dart
    └── phase_2_4_test.dart
```

**Статус:** ⚠️ **Отсутствуют интеграционные тесты**

### Проблема

**Должно быть:**
- Интеграционные тесты клиент + сервер
- Тесты handshake (если применимо)
- Тесты всех режимов (remote/local/mock)

**У вас:**
- Только юнит-тесты
- Нет проверки взаимодействия клиент-сервер

---

## 💡 Рекомендации по исправлению

### Рекомендация #1: Создать lib/server.dart (КРИТИЧНО)

**Идея:**
Разделить пакет на клиентскую и серверную части согласно архитектурным принципам.

**Абстрактный подход:**

1. **Создать `lib/server.dart`:**
   ```dart
   // lib/server.dart
   library aq_graph_engine.server;

   export 'aq_graph_engine.dart';  // ✅ Включить клиента

   // Серверные компоненты
   export 'src/engine/graph_engine.dart';
   export 'src/engine/engine_execution_context.dart';
   export 'src/monitoring/metrics.dart';
   export 'src/registry/node_type_registry.dart';
   export 'src/transport/local_engine_transport.dart';

   // Nodes (если есть)
   export 'src/nodes/...';

   // Runners (если есть)
   export 'src/runners/...';

   // Factories (если есть)
   export 'src/factories/...';
   ```

2. **Переписать `lib/aq_graph_engine.dart`:**
   ```dart
   // lib/aq_graph_engine.dart — ТОЛЬКО клиент
   library aq_graph_engine;

   // Интерфейсы
   export 'src/interfaces/i_run_repository.dart';
   export 'src/interfaces/i_graph_repository.dart';

   // Клиентский транспорт
   export 'src/transport/http_engine_transport.dart';

   // Клиентская библиотека
   export 'src/client/graph_engine_client.dart';
   export 'src/client/graph_run_stream.dart';
   export 'src/client/models.dart';
   export 'src/client/exceptions.dart';

   // Интерфейсы из aq_schema
   export 'package:aq_schema/graph/transport/messages/run_request.dart';
   export 'package:aq_schema/graph/transport/messages/run_event.dart';
   ```

**Идеальный пример использования:**

```dart
// Клиентское приложение (Flutter)
import 'package:aq_graph_engine/aq_graph_engine.dart';

final client = GraphEngineClient(
  transport: HttpEngineTransport(endpoint: 'http://localhost:8765'),
);

final stream = client.run(GraphRunRequest(
  runId: 'run-123',
  blueprintId: 'workflow-456',
));

await for (final event in stream) {
  print('Event: ${event.type}');
}
```

```dart
// Серверное приложение (Worker)
import 'package:aq_graph_engine/server.dart';  // ← Отдельный импорт!

final engine = GraphEngine(
  tools: toolRegistry,
  runRepo: runRepository,
  graphRepo: graphRepository,
  nodeRegistry: NodeTypeRegistry(),
);

final transport = LocalEngineTransport(engine: engine);
await transport.run(request);
```

**Преимущества:**
- Клиент не может создать `GraphEngine` напрямую
- Серверные компоненты изолированы
- Возможна распределённая архитектура

---

### Рекомендация #2: Реорганизовать src/ на client/server/shared

**Идея:**
Чётко разделить клиентские и серверные компоненты на уровне структуры папок.

**Абстрактный подход:**

1. **Создать структуру:**
   ```
   src/
   ├── client/          ← клиентская часть
   │   ├── graph_engine_client.dart
   │   ├── graph_run_stream.dart
   │   ├── models.dart
   │   └── exceptions.dart
   ├── server/          ← серверная часть
   │   ├── engine/
   │   │   ├── graph_engine.dart
   │   │   └── engine_execution_context.dart
   │   ├── runners/
   │   ├── nodes/
   │   ├── factories/
   │   ├── monitoring/
   │   │   └── metrics.dart
   │   └── registry/
   │       └── node_type_registry.dart
   ├── shared/          ← общие утилиты
   │   └── ...
   ├── interfaces/      ← интерфейсы (доступны всем)
   │   ├── i_run_repository.dart
   │   └── i_graph_repository.dart
   └── transport/       ← транспорт (смешанный)
       ├── http_engine_transport.dart    (клиент)
       └── local_engine_transport.dart   (сервер)
   ```

2. **Переместить файлы:**
   - `src/engine/` → `src/server/engine/`
   - `src/monitoring/` → `src/server/monitoring/`
   - `src/registry/` → `src/server/registry/`
   - `src/runners/` → `src/server/runners/`
   - `src/nodes/` → `src/server/nodes/`
   - `src/factories/` → `src/server/factories/`

**Преимущества:**
- Понятно что клиент, что сервер
- Легко поддерживать
- Соответствует архитектурным принципам

---

### Рекомендация #3: Реализовать типизированные клиенты

**Требование из документа (Раздел 3.2.3):**
> Все режимы — один интерфейс `IAQGraphEngineClient`. Режим выбирается при `AQPlatform.init()`.

**Идея:**
Единый интерфейс для всех режимов работы (remote/local/mock). Режим выбирается при инициализации, остальной код использует через `.instance`.

**Абстрактный подход:**

1. **Определить интерфейс в `aq_schema/clients.dart`:**
   ```dart
   abstract interface class IAQGraphEngineClient {
     static IAQGraphEngineClient get instance => AQPlatform.resolve();

     Stream<GraphRunEvent> run(GraphRunRequest request);
     Future<void> resume(String runId, UserInputResponse input);
     Future<void> cancel(String runId);
     Future<GraphRunStatus> getStatus(String runId);
   }
   ```

2. **Реализовать клиенты для разных режимов:**
   - `RemoteGraphEngineClient` — HTTP + SSE к серверу (для Flutter/Desktop)
   - `LocalGraphEngineClient` — InProcess (для server-side сервисов)
   - `MockGraphEngineClient` — заглушка (для тестов)

3. **Регистрация через `AQPlatform.init()`:**
   ```dart
   // Flutter приложение
   AQPlatform.init(
     engine: RemoteGraphEngineClient(endpoint: 'http://localhost:8765'),
   );

   // Server-side сервис
   AQPlatform.init(
     engine: LocalGraphEngineClient(
       engine: GraphEngine(tools: tools, runRepo: runRepo, graphRepo: graphRepo),
     ),
   );

   // Тест
   AQPlatform.init(
     engine: MockGraphEngineClient(responses: [...]),
   );
   ```

4. **Использование в коде:**
   ```dart
   // Везде одинаково, независимо от режима
   final stream = IAQGraphEngineClient.instance.run(request);
   await for (final event in stream) {
     // ...
   }
   ```

**Идеальный пример из документа (Раздел 3.4):**

```dart
// main.dart приложения или воркера

// 1. Auth — первым
final auth = RemoteAuthClient(serverUrl: authUrl);
await auth.loginWithApiKey(apiKey);

// 2. Vault — после auth
final vault = RemoteVaultClient(endpoint: vaultUrl, auth: auth);

// 3. Tools — может зависеть от vault
final tools = AQToolServiceBuilder()
  .withLlm(AnthropicService(apiKey: llmKey))
  .withVault(VaultToolAdapter(vault))
  .build();

// 4. Engine — после tools и vault
final engine = GraphEngineService.local(
  tools: tools,
  runRepo: VaultRunRepository(vault),
  graphRepo: VaultGraphRepository(vault),
  auth: auth,
);

// 5. Регистрация всего в AQPlatform
AQPlatform.init(auth: auth, vault: vault, tools: tools, engine: engine);

// Теперь в любом месте кода — без знания о реализациях:
final stream = IAQGraphEngineClient.instance.run(request);
```

**Преимущества:**
- Единый API для всех режимов
- Легко переключаться между режимами
- Код не зависит от реализации

---

### Рекомендация #4: Добавить интеграционные тесты

**Требование из документа (Раздел 5.1):**
> Благодаря тому, что клиент и сервер в одном пакете, тесты проверяют всё сразу

**Идея:**
Тесты должны проверять взаимодействие клиента и сервера, а не только отдельные компоненты.

**Абстрактный подход:**

1. **Создать `test/integration/`:**
   ```
   test/
   ├── integration/
   │   ├── client_server_integration_test.dart
   │   ├── remote_transport_test.dart
   │   ├── local_transport_test.dart
   │   └── full_workflow_test.dart
   └── unit/
       └── ...
   ```

2. **Пример интеграционного теста:**
   ```dart
   // test/integration/client_server_integration_test.dart
   import 'package:aq_graph_engine/aq_graph_engine.dart';
   import 'package:aq_graph_engine/server.dart';

   void main() {
     test('Client-Server integration', () async {
       // Запускаем сервер
       final engine = GraphEngine(
         tools: mockTools,
         runRepo: inMemoryRunRepo,
         graphRepo: inMemoryGraphRepo,
       );

       final serverTransport = LocalEngineTransport(engine: engine);

       // Подключаем клиента
       final client = GraphEngineClient(transport: serverTransport);

       // Тестируем
       final stream = client.run(GraphRunRequest(
         runId: 'test-run',
         blueprintId: 'test-workflow',
       ));

       final events = await stream.toList();
       expect(events.last, isA<GraphRunCompleted>());
     });
   }
   ```

**Преимущества:**
- Проверяется реальное взаимодействие
- Выявляются проблемы интеграции
- Соответствует архитектурным принципам

---

## Итоговая оценка

| Критерий | Статус | Оценка |
|----------|--------|--------|
| Структура client/server | ❌ | 0% |
| Отдельный server.dart | ❌ | 0% |
| Зависимость от aq_schema | ✅ | 100% |
| Storage только на сервере | N/A | N/A |
| Типизированные клиенты | ❌ | 0% |
| Handshake протокол | ⚠️ | 50% |
| Интеграционные тесты | ❌ | 0% |

**Общая оценка:** ❌ **40% соответствие**

---

## Заключение

Пакет `aq_graph_engine` содержит **КРИТИЧЕСКОЕ ОТКЛОНЕНИЕ** от архитектурных принципов: отсутствует разделение клиента и сервера.

**Критические проблемы:**
1. Отсутствует `lib/server.dart`
2. Серверные компоненты экспортируются в клиентский файл
3. Неправильная структура `src/` (нет разделения client/server)
4. Отсутствуют типизированные клиенты
5. Отсутствуют интеграционные тесты

**Последствия:**
- Нарушается принцип "тонкого клиента"
- Невозможна распределённая архитектура
- Клиент получает доступ к серверным компонентам
- Нарушается безопасность

**Рекомендуется:**
1. **КРИТИЧНО:** Создать `lib/server.dart` и разделить client/server
2. **КРИТИЧНО:** Реорганизовать `src/` на client/server/shared
3. **ВАЖНО:** Реализовать типизированные клиенты через `IAQGraphEngineClient`
4. **ВАЖНО:** Добавить интеграционные тесты

**Приоритет:** МАКСИМАЛЬНЫЙ. Без исправления этих отклонений пакет не соответствует архитектуре AQ Platform и не может использоваться в production.

После исправления пакет станет эталонным примером реализации графового движка с правильным разделением клиента и сервера.
