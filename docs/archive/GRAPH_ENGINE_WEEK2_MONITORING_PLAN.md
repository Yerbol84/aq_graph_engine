# 📊 НЕДЕЛЯ 2: МОНИТОРИНГ + ОТКАЗОУСТОЙЧИВОСТЬ

**Дата начала:** 2026-04-10
**Статус:** 🚀 В РАБОТЕ
**Приоритет:** КРИТИЧНЫЙ

---

## 🎯 ЦЕЛЬ НЕДЕЛИ

Добавить **visibility** и **надёжность** в Graph Engine для production использования.

**Результат:** Система с полным мониторингом, метриками и базовой отказоустойчивостью.

---

## 📋 ПЛАН НА НЕДЕЛЮ

### День 1-2: Prometheus метрики

**Цель:** Собирать метрики выполнения

**Задачи:**

1. **Добавить зависимость `prometheus_client`**
   ```yaml
   dependencies:
     prometheus_client: ^1.0.0
   ```

2. **Создать класс `GraphEngineMetrics`**

   Файл: `pkgs/aq_graph_engine/lib/src/monitoring/metrics.dart`

   ```dart
   import 'package:prometheus_client/prometheus_client.dart';

   class GraphEngineMetrics {
     // Счётчики
     static final runStartedCounter = Counter(
       name: 'graph_runs_started_total',
       help: 'Total number of graph runs started',
       labelNames: ['project_id', 'blueprint_id'],
     );

     static final runCompletedCounter = Counter(
       name: 'graph_runs_completed_total',
       help: 'Total number of graph runs completed successfully',
       labelNames: ['project_id', 'blueprint_id'],
     );

     static final runFailedCounter = Counter(
       name: 'graph_runs_failed_total',
       help: 'Total number of graph runs failed',
       labelNames: ['project_id', 'blueprint_id', 'error_type'],
     );

     // Гистограммы
     static final runDurationHistogram = Histogram(
       name: 'graph_run_duration_seconds',
       help: 'Duration of graph run execution',
       labelNames: ['project_id', 'blueprint_id'],
       buckets: [0.1, 0.5, 1, 2, 5, 10, 30, 60, 120, 300],
     );

     static final nodeExecutionHistogram = Histogram(
       name: 'graph_node_execution_seconds',
       help: 'Duration of individual node execution',
       labelNames: ['node_type', 'project_id'],
       buckets: [0.01, 0.05, 0.1, 0.5, 1, 2, 5, 10, 30],
     );

     // Gauge
     static final activeRunsGauge = Gauge(
       name: 'graph_active_runs',
       help: 'Number of currently active graph runs',
     );

     static final queuedRunsGauge = Gauge(
       name: 'graph_queued_runs',
       help: 'Number of runs waiting in queue',
     );
   }
   ```

3. **Интегрировать метрики в `PolymorphicWorkflowRunner`**

   Добавить в начало `start()`:
   ```dart
   GraphEngineMetrics.runStartedCounter.labels([projectId, graph.id]).inc();
   GraphEngineMetrics.activeRunsGauge.inc();
   final timer = GraphEngineMetrics.runDurationHistogram
       .labels([projectId, graph.id])
       .startTimer();
   ```

   В конце успешного выполнения:
   ```dart
   timer.observeDuration();
   GraphEngineMetrics.runCompletedCounter.labels([projectId, graph.id]).inc();
   GraphEngineMetrics.activeRunsGauge.dec();
   ```

   При ошибке:
   ```dart
   timer.observeDuration();
   GraphEngineMetrics.runFailedCounter
       .labels([projectId, graph.id, e.runtimeType.toString()])
       .inc();
   GraphEngineMetrics.activeRunsGauge.dec();
   ```

