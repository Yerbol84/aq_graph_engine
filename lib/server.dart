// AQ Graph Engine — серверная библиотека
//
// Этот файл экспортирует серверные компоненты графового движка.
// Используйте его в серверных приложениях (workers, services).
//
// Включает в себя:
// - Все клиентские компоненты (из aq_graph_engine.dart)
// - Серверные компоненты (движок, runners, registry, metrics)

library aq_graph_engine.server;

// Включить клиентскую часть
export 'aq_graph_engine.dart';

// Главный движок
export 'src/server/engine/graph_engine.dart';
export 'src/server/engine/engine_execution_context.dart';
export 'package:aq_schema/graph/engine/condition_evaluator.dart';

// Runners
export 'src/server/runners/workflow_runner.dart';
export 'src/server/runners/node_executor.dart';
export 'src/server/runners/graph_traversal.dart';
export 'src/server/runners/instruction_runner.dart';
export 'src/server/runners/prompt_runner.dart';

// Реестр типов узлов
export 'src/server/registry/node_type_registry.dart';

// Мониторинг
export 'src/server/monitoring/metrics.dart';

// Локальный транспорт (только для сервера)
export 'src/transport/local_engine_transport.dart';

// Data Layer реализации репозиториев (через IDataLayer.instance)
export 'src/server/storage/data_layer_run_repository.dart';
export 'src/server/storage/data_layer_graph_repository.dart';
