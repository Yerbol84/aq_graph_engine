# ПЛАН: Документирование контрактов IRunRepository и IRunStateManager

**Цель:** Сделать разграничение ответственностей настолько явным, что любой разработчик (или AI) не перепутает эти два интерфейса.

**Метод:** Документация прямо в коде интерфейсов + правило в `agent_framework.xml`.

---

## Проблема которую решаем

Сейчас оба интерфейса работают при suspend:
```dart
await _stateManager.suspend(runId, context, node.id);  // зачем?
await _repo.suspendRun(runId, contextJson, nodeId);     // и это тоже?
```

Разработчик не понимает зачем два вызова. Это приводит к:
- Дублированию логики
- Неправильному использованию (вызов не того интерфейса)
- Путанице при добавлении новых реализаций

---

## Чёткое разграничение

### IRunRepository — "Что произошло с run"

**Отвечает за:** персистентность жизненного цикла run.

Хранит:
- Статус run (running / suspended / completed / failed)
- Логи выполнения
- `contextJson` — снапшот для resume (записывается ТОЛЬКО при suspend)
- `suspendedNodeId` — с какого узла возобновить
- `graphSnapshot` — граф на момент запуска

**Аналогия:** журнал событий. Каждая запись — факт о run.

**Когда использовать:** когда нужно изменить статус, записать логи, сохранить/получить данные run из БД.

**Когда НЕ использовать:** для промежуточного кэширования RunContext между узлами.

---

### IRunStateManager — "Как кэшировать RunContext между узлами"

**Отвечает за:** стратегию checkpoint/restore RunContext во время выполнения.

Хранит:
- `RunContext` (переменные, состояние выполнения) — в памяти или персистентно
- Счётчик шагов для интервального checkpoint
- Hot cache для быстрого restore

**Аналогия:** буфер записи. Решает когда и как сохранять промежуточное состояние.

**Когда использовать:** после выполнения узла с `IStatefulNode` — для checkpoint RunContext.

**Когда НЕ использовать:** для управления статусом run, записи логов, suspend/resume lifecycle.

---

## Текущее дублирование (что убрать)

`IRunStateManager` содержит `suspend`/`resume`/`complete` — это lifecycle run, не стратегия кэширования. Они дублируют `IRunRepository`.

**Решение:** убрать `suspend`/`resume`/`complete` из `IRunStateManager`. Оставить только:
- `checkpoint` / `checkpointForNode` — кэширование RunContext
- `restore` — восстановление RunContext из кэша
- `metrics` — статистика

---

## Шаги реализации

### Шаг 1: Обновить `IRunStateManager` в `aq_schema`

Файл: `aq_schema/lib/graph/engine/i_run_state_manager.dart`

Убрать:
- `suspend(runId, context, nodeId)` — это lifecycle, не кэш
- `resume(runId)` — это lifecycle
- `complete(runId)` — это lifecycle
- `getSuspendedNodeId(runId)` — это данные run, не кэш

Оставить:
- `checkpoint(runId, context)` — сохранить RunContext
- `checkpointForNode(runId, context, hint)` — умный checkpoint по hint
- `restore(runId)` — восстановить RunContext
- `metrics` — статистика

Добавить в заголовок файла чёткий контракт (см. ниже).

### Шаг 2: Обновить `IRunRepository` в `aq_schema`

Файл: `aq_schema/lib/graph/engine/i_run_repository.dart`

Добавить:
- `resume(runId)` — сбросить suspended state (уже есть в `suspendRun`, нужен явный метод)
- `complete(runId)` — cleanup после завершения run

Добавить в заголовок файла чёткий контракт.

### Шаг 3: Обновить реализации `IRunStateManager`

Файлы в `aq_schema/lib/graph/engine/state_strategies/`:
- `InMemoryStateManager` — убрать `suspend`/`resume`/`complete`/`getSuspendedNodeId`
- `NoopStateManager` — убрать те же методы
- `IntervalStateManager` — убрать те же методы

### Шаг 4: Обновить `WorkflowRunner` в `aq_graph_engine`

Файл: `aq_graph_engine/lib/src/server/runners/workflow_runner.dart`

- `_stateManager.suspend(...)` → убрать (дублирует `_repo.suspendRun`)
- `_stateManager.resume(...)` → `_repo.resume(runId)`
- `_stateManager.complete(...)` → `_repo.complete(runId)`

### Шаг 5: Обновить все реализации `IRunRepository`

Добавить `resume` и `complete` во все 7 реализаций (дефолт в abstract class — no-op).

### Шаг 6: Добавить правило в `agent_framework.xml`

Правило: "IRunRepository vs IRunStateManager — не путать".

---

## Проверка после каждого шага

```bash
dart analyze lib/  # aq_schema
dart analyze lib/  # aq_graph_engine
dart test test/unit/
dart run bin/main.dart  # сценарии 01-05
```

---

## Критерий успеха

После реализации любой разработчик читая заголовок интерфейса должен за 10 секунд понять:
- `IRunRepository` — статус, логи, lifecycle run → БД
- `IRunStateManager` — кэш RunContext между узлами → стратегия
