# Детальный план реализации

**Дата:** 2026-05-02  
**Scope:** `aq_schema/lib/graph/`, `aq_graph_engine`, `aq_graph_worker`  
**Порядок важен** — каждый шаг зависит от предыдущего

---

## Шаг 1: ConditionEvaluator → aq_schema

**Почему первым:** другие шаги не зависят от него, но он самый простой.  
Делаем сначала чтобы сразу убрать из движка.

### 1.1 Создать в aq_schema
Файл: `aq_schema/lib/graph/engine/condition_evaluator.dart`  
Содержимое: точная копия из `aq_graph_engine/lib/src/server/engine/condition_evaluator.dart`

### 1.2 Экспортировать из barrel
Файл: `aq_schema/lib/graph/graph.dart`  
Добавить: `export 'engine/condition_evaluator.dart';`

### 1.3 Обновить импорт в движке
Файл: `aq_graph_engine/lib/src/server/runners/graph_traversal.dart`  
Было: `import '../engine/condition_evaluator.dart';`  
Стало: `import 'package:aq_schema/graph/engine/condition_evaluator.dart';`

### 1.4 Удалить из движка
Файл: `aq_graph_engine/lib/src/server/engine/condition_evaluator.dart` — удалить

### 1.5 Проверка
```bash
dart analyze lib/  # aq_schema — 0 errors
dart analyze lib/  # aq_graph_engine — 0 errors
dart test test/unit/
```

---

## Шаг 2: appendLog в IRunRepository

**Почему вторым:** меняем интерфейс в `aq_schema` — все реализации должны обновиться сразу.

### 2.1 Добавить метод в интерфейс
Файл: `aq_schema/lib/graph/engine/i_run_repository.dart`  
Добавить:
```dart
/// Добавить одну строку лога (append-only, без перезаписи).
Future<void> appendLog(String runId, String entry);
```

### 2.2 Реализовать в DataLayerRunRepository
Файл: `aq_graph_engine/lib/src/server/storage/data_layer_run_repository.dart`
```dart
@override
Future<void> appendLog(String runId, String entry) async {
  final run = await _runs.findById(runId);
  if (run == null) return;
  final logs = _parseLogs(run.logsJson)..add(entry);
  await _runs.save(run.copyWith(logsJson: jsonEncode(logs)), actorId: 'graph_engine');
}
```

### 2.3 Обновить WorkflowRunner
Файл: `aq_graph_engine/lib/src/server/runners/workflow_runner.dart`

`_log()` вызывает `appendLog` вместо накопления в `_logs`.  
Убрать `final List<String> _logs = []`.  
`updateRunLog(runId, _logs)` → `updateRunLog(runId, [])` (логи уже в БД).

**Важно:** при resume восстановление логов из `savedRun.logsJson` остаётся —  
это нужно для отображения истории, не для передачи в БД.

### 2.4 Обновить GraphTraversal
Файл: `aq_graph_engine/lib/src/server/runners/graph_traversal.dart`  
`log` callback теперь вызывает `appendLog` через `repo`.

### 2.5 Обновить все mock реализации
- `aq_graph_worker/test/engine_inmemory_test.dart` — `_InMemoryRunRepository`
- `aq_graph_worker/test/integration/test_engine_setup.dart` — `VaultRunRepository`
- `aq_graph_worker/examples/scenarios/shared/lib/helpers.dart` — `InMemoryRunRepo`
- `aq_graph_engine/test/unit/phase_2_4_test.dart` — `_MockRunRepository`
- `aq_graph_engine/test/unit/engine_core_test.dart` — `_SimpleRunRepo`

### 2.6 Проверка
```bash
dart analyze lib/  # aq_schema
dart analyze lib/  # aq_graph_engine
dart test test/unit/  # aq_graph_engine
dart run bin/main.dart  # сценарии 01-05
```

---

## Шаг 3: DLQ реализация

