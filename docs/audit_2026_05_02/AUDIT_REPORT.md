# AUDIT REPORT — aq_graph_engine

**Дата:** 2026-05-02  
**Режим:** Независимый аудит  
**Статус:** ЧАСТИЧНО РЕШЕНО  
**Готовность к продакшну:** С РИСКАМИ  
**Уровень инженерии:** middle

---

## Критические баги

### BUG-1: appendLog fire-and-forget — потеря логов

```dart
_repo.appendLog(runId, entry).ignore(); // fire-and-forget
```

`.ignore()` подавляет все ошибки Future. Если БД недоступна — логи теряются молча.  
В продакшне: граф выполнился, логи в БД неполные, никто не знает.

### BUG-2: Дублирование логов при suspend

`appendLog` пишет каждую строку в БД.  
`suspendRun` принимает `logs: _logs` (весь накопленный список) и делает `existingLogs.addAll(logs)`.  
Результат: каждая строка лога записана дважды при suspend.

### BUG-3: projectPath теряется при resume

```dart
// respondToInput:
projectPath: '',  // пустая строка вместо реального пути
```

`WorkflowRun` не хранит `projectPath`. При resume FileReadNode/FileWriteNode получают пустой путь и падают.

### BUG-4: Двойной write на каждый узел

`appendLog` (N раз) + `updateRunLog(runId, [])` (пустой список, но всё равно `_runs.save()`) = 2N записей в БД вместо N.

---

## Серьёзные проблемы

### ISSUE-1: tryAcquireLock — заглушка

```dart
Future<bool> tryAcquireLock(...) async => true;
```

При горизонтальном масштабировании один run запускается несколькими воркерами одновременно.

### ISSUE-2: GraphTraversal делает 5 I/O на каждый узел

Traversal — алгоритм обхода. Не должен знать о персистентности.

### ISSUE-3: appendLog — read-modify-write, не true append

```dart
final run = await _runs.findById(runId);  // read
final logs = _parseLogs(run.logsJson)..add(entry);
await _runs.save(run.copyWith(...), ...); // write
```

При параллельных ветках — race condition на `logsJson`.

### ISSUE-4: InstructionRunner — toJson/fromJson на каждом узле

Граф уже загружен. Сериализация/десериализация на каждом шаге — лишняя работа.

### ISSUE-5: _short() дублируется в двух файлах

Одна функция в `workflow_runner.dart` и `graph_traversal.dart`.

### ISSUE-6: cleanupDLQ — soft delete, не физическое удаление

`LoggedRepository.delete()` делает soft delete. Runs остаются в БД, только помечаются.  
Возвращаемое значение "количество удалённых" вводит в заблуждение.

---

## Архитектурные несоответствия

### ARCH-1: IRunStateManager и IRunRepository — дублирование ответственности

При suspend вызываются оба. Нет единого источника истины для состояния run.

### ARCH-2: GraphTraversal знает о репозитории

Traversal принимает `IRunRepository` и вызывает его напрямую. Нарушение SRP.

### ARCH-3: Нет тестов с реальным DataLayerRunRepository

Все 53 теста используют mock-репозитории. DLQ, appendLog, cleanupDLQ не тестируются реально.

---

## Edge cases без покрытия

- Два параллельных узла бросают SuspendExecutionException одновременно
- Crash между appendLog и updateRunLog — run завис в статусе running
- cleanupDLQ при активном run со статусом failed
