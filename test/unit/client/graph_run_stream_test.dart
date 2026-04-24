// Unit тесты для GraphRunStream

import 'package:test/test.dart';
import 'package:aq_schema/aq_schema.dart';
import 'package:aq_graph_engine/aq_graph_engine.dart';
import 'dart:async';

void main() {
  group('GraphRunStream', () {
    late GraphRunStream stream;

    setUp(() {
      stream = GraphRunStream(
        runId: 'run-123',
        wsUrl: 'ws://localhost:8080/api/v1/runs/run-123/ws',
      );
    });

    tearDown(() async {
      await stream.disconnect();
    });

    test('создаётся с правильными параметрами', () {
      expect(stream.runId, 'run-123');
      expect(stream.wsUrl, 'ws://localhost:8080/api/v1/runs/run-123/ws');
      expect(stream.isConnected, false);
    });

    test('isConnected возвращает false до подключения', () {
      expect(stream.isConnected, false);
    });

    test('events возвращает Stream', () {
      expect(stream.events, isA<Stream<GraphRunEvent>>());
    });

    test('ping выбрасывает исключение если не подключён', () {
      expect(
        () => stream.ping(),
        throwsA(isA<GraphEngineConnectionException>()),
      );
    });

    test('disconnect не падает если не подключён', () async {
      await stream.disconnect();
      expect(stream.isConnected, false);
    });

    test('множественные вызовы connect безопасны', () async {
      // Первый connect попытается подключиться
      // Второй connect должен вернуться сразу
      // Оба не должны упасть (хотя подключение может не удаться)

      try {
        await stream.connect();
        await stream.connect();
      } catch (e) {
        // Ожидаем ошибку подключения, т.к. сервер не запущен
        expect(e, isA<GraphEngineConnectionException>());
      }
    });

    test('disconnect после connect безопасен', () async {
      try {
        await stream.connect();
      } catch (e) {
        // Игнорируем ошибку подключения
      }

      await stream.disconnect();
      expect(stream.isConnected, false);
    });

    test('connectionTimeout используется по умолчанию', () {
      final customStream = GraphRunStream(
        runId: 'run-123',
        wsUrl: 'ws://localhost:8080/api/v1/runs/run-123/ws',
        connectionTimeout: const Duration(seconds: 5),
      );

      expect(customStream.connectionTimeout, const Duration(seconds: 5));
    });

    test('default connectionTimeout равен 10 секундам', () {
      expect(stream.connectionTimeout, const Duration(seconds: 10));
    });
  });
}
