# План исправления критических проблем aq_graph_engine

**Дата:** 2026-04-10
**Статус:** В работе
**Базовый документ:** CODE_AUDIT_REPORT.md

---

## ✅ ВЫПОЛНЕНО

### 1. Создан пакет aq_tool_service

**Проблема:** LLM и Vault сервисы были заглушками с `UnimplementedError`

**Решение:** Создан универсальный интерфейс `IAQToolService` для работы с любыми инструментами через единый API.

**Результат:**
- ✅ Пакет `pkgs/aq_tool_service` создан
- ✅ Интерфейс `IAQToolService` с singleton геттером
- ✅ Модели `ToolCallRequest`, `ToolCallResponse`, `ToolDescriptor`
- ✅ Базовый класс `BaseToolService` с регистрацией инструментов
- ✅ Тесты (10/10 passed)
- ✅ Документация и примеры использования
- ✅ Руководство по интеграции с `aq_graph_engine`

**Следующий шаг:** Интегрировать в `aq_graph_worker` (см. раздел "В работе")

---

## 🔴 КРИТИЧНО (блокирует запуск)

### 2. Создать lib/server.dart

**Проблема:** Серверные компоненты экспортируются в клиентский файл, нарушая принцип "тонкого клиента"

**Текущее состояние:**
```dart
// lib/aq_graph_engine.dart — СМЕШАННЫЙ экспорт
export 'src/engine/graph_engine.dart';              // ❌ СЕРВЕРНЫЙ
export 'src/engine/engine_execution_context.dart';  // ❌ СЕРВЕРНЫЙ
export 'src/monitoring/metrics.dart';               // ❌ СЕРВЕРНЫЙ
export 'src/registry/node_type_registry.dart';      // ❌ СЕРВЕРНЫЙ
export 'src/transport/local_engine_transport.dart'; // ❌ СЕРВЕРНЫЙ
export 'src/client/graph_engine_client.dart';       // ✅ Клиентский
```

**План действий:**

#### 2.1. Создать lib/server.dart
```dart
// lib/server.dart
library aq_graph_engine.server;

// Включить клиентскую часть
export 'aq_graph_engine.dart';

// Серверные компоненты
export 'src/engine/graph_engine.dart';
export 'src/engine/engine_execution_context.dart';
export 'src/monitoring/metrics.dart';
export 'src/registry/node_type_registry.dart';
export 'src/transport/local_engine_transport.dart';

// Runners
export 'src/runners/polymorphic_workflow_runner.dart';
export 'src/runners/instruction_runner.dart';
export 'src/runners/prompt_runner.dart';

// Factories (если нужны)
export 'src/factories/workflow_node_factory.dart';
```

#### 2.2. Переписать lib/aq_graph_engine.dart (ТОЛЬКО клиент)
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

#### 2.3. Обновить импорты в server_apps
```dart
// server_apps/aq_graph_worker/lib/worker/graph_worker.dart
// Было:
import 'package:aq_graph_engine/aq_graph_engine.dart';

// Стало:
import 'package:aq_graph_engine/server.dart';
```

**Оценка времени:** 2-3 часа
**Приоритет:** КРИТИЧЕСКИЙ

---

### 3. Реорганизовать src/ на client/server/shared

**Проблема:** Неправильная структура папок — серверные компоненты разбросаны по корню `src/`

**Текущая структура:**
```
src/
├── client/          ✅ Клиентская часть
├── engine/          ❌ Должно быть в server/
├── transport/       ⚠️ Смешанный
├── interfaces/      ✅ Интерфейсы (shared)
├── monitoring/      ❌ Должно быть в server/
├── registry/        ❌ Должно быть в server/
├── nodes/           ❌ Должно быть в server/
├── runners/         ❌ Должно быть в server/
└── factories/       ❌ Должно быть в server/
```

**Целевая структура:**
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

**План действий:**

#### 3.1. Создать структуру папок
```bash
mkdir -p pkgs/aq_graph_engine/lib/src/server/engine
mkdir -p pkgs/aq_graph_engine/lib/src/server/runners
mkdir -p pkgs/aq_graph_engine/lib/src/server/nodes
mkdir -p pkgs/aq_graph_engine/lib/src/server/factories
mkdir -p pkgs/aq_graph_engine/lib/src/server/monitoring
mkdir -p pkgs/aq_graph_engine/lib/src/server/registry
mkdir -p pkgs/aq_graph_engine/lib/src/shared
```

#### 3.2. Переместить файлы
```bash
# Engine
mv src/engine/* src/server/engine/

# Runners
mv src/runners/* src/server/runners/

# Nodes
mv src/nodes/* src/server/nodes/

# Factories
mv src/factories/* src/server/factories/

# Monitoring
mv src/monitoring/* src/server/monitoring/

# Registry
mv src/registry/* src/server/registry/
```

#### 3.3. Обновить импорты во всех файлах
```dart
// Было:
import '../engine/graph_engine.dart';

// Стало:
import '../server/engine/graph_engine.dart';
```

**Оценка времени:** 4-5 часов
**Приоритет:** КРИТИЧЕСКИЙ

---

## 🟡 ВАЖНО (для production)

### 4. Заменить print() на логгер

**Проблема:** 14 вызовов `print()` в клиентском коде

**Проверка:**
```bash
$ grep -r "print(" pkgs/aq_graph_engine/lib/src/client/ | wc -l
14
```

