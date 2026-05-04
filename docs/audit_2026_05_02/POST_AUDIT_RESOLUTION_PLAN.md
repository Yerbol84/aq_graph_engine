# POST-AUDIT RESOLUTION PLAN

**Дата:** 2026-05-02  
**Пакет:** aq_graph_engine  
**Принцип:** одна проблема = одна корневая причина = одно чёткое решение

---

## 1. Обзор проблем

| ID | Название | Приоритет |
|----|----------|-----------|
| BUG-1 | appendLog fire-and-forget | CRITICAL |
| BUG-2 | Дублирование логов при suspend | CRITICAL |
| BUG-3 | projectPath теряется при resume | CRITICAL |
| BUG-4 | Двойной write на каждый узел | HIGH |
| ISSUE-1 | tryAcquireLock заглушка | HIGH |
| ISSUE-2 | GraphTraversal делает 5 I/O на узел | HIGH |
| ISSUE-3 | appendLog — read-modify-write | HIGH |
| ISSUE-4 | InstructionRunner toJson/fromJson на каждом узле | MEDIUM |
| ISSUE-5 | _short() дублируется | LOW |
| ISSUE-6 | cleanupDLQ — soft delete вводит в заблуждение | MEDIUM |
| ARCH-1 | IRunStateManager + IRunRepository дублируют ответственность | HIGH |
| ARCH-2 | GraphTraversal знает о репозитории | HIGH |
| ARCH-3 | Нет тестов с реальным DataLayerRunRepository | HIGH |

---

## 2. Детальный разбор

---

### BUG-1: appendLog fire-and-forget

**Описание**  
`_repo.appendLog(runId, entry).ignore()` — ошибки записи лога подавляются молча.

**Тип:** кодовая + архитектурная

**Root Cause**  
Попытка сделать логирование "быстрым" (не блокировать выполнение узла) привела к потере гарантий доставки.

**5 Whys:**
1. Почему `.ignore()`? — чтобы не ждать записи лога
2. Почему не ждать? — чтобы не замедлять выполнение узла
3. Почему замедляет? — потому что appendLog делает read-modify-write (медленно)
4. Почему read-modify-write? — потому что `logsJson` хранится как JSON-строка в одном поле
5. Почему в одном поле? — потому что `WorkflowRun` не имеет отдельной таблицы логов

**Настоящая причина:** неправильная модель хранения логов. Логи как JSON-строка в поле модели — это не append-friendly структура.

**Решение (основное)**  
Убрать `appendLog` из hot path `_log()`. Логи накапливаются в памяти (`_logs`), записываются в БД батчем при смене статуса (completed/failed/suspended). Это уже делает `updateRunLog` — нужно просто убрать дублирование.

```dart
void _log(String message) {
  final entry = '[${DateTime.now().toString().substring(11, 19)}] $message';
  _logs.add(entry);  // только в память
  graphEngineServerLogger.fine(entry);
}
// При завершении: updateRunLog(runId, _logs, status: completed) — один write
```

**Альтернатива:** отдельная таблица `workflow_run_logs` с true append (INSERT). Правильнее архитектурно, но требует изменения схемы БД и `aq_schema`.

**Impact Analysis**  
- Убрать `appendLog` из `IRunRepository` (или оставить как no-op дефолт)
- Убрать `_repo.appendLog(runId, entry).ignore()` из `_log()`
- `updateRunLog` снова передаёт `_logs` (не пустой список)
- `DataLayerRunRepository.updateRunLog` снова работает корректно

**Риски решения**  
При crash между узлами логи теряются (не записаны в БД). Это приемлемо — логи это observability, не бизнес-данные. Статус run при этом остаётся `running` — это отдельная проблема (BUG-4).

**Как предотвратить в будущем**  
Правило: `.ignore()` запрещён в продакшн коде. Добавить lint rule или code review checklist.

**Приоритет:** CRITICAL — исправить первым

---

### BUG-2: Дублирование логов при suspend

**Описание**  
`appendLog` пишет каждую строку в БД. `suspendRun(logs: _logs)` добавляет весь список поверх. Каждая строка в БД дважды.

**Тип:** кодовая

**Root Cause**  
Два механизма записи логов работают одновременно без координации.

**5 Whys:**
1. Почему дублирование? — `suspendRun` добавляет `_logs` поверх уже записанных
2. Почему `_logs` передаётся в `suspendRun`? — исторически, до введения `appendLog`
3. Почему `appendLog` добавили не убрав старый механизм? — инкрементальное изменение без полного рефакторинга
4. Почему не было полного рефакторинга? — изменение делалось по частям в разных итерациях
5. Почему по частям? — отсутствие атомарного подхода к изменению механизма логирования

