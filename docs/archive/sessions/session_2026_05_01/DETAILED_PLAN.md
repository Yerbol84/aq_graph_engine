# aq_graph_engine — Детальный план оставшихся задач

**Дата:** 2026-05-01  
**Scope:** только `aq_graph_engine`  
**Baseline:** dart analyze 0 errors · dart test 53/53 · сценарии 01–05 ✅

---

## Задача 6: Разбиение WorkflowRunner (God Object)

### Проблема
`workflow_runner.dart` — 508 строк, один класс делает 6 вещей:
1. Lifecycle run (start/complete/fail/suspend)
2. Обход графа (traversal: edges, join, parallel)
3. Выполнение узла (execute + retry)
4. Suspend/Resume (сериализация снапшота)
5. Логирование
6. Метрики

**Почему это плохо:**
- Невозможно тестировать части изолированно
- Изменение retry логики требует читать весь файл
- Изменение traversal ломает suspend/resume и наоборот
- Нарушение SRP — единственная причина изменения

**На что влияет:** читаемость, тестируемость, поддержка

### Варианты

**Вариант A — Выделить 3 класса (рекомендуется)**

```
workflow_runner.dart        # оркестратор: lifecycle + координация (~100 строк)
graph_traversal.dart        # обход графа: edges, join, parallel (~150 строк)
node_executor.dart          # execute + retry (~80 строк)
```

`WorkflowRunner` создаёт `GraphTraversal` и `NodeExecutor`, вызывает их методы.  
`GraphTraversal` получает callback `onNodeReady(node, context)` — вызывает `NodeExecutor`.

**Вариант B — Выделить только `NodeExecutor`**

Минимальное изменение. Только retry логика уходит в отдельный класс.  
`WorkflowRunner` остаётся большим, но retry изолирован.

**Вариант C — Ничего не делать**

Код работает. Разбиение — косметика без функционального эффекта.

### Решение
**Вариант A.** Разбиение даёт реальную пользу: `NodeExecutor` можно тестировать без графа, `GraphTraversal` — без репозитория.

**Важно:** `_RunRepoWithEvents` (Decorator) тоже выносится в отдельный файл `run_repo_event_bridge.dart` — сейчас это 80 строк boilerplate внутри `local_engine_transport.dart`.

### Риски
- Нужно аккуратно пробросить `isResume` и `_nodeIterations` через новые классы
- Тесты должны остаться зелёными

---

## Задача 7: Логирование — print() → структурированный логгер

### Проблема
```
WorkflowRunner:        1 вызов print()
LocalEngineTransport: 15 вызовов print()
HttpEngineTransport:   6 вызовов print()
```

`PromptRunner` уже использует `graphEngineServerLogger` из `lib/src/shared/logger.dart` — правильно.  
Остальные используют `print()` напрямую.

**Почему это плохо:**
- В продакшне нельзя отключить вывод
- Нет уровней (debug/info/warning/error)
- Нет структуры — нельзя парсить логи
- Нет контекста (runId, nodeType) в структурированном виде

**На что влияет:** observability в продакшне, debugging

### Варианты

**Вариант A — Заменить print() на существующий `graphEngineServerLogger`**

`logger.dart` уже есть. Просто заменить все `print(...)` на `graphEngineServerLogger.info(...)` / `.warning(...)` / `.severe(...)`.

**Вариант B — Добавить runId в каждый лог через Logger hierarchy**

Создать `Logger('aq_graph_engine.server.$runId')` для каждого run.  
Позволяет фильтровать логи по runId.

**Вариант C — Оставить print() в WorkflowRunner**

`WorkflowRunner` уже пишет в `_logs` (для хранения в репо) через `_log()`.  
`print()` там — это дублирование для консоли. Можно просто убрать `print()` из `_log()`.

### Решение
**Вариант A для транспортов** (15+6 вызовов).  
**Вариант C для WorkflowRunner** — там `_log()` уже делает `print()` внутри. Убрать `print()` из `_log()` и добавить `graphEngineServerLogger.fine(message)` — тогда логи идут и в репо и в логгер.