**План действий:**

#### 4.1. Добавить зависимость на logging
```yaml
# pubspec.yaml
dependencies:
  logging: ^1.2.0
```

#### 4.2. Создать logger utility
```dart
// lib/src/shared/logger.dart
import 'package:logging/logging.dart';

final graphEngineLogger = Logger('aq_graph_engine');

void setupLogging({Level level = Level.INFO}) {
  Logger.root.level = level;
  Logger.root.onRecord.listen((record) {
    print('${record.level.name}: ${record.time}: ${record.message}');
  });
}
```

#### 4.3. Заменить все print() на logger
```dart
// Было:
print('⚠️ Ошибка: $e');

// Стало:
graphEngineLogger.warning('Ошибка: $e');
```

**Оценка времени:** 1-2 часа
**Приоритет:** ВАЖНО

---

### 5. Добавить integration тесты

**Проблема:** Отсутствуют интеграционные тесты клиент + сервер

**Текущее состояние:**
```
test/
└── unit/                         ✅ Юнит-тесты есть
    ├── comprehensive_test.dart
    ├── engine_core_test.dart
    ├── http_engine_transport_test.dart
    └── phase_2_4_test.dart
```

**План действий:**

#### 5.1. Создать структуру
```bash
mkdir -p pkgs/aq_graph_engine/test/integration
```

#### 5.2. Добавить интеграционные тесты
```dart
// test/integration/client_server_integration_test.dart
import 'package:aq_graph_engine/aq_graph_engine.dart';
import 'package:aq_graph_engine/server.dart';
import 'package:test/test.dart';

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

**Оценка времени:** 3-4 часа
**Приоритет:** ВАЖНО

---

### 6. Интегрировать aq_tool_service в aq_graph_worker

**Проблема:** WorkerLlmService и WorkerVaultService — заглушки

**План действий:**

#### 6.1. Добавить зависимость
```yaml
# server_apps/aq_graph_worker/pubspec.yaml
dependencies:
  aq_tool_service:
    path: ../../pkgs/aq_tool_service
```

#### 6.2. Обновить WorkerLlmService
```dart
// server_apps/aq_graph_worker/lib/hands/worker_hands_registry.dart
import 'package:aq_tool_service/aq_tool_service.dart';

class WorkerLlmService implements IAQLlmService {
  @override
  Future<AQLlmResponse> complete({
    required String prompt,
    String? model,
    double? temperature,
  }) async {
    final response = await AQToolService.instance.callTool(
      toolName: 'llm',
      payload: {
        'prompt': prompt,
        if (model != null) 'model': model,
        if (temperature != null) 'temperature': temperature,
      },
    );

    if (!response.success) {
      throw Exception('LLM error: ${response.error}');
    }

    return AQLlmResponse.fromJson(response.result);
  }
}
```

#### 6.3. Обновить WorkerVaultService
```dart
class WorkerVaultService implements IAQVaultService {
  @override
  Future<AQVaultItem?> read(String path, RunContext ctx) async {
    final response = await AQToolService.instance.callTool(
      toolName: 'vault',
      payload: {
        'operation': 'read',
        'path': path,
      },
      context: {
        'runId': ctx.runId,
        'userId': ctx.userId,
      },
    );

    if (!response.success) {
      if (response.errorCode == 'NOT_FOUND') return null;
      throw Exception('Vault error: ${response.error}');
    }

    return AQVaultItem.fromJson(response.result);
  }

  // ... остальные методы аналогично
}
```

#### 6.4. Инициализация в main.dart
```dart
// server_apps/aq_graph_worker/bin/main.dart
import 'package:aq_tool_service/aq_tool_service.dart';

void main() async {
  // Инициализировать AQToolService
  // (пока с mock реализацией, потом заменим на реальную)
  AQToolService.init(MockToolService());

  // Запустить воркер
  final worker = GraphWorker(
    hands: WorkerHandsRegistry(),
  );

  await worker.start();
}
```

**Оценка времени:** 2-3 часа
**Приоритет:** ВАЖНО

---

## 🟢 ЖЕЛАТЕЛЬНО (для качества)

### 7. Реализовать MCP адаптер

**Статус:** Отложено до завершения критических задач

### 8. Добавить token refresh

**Статус:** Отложено до завершения критических задач

### 9. Проверить race conditions

**Статус:** Отложено до завершения критических задач

---

## Итоговая оценка времени

| Задача | Приоритет | Время | Статус |
|--------|-----------|-------|--------|
| 1. aq_tool_service | 🔴 Критично | 4 часа | ✅ Выполнено |
| 2. lib/server.dart | 🔴 Критично | 2-3 часа | ⏳ Следующая |
| 3. Реорганизация src/ | 🔴 Критично | 4-5 часов | ⏳ После #2 |
| 4. Заменить print() | 🟡 Важно | 1-2 часа | ⏳ После #3 |
| 5. Integration тесты | 🟡 Важно | 3-4 часа | ⏳ После #3 |
| 6. Интеграция в worker | 🟡 Важно | 2-3 часа | ⏳ После #2 |

**Общее время:** 16-21 час (2-3 рабочих дня)

---

## Следующий шаг

**Задача #2: Создать lib/server.dart**

Начать с разделения клиентских и серверных экспортов для соблюдения архитектурных принципов.
