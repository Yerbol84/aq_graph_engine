# 🎯 АРХИТЕКТУРНЫЙ ПЛАН ИСПРАВЛЕНИЯ ТЕСТОВ GRAPH ENGINE

## 📋 EXECUTIVE SUMMARY

**Проблема:** Тесты создают иллюзию покрытия, но не проверяют критическую функциональность. Особенно проблема с waitAll - тест заявляет одно, проверяет другое, а в комментарии написано третье.

**Решение:** Трёхуровневая стратегия тестирования:
1. **Unit тесты** - изолированная проверка логики движка
2. **Integration тесты** - проверка работы с реальными узлами и хранилищем
3. **E2E тесты в Docker** - имитация production окружения

---

## 🏗️ АРХИТЕКТУРНАЯ СТРАТЕГИЯ

### Принцип 1: Тесты должны проверять ЧТО заявляют

**Текущая проблема:**
```dart
test('узел D выполняется ОДИН раз', () {
  // Комментарий: выполнится ДВАЖДЫ
  // Проверка: File.exists() ✅
  // ❌ НЕ проверяет ни "один раз", ни "дважды"
});
```

**Решение:**
- Название теста = проверяемое поведение
- Если поведение не реализовано → `skip: true` с TODO
- Если проверяем текущее поведение → название должно соответствовать

### Принцип 2: Тестируем не только результат, но и процесс

**Что проверять:**
1. **Результат** - файлы созданы, данные корректны
2. **Процесс** - порядок выполнения, количество вызовов
3. **Логи** - правильные сообщения в нужный момент
4. **События** - последовательность GraphRunEvent
5. **Состояние БД** - Run записан корректно

### Принцип 3: Изоляция уровней тестирования

```
Unit Tests (in-memory, моки)
    ↓
Integration Tests (локальный PostgreSQL)
    ↓
E2E Tests (Docker Compose, полный стек)
```

---

## 📊 ТРЁХУРОВНЕВАЯ СТРАТЕГИЯ

### Уровень 1: Unit Tests (быстрые, изолированные)

**Цель:** Проверить логику движка без внешних зависимостей

**Что тестируем:**
- `_arrivedEdges` Map корректно заполняется
- `waitAll` логика подсчёта входящих рёбер
- `firstCome` пропускает узел сразу
- `exclusive` блокирует альтернативные рёбра
- Обработка ошибок в узлах
- Генерация событий

**Инструменты:**
- In-memory хранилище
- Mock узлы с счётчиками выполнений
- Синхронное выполнение для детерминизма

**Пример:**
```dart
test('waitAll: узел ждёт все входящие рёбра', () {
  final engine = PolymorphicGraphEngine(...);
  final executionCounter = <String, int>{};
  
  // Mock узел с счётчиком
  final nodeD = MockNode(
    id: 'D',
    joinStrategy: JoinStrategy.waitAll,
    onExecute: () => executionCounter['D'] = (executionCounter['D'] ?? 0) + 1,
  );
  
  // Diamond: A -> B,C -> D
  final graph = createDiamondGraph(nodeD: nodeD);
  
  await engine.run(graph);
  
  // Проверка: D выполнился ОДИН раз
  expect(executionCounter['D'], 1);
  
  // Проверка логов
  expect(engine.logs, contains('waiting for 1 more edge'));
  expect(engine.logs, contains('All 2 edges arrived'));
});
```

### Уровень 2: Integration Tests (средние, с БД)

**Цель:** Проверить работу с реальными узлами и PostgreSQL

**Что тестируем:**
- Реальные узлы (FileWrite, FileRead, etc)
- Сохранение Run в БД
- Логи в БД
- Контекст между узлами
- Параллельное выполнение

**Инструменты:**
- Локальный PostgreSQL (testcontainers или docker-compose)
- Реальные узлы
- Временные файлы для FileWrite/FileRead

**Требования:**
- БД должна быть изолирована (отдельная схема на тест)
- Cleanup после каждого теста
- Проверка состояния БД после выполнения