4. **Добавить endpoint `/metrics`**

   Файл: `server_apps/graph_engine_server/lib/routes/metrics_router.dart`

   ```dart
   import 'package:shelf/shelf.dart';
   import 'package:shelf_router/shelf_router.dart';
   import 'package:prometheus_client/prometheus_client.dart';

   class MetricsRouter {
     Router get router {
       final router = Router();

       router.get('/metrics', (Request request) {
         final registry = CollectorRegistry.defaultRegistry;
         final metrics = registry.collectMetricFamilySamples();

         // Форматировать в Prometheus text format
         final buffer = StringBuffer();
         for (final family in metrics) {
           buffer.writeln('# HELP ${family.name} ${family.help}');
           buffer.writeln('# TYPE ${family.name} ${family.type}');

           for (final sample in family.samples) {
             buffer.write(sample.name);
             if (sample.labelNames.isNotEmpty) {
               buffer.write('{');
               for (var i = 0; i < sample.labelNames.length; i++) {
                 if (i > 0) buffer.write(',');
                 buffer.write('${sample.labelNames[i]}="${sample.labelValues[i]}"');
               }
               buffer.write('}');
             }
             buffer.writeln(' ${sample.value}');
           }
         }

         return Response.ok(
           buffer.toString(),
           headers: {'Content-Type': 'text/plain; version=0.0.4'},
         );
       });

       return router;
     }
   }
   ```

5. **Зарегистрировать роутер в main.dart**
   ```dart
   final metricsRouter = MetricsRouter();
   final handler = Pipeline()
       .addMiddleware(logRequests())
       .addHandler(
         Cascade()
             .add(apiRouter.router)
             .add(metricsRouter.router)
             .handler,
       );
   ```

**Результат:** Prometheus метрики доступны на `/metrics`

**Effort:** 2 дня

---

### День 3-4: Grafana дашборды

**Цель:** Визуализация метрик

**Задачи:**

1. **Создать docker-compose с Prometheus + Grafana**

   Файл: `deploys/monitoring/docker-compose.yml`

   ```yaml
   version: '3.8'

   services:
     prometheus:
       image: prom/prometheus:latest
       ports:
         - "9090:9090"
       volumes:
         - ./prometheus.yml:/etc/prometheus/prometheus.yml
         - prometheus_data:/prometheus
       command:
         - '--config.file=/etc/prometheus/prometheus.yml'
         - '--storage.tsdb.path=/prometheus'

     grafana:
       image: grafana/grafana:latest
       ports:
         - "3000:3000"
       environment:
         - GF_SECURITY_ADMIN_PASSWORD=admin
       volumes:
         - grafana_data:/var/lib/grafana
         - ./grafana/dashboards:/etc/grafana/provisioning/dashboards
         - ./grafana/datasources:/etc/grafana/provisioning/datasources

   volumes:
     prometheus_data:
     grafana_data:
   ```

2. **Создать Prometheus config**

   Файл: `deploys/monitoring/prometheus.yml`

   ```yaml
   global:
     scrape_interval: 15s
     evaluation_interval: 15s

   scrape_configs:
     - job_name: 'graph_engine'
       static_configs:
         - targets: ['host.docker.internal:8081']
   ```

3. **Создать Grafana дашборд "Graph Engine Overview"**

   Файл: `deploys/monitoring/grafana/dashboards/graph_engine_overview.json`

   Панели:
   - **Runs Started** (Counter) - rate(graph_runs_started_total[5m])
   - **Runs Completed** (Counter) - rate(graph_runs_completed_total[5m])
   - **Runs Failed** (Counter) - rate(graph_runs_failed_total[5m])
   - **Success Rate** (%) - (rate(graph_runs_completed_total[5m]) / rate(graph_runs_started_total[5m])) * 100
   - **Active Runs** (Gauge) - graph_active_runs
   - **Run Duration p50** - histogram_quantile(0.5, graph_run_duration_seconds_bucket)
   - **Run Duration p95** - histogram_quantile(0.95, graph_run_duration_seconds_bucket)
   - **Run Duration p99** - histogram_quantile(0.99, graph_run_duration_seconds_bucket)

4. **Создать дашборд "Node Performance"**

   Панели:
   - **Top 10 Slowest Nodes** - topk(10, avg by (node_type) (graph_node_execution_seconds))
   - **Node Execution Count** - sum by (node_type) (rate(graph_node_execution_seconds_count[5m]))
   - **Node Duration by Type** - histogram_quantile(0.95, sum by (node_type, le) (graph_node_execution_seconds_bucket))

5. **Создать README с инструкциями**

   Файл: `deploys/monitoring/README.md`

**Результат:** Grafana дашборды готовы и доступны на http://localhost:3000

**Effort:** 2 дня

---

### День 5: Базовая отказоустойчивость

**Цель:** Graceful shutdown и базовый retry

**Задачи:**

