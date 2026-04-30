// Исключения для клиентской библиотеки Graph Engine

/// Базовое исключение Graph Engine
class GraphEngineException implements Exception {
  final String message;
  final int? statusCode;
  final String? code;
  final dynamic details;

  GraphEngineException(
    this.message, {
    this.statusCode,
    this.code,
    this.details,
  });

  @override
  String toString() {
    final buffer = StringBuffer('GraphEngineException: $message');
    if (statusCode != null) buffer.write(' (HTTP $statusCode)');
    if (code != null) buffer.write(' [code: $code]');
    return buffer.toString();
  }
}

/// Ошибка подключения к серверу
class GraphEngineConnectionException extends GraphEngineException {
  GraphEngineConnectionException(
    super.message, {
    super.statusCode,
    super.code,
    super.details,
  });
}

/// Таймаут запроса
class GraphEngineTimeoutException extends GraphEngineException {
  GraphEngineTimeoutException(
    super.message, {
    super.statusCode,
    super.code,
    super.details,
  });
}

/// Ресурс не найден (404)
class GraphEngineNotFoundException extends GraphEngineException {
  GraphEngineNotFoundException(
    super.message, {
    int? statusCode,
    super.code,
    super.details,
  }) : super(statusCode: statusCode ?? 404);
}

/// Ошибка авторизации (401)
class GraphEngineUnauthorizedException extends GraphEngineException {
  GraphEngineUnauthorizedException(
    super.message, {
    int? statusCode,
    super.code,
    super.details,
  }) : super(statusCode: statusCode ?? 401);
}

/// Недостаточно прав (403)
class GraphEngineForbiddenException extends GraphEngineException {
  GraphEngineForbiddenException(
    super.message, {
    int? statusCode,
    super.code,
    super.details,
  }) : super(statusCode: statusCode ?? 403);
}

/// Ошибка валидации (400)
class GraphEngineValidationException extends GraphEngineException {
  GraphEngineValidationException(
    super.message, {
    int? statusCode,
    super.code,
    super.details,
  }) : super(statusCode: statusCode ?? 400);
}

/// Внутренняя ошибка сервера (500)
class GraphEngineServerException extends GraphEngineException {
  GraphEngineServerException(
    super.message, {
    int? statusCode,
    super.code,
    super.details,
  }) : super(statusCode: statusCode ?? 500);
}
