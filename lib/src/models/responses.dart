import 'package:json_annotation/json_annotation.dart';

part 'responses.g.dart';

/// Base response structure from Strapi API.
@JsonSerializable(genericArgumentFactories: true)
class StrapiResponse<T> {
  /// Creates a new [StrapiResponse] instance.
  const StrapiResponse({
    required this.data,
    this.meta,
  });

  /// Creates a [StrapiResponse] from a JSON map.
  factory StrapiResponse.fromJson(
    Map<String, dynamic> json,
    T Function(Object? json) fromJsonT,
  ) =>
      _$StrapiResponseFromJson(json, fromJsonT);

  /// The response data.
  final T data;

  /// Metadata about the response (pagination, etc.).
  final StrapiMeta? meta;

  /// Converts the response to a JSON map.
  Map<String, dynamic> toJson(Object? Function(T value) toJsonT) =>
      _$StrapiResponseToJson(this, toJsonT);
}

/// Metadata structure for Strapi responses.
@JsonSerializable()
class StrapiMeta {
  /// Creates a new [StrapiMeta] instance.
  const StrapiMeta({
    this.pagination,
  });

  /// Creates a [StrapiMeta] from a JSON map.
  factory StrapiMeta.fromJson(Map<String, dynamic> json) =>
      _$StrapiMetaFromJson(json);

  /// Pagination information.
  final StrapiPagination? pagination;

  /// Converts the metadata to a JSON map.
  Map<String, dynamic> toJson() => _$StrapiMetaToJson(this);
}

/// Pagination information from Strapi.
@JsonSerializable()
class StrapiPagination {
  /// Creates a new [StrapiPagination] instance.
  const StrapiPagination({
    required this.page,
    required this.pageSize,
    required this.pageCount,
    required this.total,
  });

  /// Creates a [StrapiPagination] from a JSON map.
  factory StrapiPagination.fromJson(Map<String, dynamic> json) =>
      _$StrapiPaginationFromJson(json);

  /// Current page number.
  final int page;

  /// Number of items per page.
  final int pageSize;

  /// Total number of pages.
  final int pageCount;

  /// Total number of items.
  final int total;

  /// Converts the pagination to a JSON map.
  Map<String, dynamic> toJson() => _$StrapiPaginationToJson(this);
}

/// Authentication response from Strapi.
@JsonSerializable()
class AuthResponse {
  /// Creates a new [AuthResponse] instance.
  const AuthResponse({
    required this.jwt,
    required this.user,
  });

  /// Creates an [AuthResponse] from a JSON map.
  factory AuthResponse.fromJson(Map<String, dynamic> json) =>
      _$AuthResponseFromJson(json);

  /// JWT token for authentication.
  final String jwt;

  /// User information.
  final Map<String, dynamic> user;

  /// Converts the auth response to a JSON map.
  Map<String, dynamic> toJson() => _$AuthResponseToJson(this);
}

/// Error response from Strapi API.
@JsonSerializable()
class StrapiError {
  /// Creates a new [StrapiError] instance.
  const StrapiError({
    required this.status,
    required this.name,
    required this.message,
    this.details,
  });

  /// Creates a [StrapiError] from a JSON map.
  factory StrapiError.fromJson(Map<String, dynamic> json) =>
      _$StrapiErrorFromJson(json);

  /// HTTP status code.
  final int status;

  /// Error name/type.
  final String name;

  /// Error message.
  final String message;

  /// Additional error details.
  final Map<String, dynamic>? details;

  /// Converts the error to a JSON map.
  Map<String, dynamic> toJson() => _$StrapiErrorToJson(this);

  @override
  String toString() {
    return 'StrapiError(status: $status, name: $name, message: $message)';
  }
}
