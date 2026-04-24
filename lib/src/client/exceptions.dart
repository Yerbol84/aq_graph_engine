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
    if (statusCode != null) {
      buffer.write(' (HTTP $statusCode)');
    }
    if (code != null) {
      buffer.write(' [code: $code]');
    }
    return buffer.toString();
  }
}

/// Ошибка подключения к серверу
class GraphEngineConnectionException extends GraphEngineException {
  GraphEngineConnectionException(
    String message, {
    int? statusCode,
    String? code,
    dynamic details,
  }) : super(
          message,
          statusCode: statusCode,
          code: code,
          details: details,
        );
}

/// Таймаут запроса
class GraphEngineTimeoutException extends GraphEngineException {
  GraphEngineTimeoutException(
    String message, {
    int? statusCode,
    String? code,
    dynamic details,
  }) : super(
          message,
          statusCode: statusCode,
          code: code,
          details: details,
        );
}

/// Ресурс не найден (404)
class GraphEngineNotFoundException extends GraphEngineException {
  GraphEngineNotFoundException(
    String message, {
    int? statusCode,
    String? code,
    dynamic details,
  }) : super(
          message,
          statusCode: statusCode ?? 404,
          code: code,
          details: details,
        );
}

/// Ошибка авторизации (401)
class GraphEngineUnauthorizedException extends GraphEngineException {
  GraphEngineUnauthorizedException(
    String message, {
    int? statusCode,
    String? code,
    dynamic details,
  }) : super(
          message,
          statusCode: statusCode ?? 401,
          code: code,
          details: details,
        );
}

/// Недостаточно прав (403)
class GraphEngineForbiddenException extends GraphEngineException {
  GraphEngineForbiddenException(
    String message, {
    int? statusCode,
    String? code,
    dynamic details,
  }) : super(
          message,
          statusCode: statusCode ?? 403,
          code: code,
          details: details,
        );
}

/// Ошибка валидации (400)
class GraphEngineValidationException extends GraphEngineException {
  GraphEngineValidationException(
    String message, {
    int? statusCode,
    String? code,
    dynamic details,
  }) : super(
          message,
          statusCode: statusCode ?? 400,
          code: code,
          details: details,
        );
}

/// Внутренняя ошибка сервера (500)
class GraphEngineServerException extends GraphEngineException {
  GraphEngineServerException(
    String message, {
    int? statusCode,
    String? code,
    dynamic details,
  }) : super(
          message,
          statusCode: statusCode ?? 500,
          code: code,
          details: details,
        );
}