**Настоящая причина:** два механизма логирования введены без удаления старого.

**Решение (основное)**  
Следует из BUG-1: убрать `appendLog` из hot path. Тогда `suspendRun(logs: _logs)` — единственный механизм, дублирования нет.

Дополнительно: `suspendRun` в `IRunRepository` не должен принимать `logs` — это нарушение SRP (suspend = сохранить контекст, не логи). Логи пишутся отдельно через `updateRunLog`.

```dart
// Было:
await _repo.suspendRun(runId: runId, contextJson: ..., nodeId: ..., logs: _logs);
await _repo.updateRunLog(runId, [], status: suspended);

// Должно быть:
await _repo.suspendRun(runId: runId, contextJson: ..., nodeId: ...);
await _repo.updateRunLog(runId, _logs, status: suspended);
```

**Impact Analysis**  
- Изменить сигнатуру `suspendRun` в `IRunRepository` (убрать `logs`) — breaking change
- Обновить все 7 реализаций
- `DataLayerRunRepository.suspendRun` — убрать `existingLogs.addAll(logs)`

**Приоритет:** CRITICAL

---

### BUG-3: projectPath теряется при resume

**Описание**  
`respondToInput` передаёт `projectPath: ''`. Узлы работающие с файловой системой падают.

**Тип:** архитектурная + кодовая

**Root Cause**  
`WorkflowRun` не хранит `projectPath`. При resume нет источника для восстановления этого значения.

**5 Whys:**
1. Почему `projectPath: ''`? — нет источника данных при resume
2. Почему нет источника? — `WorkflowRun` не содержит `projectPath`
3. Почему не содержит? — при проектировании модели это поле не было включено
4. Почему не было включено? — `projectPath` считался runtime-параметром, не персистентным
5. Почему это неправильно? — resume требует воспроизведения исходного контекста запуска

**Настоящая причина:** `WorkflowRun` не хранит все параметры необходимые для resume.

**Решение (основное)**  
Добавить `projectPath` в `WorkflowRun` (изменение `aq_schema`). При `createRun` сохранять. При resume брать из `existingRun.projectPath`.

**Альтернатива (временная, TECH DEBT):** передавать `projectPath` через `UserInputResponse.values` как специальное поле. Некрасиво, но не требует изменения схемы.

**Impact Analysis**  
- `WorkflowRun` в `aq_schema` — добавить поле (отдельная сессия)
- `DataLayerRunRepository.createRun` — сохранять `projectPath`
- `respondToInput` — брать `existingRun.projectPath`

**Приоритет:** CRITICAL

**Tech Debt (временное решение):**  
До изменения `aq_schema` — сохранять `projectPath` в `graphSnapshot` при создании run:
```dart
graphSnapshot: {...execContext.graph.toMap(), '_projectPath': execContext.projectPath}
```
При resume: `existingRun.graphSnapshot['_projectPath'] as String? ?? ''`  
Удалить после добавления поля в `WorkflowRun`.

---

### BUG-4: Двойной write на каждый узел

**Описание**  
`appendLog` (write) + `updateRunLog(runId, [])` (write с пустым списком) = 2 записи в БД на каждый узел.

**Тип:** кодовая

**Root Cause**  
`updateRunLog` с пустым списком всё равно вызывает `_runs.save()` — нет проверки на пустоту.

**Решение (основное)**  
Следует из BUG-1: убрать `appendLog`. `updateRunLog(runId, [])` — добавить guard:

```dart
// DataLayerRunRepository:
Future<void> updateRunLog(String runId, List<String> logs, {WorkflowRunStatus? status}) async {
  if (logs.isEmpty && status == null) return; // ничего не делать
  ...
}
```

**Приоритет:** HIGH (решается вместе с BUG-1)

---

### ISSUE-1: tryAcquireLock — заглушка

**Описание**  
`tryAcquireLock` всегда возвращает `true`. При нескольких воркерах один run запускается несколько раз.

**Тип:** архитектурная + эксплуатационная

**Root Cause**  
Distributed locking требует внешнего координатора (Redis, Postgres advisory locks). `IDataLayer` не предоставляет такого API.

**5 Whys:**
1. Почему заглушка? — нет реализации
2. Почему нет реализации? — `IDataLayer` не имеет lock API
3. Почему не имеет? — это не было спроектировано в `aq_schema`
4. Почему не спроектировано? — single-worker сценарий был приоритетом
5. Почему это проблема сейчас? — горизонтальное масштабирование требует координации

