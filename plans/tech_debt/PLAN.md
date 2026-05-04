# Tech Debt Plan — aq_graph_engine

Статус: 📋 ПЛАН  
Дата: 2026-05-04

---

## TD-1: Убрать projectPath хак из graphSnapshot

**Приоритет:** HIGH  
**Риск:** Низкий (аддитивное изменение)  
**Зависимость:** aq_schema (WorkflowRun)

**Проблема:**  
`projectPath` сохраняется как `graphSnapshot['_projectPath']` — хак вместо поля модели.
При resume читается обратно через `graphSnapshot['_projectPath'] as String? ?? ''`.
Если структура `graphSnapshot` изменится — сломается тихо в runtime.

**Файлы:**
- `aq_schema/lib/graph/engine/workflow_run.dart` — добавить поле `projectPath`
- `aq_graph_engine/lib/src/transport/local_engine_transport.dart` — убрать хак, использовать поле

**Шаги:**
1. Добавить `final String projectPath` в `WorkflowRun` (aq_schema)
2. Обновить `toMap()` / `fromMap()` через `WorkflowRun.keys`
3. В `local_engine_transport.dart` убрать `'_projectPath'` из `graphSnapshot`
4. При resume читать `existingRun.projectPath` напрямую
5. Запустить тесты

---

## TD-2: Удалить deprecated WorkflowGraph v1

**Приоритет:** MEDIUM  
**Риск:** Средний — нужно проверить DataLayerGraphRepository  
**Зависимость:** TD-1 не требуется

**Проблема:**  
`WorkflowGraph` (enum-based, v1) помечен `@Deprecated` но живёт в `aq_schema`.
`WorkflowNodeFactory` тоже deprecated.
`DataLayerGraphRepository` конвертирует v1 → v2 при каждой загрузке — лишняя логика.

**Файлы:**
- `aq_schema/lib/graph/graphs/workflow_graph.dart` — удалить `WorkflowGraph`, `WorkflowNode`, `WorkflowNodeType`, `WorkflowEdge`
- `aq_graph_engine/lib/src/server/factories/workflow_node_factory.dart` — удалить файл
- `aq_graph_engine/lib/src/server/storage/data_layer_graph_repository.dart` — убрать legacy конвертацию
- `aq_graph_engine/lib/server.dart` — убрать экспорт `workflow_node_factory.dart` если есть

**Шаги:**
1. Проверить все `import workflow_graph.dart` и `WorkflowGraph` usage
2. Убедиться что `DataLayerGraphRepository` работает без legacy ветки
3. Удалить файлы
4. Запустить тесты — убедиться что ничего не сломалось

---

## TD-3: Восстановить GraphValidator

**Приоритет:** HIGH  
**Риск:** Низкий  
**Зависимость:** нет

**Проблема:**  
`GraphValidator` полностью закомментирован. Граф с битыми рёбрами, несуществующими
узлами, неправильными контрактами запускается и падает в runtime вместо отклонения при загрузке.

**Файлы:**
- `aq_graph_engine/lib/src/server/validation/graph_validator.dart` — раскомментировать
- `aq_graph_engine/lib/src/transport/local_engine_transport.dart` — вызвать валидацию перед запуском

**Шаги:**
1. Раскомментировать и починить `GraphValidator`
2. Добавить вызов в `LocalEngineTransport._execute()` после загрузки графа
3. При ошибке валидации — `GraphRunEvent.error(...)` вместо runtime crash
4. Написать тесты на невалидные графы

---

## TD-4: Distributed lock для multi-worker

**Приоритет:** LOW (нужен только для production multi-worker)  
**Риск:** Высокий — требует поддержки в IDataLayer  
**Зависимость:** data layer (не наша область сейчас)

**Проблема:**  
`tryAcquireLock` / `releaseLock` в `DataLayerRunRepository` всегда возвращают `true`.
При N воркерах один run может выполняться параллельно — race condition.

**Файлы:**
- `aq_graph_engine/lib/src/server/storage/data_layer_run_repository.dart`

**Шаги:**
1. Дождаться поддержки pessimistic lock в IDataLayer (data layer team)
2. Реализовать через `IDataLayer.instance.lock(runId, ttl)`
3. Добавить интеграционный тест с двумя воркерами

**Статус:** ЗАБЛОКИРОВАН — ждём data layer

---

## TD-5: Реализовать fileContext в PromptRunner

**Приоритет:** LOW  
**Риск:** Низкий  
**Зависимость:** TD-6 (IToolEngineProtocol) — fileContext читает файл через сервис

**Проблема:**  
`PromptNodeType.fileContext` не реализован — `// TODO: Реализовать когда понадобится`.
Промпты с контекстом файлов не работают.

**Файлы:**
- `aq_graph_engine/lib/src/server/runners/prompt_runner.dart`
- `aq_schema/lib/graph/nodes/prompt/` — возможно нужен новый узел

**Шаги:**
1. Реализовать после TD-6 (через `IToolEngineProtocol.instance.callTool('fs_read', ...)`)
2. Написать тест

---

## Отчёт об исполнении

| ID | Задача | Статус | Дата |
|----|--------|--------|------|
| TD-1 | projectPath хак | ⏳ | — |
| TD-2 | Удалить deprecated WorkflowGraph v1 | ⏳ | — |
| TD-3 | Восстановить GraphValidator | ⏳ | — |
| TD-4 | Distributed lock | 🔒 заблокирован | — |
| TD-5 | fileContext в PromptRunner | ⏳ | — |