### Риски
Минимальные. Чисто механическая замена.

---

## Задача 8: Append-only логи (O(n²) → O(1))

### Проблема
```dart
final List<String> _logs = [];  // накапливается весь run

// После каждого узла:
await _repo.updateRunLog(runId, _logs);  // передаёт ВСЕ логи каждый раз
```

При 100 узлах: 100 + 99 + 98 + ... = ~5000 строк передаётся суммарно вместо 100.

**Почему это плохо:**
- O(n²) I/O — при длинных графах деградация производительности
- Память: весь лог хранится в RAM до конца run
- При crash теряются все логи (не сохранены промежуточно)

**На что влияет:** производительность, надёжность при сбоях

### Варианты

**Вариант A — Добавить `appendLog()` в `IRunRepository`**

```dart
Future<void> appendLog(String runId, String entry);
```

`WorkflowRunner._log()` вызывает `appendLog` напрямую.  
Убрать `_logs: List<String>` из runner'а.

**Проблема:** `IRunRepository` живёт в `aq_schema` — изменение требует отдельной сессии.  
Плюс нужно обновить все реализации (DataLayer, InMemory, Vault).

**Вариант B — Flush логов батчами (не накапливать весь список)**

Хранить только последние N логов в памяти, flush каждые K узлов.  
Не меняет интерфейс репозитория.

**Вариант C — Оставить как есть**

Для текущих графов (10–50 узлов) проблема незначительна.  
Оптимизировать когда появятся реальные графы с 500+ узлами.

### Решение
**Вариант C сейчас.** Причина: Вариант A требует изменения `IRunRepository` в `aq_schema` — это отдельная сессия. Вариант B — преждевременная оптимизация без реальных данных о нагрузке.

**Зафиксировать как tech debt** с условием: реализовать когда появятся графы 200+ узлов или метрики покажут деградацию.

---

## Задача 9: Stateless Runner

### Проблема
`WorkflowRunner` хранит состояние в полях:
```dart
final List<String> _logs = {};
final Set<String> _visitedEdges = {};
final Map<String, Set<String>> _arrivedEdges = {};
final Map<String, int> _nodeIterations = {};
```

Это **state run'а**, не runner'а. При resume создаётся новый `WorkflowRunner` — состояние теряется (кроме того что восстанавливается из снапшота).

**Почему это плохо:**
- `_arrivedEdges` (для `waitAll` join) не персистируется → при resume после suspend join не восстановится
- `_nodeIterations` не персистируется → при resume счётчик циклов сбрасывается
- Нельзя создать несколько runner'ов для одного run

**На что влияет:** корректность resume при сложных графах (parallel + waitAll + suspend)

### Варианты

**Вариант A — Перенести state в `RunSnapshot` (персистируется)**

```dart
// В снапшоте:
{
  'user_context': {...},
  'engine_state': {
    'visited_edges': [...],
    'arrived_edges': {...},    // добавить
    'node_iterations': {...},  // добавить
  }
}
```

Runner восстанавливает всё из снапшота при resume.

**Вариант B — Оставить как есть, задокументировать ограничение**

Текущий suspend/resume работает для простых случаев (линейный граф, один suspend).  
Ограничение: `waitAll` + suspend не поддерживается корректно.

**Вариант C — Полный stateless через event sourcing**

Каждое действие runner'а — событие. Состояние восстанавливается replay событий.  
Это архитектура Temporal. Слишком большое изменение для текущего этапа.

### Решение
**Вариант A** — минимальное изменение с максимальным эффектом.  
Добавить `arrived_edges` и `node_iterations` в `engine_state` снапшота.  
Восстанавливать при resume.

