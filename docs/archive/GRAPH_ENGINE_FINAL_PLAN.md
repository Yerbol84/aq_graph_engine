# Graph Engine - Финальный план реализации

**Дата:** 2026-04-08
**Статус:** READY TO IMPLEMENT

## ЦЕЛЬ

Превратить enum-based узлы графов в типобезопасную иерархию классов с полиморфизмом.

---

## ПРАВИЛО РАЗМЕЩЕНИЯ

### В aq_schema (корневой пакет):
- ✅ Модели графов (WorkflowGraph, InstructionGraph, PromptGraph)
- ✅ Узлы графов (все 17 классов)
- ✅ Базовые интерфейсы (IHand, RunContext, ToolRegistry)
- ✅ Всё что используется в разных местах платформы

### В aq_graph_engine (внутри пакета):
- ✅ Runners (выполнение графов)
- ✅ Фабрики (создание узлов из JSON)
- ✅ Транспорт (клиент-сервер)
- ✅ Только внутренняя логика движка

---

## СТРУКТУРА ПАПОК

### aq_schema (домены)
```
pkgs/aq_schema/lib/graph/
├── core/
│   └── graph_def.dart
├── graphs/
│   ├── workflow_graph.dart
│   ├── instruction_graph.dart
│   └── prompt_graph.dart
├── engine/
│   ├── i_hand.dart
│   ├── run_context.dart
│   ├── tool_registry.dart
│   └── workflow_run.dart
└── nodes/                    # ← ВСЕ УЗЛЫ ЗДЕСЬ!
    ├── base/
    │   ├── i_workflow_node.dart
    │   ├── i_instruction_node.dart
    │   ├── i_prompt_node.dart
    │   ├── automatic_node.dart
    │   ├── interactive_node.dart
    │   └── composite_node.dart
    ├── workflow/             # ← Узлы для WorkflowGraph
    │   ├── automatic/
    │   │   ├── llm_action_node.dart
    │   │   ├── file_read_node.dart
    │   │   ├── file_write_node.dart
    │   │   └── git_commit_node.dart
    │   ├── interactive/
    │   │   ├── user_input_node.dart
    │   │   ├── manual_review_node.dart
    │   │   ├── file_upload_node.dart
    │   │   └── co_creation_chat_node.dart
    │   └── composite/
    │       ├── subgraph_node.dart
    │       └── run_instruction_node.dart
    ├── instruction/          # ← Узлы для InstructionGraph
    │   ├── system_action_instruction_node.dart
    │   ├── validation_check_instruction_node.dart
    │   ├── step_description_instruction_node.dart
    │   └── user_input_request_instruction_node.dart
    └── prompt/               # ← Узлы для PromptGraph
        ├── text_block_prompt_node.dart
        ├── variable_prompt_node.dart
        └── file_context_prompt_node.dart
```

### aq_graph_engine (внутренняя логика)
```
pkgs/aq_graph_engine/lib/src/
├── engine/
│   └── graph_engine.dart
├── runners/
│   ├── polymorphic_workflow_runner.dart
│   ├── instruction_runner.dart
│   └── prompt_runner.dart
├── factories/                # ← Фабрики внутри движка
│   ├── workflow_node_factory.dart
│   ├── instruction_node_factory.dart
│   └── prompt_node_factory.dart
├── interfaces/
│   ├── i_graph_repository.dart
│   └── i_run_repository.dart
├── transport/
│   └── local_engine_transport.dart
└── client/
    ├── graph_engine_client.dart
    └── models.dart
```

---

## ИЕРАРХИЯ УЗЛОВ

### WorkflowGraph узлы
```
IWorkflowNode (интерфейс)
├── AutomaticNode (базовый)
│   ├── LlmActionNode
│   ├── FileReadNode
│   ├── FileWriteNode
│   └── GitCommitNode
├── InteractiveNode (базовый)
│   ├── UserInputNode
│   ├── ManualReviewNode
│   ├── FileUploadNode
│   └── CoCreationChatNode
└── CompositeNode (базовый)
    ├── SubGraphNode
    └── RunInstructionNode
```

### InstructionGraph узлы
```
IInstructionNode (интерфейс)
├── SystemActionInstructionNode
├── ValidationCheckInstructionNode
├── StepDescriptionInstructionNode
└── UserInputRequestInstructionNode
```

### PromptGraph узлы
```
IPromptNode (интерфейс)
├── TextBlockPromptNode
├── VariablePromptNode
└── FileContextPromptNode
```

---

## PHASE 1: Создать иерархию узлов WorkflowGraph в aq_schema

**Локация:** `pkgs/aq_schema/lib/graph/nodes/workflow/`

**Задачи:**
- [ ] Создать базовые классы в `nodes/base/`
  - [ ] `i_workflow_node.dart`
  - [ ] `automatic_node.dart`
  - [ ] `interactive_node.dart`
  - [ ] `composite_node.dart`
- [ ] Создать 4 автоматических узла в `nodes/workflow/automatic/`
  - [ ] `llm_action_node.dart`
  - [ ] `file_read_node.dart`
  - [ ] `file_write_node.dart`
  - [ ] `git_commit_node.dart`
- [ ] Создать 4 интерактивных узла в `nodes/workflow/interactive/`
  - [ ] `user_input_node.dart`
  - [ ] `manual_review_node.dart`
  - [ ] `file_upload_node.dart`
  - [ ] `co_creation_chat_node.dart`