**Пример:**
```dart
test('Diamond pattern: FileWrite выполняется дважды (firstCome)', () async {
  final project = await createTestProject();
  final tempDir = Directory.systemTemp.createTempSync();
  
  // Граф: A -> B,C -> D (все FileWrite)
  final workflow = createDiamondWorkflow(
    nodeD: FileWriteNode(joinStrategy: JoinStrategy.firstCome),
  );
  
  final client = GraphEngineClient(baseUrl: testUrl);
  final request = GraphRunRequest(runId: uuid(), ...);
  
  await expectCompleted(client.run(request));
  
  // Проверка 1: Файл создан
  expect(await File('${tempDir.path}/D.txt').exists(), true);
  
  // Проверка 2: Узел D выполнился ДВАЖДЫ
  final run = await runRepo.get(request.runId);
  final logs = jsonDecode(run.logsJson);
  final nodeDExecutions = logs.where((log) => 
    log.contains('Executing: fileWrite [D]')).length;
  expect(nodeDExecutions, 2, reason: 'firstCome allows multiple executions');
  
  // Проверка 3: Оба ребра прошли
  expect(logs, contains('Edge [B->D] triggered'));
  expect(logs, contains('Edge [C->D] triggered'));
});
```

### Уровень 3: E2E Tests в Docker (медленные, полный стек)

**Цель:** Имитация production окружения

**Что тестируем:**
- Полный стек в Docker Compose
- Graph Worker в отдельном контейнере
- PostgreSQL в контейнере
- Сетевое взаимодействие
- Отказоустойчивость (restart контейнеров)

**Инструменты:**
- Docker Compose с полным стеком
- Testcontainers для управления контейнерами
- HTTP клиент для API

**Структура:**
```yaml
# docker-compose.test.yml
services:
  postgres:
    image: postgres:15
    environment:
      POSTGRES_DB: aq_test
      
  graph_worker:
    build: ./server_apps/aq_graph_worker
    depends_on:
      - postgres
    environment:
      DATABASE_URL: postgres://postgres@postgres/aq_test
      
  test_runner:
    build: ./test/e2e
    depends_on:
      - graph_worker
```

**Пример теста:**
```dart
test('E2E: Diamond pattern через HTTP API', () async {
  // 1. Запустить Docker Compose
  await DockerCompose.up('docker-compose.test.yml');
  
  // 2. Дождаться готовности сервисов
  await waitForService('http://localhost:8080/health');
  
  // 3. Создать граф через API
  final client = http.Client();
  final workflow = createDiamondWorkflow();
  await client.post('http://localhost:8080/workflows', body: workflow.toJson());
  
  // 4. Запустить через API
  final response = await client.post('http://localhost:8080/runs', ...);
  final runId = jsonDecode(response.body)['runId'];
  
  // 5. Подписаться на события через SSE
  final events = await client.get('http://localhost:8080/runs/$runId/events');
  
  // 6. Дождаться завершения
  await expectEventStream(events, contains('completed'));
  
  // 7. Проверить результат через API
  final run = await client.get('http://localhost:8080/runs/$runId');
  expect(jsonDecode(run.body)['status'], 'completed');
  
  // 8. Cleanup
  await DockerCompose.down();
});
```

---

## 🔥 ПРИОРИТИЗАЦИЯ ИСПРАВЛЕНИЙ

### Фаза 1: КРИТИЧНЫЕ ИСПРАВЛЕНИЯ (1-2 дня)

**Цель:** Убрать ложь из тестов

1. **Исправить фейковый тест waitAll**
   - Переименовать в "firstCome: выполняется дважды"
   - Добавить реальную проверку количества выполнений
   - Создать отдельный тест для waitAll с `skip: true`

2. **Добавить проверку количества выполнений**
   - Парсить логи из БД
   - Считать количество "Executing: [nodeId]"
   - Добавить в все diamond pattern тесты