**Важно:** это нужно делать **после Задачи 6** (разбиение runner'а) — иначе сложнее.

---

## Задача S4: `buildDefaultRegistry()` — синглтон

### Проблема
```dart
// В LocalEngineTransport._execute(), строка 86:
final registry = buildDefaultRegistry();  // при каждой конвертации deprecated WorkflowGraph
```

Создаёт новый реестр (регистрирует ~15 типов узлов) при каждом запуске графа с deprecated `WorkflowGraph`.

**Почему это плохо:**
- Лишняя работа при каждом вызове
- Нарушение `dip_ports_rules` — должен быть синглтон

**На что влияет:** производительность (незначительно), архитектурная чистота

### Варианты

**Вариант A — Синглтон через `INodeTypeRegistry.instance` (по правилам DIP)**

Создать интерфейс `INodeTypeRegistry` в `aq_schema`, реализовать в `aq_graph_engine`.  
Инициализировать в точке сборки.

**Проблема:** требует изменения `aq_schema` — отдельная сессия.

**Вариант B — Lazy singleton внутри пакета**

```dart
// В node_type_registry.dart:
NodeTypeRegistry? _defaultRegistry;
NodeTypeRegistry getDefaultRegistry() => _defaultRegistry ??= buildDefaultRegistry();
```

Создаётся один раз, переиспользуется. Без изменения `aq_schema`.

**Вариант C — Убрать конвертацию deprecated WorkflowGraph из транспорта**

Конвертация `WorkflowGraph → TypedWorkflowGraph` не должна быть в транспорте (S5).  
Если убрать её — проблема S4 исчезает сама.

### Решение
**Вариант C** — решает и S4 и S5 одновременно. Конвертация переезжает в `DataLayerGraphRepository` (правильное место — репозиторий знает о форматах хранения). Транспорт получает уже `TypedWorkflowGraph`.

---

## Задача S5: Конвертация `WorkflowGraph → TypedWorkflowGraph` в транспорте

### Проблема
```dart
// LocalEngineTransport._execute():
} else if (graph is WorkflowGraph) {  // deprecated
  final registry = buildDefaultRegistry();
  // ... конвертация 20 строк ...
}
```

Транспорт — это передача данных. Он не должен знать о форматах хранения и конвертации моделей.

**Почему это плохо:**
- Нарушение SRP транспорта
- Транспорт зависит от `NodeTypeRegistry` — лишняя зависимость
- Дублирование: `DataLayerGraphRepository` тоже умеет загружать графы

**На что влияет:** архитектурная чистота, зависимости

### Варианты

**Вариант A — Конвертация в `DataLayerGraphRepository.loadGraph()`**

Репозиторий возвращает только `TypedWorkflowGraph`. Если в БД `WorkflowGraph` — конвертирует при загрузке.  
Транспорт получает уже правильный тип.

**Вариант B — Конвертация в отдельном `GraphConverter` сервисе**

Отдельный класс с одной ответственностью.

**Вариант C — Убрать поддержку deprecated `WorkflowGraph` совсем**

Если все графы уже `TypedWorkflowGraph` — конвертация не нужна.  
Нужно проверить реальные данные.

### Решение
**Вариант A.** `DataLayerGraphRepository` — правильное место. Он уже знает о форматах хранения. Транспорт просто вызывает `loadGraph()` и получает `TypedWorkflowGraph`.

**Важно:** `InMemoryGraphRepository` в примерах уже хранит `TypedWorkflowGraph` — там конвертация не нужна. Значит проблема только в `DataLayerGraphRepository`.

---

## Задача S7: `_RunRepoWithEvents` — отдельный файл

### Проблема
`_RunRepoWithEvents` — 80 строк Decorator паттерна внутри `local_engine_transport.dart`.  
Это отдельная ответственность: "репозиторий который шлёт события в stream".

**Почему это плохо:**
- `local_engine_transport.dart` — 320 строк, два класса
- `_RunRepoWithEvents` нельзя переиспользовать или тестировать изолированно

**На что влияет:** читаемость, тестируемость

### Варианты

**Вариант A — Вынести в `lib/src/server/runners/run_repo_event_bridge.dart`**

Отдельный файл, публичный класс `RunRepoEventBridge`.

**Вариант B — Вынести в `lib/src/transport/run_repo_event_bridge.dart`**

Рядом с транспортом — логически связано (события идут в stream транспорта).

**Вариант C — Оставить как есть**

Работает. Чисто косметика.

### Решение
**Вариант B** — логически правильнее: bridge между репозиторием и stream транспорта.  
Делать **вместе с Задачей 6** (разбиение runner'а) — один проход.

---

## Задача S9: DLQ заглушки в `DataLayerRunRepository`

### Проблема
```dart
Future<List<WorkflowRun>> getDLQJobs(...) async => [];  // заглушка
Future<int> cleanupDLQ(...) async => 0;                 // заглушка
```

**Почему это плохо:**
- По правилам `agent_framework.xml` — незавершённая реализация недопустима
- DLQ не работает в продакшне через DataLayer

**На что влияет:** надёжность в продакшне (failed runs теряются)

### Варианты

**Вариант A — Реализовать через `IDataLayer` query API**

```dart
Future<List<WorkflowRun>> getDLQJobs(...) async {
  return _runs.query(
    filter: VaultQuery.equals('status', 'failed'),
    limit: limit, offset: offset,
  );
}
```

**Проблема:** нужно проверить что `LoggedRepository` поддерживает query с фильтром по статусу.

**Вариант B — Хранить DLQ отдельной коллекцией**

Отдельная коллекция `workflow_runs_dlq`. `moveToDLQ` копирует туда.  
Чище семантически, но требует отдельной схемы.

**Вариант C — Оставить заглушки, задокументировать**

DLQ — это инфраструктурная фича. Пока нет реальных воркеров с retry — не критично.

### Решение
**Вариант A** — если `LoggedRepository` поддерживает query. Нужно проверить `IDataLayer` API перед реализацией. Если не поддерживает — **Вариант C** с явным комментарием `// TODO: requires IDataLayer.query() support`.

---

## Задача A1: `GraphEngine` создаёт транспорты сам

### Проблема
```dart
// GraphEngine конструктор:
_transport = LocalEngineTransport(tools: tools, runRepo: runRepo, ...);
```

По правилам `dip_ports_rules`: только приложение (точка сборки) создаёт реализации.  
`GraphEngine` знает о конкретных классах `LocalEngineTransport`, `HttpEngineTransport`.

**Почему это плохо:**
- Нарушение DIP — зависимость на конкретные классы
- Нельзя подменить транспорт без изменения `GraphEngine`
- Тестирование требует реальных транспортов

**На что влияет:** тестируемость, расширяемость

### Варианты

**Вариант A — Убрать фабричную логику, принимать только `IEngineTransport`**

```dart
GraphEngine({
  required IEngineTransport transport,  // только интерфейс
});
```

Точка сборки (main.dart воркера) создаёт транспорт и передаёт.  
`GraphEngineMode` enum убирается — это ответственность точки сборки.

**Вариант B — Оставить фабрику, но добавить `transport` параметр (уже есть)**

Сейчас уже есть `IEngineTransport? transport` параметр — если передан, используется он.  
Фабричная логика остаётся как convenience.

**Вариант C — Ничего не менять**

Фабрика удобна для пользователей пакета. Нарушение DIP — теоретическое.

### Решение
**Вариант B уже реализован** — `transport` параметр есть. Это достаточно.  
Полный переход на Вариант A — breaking change для пользователей `GraphEngine`.  
**Оставить как есть**, добавить документацию что `transport` — предпочтительный способ.

---

## Задача A4: `ConditionEvaluator` → `aq_schema`

### Проблема
`ConditionEvaluator` — чистая утилита (парсинг выражений типа `"status == 'done'"`).  
Нет зависимостей на движок. Живёт в `aq_graph_engine/lib/src/server/engine/`.

**Почему это плохо:**
- Недоступна другим пакетам (например, `aq_graph_worker` для валидации условий)
- По правилам — переиспользуемые утилиты в `aq_schema`

**На что влияет:** переиспользование

### Варианты

**Вариант A — Перенести в `aq_schema/lib/graph/engine/condition_evaluator.dart`**

Отдельная сессия с `aq_schema` как текущим пакетом.

**Вариант B — Оставить в движке, экспортировать из `server.dart`**

Уже экспортируется из `server.dart`. Доступна через `aq_graph_engine`.

**Вариант C — Ничего не делать**

Пока нет реального потребителя кроме движка.

### Решение
**Вариант B** — уже экспортируется. Перенос в `aq_schema` — когда появится второй потребитель.

---

## Задача A6: Параллельный shared mutable state

### Проблема
```dart
// При EdgeExecutionMode.parallel:
await Future.wait([
  _processNode(n1, ...),  // пишет в _logs, _visitedEdges, _nodeIterations
  _processNode(n2, ...),  // пишет в те же поля одновременно
]);
```

В Dart `List`, `Set`, `Map` — не thread-safe при concurrent `await`.

**Почему это плохо:**
- Потенциальная потеря данных в `_logs` и `_visitedEdges`
- Некорректный счётчик `_nodeIterations`

**На что влияет:** корректность при параллельных ветках

### Варианты

**Вариант A — Использовать `Mutex` или `Lock`**

Обернуть запись в `_logs` и `_visitedEdges` в синхронизацию.  
В Dart нет встроенного mutex — нужна библиотека `synchronized`.

**Вариант B — Изолировать state параллельных веток**

Каждая ветка получает свой `_logs` и `_visitedEdges`.  
После завершения — merge в основной.

**Вариант C — Запретить параллельное выполнение (временно)**

`EdgeExecutionMode.parallel` → выполнять последовательно.  
Документировать как known limitation.

**Вариант D — Принять риск**

В Dart single-threaded event loop. `await` создаёт точки переключения, но не параллельные потоки.  
Реальная гонка возможна только если два `Future` работают одновременно в разных isolates.  
Здесь — один isolate, значит гонки нет. `Future.wait` — concurrent, не parallel.

### Решение
**Вариант D** — в Dart `Future.wait` не создаёт настоящего параллелизма (нет isolates).  
Это concurrent execution в одном event loop. Гонки данных нет.  
Проблема теоретическая, не практическая для Dart.

---

## Итоговый приоритизированный план

| # | Задача | Приоритет | Сложность | Зависимости |
|---|--------|-----------|-----------|-------------|
| 1 | **Задача 6** — Разбиение WorkflowRunner | 🔴 Высокий | Средняя | — |
| 2 | **Задача S7** — `_RunRepoWithEvents` в отдельный файл | 🔴 Высокий | Низкая | Делать вместе с 6 |
| 3 | **Задача 7** — Логирование print() → logger | 🟠 Средний | Низкая | — |
| 4 | **Задача S5+S4** — Конвертация из транспорта в репозиторий | 🟠 Средний | Низкая | — |
| 5 | **Задача 9** — Stateless runner (engine_state в снапшот) | 🟠 Средний | Средняя | После 6 |
| 6 | **Задача S9** — DLQ реализация | 🟡 Низкий | Средняя | Проверить IDataLayer query |
| 7 | **Задача 8** — Append-only логи | 🟡 Низкий | Высокая | Требует aq_schema |
| 8 | **Задача A4** — ConditionEvaluator → aq_schema | 🟡 Низкий | Низкая | Отдельная сессия |
| 9 | **Задача A1** — GraphEngine DIP | ⚪ Отложить | — | Уже частично решено |
| 10 | **Задача A6** — Parallel state | ⚪ Не делать | — | Не проблема в Dart |

---

## Что делаем в этой сессии

**Шаг 1:** Задача 6 + S7 — разбиение WorkflowRunner и вынос RunRepoEventBridge  
**Шаг 2:** Задача 7 — логирование  
**Шаг 3:** Задача S5+S4 — конвертация из транспорта в репозиторий  
**Шаг 4:** Задача 9 — engine_state в снапшот  

После каждого шага: `dart analyze` + `dart test` + сценарии.
