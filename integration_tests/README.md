# Integration Tests - Graph Engine

## Описание

Полный набор интеграционных тестов для Graph Engine, покрывающих все жизненные циклы графов.

## Архитектура тестов

### Принцип "Тонкий клиент"

Тесты следуют архитектурному принципу "Тонкий клиент":

```dart
// ✅ ПРАВИЛЬНО - через репозитории
await Vault.connect('http://localhost:8765', tenantId: 'test');
final repo = Vault.instance.versioned<WorkflowGraph>(...);
await repo.createEntity(graph);

// ❌ НЕПРАВИЛЬНО - прямые HTTP запросы
final response = await http.post('http://localhost:8765/vault/rpc', ...);
```

### Две линии бизнес-логики

#### Линия 1: Управление проектами и графами
- Создание проектов через `DirectRepository`
- Создание графов через `VersionedRepository`
- Чтение/обновление через репозитории

#### Линия 2: Выполнение графов
- Запуск через `GraphEngineClient`
- Обработка событий через `Stream<GraphRunEvent>`
- Проверка результатов через `LoggedRepository`

## Структура тестов

```
test/integration/
├── README.md                           # Этот файл
├── test_helpers.dart                   # Вспомогательные функции
├── workflow_lifecycle_test.dart        # Жизненный цикл WorkflowGraph
├── instruction_lifecycle_test.dart     # Жизненный цикл InstructionGraph
├── prompt_lifecycle_test.dart          # Жизненный цикл PromptGraph
├── suspend_resume_test.dart            # Suspend/Resume механизм
├── parallel_execution_test.dart        # Параллельное выполнение
├── error_handling_test.dart            # Обработка ошибок
└── composite_nodes_test.dart           # SubGraph и RunInstruction
```

## Требования

### Запущенные стэки

```bash
# Проверить статус
docker ps | grep -E "(aq_studio_data_service|aq_graph_engine)"

# Должны быть запущены:
# - aq_studio_data_service (порт 8765)
# - aq_graph_engine (порт 8081)
```

### Переменные окружения

```bash
export DATA_SERVICE_URL=http://localhost:8765
export GRAPH_ENGINE_URL=http://localhost:8081
```

## Запуск тестов

```bash
# Все интеграционные тесты
dart test test/integration/

# Конкретный файл
dart test test/integration/workflow_lifecycle_test.dart

# С подробным выводом
dart test test/integration/ --reporter=expanded
```

## Жизненные циклы

### WorkflowGraph Lifecycle

```
1. Создание проекта → DirectRepository
2. Создание WorkflowGraph → VersionedRepository
3. Запуск через GraphEngine → HTTP API
4. Обработка событий → Stream<GraphRunEvent>
5. Проверка результата → LoggedRepository
```

**Статусы:** `pending` → `running` → `completed`/`failed`

**Suspend/Resume:** `running` → `suspended` → `running` → `completed`

### InstructionGraph Lifecycle

```
1. Создание InstructionGraph → VersionedRepository
2. Вызов из WorkflowGraph → RunInstructionNode
3. Выполнение с контрактом → InstructionRunner
4. Возврат результата → output_mapping
```

**Особенности:**
- Контракт (inputs/outputs)
- Циклы разрешены (maxSteps=20)
- Изолированный контекст

### PromptGraph Lifecycle

```
1. Создание PromptGraph → VersionedRepository
2. Компиляция промпта → PromptRunner
3. Подстановка переменных → {{variable}}
4. Использование в LlmActionNode
```

## Покрытие тестами

### WorkflowGraph узлы (10 типов)

- [x] `llmAction` - запрос к LLM
- [x] `fileRead` - чтение файла
- [x] `fileWrite` - запись файла
- [x] `gitCommit` - git commit
- [x] `userInput` - запрос ввода (suspend)
- [x] `manualReview` - ручная проверка (suspend)
- [x] `fileUpload` - загрузка файла (suspend)
- [x] `coCreationChat` - интерактивный чат (suspend)
- [x] `subGraph` - вложенный Workflow
- [x] `runInstruction` - вызов Instruction

