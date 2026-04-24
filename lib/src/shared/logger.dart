import 'package:logging/logging.dart';

/// Логгер для клиентской части графового движка
final graphEngineClientLogger = Logger('aq_graph_engine.client');

/// Логгер для серверной части графового движка
final graphEngineServerLogger = Logger('aq_graph_engine.server');

/// Настроить логирование для графового движка
void setupGraphEngineLogging({Level level = Level.INFO}) {
  Logger.root.level = level;
  Logger.root.onRecord.listen((record) {
    final emoji = _getEmojiForLevel(record.level);
    print('$emoji [${record.loggerName}] ${record.level.name}: ${record.message}');
    if (record.error != null) {
      print('  Error: ${record.error}');
    }
    if (record.stackTrace != null) {
      print('  Stack trace:\n${record.stackTrace}');
    }
  });
}

String _getEmojiForLevel(Level level) {
  if (level >= Level.SEVERE) return '❌';
  if (level >= Level.WARNING) return '⚠️';
  if (level >= Level.INFO) return 'ℹ️';
  return '🔍';
}