3. **Удалить дубликаты**
   - Оставить один diamond pattern тест
   - Остальные либо удалить, либо сделать уникальными

**Результат:** Тесты не врут

### Фаза 2: UNIT ТЕСТЫ (3-5 дней)

**Цель:** Проверить логику движка изолированно

1. **Создать Mock узлы**
   ```dart
   class MockNode implements IGraphNode {
     final String id;
     final JoinStrategy joinStrategy;
     final Function() onExecute;
     int executionCount = 0;
     
     @override
     Future<void> execute(context) async {
       executionCount++;
       onExecute();
     }
   }
   ```

2. **Тесты на waitAll логику**
   - Узел ждёт все рёбра
   - Логи ожидания корректны
   - `_arrivedEdges` Map заполняется правильно
   - Map очищается после выполнения

3. **Тесты на firstCome логику**
   - Узел выполняется при первом ребре
   - Последующие рёбра тоже выполняют узел
   - Нет блокировок

4. **Тесты на exclusive логику**
   - Первое ребро блокирует остальные
   - Логи блокировки корректны
   - onError не выполняется если onSuccess прошёл

5. **Негативные тесты**
   - Deadlock с waitAll (узел ждёт ребро, которое не придёт)
   - Циклический граф
   - Узел без входящих рёбер с waitAll

**Результат:** Логика движка покрыта unit тестами

### Фаза 3: INTEGRATION ТЕСТЫ (5-7 дней)

**Цель:** Проверить работу с реальными компонентами

1. **Настроить тестовую БД**
   ```dart
   // test/integration/test_helpers.dart
   Future<void> setupTestDatabase() async {
     final container = await PostgreSQLContainer().start();
     await runMigrations(container.connectionString);
     return container;
   }
   ```

2. **Переписать существующие integration тесты**
   - Добавить проверку логов из БД
   - Добавить проверку количества выполнений
   - Добавить проверку порядка выполнения (timestamp)
   - Добавить проверку состояния Run

3. **Добавить тесты на параллельность**
   - Проверить timestamp в логах
   - Проверить что ветки выполняются одновременно
   - Проверить изоляцию контекста между ветками

4. **Добавить тесты на ошибки**
   - Ошибка в одной ветке не влияет на другую
   - onError ребро выполняется при ошибке
   - Логи ошибок корректны

**Результат:** Integration тесты проверяют реальную работу

### Фаза 4: E2E ТЕСТЫ В DOCKER (7-10 дней)

**Цель:** Имитация production

1. **Создать Docker Compose для тестов**
   ```yaml
   # test/e2e/docker-compose.test.yml
   services:
     postgres:
       image: postgres:15
       
     graph_worker:
       build: ../../server_apps/aq_graph_worker
       
     test_runner:
       build: .
       command: dart test
   ```

2. **Создать E2E тесты**
   - Запуск через HTTP API
   - Подписка на события через SSE
   - Проверка результатов через API
   - Проверка БД напрямую

3. **Тесты на отказоустойчивость**
   - Restart контейнера во время выполнения
   - Потеря соединения с БД
   - Timeout узлов

**Результат:** Уверенность в production-ready коде

### Фаза 5: СТРЕСС-ТЕСТЫ (опционально, 3-5 дней)

**Цель:** Проверить производительность

1. **Большие графы**
   - 1000 узлов последовательно
   - 100 параллельных веток
   - Глубокая вложенность (100 уровней)

2. **Метрики**
   - Время выполнения
   - Потребление памяти
   - Количество запросов к БД

3. **Нагрузочные тесты**
   - 100 одновременных запусков
   - Очередь задач
   - Graceful degradation

**Результат:** Понимание пределов системы

---

## 📁 СТРУКТУРА ТЕСТОВ

