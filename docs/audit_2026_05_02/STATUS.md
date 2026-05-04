# Статус аудита — aq_graph_engine

**Аудит проведён:** 2026-05-02  
**Последнее обновление:** 2026-05-02

---

## Итоговый статус

| ID | Проблема | Приоритет | Статус | Решение |
|----|----------|-----------|--------|---------|
| BUG-1 | appendLog fire-and-forget | CRITICAL | ✅ Решено | `.ignore()` убран; `appendLog` — no-op дефолт в abstract class |
| BUG-2 | Дублирование логов при suspend | CRITICAL | ✅ Решено | Убран параметр `logs` из `suspendRun` |
| BUG-3 | projectPath теряется при resume | CRITICAL | ⚠️ TD-1 | Временный костыль через `graphSnapshot['_projectPath']` |
| BUG-4 | Двойной write на каждый узел | HIGH | ✅ Решено | Guard в `updateRunLog`: `if (logs.isEmpty && status == null) return` |
| ISSUE-1 | tryAcquireLock заглушка | HIGH | ❌ TD-2 | Single-worker only до реализации advisory locks |
| ISSUE-2 | GraphTraversal делает 5 I/O на узел | HIGH | ✅ Решено | `IRunRepository` убран из `GraphTraversal`, заменён на `onNodeExecuted` callback |
| ISSUE-3 | appendLog — read-modify-write | HIGH | ✅ Решено | Следствие BUG-1: `appendLog` убран из hot path |
| ISSUE-4 | InstructionRunner toJson/fromJson на каждом узле | MEDIUM | 🔄 В процессе | `TypedInstructionGraph` создан, миграция `InstructionRunner` — текущая сессия |
| ISSUE-5 | _short() дублируется | LOW | ✅ Решено | Вынесен в `shared/logger.dart` как `shortId()` |
| ISSUE-6 | cleanupDLQ — soft delete вводит в заблуждение | MEDIUM | ❌ Открыто | Нужно обновить документацию метода |
| ARCH-1 | IRunStateManager + IRunRepository дублируют ответственность | HIGH | ✅ Решено | Чёткое разграничение задокументировано в интерфейсах и `agent_framework.xml` |
| ARCH-2 | GraphTraversal знает о репозитории | HIGH | ✅ Решено | Решено вместе с ISSUE-2 |
| ARCH-3 | Нет тестов с реальным DataLayerRunRepository | HIGH | ✅ Решено | Добавлен `test/integration/data_layer_run_repository_test.dart` |

---

## Технический долг

| ID | Описание | Условие удаления |
|----|----------|-----------------|
| TD-1 | `projectPath` в `graphSnapshot` | После добавления поля `projectPath` в `WorkflowRun` (`aq_schema`) |
| TD-2 | `tryAcquireLock → true` | После реализации Postgres advisory locks в `aq_data_layer` |
| TD-3 | `appendLog` как no-op дефолт | После реализации отдельной таблицы логов в `aq_data_layer` |

---

## Edge cases без покрытия

- Два параллельных узла бросают `SuspendExecutionException` одновременно
- Crash между `appendLog` и `updateRunLog` — run завис в статусе `running`
- `cleanupDLQ` при активном run со статусом `failed`

---

## Что ещё не сделано (из плана production-готовности)

- `HttpEngineTransport` — удалённое выполнение (клиент → сервер) не реализован
- Метрики и observability
- Rate limiting
- Горизонтальное масштабирование (блокирует TD-2)
