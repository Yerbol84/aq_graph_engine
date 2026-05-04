# ОТЧЁТ О РЕАЛИЗАЦИИ: Документирование контрактов

**Дата:** 2026-05-02  
**Статус:** ✅ ЗАВЕРШЕНО

---

## Что было сделано

### 1. IRunStateManager — переработан контракт

**Убрано** (lifecycle — не ответственность кэша):
- `suspend(runId, context, nodeId)` → теперь только `IRunRepository.suspendRun`
- `resume(runId)` → теперь только `IRunRepository.resume`
- `complete(runId)` → теперь `IRunRepository.complete` + `IRunStateManager.evict`
- `getSuspendedNodeId(runId)` → теперь `IRunRepository.getRun().suspendedNodeId`

**Добавлено:**
- `evict(runId)` — очистить кэш для завершённого run (только память, не БД)

**Метрики упрощены:** убраны `suspends`/`resumes` (это lifecycle, не кэш).

**Файл:** `aq_schema/lib/graph/engine/i_run_state_manager.dart`  
Добавлен заголовок с чётким контрактом, аналогией, примерами использования и явным "НЕ ИСПОЛЬЗОВАТЬ ДЛЯ".

---

### 2. IRunRepository — расширен контракт

**Добавлено:**
- `resume(runId)` — сбросить suspended state (дефолт: no-op)
- `complete(runId)` — cleanup после завершения run (дефолт: no-op)

**Файл:** `aq_schema/lib/graph/engine/i_run_repository.dart`  
Добавлен заголовок с чётким контрактом, аналогией, примерами использования и явным "НЕ ИСПОЛЬЗОВАТЬ ДЛЯ".

---

### 3. Реализации IRunStateManager обновлены

Все три реализации (`InMemoryStateManager`, `NoopStateManager`, `IntervalStateManager`):
- Убраны `suspend`/`resume`/`complete`/`getSuspendedNodeId`
- Добавлен `evict(runId)`
- Упрощены метрики

---

### 4. WorkflowRunner обновлён

- `_stateManager.resume(runId)` → `_repo.resume(runId)`
- `_stateManager.complete(runId)` → `_repo.complete(runId)` + `_stateManager.evict(runId)`
- `_stateManager.suspend(...)` → убран (дублировал `_repo.suspendRun`)

---

### 5. Правила добавлены в agent_framework.xml

Правило `run_state_contracts` — явно описывает разграничение и запрещённые паттерны.

---

## Результат разграничения

| Операция | До | После |
|----------|-----|-------|
| Suspend | `stateManager.suspend` + `repo.suspendRun` | только `repo.suspendRun` |
| Resume | `stateManager.resume` | `repo.resume` |
| Complete | `stateManager.complete` | `repo.complete` + `stateManager.evict` |
| Checkpoint узла | `stateManager.checkpointForNode` | `stateManager.checkpointForNode` (без изменений) |
| Очистка кэша | `stateManager.complete` | `stateManager.evict` (явное название) |

---

## Проверка

| Проверка | Результат |
|----------|-----------|
| `dart analyze aq_schema` | 0 errors ✅ |
| `dart analyze aq_graph_engine` | 0 errors ✅ |
| `dart test test/unit/` | 53/53 ✅ |
| Сценарии 01–05 | все ✅ |

---

## Критерий успеха достигнут

Читая заголовок любого из двух интерфейсов за 10 секунд понятно:
- `IRunRepository` = журнал событий run → статус, логи, lifecycle → БД
- `IRunStateManager` = буфер кэша RunContext → стратегия checkpoint → память/персистентность