### InstructionGraph узлы (4 типа)

- [x] `toolCall` - вызов Tool
- [x] `llmQuery` - запрос к LLM
- [x] `condition` - условие
- [x] `transform` - преобразование данных

### PromptGraph узлы (3 типа)

- [x] `textBlock` - текстовый блок
- [x] `variableInsert` - вставка переменной
- [x] `conditionalBlock` - условный блок

### Сценарии

- [x] Простое выполнение (1 узел)
- [x] Последовательное выполнение (цепочка узлов)
- [x] Параллельное выполнение (branches)
- [x] Suspend/Resume (интерактивные узлы)
- [x] Композиция (SubGraph, RunInstruction)
- [x] Обработка ошибок (onError edges)
- [x] Циклы в InstructionGraph
- [x] Контракт валидация

## Примеры

### Простой тест

```dart
test('Создание и запуск простого WorkflowGraph', () async {
  // 1. Подключиться к Data Service
  await Vault.connect('http://localhost:8765', tenantId: 'test');

  // 2. Создать проект
  final projectRepo = Vault.instance.direct<AqStudioProject>(
    collection: AqStudioProject.kCollection,
    fromMap: AqStudioProject.fromMap,
  );
  final project = AqStudioProject(
    id: uuid(),
    tenantId: 'test',
    name: 'Test Project',
  );
  await projectRepo.save(project);

  // 3. Создать граф
  final workflowRepo = Vault.instance.versioned<WorkflowGraph>(
    collection: WorkflowGraph.kCollection,
    fromMap: WorkflowGraph.fromMap,
  );
  final workflow = WorkflowGraph(
    id: uuid(),
    tenantId: 'test',
    ownerId: project.id,
    name: 'Simple Workflow',
    nodes: {
      'node1': WorkflowNode(
        id: 'node1',
        type: WorkflowNodeType.fileRead,
        config: {
          'file_path': '/tmp/test.txt',
          'output_var': 'content',
        },
      ),
    },
    edges: {},
  );
  await workflowRepo.createEntity(workflow);

  // 4. Запустить через движок
  final client = GraphEngineClient('http://localhost:8081');
  final request = GraphRunRequest(
    runId: uuid(),
    projectId: project.id,
    blueprintId: workflow.id,
    projectPath: '/tmp',
  );

  final events = client.run(request);

  // 5. Проверить события
  final eventList = await events.toList();
  expect(eventList.any((e) => e.type == GraphRunEventType.completed), true);

  // 6. Проверить результат в БД
  final runRepo = Vault.instance.logged<WorkflowRun>(
    collection: 'workflow_runs',
    fromMap: WorkflowRun.fromMap,
  );
  final run = await runRepo.findById(request.runId);
  expect(run.status, 'completed');
});
```

## Troubleshooting

### Стэки не запущены

```bash
cd deploys/aq_studio_dl_stack && docker-compose up -d
cd deploys/aq_graph_engine_stack && docker-compose up -d
```

### Порты заняты

Проверить `.env` файлы в стэках и изменить порты если нужно.

### Тесты падают с timeout

Увеличить timeout в тестах:

```dart
test('...', () async {
  // ...
}, timeout: Timeout(Duration(minutes: 5)));
```

### База данных не очищается

Тесты используют `tenantId: 'test'` для изоляции. Для полной очистки:

```bash
docker exec -it aq_studio_postgres psql -U aq -d aq_studio -c "DELETE FROM workflow_graphs WHERE tenant_id = 'test';"
```

## Детальное покрытие по файлам

### workflow_lifecycle_test.dart (12 тестов)
- ✅ Простое выполнение: fileRead, fileWrite, llmAction
- ✅ Цепочки узлов: fileRead → fileWrite, fileRead → llmAction → fileWrite
- ✅ Проверка событий: statusChanged, log, completed
- ✅ Проверка логов выполнения
- ✅ Обработка ошибок: несуществующий файл, audit trail

