/// Base exception class for all LDK-related errors.
abstract class LDKException implements Exception {
  /// Creates a new [LDKException] with the given message.
  const LDKException(this.message);

  /// The error message.
  final String message;

  @override
  String toString() => 'LDKException: $message';
}

/// Exception thrown when authentication fails.
class LDKAuthException extends LDKException {
  /// Creates a new [LDKAuthException].
  const LDKAuthException(super.message, {this.statusCode});

  /// HTTP status code associated with the error (if applicable).
  final int? statusCode;

  @override
  String toString() => 'LDKAuthException: $message';
}

/// Exception thrown when network operations fail.
class LDKNetworkException extends LDKException {
  /// Creates a new [LDKNetworkException].
  const LDKNetworkException(super.message,
      {this.statusCode, this.originalError});

  /// HTTP status code associated with the error.
  final int? statusCode;

  /// The original error that caused this exception.
  final Object? originalError;

  @override
  String toString() => 'LDKNetworkException: $message';
}

/// Exception thrown when validation fails.
class LDKValidationException extends LDKException {
  /// Creates a new [LDKValidationException].
  const LDKValidationException(super.message, {this.errors});

  /// Detailed validation errors.
  final Map<String, List<String>>? errors;

  @override
  String toString() => 'LDKValidationException: $message';
}

/// Exception thrown when server returns an error.
class LDKServerException extends LDKException {
  /// Creates a new [LDKServerException].
  const LDKServerException(super.message, {this.statusCode, this.errorDetails});

  /// HTTP status code from the server.
  final int? statusCode;

  /// Additional error details from the server.
  final Map<String, dynamic>? errorDetails;

  @override
  String toString() => 'LDKServerException: $message';
}

/// Exception thrown when configuration is invalid.
class LDKConfigurationException extends LDKException {
  /// Creates a new [LDKConfigurationException].
  const LDKConfigurationException(super.message);

  @override
  String toString() => 'LDKConfigurationException: $message';
}

/// Exception thrown when file operations fail.
class LDKFileException extends LDKException {
  /// Creates a new [LDKFileException].
  const LDKFileException(super.message, {this.originalError});

  /// The original error that caused this exception.
  final Object? originalError;

  @override
  String toString() => 'LDKFileException: $message';
}