- [ ] Создать 2 композитных узла в `nodes/workflow/composite/`
  - [ ] `subgraph_node.dart`
  - [ ] `run_instruction_node.dart`
- [ ] **УДАЛИТЬ** `WorkflowNodeType` enum из `workflow_graph.dart`
- [ ] Обновить `WorkflowGraph.nodes` → `Map<String, IWorkflowNode>`
- [ ] Обновить экспорты в `aq_schema.dart`

---

## PHASE 2: Создать иерархию узлов InstructionGraph в aq_schema

**Локация:** `pkgs/aq_schema/lib/graph/nodes/instruction/`

**Задачи:**
- [ ] Создать `i_instruction_node.dart` в `nodes/base/`
- [ ] Создать 4 класса узлов в `nodes/instruction/`
  - [ ] `system_action_instruction_node.dart`
  - [ ] `validation_check_instruction_node.dart`
  - [ ] `step_description_instruction_node.dart`
  - [ ] `user_input_request_instruction_node.dart`
- [ ] **УДАЛИТЬ** `InstructionNodeType` enum из `instruction_graph.dart`
- [ ] Обновить `InstructionGraph.nodes` → `Map<String, IInstructionNode>`
- [ ] Обновить экспорты в `aq_schema.dart`

---

## PHASE 3: Создать иерархию узлов PromptGraph в aq_schema

**Локация:** `pkgs/aq_schema/lib/graph/nodes/prompt/`

**Задачи:**
- [ ] Создать `i_prompt_node.dart` в `nodes/base/`
- [ ] Создать 3 класса узлов в `nodes/prompt/`
  - [ ] `text_block_prompt_node.dart`
  - [ ] `variable_prompt_node.dart`
  - [ ] `file_context_prompt_node.dart`
- [ ] **УДАЛИТЬ** `PromptNodeType` enum из `prompt_graph.dart`
- [ ] Обновить `PromptGraph.nodes` → `Map<String, IPromptNode>`
- [ ] Обновить экспорты в `aq_schema.dart`

---

## PHASE 4: Создать фабрики узлов в aq_graph_engine

**Локация:** `pkgs/aq_graph_engine/lib/src/factories/`

**Задачи:**
- [ ] Создать `workflow_node_factory.dart`
  - fromJson создаёт правильный класс по полю `type`
- [ ] Создать `instruction_node_factory.dart`
- [ ] Создать `prompt_node_factory.dart`
- [ ] Обновить `fromMap()` в графах - используют фабрики
- [ ] Обновить экспорты в `aq_graph_engine.dart`

---

## PHASE 5: Обновить Runners (полиморфизм)

**Локация:** `pkgs/aq_graph_engine/lib/src/runners/`

**Задачи:**
- [ ] `PolymorphicWorkflowRunner`
  - Убрать все `switch (node.type)`
  - Использовать `await node.execute(context, tools, graphRepo)`
- [ ] `InstructionRunner`
  - Убрать все `switch (node.type)`
  - Использовать `await node.execute(context, tools, graphRepo)`
- [ ] `PromptRunner`
  - Убрать все `switch (node.type)`
  - Использовать `node.compile(context)` или аналог

---

## PHASE 6: Тесты

**Задачи:**
- [ ] Unit тесты для каждого узла (17 узлов)
  - Проверка fromJson/toJson
  - Проверка execute()
  - Проверка copyWith()
- [ ] Unit тесты для фабрик
  - Правильное создание узлов по type
  - Обработка неизвестных типов
- [ ] Integration тесты
  - Полный Workflow с разными узлами
  - Полная Instruction
  - Suspend/resume для интерактивных узлов
  - Изоляция по проектам

---

## PHASE 7: Документация

**Задачи:**
- [ ] Обновить `pkgs/aq_graph_engine/README.md`
  - Новая архитектура
  - Иерархия узлов
  - Примеры использования
- [ ] Создать диаграммы архитектуры
- [ ] Создать примеры в `pkgs/aq_graph_engine/example/`

---

## КРИТЕРИИ ГОТОВНОСТИ

- [ ] Все enum типов узлов УДАЛЕНЫ
- [ ] Все узлы в `aq_schema/lib/graph/nodes/`
- [ ] Фабрики в `aq_graph_engine/lib/src/factories/`
- [ ] Runners используют полиморфизм (нет switch)
- [ ] Тесты зелёные
- [ ] Документация обновлена

---

## КЛЮЧЕВЫЕ ПРИНЦИПЫ

1. **Типобезопасность:** Тип узла = класс узла (не enum!)
2. **Полиморфизм:** `node.execute()` вместо `switch (node.type)`
3. **Изоляция:** Узлы в aq_schema (домены), фабрики в aq_graph_engine (логика)
4. **Проекты:** Все графы принадлежат проекту (`graph.ownerId == projectId`)
5. **Контексты:** Изолированные контексты для Instruction и SubGraph

---

## ОЦЕНКА ВРЕМЕНИ

- **Phase 1:** 2 дня (10 узлов WorkflowGraph)
- **Phase 2:** 1 день (4 узла InstructionGraph)
- **Phase 3:** 0.5 дня (3 узла PromptGraph)
- **Phase 4:** 0.5 дня (3 фабрики)
- **Phase 5:** 1 день (обновить Runners)
- **Phase 6:** 1 день (тесты)
- **Phase 7:** 0.5 дня (документация)

**Итого:** 6.5 дней

---

**Последнее обновление:** 2026-04-08
**Автор:** Voland + Claude
**Статус:** УТВЕРЖДЁН, НАЧИНАЕМ РАБОТУ