### instruction_lifecycle_test.dart (10 тестов)
- ✅ Простой вызов через RunInstructionNode
- ✅ Цепочка transform узлов
- ✅ Валидация контракта: обязательные параметры, типы
- ✅ Условная логика: condition узел с ветвлением
- ✅ Циклы: loop с ограничением maxSteps=20
- ✅ Защита от бесконечного цикла
- ✅ Изоляция контекста между инструкциями

### prompt_lifecycle_test.dart (8 тестов)
- ✅ Простой текстовый промпт
- ✅ Промпт с подстановкой переменных
- ✅ Условные блоки в промптах
- ✅ Многоблочный промпт с несколькими переменными
- ✅ Обработка отсутствующих переменных
- ✅ Интеграция: fileRead → llmAction(prompt) → fileWrite

### suspend_resume_test.dart (11 тестов)
- ✅ UserInput: приостановка и возобновление
- ✅ Множественные приостановки в одном графе
- ✅ ManualReview: приостановка на проверке
- ✅ FileUpload: приостановка на загрузке файла
- ✅ CoCreationChat: интерактивный чат
- ✅ Сохранение контекста между suspend и resume
- ✅ Audit trail при suspend/resume

### parallel_execution_test.dart (9 тестов)
- ✅ Две параллельные ветки
- ✅ Три параллельные ветки
- ✅ Изоляция переменных между ветками
- ✅ Ошибка в одной ветке
- ✅ OnError edge для параллельных веток
- ✅ Параллельные ветки с последующим слиянием
- ✅ Вложенные параллельные ветки

### composite_nodes_test.dart (8 тестов)
- ✅ Простой SubGraph с одним узлом
- ✅ SubGraph с output mapping
- ✅ Вложенные SubGraph (3 уровня)
- ✅ RunInstruction с transform
- ✅ RunInstruction с условной логикой
- ✅ SubGraph содержащий RunInstruction
- ✅ Сложная композиция: Workflow → SubGraph → Instruction → SubGraph

### error_handling_test.dart (14 тестов)
- ✅ Ошибка чтения несуществующего файла
- ✅ Ошибка записи в недоступную директорию
- ✅ Отсутствие обязательной переменной
- ✅ OnError edge перенаправляет выполнение
- ✅ Цепочка OnError edges
- ✅ Валидация контракта InstructionGraph
- ✅ Валидация типов в контракте
- ✅ Ошибка внутри SubGraph
- ✅ Обработка ошибки SubGraph через OnError
- ✅ Ошибка в RunInstruction узле
- ✅ Retry механизм через OnError edge

## Метрики

- **Общее количество файлов:** 8 (включая README и helpers)
- **Общее количество тестов:** 72
- **Покрытие узлов:** 17/17 (100%)
  - WorkflowGraph: 10/10 узлов
  - InstructionGraph: 4/4 узла
  - PromptGraph: 3/3 узла
- **Покрытие сценариев:** 8/8 (100%)
- **Время выполнения:** ~10-15 минут (все тесты)

## Статус реализации

### ✅ Полностью покрыто тестами
- Жизненный цикл всех трёх типов графов
- Все типы узлов (17 штук)
- Suspend/Resume механизм
- Параллельное выполнение
- Композитные узлы (SubGraph, RunInstruction)
- Обработка ошибок и OnError edges
- Валидация контрактов
- Audit trail

### 🔄 Требует реализации в движке
Тесты написаны под ожидаемое поведение. При запуске тестов выявятся недостающие части реализации:
- Некоторые типы узлов могут быть не реализованы
- Механизм suspend/resume может требовать доработки
- OnError edges могут требовать реализации
- Валидация контрактов может быть неполной

### 📋 Следующие шаги
1. Запустить тесты и выявить недостающую функциональность
2. Реализовать недостающие узлы и механизмы
3. Добавить performance тесты (большие графы, много узлов)
4. Добавить stress тесты (concurrent execution, memory leaks)
5. Добавить тесты для edge cases