```
pkgs/aq_graph_engine/test/
├── unit/                          # Быстрые, изолированные
│   ├── engine/
│   │   ├── join_strategy_test.dart      # waitAll, firstCome, exclusive
│   │   ├── edge_tracking_test.dart      # _arrivedEdges Map
│   │   ├── event_generation_test.dart   # GraphRunEvent
│   │   └── error_handling_test.dart     # Обработка ошибок
│   ├── nodes/
│   │   └── mock_node_test.dart          # Mock узлы
│   └── helpers/
│       └── test_helpers.dart
│
├── integration/                   # Средние, с БД
│   ├── setup/
│   │   ├── test_database.dart           # PostgreSQL setup
│   │   └── test_helpers.dart
│   ├── diamond_pattern_test.dart        # Diamond с реальными узлами
│   ├── parallel_execution_test.dart     # Параллельность
│   ├── error_handling_test.dart         # Ошибки в узлах
│   ├── workflow_lifecycle_test.dart     # Полный цикл
│   └── database_state_test.dart         # Проверка БД
│
└── e2e/                           # Медленные, Docker
    ├── docker-compose.test.yml
    ├── Dockerfile
    ├── full_stack_test.dart             # Полный стек
    ├── api_test.dart                    # HTTP API
    ├── resilience_test.dart             # Отказоустойчивость
    └── stress_test.dart                 # Нагрузка
```

---

## 🛠️ ИНСТРУМЕНТЫ И БИБЛИОТЕКИ

### Для Unit тестов:
- `test` - стандартный фреймворк
- `mockito` - моки (если нужно)
- Кастомные Mock узлы

### Для Integration тестов:
- `test`
- `testcontainers` - управление PostgreSQL контейнером
- `dart_vault` - реальное хранилище

### Для E2E тестов:
- `test`
- `docker_compose` - управление стеком
- `http` - HTTP клиент
- `sse_client` - подписка на события

---

## ✅ КРИТЕРИИ ГОТОВНОСТИ

### Unit тесты готовы когда:
- ✅ Все join strategies покрыты
- ✅ `_arrivedEdges` Map протестирована
- ✅ Негативные сценарии покрыты
- ✅ Тесты выполняются < 1 секунды

### Integration тесты готовы когда:
- ✅ Все типы узлов протестированы
- ✅ Проверяются логи из БД
- ✅ Проверяется количество выполнений
- ✅ Проверяется порядок выполнения
- ✅ Тесты выполняются < 30 секунд

### E2E тесты готовы когда:
- ✅ Полный стек в Docker работает
- ✅ API протестирован
- ✅ События через SSE работают
- ✅ Отказоустойчивость проверена
- ✅ Тесты выполняются < 5 минут

---

## 🎯 ИТОГОВЫЙ ПЛАН ДЕЙСТВИЙ

### Неделя 1: Критичные исправления
- День 1: Исправить фейковый тест waitAll
- День 2: Добавить проверку количества выполнений
- День 3: Удалить дубликаты, рефакторинг

### Неделя 2: Unit тесты
- День 1-2: Mock узлы и инфраструктура
- День 3-4: Тесты на join strategies
- День 5: Негативные тесты

### Неделя 3: Integration тесты
- День 1-2: Настройка тестовой БД
- День 3-4: Переписать существующие тесты
- День 5: Новые integration тесты

### Неделя 4: E2E тесты
- День 1-2: Docker Compose setup
- День 3-4: E2E тесты
- День 5: Тесты на отказоустойчивость

---

## 💡 КЛЮЧЕВЫЕ ПРИНЦИПЫ

1. **Тест должен делать то, что заявляет** - название = проверка
2. **Проверяем процесс, не только результат** - логи, события, порядок
3. **Изоляция уровней** - unit/integration/e2e не смешиваем
4. **Docker для E2E** - имитация production обязательна
5. **Негативные тесты обязательны** - не только happy path
6. **Проверка БД обязательна** - Run должен быть сохранён корректно

---

**Дата создания:** 2026-04-09
**Основано на:** GRAPH_ENGINE_TESTS_AUDIT.md
**Статус:** План готов к реализации
