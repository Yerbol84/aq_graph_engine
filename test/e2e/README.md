# 🐳 E2E Тесты Graph Engine в Docker

Полный стек E2E тестов в изолированном Docker окружении.

---

## 🎯 Что тестируется

E2E тесты проверяют **полный стек** в Docker контейнерах:

- ✅ PostgreSQL в контейнере
- ✅ Data Service в контейнере
- ✅ Graph Engine в контейнере
- ✅ Тесты запускаются в отдельном контейнере

Это **имитирует production окружение** и даёт максимальную уверенность в работоспособности кода.

---

## 📋 Требования

- Docker 20.10+
- Docker Compose 2.0+
- 2GB свободной RAM
- 5GB свободного места на диске

---

## 🚀 Быстрый старт

### 1. Запустить все тесты

```bash
cd pkgs/aq_graph_engine/test/e2e
docker-compose -f docker-compose.test.yml up --build --abort-on-container-exit
```

### 2. Посмотреть логи

```bash
docker-compose -f docker-compose.test.yml logs -f test_runner
```

### 3. Остановить и очистить

```bash
docker-compose -f docker-compose.test.yml down -v
```

---

## 📊 Структура тестов

### Тест 1: Health Checks
Проверяет что все сервисы доступны и отвечают на `/health`

### Тест 2: Простой Workflow
- Создаёт проект через Data Service API
- Создаёт workflow через Data Service API
- Запускает через Graph Engine API
- Проверяет статус через polling
- Проверяет результат в БД

### Тест 3: Параллельное выполнение
- Создаёт workflow с параллельными ветками
- Запускает через API
- Проверяет что все ветки выполнились
- Проверяет логи в БД

### Тест 4: Обработка ошибок
- Создаёт workflow с узлом который упадёт
- Запускает через API
- Проверяет что статус = "failed"
- Проверяет errorMessage в БД

---

## 🔧 Конфигурация

### Переменные окружения

Можно переопределить через `.env` файл:

```bash
# Порты (чтобы не конфликтовать с локальными сервисами)
POSTGRES_PORT=5433
DATA_SERVICE_PORT=8766
GRAPH_ENGINE_PORT=8082

# База данных
POSTGRES_DB=aq_test
POSTGRES_USER=aq_test
POSTGRES_PASSWORD=aq_test_secret

# Таймауты
TEST_TIMEOUT=300000  # 5 минут
```

### Сервисы

| Сервис | Контейнер | Порт | Health Check |
|--------|-----------|------|--------------|
| PostgreSQL | aq_test_postgres | 5433 | `pg_isready` |
| Data Service | aq_test_data_service | 8766 | `/health` |
| Graph Engine | aq_test_graph_engine | 8082 | `/health` |
| Test Runner | aq_test_runner | - | - |

---

## 🐛 Отладка

### Проверить что сервисы запустились

```bash
docker-compose -f docker-compose.test.yml ps
```

Все сервисы должны быть в статусе `healthy`.

### Проверить логи конкретного сервиса

```bash
# PostgreSQL
docker-compose -f docker-compose.test.yml logs postgres

# Data Service
docker-compose -f docker-compose.test.yml logs data_service

# Graph Engine
docker-compose -f docker-compose.test.yml logs graph_engine

# Test Runner
docker-compose -f docker-compose.test.yml logs test_runner
```

### Подключиться к контейнеру

```bash
# Зайти в test_runner
docker exec -it aq_test_runner /bin/bash

# Зайти в PostgreSQL
docker exec -it aq_test_postgres psql -U aq_test -d aq_test
```

### Проверить БД напрямую

```bash
docker exec -it aq_test_postgres psql -U aq_test -d aq_test -c "SELECT * FROM workflow_runs LIMIT 10;"
```

### Запустить тесты локально (без Docker)

```bash
# Запустить сервисы
docker-compose -f docker-compose.test.yml up -d postgres data_service graph_engine

# Дождаться готовности
sleep 10

# Запустить тесты локально
export DATA_SERVICE_URL=http://localhost:8766
export GRAPH_ENGINE_URL=http://localhost:8082
dart test e2e_tests.dart
```