**Почему третьим:** зависит от `VaultQuery` API который уже проверен.  
Только `aq_graph_engine` — не трогаем `aq_schema`.

### 3.1 Реализовать getDLQJobs
Файл: `aq_graph_engine/lib/src/server/storage/data_layer_run_repository.dart`
```dart
@override
Future<List<WorkflowRun>> getDLQJobs({int limit = 100, int offset = 0}) async {
  return _runs.findAll(
    query: VaultQuery()
        .where('status', VaultOperator.equals, WorkflowRunStatus.failed.value)
        .orderBy('createdAt', descending: true)
        .page(limit: limit, offset: offset),
  );
}
```

### 3.2 Реализовать cleanupDLQ
```dart
@override
Future<int> cleanupDLQ({required Duration olderThan}) async {
  final cutoff = DateTime.now().subtract(olderThan);
  final old = await _runs.findAll(
    query: VaultQuery()
        .where('status', VaultOperator.equals, WorkflowRunStatus.failed.value)
        .where('createdAt', VaultOperator.lessThan, cutoff.toIso8601String()),
  );
  for (final run in old) {
    await _runs.delete(run.id, actorId: 'graph_engine');
  }
  return old.length;
}
```

### 3.3 Проверка
```bash
dart analyze lib/  # aq_graph_engine — 0 errors
dart test test/unit/
```

---

## Шаг 4: aq_graph_worker — правильные импорты

**Почему последним:** зависит от того что `IRunRepository` уже в `aq_schema` (уже сделано).  
Чисто механическая замена импортов.

### 4.1 Найти все файлы с неправильным импортом
```bash
grep -rn "aq_graph_engine/server.dart" aq_graph_worker/
```

### 4.2 Заменить импорты
В каждом найденном файле:
```dart
// было:
import 'package:aq_graph_engine/server.dart';  // только ради IRunRepository
// стало:
import 'package:aq_schema/graph.dart';          // IRunRepository теперь здесь
import 'package:aq_graph_engine/server.dart';   // оставить если нужен GraphEngine
```

**Правило:** если файл использует `GraphEngine`, `WorkflowRunner` и т.д. — импорт движка остаётся.  
Если только `IRunRepository`/`IGraphRepository` — заменяем на `aq_schema`.

### 4.3 Проверка
```bash
dart analyze lib/  # aq_graph_worker
dart test test/  # aq_graph_worker
dart run bin/main.dart  # сценарии 01-05
```

---

## Итоговый порядок файлов

| Шаг | Файл | Действие |
|-----|------|----------|
| 1.1 | `aq_schema/lib/graph/engine/condition_evaluator.dart` | создать |
| 1.2 | `aq_schema/lib/graph/graph.dart` | добавить экспорт |
| 1.3 | `aq_graph_engine/.../graph_traversal.dart` | обновить импорт |
| 1.4 | `aq_graph_engine/.../condition_evaluator.dart` | удалить |
| 2.1 | `aq_schema/lib/graph/engine/i_run_repository.dart` | добавить `appendLog` |
| 2.2 | `aq_graph_engine/.../data_layer_run_repository.dart` | реализовать |
| 2.3 | `aq_graph_engine/.../workflow_runner.dart` | использовать |
| 2.4 | `aq_graph_engine/.../graph_traversal.dart` | обновить log callback |
| 2.5 | 5 mock файлов в `aq_graph_worker` | добавить `appendLog` |
| 2.5 | 2 mock файла в `aq_graph_engine/test` | добавить `appendLog` |
| 3.1 | `aq_graph_engine/.../data_layer_run_repository.dart` | реализовать DLQ |
| 4.x | файлы `aq_graph_worker` | обновить импорты |

---

## Проверки после каждого шага

После каждого шага:
1. `dart analyze lib/` — 0 errors в изменённых пакетах
2. `dart test test/unit/` — все тесты зелёные
3. Сценарии 01–05 — все УСПЕХ (после шагов 2 и 4)