1. **Graceful Shutdown**

   Добавить в `server_apps/graph_engine_server/bin/main.dart`:

   ```dart
   import 'dart:io';

   void main() async {
     // ... существующий код ...

     // Обработка SIGTERM/SIGINT
     ProcessSignal.sigterm.watch().listen((signal) async {
       print('Received SIGTERM, shutting down gracefully...');
       await shutdown();
       exit(0);
     });

     ProcessSignal.sigint.watch().listen((signal) async {
       print('Received SIGINT, shutting down gracefully...');
       await shutdown();
       exit(0);
     });
   }

   Future<void> shutdown() async {
     print('1. Stopping accepting new requests...');
     // TODO: Остановить прием новых запросов

     print('2. Waiting for active runs to complete...');
     // TODO: Дождаться завершения активных запусков

     print('3. Closing database connections...');
     await Vault.disconnect();

     print('Shutdown complete.');
   }
   ```

2. **Базовый Retry механизм**

   Создать: `pkgs/aq_graph_engine/lib/src/resilience/retry_policy.dart`

   ```dart
   class RetryPolicy {
     final int maxAttempts;
     final Duration initialDelay;
     final double backoffMultiplier;

     const RetryPolicy({
       this.maxAttempts = 3,
       this.initialDelay = const Duration(seconds: 1),
       this.backoffMultiplier = 2.0,
     });

     Future<T> execute<T>(Future<T> Function() action) async {
       var attempt = 0;
       var delay = initialDelay;

       while (true) {
         attempt++;

         try {
           return await action();
         } catch (e) {
           if (attempt >= maxAttempts) {
             rethrow;
           }

           print('Attempt $attempt failed: $e. Retrying in ${delay.inSeconds}s...');
           await Future.delayed(delay);
           delay = Duration(milliseconds: (delay.inMilliseconds * backoffMultiplier).round());
         }
       }
     }
   }
   ```

3. **Интегрировать retry в критичные операции**

   Обернуть вызовы к БД:
   ```dart
   final retryPolicy = RetryPolicy(maxAttempts: 3);
   final run = await retryPolicy.execute(() => runRepo.findById(runId));
   ```

**Результат:** Graceful shutdown и retry для БД операций

**Effort:** 1 день

---

## 📊 КРИТЕРИИ УСПЕХА

### Метрики:
- ✅ Prometheus endpoint `/metrics` работает
- ✅ Метрики собираются корректно
- ✅ Grafana дашборды показывают данные

### Отказоустойчивость:
- ✅ Graceful shutdown работает (SIGTERM/SIGINT)
- ✅ Retry механизм обрабатывает временные ошибки БД

### Документация:
- ✅ README с инструкциями по запуску мониторинга
- ✅ Примеры запросов к Prometheus

---

## 🚀 ЗАПУСК

### Локальная разработка:

```bash
# 1. Запустить мониторинг стек
cd deploys/monitoring
docker-compose up -d

# 2. Запустить Graph Engine
cd server_apps/graph_engine_server
dart run bin/main.dart

# 3. Открыть Grafana
open http://localhost:3000
# Login: admin / admin

# 4. Открыть Prometheus
open http://localhost:9090
```

### Проверка метрик:

```bash
# Проверить что метрики доступны
curl http://localhost:8081/metrics

# Проверить конкретную метрику
curl http://localhost:8081/metrics | grep graph_runs_started_total
```

---

## 📝 ЧЕКЛИСТ

### День 1-2: Prometheus метрики
- [ ] Добавить зависимость `prometheus_client`
- [ ] Создать класс `GraphEngineMetrics`
- [ ] Интегрировать метрики в `PolymorphicWorkflowRunner`
- [ ] Добавить endpoint `/metrics`
- [ ] Протестировать сбор метрик

### День 3-4: Grafana дашборды
- [ ] Создать docker-compose с Prometheus + Grafana
- [ ] Создать Prometheus config
- [ ] Создать дашборд "Graph Engine Overview"
- [ ] Создать дашборд "Node Performance"
- [ ] Написать README

### День 5: Отказоустойчивость
- [ ] Реализовать graceful shutdown
- [ ] Создать RetryPolicy класс
- [ ] Интегрировать retry в БД операции
- [ ] Протестировать shutdown и retry

---

## 🎯 СЛЕДУЮЩИЕ ШАГИ

После завершения Недели 2:
- Неделя 3: Нагрузочное тестирование
- Неделя 4-5: Документация + Pilot

---

**Дата:** 2026-04-10
**Статус:** 🚀 НАЧИНАЕМ
**Приоритет:** КРИТИЧНЫЙ