---

## 📈 CI/CD Integration

### GitHub Actions

```yaml
name: E2E Tests

on: [push, pull_request]

jobs:
  e2e:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Run E2E tests
        run: |
          cd pkgs/aq_graph_engine/test/e2e
          docker-compose -f docker-compose.test.yml up --build --abort-on-container-exit

      - name: Cleanup
        if: always()
        run: |
          cd pkgs/aq_graph_engine/test/e2e
          docker-compose -f docker-compose.test.yml down -v
```

### GitLab CI

```yaml
e2e_tests:
  stage: test
  image: docker:latest
  services:
    - docker:dind
  script:
    - cd pkgs/aq_graph_engine/test/e2e
    - docker-compose -f docker-compose.test.yml up --build --abort-on-container-exit
  after_script:
    - docker-compose -f docker-compose.test.yml down -v
```

---

## 🎯 Makefile команды

Добавьте в корневой `Makefile`:

```makefile
# E2E тесты
.PHONY: test-e2e
test-e2e:
	cd pkgs/aq_graph_engine/test/e2e && \
	docker-compose -f docker-compose.test.yml up --build --abort-on-container-exit && \
	docker-compose -f docker-compose.test.yml down -v

# E2E тесты (только запуск, без cleanup)
.PHONY: test-e2e-run
test-e2e-run:
	cd pkgs/aq_graph_engine/test/e2e && \
	docker-compose -f docker-compose.test.yml up --build --abort-on-container-exit

# E2E тесты (cleanup)
.PHONY: test-e2e-clean
test-e2e-clean:
	cd pkgs/aq_graph_engine/test/e2e && \
	docker-compose -f docker-compose.test.yml down -v

# E2E тесты (логи)
.PHONY: test-e2e-logs
test-e2e-logs:
	cd pkgs/aq_graph_engine/test/e2e && \
	docker-compose -f docker-compose.test.yml logs -f test_runner
```

Использование:

```bash
make test-e2e        # Запустить тесты и очистить
make test-e2e-run    # Только запустить
make test-e2e-clean  # Только очистить
make test-e2e-logs   # Посмотреть логи
```

---

## ⚠️ Известные проблемы

### Проблема: Тесты падают с timeout

**Причина:** Сервисы не успели запуститься

**Решение:** Увеличить `retries` в healthcheck или добавить `sleep` перед запуском тестов

### Проблема: Порт уже занят

**Причина:** Локальные сервисы используют те же порты

**Решение:** Изменить порты в docker-compose.test.yml или остановить локальные сервисы

### Проблема: Out of memory

**Причина:** Недостаточно RAM для всех контейнеров

**Решение:** Увеличить RAM для Docker или запускать тесты по одному

---

## 📊 Метрики

### Время выполнения

- Сборка образов: ~2-3 минуты (первый раз)
- Запуск сервисов: ~10-15 секунд
- Выполнение тестов: ~30-60 секунд
- **Итого:** ~3-5 минут (первый раз), ~1-2 минуты (последующие)

### Ресурсы

- RAM: ~1.5GB
- Disk: ~3GB (образы)
- CPU: 2-4 ядра (рекомендуется)

---

## 🎓 Лучшие практики

1. **Запускайте E2E тесты перед каждым PR** - это гарантирует что код работает в production-like окружении

2. **Используйте отдельные порты** - чтобы не конфликтовать с локальными сервисами

3. **Очищайте после тестов** - используйте `down -v` чтобы удалить volumes

4. **Проверяйте логи при падении** - `docker-compose logs` покажет что пошло не так

5. **Добавьте в CI/CD** - автоматический запуск на каждый commit

---

## 📚 Дополнительные ресурсы

- [Docker Compose документация](https://docs.docker.com/compose/)
- [Testcontainers](https://www.testcontainers.org/) - альтернативный подход
- [GRAPH_ENGINE_TEST_REFACTORING_PLAN.md](../../../../GRAPH_ENGINE_TEST_REFACTORING_PLAN.md) - полный план тестирования

---

**Создано:** 2026-04-09
**Статус:** ✅ Готово к использованию
