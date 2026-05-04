# Миграция IRunRepository и IGraphRepository → aq_schema

**Статус:** ✅ ЗАВЕРШЕНО  
**Приоритет:** Высокий  
**Причина:** Breaking change публичного API без полного аудита потребителей

---

## Проблема

`IRunRepository` и `IGraphRepository` живут в `aq_graph_engine/lib/src/interfaces/`
и экспортируются публично из `aq_graph_engine.dart`:

```dart
export 'src/interfaces/i_run_repository.dart';
export 'src/interfaces/i_graph_repository.dart';
```

Это нарушение `aq_schema_architecture_rules`:
> Всё что нужно двум и более пакетам — живёт в aq_schema.

Потребители интерфейса:
- `aq_graph_engine` — реализует `DataLayerRunRepository`, `_RunRepoWithEvents`
- `aq_graph_worker` — реализует `VaultRunRepository` в тестах
- `aq_graph_worker/examples` — реализует `InMemoryRunRepo` в сценариях

Из-за этого `aq_graph_worker` вынужден зависеть от `aq_graph_engine` чтобы получить интерфейс.
Любое изменение сигнатуры — breaking change для всех потребителей одновременно.

---

## План миграции

### Сессия 1: aq_schema (текущий пакет = aq_schema)

**Задача:** Создать интерфейсы в правильном месте.

1. Создать `lib/graph/engine/i_run_repository.dart`:
   ```dart
   import 'package:aq_schema/graph/engine/workflow_run.dart';
   
   abstract class IRunRepository {
     Future<void> createRun(WorkflowRun run);
     Future<void> updateRunLog(String runId, List<String> logs, {WorkflowRunStatus? status});
     Future<void> suspendRun({...});
     Future<WorkflowRun?> getRun(String runId);
     Future<bool> compareAndSetStatus({..., WorkflowRunStatus expectedStatus, WorkflowRunStatus newStatus});
     Future<bool> tryAcquireLock({...});
     Future<bool> releaseLock({...});
     Future<void> moveToDLQ({...});
     Future<List<WorkflowRun>> getDLQJobs({...});
     Future<bool> retryFromDLQ({required String runId});
     Future<int> cleanupDLQ({required Duration olderThan});
   }
   ```

2. Создать `lib/graph/engine/i_graph_repository.dart`:
   ```dart
   abstract class IGraphRepository {
     Future<$Graph?> loadGraph(String blueprintId);
   }
   ```

3. Экспортировать из `lib/graph/graph.dart` barrel.

4. Проверка: `dart analyze`, `dart test`.

### Сессия 2: aq_graph_engine (текущий пакет = aq_graph_engine)

**Задача:** Переключить импорты на aq_schema.

1. Удалить `lib/src/interfaces/i_run_repository.dart`
2. Удалить `lib/src/interfaces/i_graph_repository.dart`
3. Обновить все импорты внутри пакета:
   ```dart
   // было:
   import '../../interfaces/i_run_repository.dart';
   // стало:
   import 'package:aq_schema/graph.dart';
   ```
4. Убрать экспорт из `aq_graph_engine.dart` (интерфейс теперь в aq_schema).
5. Проверка: `dart analyze`, `dart test`, сценарии.

### Сессия 3: aq_graph_worker (текущий пакет = aq_graph_worker)

**Задача:** Убрать зависимость на aq_graph_engine для интерфейсов.

1. В `pubspec.yaml` — убедиться что `aq_schema` в зависимостях.
2. Обновить импорты в тестах и примерах:
   ```dart
   // было:
   import 'package:aq_graph_engine/server.dart'; // только ради IRunRepository
   // стало:
   import 'package:aq_schema/graph.dart';
   ```
3. Проверка: `dart analyze`, `dart test`.

---

## Текущее состояние (после Этапа 2)

`IRunRepository` уже типизирован (`WorkflowRun?` вместо `Map`).
Интерфейс пока остаётся в `aq_graph_engine` — переезд в следующей сессии.

Все реализации обновлены:
- ✅ `DataLayerRunRepository`
- ✅ `_RunRepoWithEvents`  
- ✅ `_MockRunRepository` (тесты)
- ✅ `InMemoryRunRepo` (сценарии)
- ✅ `VaultRunRepository` (интеграционные тесты)
