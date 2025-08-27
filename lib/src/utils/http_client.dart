import 'dart:io';

import 'package:dio/dio.dart';
import 'package:logger/logger.dart';

import 'package:ldk/src/exceptions.dart';

/// HTTP client wrapper for Strapi API communication.
class LDKHttpClient {
  /// Creates a new [LDKHttpClient] instance.
  LDKHttpClient({
    required String baseUrl,
    String? authToken,
    bool enableLogging = false,
    Duration? connectTimeout,
    Duration? receiveTimeout,
  }) : _dio = Dio() {
    _dio.options.baseUrl = baseUrl;
    _dio.options.connectTimeout = connectTimeout ?? const Duration(seconds: 30);
    _dio.options.receiveTimeout = receiveTimeout ?? const Duration(seconds: 30);
    _dio.options.headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    if (authToken != null) {
      setAuthToken(authToken);
    }

    if (enableLogging) {
      _dio.interceptors.add(LogInterceptor(
        requestBody: true,
        responseBody: true,
        requestHeader: true,
        responseHeader: true,
        error: true,
        logPrint: (object) => _logger.d(object),
      ));
    }

    _dio.interceptors.add(InterceptorsWrapper(
      onError: _handleError,
    ));
  }

  final Dio _dio;
  final Logger _logger = Logger();

  /// Sets the authentication token for all requests.
  void setAuthToken(String token) {
    _dio.options.headers['Authorization'] = 'Bearer $token';
  }

  /// Removes the authentication token.
  void clearAuthToken() {
    _dio.options.headers.remove('Authorization');
  }

  /// Performs a GET request.
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    try {
      return await _dio.get<T>(
        path,
        queryParameters: queryParameters,
        options: options,
        cancelToken: cancelToken,
      );
    } catch (e) {
      throw _handleDioError(e);
    }
  }

  /// Performs a POST request.
  Future<Response<T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    try {
      return await _dio.post<T>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
        cancelToken: cancelToken,
      );
    } catch (e) {
      throw _handleDioError(e);
    }
  }

  /// Performs a PUT request.
  Future<Response<T>> put<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    try {
      return await _dio.put<T>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
        cancelToken: cancelToken,
      );
    } catch (e) {
      throw _handleDioError(e);
    }
  }

  /// Performs a DELETE request.
  Future<Response<T>> delete<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    try {
      return await _dio.delete<T>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
        cancelToken: cancelToken,
      );
    } catch (e) {
      throw _handleDioError(e);
    }
  }

  /// Uploads a file using multipart form data.
  Future<Response<T>> uploadFile<T>(
    String path,
    File file, {
    String fieldName = 'files',
    Map<String, dynamic>? data,
    ProgressCallback? onSendProgress,
    CancelToken? cancelToken,
  }) async {
    try {
      final formData = FormData();

      // Add the file
      formData.files.add(MapEntry(
        fieldName,
        await MultipartFile.fromFile(
          file.path,
          filename: file.path.split('/').last,
        ),
      ));

      // Add additional data if provided
      if (data != null) {
        for (final entry in data.entries) {
          formData.fields.add(MapEntry(entry.key, entry.value.toString()));
        }
      }

      return await _dio.post<T>(
        path,
        data: formData,
        onSendProgress: onSendProgress,
        cancelToken: cancelToken,
      );
    } catch (e) {
      throw _handleDioError(e);
    }
  }

  /// Uploads multiple files using multipart form data.
  Future<Response<T>> uploadFiles<T>(
    String path,
    List<File> files, {
    String fieldName = 'files',
    Map<String, dynamic>? data,
    ProgressCallback? onSendProgress,
    CancelToken? cancelToken,
  }) async {
    try {
      final formData = FormData();

      // Add all files
      for (final file in files) {
        formData.files.add(MapEntry(
          fieldName,
          await MultipartFile.fromFile(
            file.path,
            filename: file.path.split('/').last,
          ),
        ));
      }

      // Add additional data if provided
      if (data != null) {
        for (final entry in data.entries) {
          formData.fields.add(MapEntry(entry.key, entry.value.toString()));
        }
      }

      return await _dio.post<T>(
        path,
        data: formData,
        onSendProgress: onSendProgress,
        cancelToken: cancelToken,
      );
    } catch (e) {
      throw _handleDioError(e);
    }
  }

  /// Handles Dio errors and converts them to LDK exceptions.
  void _handleError(DioException err, ErrorInterceptorHandler handler) {
    handler.next(err);
  }

  /// Converts Dio errors to appropriate LDK exceptions.
  LDKException _handleDioError(Object error) {
    if (error is DioException) {
      final response = error.response;
      final statusCode = response?.statusCode;
      final data = response?.data;

      // Handle different types of errors
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return const LDKNetworkException('Request timeout');

        case DioExceptionType.badResponse:
          if (statusCode != null) {
            if (statusCode >= 400 && statusCode < 500) {
              // Client errors
              if (statusCode == 401) {
                return LDKAuthException(
                  _extractErrorMessage(data) ?? 'Authentication failed',
                  statusCode: statusCode,
                );
              } else if (statusCode == 400) {
                return LDKValidationException(
                  _extractErrorMessage(data) ?? 'Validation failed',
                  errors: _extractValidationErrors(data),
                );
              } else {
                return LDKServerException(
                  _extractErrorMessage(data) ?? 'Client error',
                  statusCode: statusCode,
                  errorDetails: data is Map<String, dynamic> ? data : null,
                );
              }
            } else if (statusCode >= 500) {
              // Server errors
              return LDKServerException(
                _extractErrorMessage(data) ?? 'Server error',
                statusCode: statusCode,
                errorDetails: data is Map<String, dynamic> ? data : null,
              );
            }
          }
          return LDKNetworkException(
            _extractErrorMessage(data) ?? 'HTTP error',
            statusCode: statusCode,
            originalError: error,
          );

        case DioExceptionType.cancel:
          return const LDKNetworkException('Request was cancelled');

        case DioExceptionType.connectionError:
          return const LDKNetworkException('Connection error');

        case DioExceptionType.badCertificate:
          return const LDKNetworkException('Bad certificate');

        case DioExceptionType.unknown:
        default:
          return LDKNetworkException(
            'Unknown network error: ${error.message}',
            originalError: error,
          );
      }
    }

    return LDKNetworkException(
      'Unexpected error: ${error.toString()}',
      originalError: error,
    );
  }

  /// Extracts error message from response data.
  String? _extractErrorMessage(dynamic data) {
    if (data is Map<String, dynamic>) {
      // Try different common error message fields
      return data['message'] as String? ??
          data['error'] as String? ??
          data['detail'] as String? ??
          (data['error'] as Map<String, dynamic>?)?['message'] as String?;
    }
    return null;
  }

  /// Extracts validation errors from response data.
  Map<String, List<String>>? _extractValidationErrors(dynamic data) {
    if (data is Map<String, dynamic>) {
      final details = data['details'] as Map<String, dynamic>?;
      if (details != null && details['errors'] is List) {
        final errors = <String, List<String>>{};
        for (final error in details['errors'] as List) {
          if (error is Map<String, dynamic>) {
            final path = error['path'] as List?;
            final message = error['message'] as String?;
            if (path != null && path.isNotEmpty && message != null) {
              final field = path.join('.');
              errors[field] = [...(errors[field] ?? []), message];
            }
          }
        }
        return errors.isNotEmpty ? errors : null;
      }
    }
    return null;
  }

  /// Closes the HTTP client and cleans up resources.
  void close() {
    _dio.close();
  }
}
