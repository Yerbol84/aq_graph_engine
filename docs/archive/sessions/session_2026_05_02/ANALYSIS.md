# Анализ оставшихся задач

**Дата:** 2026-05-02  
**Пакеты в работе:** `aq_schema` (только `lib/graph/`), `aq_graph_engine`, `aq_graph_worker`

---

## Задача 1: S3 — Append-only логи

### Что сейчас происходит

`WorkflowRunner` накапливает все логи в памяти в `List<String> _logs`.  
После каждого узла вызывается `updateRunLog(runId, _logs)` — передаёт **весь список** в БД.

```
Узел 1 → updateRunLog(["лог1"])           — 1 строка
Узел 2 → updateRunLog(["лог1", "лог2"])   — 2 строки
Узел 3 → updateRunLog(["лог1","лог2","лог3"]) — 3 строки
...
Узел N → updateRunLog([все N строк])      — N строк
```

Итого: 1+2+...+N = N*(N+1)/2 строк передано вместо N.

### Почему проблема

1. **O(n²) I/O** — при 100 узлах: 5050 строк вместо 100
2. **Потеря логов при crash** — если граф упал на узле 50, логи узлов 1–49 уже в БД, но узел 50 потерян
3. **Память** — весь лог хранится в RAM до конца run

### Что хотим

Новый метод в `IRunRepository`:
```dart
Future<void> appendLog(String runId, String entry);
```

`WorkflowRunner._log()` вызывает `appendLog` напрямую — без накопления в памяти.

### Где меняем

1. `aq_schema/lib/graph/engine/i_run_repository.dart` — добавить `appendLog()`
2. `aq_graph_engine/lib/src/server/storage/data_layer_run_repository.dart` — реализовать
3. `aq_graph_engine/lib/src/server/runners/workflow_runner.dart` — использовать
4. `aq_graph_worker/test/` — обновить mock реализации
5. `aq_graph_worker/examples/` — обновить InMemoryRunRepo

---

## Задача 2: S9 — DLQ реализация

### Что сейчас происходит

```dart
// DataLayerRunRepository:
Future<List<WorkflowRun>> getDLQJobs(...) async => [];  // заглушка
Future<int> cleanupDLQ(...) async => 0;                 // заглушка
```

`moveToDLQ` просто меняет статус на `failed` — не создаёт отдельную запись.

### Почему проблема

В продакшне нет способа:
- Найти все упавшие графы
- Перезапустить конкретный упавший граф
- Очистить старые ошибки

### Что хотим

DLQ = все `WorkflowRun` со статусом `failed`.  
`LoggedRepository` поддерживает `findAll({VaultQuery? query})`.  
`VaultQuery` поддерживает `where('status', VaultOperator.equals, 'failed')`.

```dart
Future<List<WorkflowRun>> getDLQJobs({int limit = 100, int offset = 0}) async {
  return _runs.findAll(
    query: VaultQuery()
        .where('status', VaultOperator.equals, 'failed')
        .orderBy('createdAt', descending: true)
        .page(limit: limit, offset: offset),
  );
}
```

### Где меняем

1. `aq_graph_engine/lib/src/server/storage/data_layer_run_repository.dart` — реализовать 3 метода

---

## Задача 3: A4 — ConditionEvaluator → aq_schema

### Что сейчас происходит

`ConditionEvaluator` живёт в `aq_graph_engine/lib/src/server/engine/condition_evaluator.dart`.  
Это чистая утилита — парсит строки вида `"status == 'done'"`, `"count > 5"`.  
Нет зависимостей на движок. Но недоступна другим пакетам.

### Почему проблема

По архитектурному правилу: переиспользуемые утилиты без зависимостей — в `aq_schema`.  
`aq_graph_worker` не может валидировать условия рёбер без запуска движка.  
Будущие пакеты (UI, validator) тоже не смогут использовать.

### Что хотим

Перенести в `aq_schema/lib/graph/engine/condition_evaluator.dart`.  
Экспортировать из `graph.dart` barrel.  
В `aq_graph_engine` — заменить локальный импорт на `aq_schema`.

### Где меняем

1. `aq_schema/lib/graph/engine/condition_evaluator.dart` — создать (копия из движка)
2. `aq_schema/lib/graph/graph.dart` — добавить экспорт
3. `aq_graph_engine/lib/src/server/runners/graph_traversal.dart` — обновить импорт
4. `aq_graph_engine/lib/src/server/engine/condition_evaluator.dart` — удалить

---

## Задача 4: aq_graph_worker — убрать зависимость на aq_graph_engine для интерфейсов

### Что сейчас происходит

В тестах и примерах `aq_graph_worker` импортируют `IRunRepository` из `aq_graph_engine`:
```dart
import 'package:aq_graph_engine/server.dart';  // ради IRunRepository
```

`IRunRepository` теперь живёт в `aq_schema`. Импорт через `aq_graph_engine` работает  
(реэкспорт), но это лишняя зависимость — воркер тянет весь движок ради интерфейса.

### Почему проблема

Нарушение `no_cross_package_deps` — пакеты не должны зависеть друг от друга,  
только от `aq_schema`. Воркер должен зависеть от движка только ради запуска графов,  
не ради интерфейсов.

### Что хотим

В тестах и примерах воркера:
```dart
// было:
import 'package:aq_graph_engine/server.dart';
// стало:
import 'package:aq_schema/graph.dart';
```

### Где меняем

5 файлов в `aq_graph_worker`:
1. `test/engine_inmemory_test.dart`
2. `test/integration/test_engine_setup.dart`
3. `examples/scenarios/shared/lib/helpers.dart`
4. `examples/scenarios/05_suspend_resume/bin/main.dart` (если нужно)
5. Проверить остальные сценарии