**Решение (основное)**  
Реализовать через Postgres advisory locks в `DataLayerRunRepository`:
```dart
// pg_try_advisory_lock(hashCode(runId))
```
Требует доступа к raw SQL через `IDataLayer` — отдельная сессия с `aq_data_layer`.

**Временное решение (TECH DEBT):**  
Документировать ограничение: "single-worker only". Добавить assertion в `GraphEngine`:
```dart
assert(mode != GraphEngineMode.remote || remoteServerUrl != null,
  'Multiple workers require distributed lock implementation');
```

**Приоритет:** HIGH  
**Tech Debt:** до реализации advisory locks — single-worker deployment only.

---

### ISSUE-2: GraphTraversal делает 5 I/O на каждый узел

**Описание**  
`processNode` вызывает `repo.getRun()` и `repo.updateRunLog()` на каждом узле. 5 I/O операций на узел.

**Тип:** архитектурная

**Root Cause**  
`GraphTraversal` принимает `IRunRepository` и использует его для управления потоком (проверка `suspended`). Traversal смешивает алгоритм обхода с персистентностью.

**5 Whys:**
1. Почему 5 I/O? — traversal проверяет статус run после каждого узла
2. Почему проверяет? — чтобы остановиться если run был отменён извне
3. Почему это делает traversal? — исторически, логика была в WorkflowRunner
4. Почему перешло в traversal? — при рефакторинге ответственность не была чётко разделена
5. Почему не разделена? — нет явного контракта между traversal и lifecycle

**Настоящая причина:** traversal не должен знать о персистентности. Проверка `suspended` — это lifecycle, не traversal.

**Решение (основное)**  
Traversal не принимает `IRunRepository`. Вместо этого — callback `onNodeExecuted`:
```dart
typedef OnNodeExecuted = Future<bool> Function(); // true = continue, false = stop
```
Runner передаёт callback который проверяет статус. Traversal только вызывает его.

**Impact Analysis**  
- Убрать `IRunRepository` из `GraphTraversal`
- Добавить `onNodeExecuted` callback
- `WorkflowRunner` реализует callback с проверкой статуса

**Приоритет:** HIGH

---

### ISSUE-3: appendLog — read-modify-write

**Описание**  
`appendLog` читает run, добавляет строку, сохраняет. При параллельных ветках — race condition.

**Тип:** архитектурная

**Root Cause**  
`logsJson` — это JSON-строка в поле модели. Нет атомарного append на уровне БД.

**Решение (основное)**  
Следует из BUG-1: убрать `appendLog` из hot path. Логи пишутся батчем. Race condition исчезает.

Долгосрочно: отдельная таблица `workflow_run_logs` с `INSERT` — true append без read-modify-write.

**Приоритет:** HIGH (решается вместе с BUG-1)

---

### ISSUE-4: InstructionRunner — toJson/fromJson на каждом узле

**Описание**  
```dart
final polymorphicNode = InstructionNodeFactory.fromJson(firstNode.toJson());
```
Граф уже загружен как объекты. Сериализация/десериализация на каждом шаге — лишняя работа.

**Тип:** кодовая

**Root Cause**  
`InstructionGraph` хранит узлы как `InstructionNode` (data class), не как `IInstructionNode` (полиморфный). При загрузке нет конвертации — она делается при выполнении.

**Решение (основное)**  
Аналогично `TypedWorkflowGraph` — создать `TypedInstructionGraph` который хранит `IInstructionNode`. Конвертация при загрузке, не при выполнении.

**Приоритет:** MEDIUM

---

### ISSUE-5: _short() дублируется

**Описание**  
Одна функция в двух файлах.

**Тип:** кодовая (DRY)

**Root Cause**  
При разбиении `WorkflowRunner` на `GraphTraversal` функция была скопирована, не вынесена.

**Решение**  
Вынести в `lib/src/shared/string_utils.dart` или в `lib/src/server/runners/runner_utils.dart`.

**Приоритет:** LOW

---

### ISSUE-6: cleanupDLQ — soft delete вводит в заблуждение

**Описание**  
`cleanupDLQ` возвращает "количество удалённых", но физически записи остаются (soft delete).

**Тип:** кодовая + продуктовая

**Root Cause**  
`LoggedRepository.delete()` делает soft delete по дизайну (audit trail). Метод `cleanupDLQ` не учитывает это.

**Решение**  
Обновить документацию метода: "помечает как удалённые (soft delete), физически не удаляет". Переименовать в `archiveDLQ` если семантика именно архивирование.

**Приоритет:** MEDIUM

---

### ARCH-1: IRunStateManager + IRunRepository — дублирование

**Описание**  
При suspend вызываются оба. Нет единого источника истины.

**Тип:** архитектурная

