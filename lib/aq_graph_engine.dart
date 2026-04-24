// AQ Graph Engine — клиентская библиотека для работы с графовым движком
//
// ВАЖНО: Этот файл экспортирует ТОЛЬКО клиентскую часть.
// Для серверных компонентов используйте: import 'package:aq_graph_engine/server.dart';

library aq_graph_engine;

// Интерфейсы для адаптеров (shared)
export 'src/interfaces/i_run_repository.dart';
export 'src/interfaces/i_graph_repository.dart';

// Клиентский транспорт
export 'src/transport/http_engine_transport.dart';

// Клиентская библиотека
export 'src/client/graph_engine_client.dart';
export 'src/client/graph_run_stream.dart';
export 'src/client/models.dart';
export 'src/client/exceptions.dart';

// Auth интерфейсы из aq_schema
export 'package:aq_schema/auth/i_auth_client.dart';
export 'package:aq_schema/auth/test_auth_client.dart';

// Transport messages из aq_schema
export 'package:aq_schema/graph/transport/messages/run_request.dart';
export 'package:aq_schema/graph/transport/messages/run_event.dart';
