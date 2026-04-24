// Абстракция хранилища запусков.
// Движок не знает, что это Drift или SQLite — он работает с этим интерфейсом.
// Приложение предоставляет конкретную реализацию через адаптер.

abstract class IRunRepository {
  /// Создать запись о новом запуске
  Future<void> createRun({
    required String runId,
    required String projectId,
    required Map<String, dynamic> graphSnapshot,
  });

  /// Обновить логи и (опционально) статус запуска
  Future<void> updateRunLog(
    String runId,
    List<String> logs, {
    String? status,
  });

  /// Приостановить запуск (граф ждёт ввода пользователя)
  Future<void> suspendRun({
    required String runId,
    required String contextJson,
    required String nodeId,
    required List<String> logs,
  });

  /// Получить данные одного запуска по ID
  /// Возвращает Map с полями: id, status, contextJson, suspendedNodeId, logsJson
  /// или null если запуск не найден
  Future<Map<String, dynamic>?> getRun(String runId);

  /// Atomic compare-and-set операция для статуса
  ///
  /// Обновляет статус только если текущий статус совпадает с expectedStatus.
  /// Возвращает true если обновление прошло успешно, false если статус не совпал.
  ///
  /// Используется для защиты от race conditions при одновременном запуске.
  ///
  /// Пример:
  /// ```dart
  /// // Пытаемся перевести из 'queued' в 'running'
  /// final success = await repo.compareAndSetStatus(
  ///   runId: 'run-123',
  ///   expectedStatus: 'queued',
  ///   newStatus: 'running',
  /// );
  ///
  /// if (!success) {
  ///   // Кто-то другой уже запустил этот run
  ///   throw StateError('Run already started');
  /// }
  /// ```
  Future<bool> compareAndSetStatus({
    required String runId,
    required String expectedStatus,
    required String newStatus,
  });

  /// Попытаться захватить lock на run для выполнения
  ///
  /// Возвращает true если lock успешно захвачен, false если run уже заблокирован.
  /// Lock автоматически освобождается через ttl или при вызове releaseLock.
  ///
  /// Используется для pessimistic locking в distributed системах.
  ///
  /// Пример:
  /// ```dart
  /// final locked = await repo.tryAcquireLock(
  ///   runId: 'run-123',
  ///   workerId: 'worker-1',
  ///   ttl: Duration(minutes: 5),
  /// );
  ///
  /// if (!locked) {
  ///   // Run уже выполняется другим worker'ом
  ///   return;
  /// }
  ///
  /// try {
  ///   // Выполняем run
  /// } finally {
  ///   await repo.releaseLock(runId: 'run-123', workerId: 'worker-1');
  /// }
  /// ```
  Future<bool> tryAcquireLock({
    required String runId,
    required String workerId,
    required Duration ttl,
  });

  /// Освободить lock на run
  ///
  /// Возвращает true если lock был освобождён, false если lock не принадлежал этому worker'у.
  Future<bool> releaseLock({
    required String runId,
    required String workerId,
  });

  // ── Dead Letter Queue ──────────────────────────────────────────────────────

  /// Переместить failed run в Dead Letter Queue
  ///
  /// Используется когда run провалился после всех retry попыток.
  /// DLQ позволяет анализировать и вручную retry проблемные runs.
  ///
  /// Пример:
  /// ```dart
  /// await repo.moveToDLQ(
  ///   runId: 'run-123',
  ///   reason: 'Failed after 3 retries: Connection timeout',
  ///   failureCount: 3,
  ///   lastError: 'SocketException: Connection refused',
  /// );
  /// ```
  Future<void> moveToDLQ({
    required String runId,
    required String reason,
    required int failureCount,
    String? lastError,
  });

  /// Получить список runs в DLQ
  ///
  /// Возвращает список Map с полями:
  /// - runId: String
  /// - projectId: String
  /// - reason: String
  /// - failureCount: int
  /// - lastError: String?
  /// - movedToDLQAt: DateTime
  /// - graphSnapshot: Map<String, dynamic>
  ///
  /// [limit] - максимальное количество записей (по умолчанию 100)
  /// [offset] - смещение для пагинации (по умолчанию 0)
  Future<List<Map<String, dynamic>>> getDLQJobs({
    int limit = 100,
    int offset = 0,
  });

  /// Retry run из DLQ
  ///
  /// Перемещает run обратно в очередь для повторного выполнения.
  /// Возвращает true если успешно, false если run не найден в DLQ.
  ///
  /// Пример:
  /// ```dart
  /// final success = await repo.retryFromDLQ(runId: 'run-123');
  /// if (success) {
  ///   // Run перемещён обратно в очередь
  /// }
  /// ```
  Future<bool> retryFromDLQ({required String runId});

  /// Удалить старые записи из DLQ
  ///
  /// Удаляет все runs которые находятся в DLQ дольше чем [olderThan].
  /// Возвращает количество удалённых записей.
  ///
  /// Пример:
  /// ```dart
  /// // Удалить все DLQ записи старше 7 дней
  /// final deleted = await repo.cleanupDLQ(
  ///   olderThan: Duration(days: 7),
  /// );
  /// print('Deleted $deleted old DLQ entries');
  /// ```
  Future<int> cleanupDLQ({required Duration olderThan});
}