**Root Cause**  
`IRunStateManager` был добавлен как отдельный слой поверх существующего `IRunRepository` без чёткого разграничения ответственности.

**Решение (основное)**  
Чёткое разграничение:
- `IRunRepository` — персистентность (CRUD runs в БД)
- `IRunStateManager` — in-memory state для текущего run (checkpoint/restore для быстрого доступа)

`IRunStateManager` не дублирует `IRunRepository` — он кэширует состояние в памяти для производительности. При suspend: сначала `IRunStateManager.suspend()` (in-memory), потом `IRunRepository.suspendRun()` (персистентность).

**Приоритет:** HIGH

---

### ARCH-2: GraphTraversal знает о репозитории

Решается в ISSUE-2 (callback вместо прямой зависимости).

---

### ARCH-3: Нет тестов с реальным DataLayerRunRepository

**Описание**  
Все 53 теста используют mock. DLQ, appendLog, cleanupDLQ не тестируются реально.

**Тип:** процессная

**Root Cause**  
Интеграционные тесты требуют реального `IDataLayer` (Postgres/InMemory). Это не настроено в `aq_graph_engine`.

**Решение**  
Добавить `test/integration/` с `InMemoryVaultStorage` (из `dart_vault`) как реальным бэкендом:
```dart
// test/integration/data_layer_run_repository_test.dart
final storage = InMemoryVaultStorage();
Vault.initialize(storage);
final repo = DataLayerRunRepository();
// тестировать реальное поведение
```

**Приоритет:** HIGH

---

## 3. План внедрения

### Этап A: Критические баги (делать немедленно)

**A1 — Убрать appendLog из hot path (BUG-1, BUG-2, BUG-4, ISSUE-3)**

Одно изменение решает 4 проблемы:
1. Убрать `_repo.appendLog(runId, entry).ignore()` из `_log()`
2. Вернуть `_logs` в `updateRunLog` (не пустой список)
3. Убрать `logs` параметр из `suspendRun` в `IRunRepository`
4. Добавить guard в `updateRunLog`: `if (logs.isEmpty && status == null) return`

Затронутые файлы:
- `aq_schema/lib/graph/engine/i_run_repository.dart` — убрать `logs` из `suspendRun`
- `aq_graph_engine/lib/src/server/storage/data_layer_run_repository.dart`
- `aq_graph_engine/lib/src/server/runners/workflow_runner.dart`
- Все 7 реализаций `IRunRepository` — обновить `suspendRun`

**A2 — projectPath при resume (BUG-3)**

Временное решение (TECH DEBT до изменения `aq_schema`):
Сохранять `projectPath` в `graphSnapshot` при `createRun`, восстанавливать при resume.

### Этап B: Архитектурные улучшения

**B1 — Убрать IRunRepository из GraphTraversal (ISSUE-2, ARCH-2)**

Заменить на callback `onNodeExecuted`.

**B2 — Интеграционные тесты (ARCH-3)**

Добавить `test/integration/data_layer_run_repository_test.dart`.

**B3 — Разграничение IRunStateManager / IRunRepository (ARCH-1)**

Документировать чёткие границы ответственности.

### Этап C: Технический долг

**C1 — TypedInstructionGraph (ISSUE-4)**

**C2 — _short() в shared (ISSUE-5)**

**C3 — tryAcquireLock реализация (ISSUE-1)**

**C4 — projectPath в WorkflowRun (BUG-3 полное решение)**

---

## 4. Изменения в процессах

### Code Review Checklist (добавить)
- [ ] Нет `.ignore()` на Future в продакшн коде
- [ ] Нет `async => true` / `async => []` в реализациях интерфейсов без комментария TECH DEBT
- [ ] При изменении механизма записи — проверить нет ли дублирования с существующим
- [ ] При resume — проверить все параметры исходного запуска восстановлены

### Правило для новых методов в IRunRepository
Новые методы добавляются как `async {}` (no-op) в abstract class.  
Реализации переопределяют только если нужна реальная логика.  
Это предотвращает breaking change при расширении контракта.

### Тестирование
Каждый новый метод в `DataLayerRunRepository` должен иметь интеграционный тест с `InMemoryVaultStorage`.

---

## 5. Список технического долга

| ID | Описание | Условие удаления |
|----|----------|-----------------|
| TD-1 | projectPath в graphSnapshot | После добавления поля в WorkflowRun (aq_schema) |
| TD-2 | tryAcquireLock → true | После реализации Postgres advisory locks |
| TD-3 | appendLog как no-op дефолт | После реализации отдельной таблицы логов |
| TD-4 | InstructionRunner toJson/fromJson | После создания TypedInstructionGraph |
