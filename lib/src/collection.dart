import 'dart:async';

import 'package:meta/meta.dart';

import 'package:strapi_ldk/src/exceptions.dart';
import 'package:strapi_ldk/src/models/responses.dart';
import 'package:strapi_ldk/src/utils/http_client.dart';
import 'package:strapi_ldk/src/utils/query_builder.dart';

/// Represents a Strapi collection for CRUD operations.
class LDKCollection {
  /// Creates a new [LDKCollection] instance.
  LDKCollection(this._httpClient, this.collectionName);

  final LDKHttpClient _httpClient;

  /// The name of the Strapi collection.
  final String collectionName;

  /// Gets the HTTP client for subclasses.
  @protected
  LDKHttpClient get httpClient => _httpClient;

  /// Gets the API endpoint for this collection.
  String get _endpoint => '/api/$collectionName';

  /// Fetches entries from the collection.
  Future<StrapiResponse<List<Map<String, dynamic>>>> get({
    LDKQueryBuilder? query,
  }) async {
    try {
      final queryParams = query?.toQueryParameters() ?? <String, String>{};

      final response = await _httpClient.get<Map<String, dynamic>>(
        _endpoint,
        queryParameters: queryParams,
      );

      if (response.data == null) {
        throw const LDKServerException('Invalid response from server');
      }

      return StrapiResponse<List<Map<String, dynamic>>>.fromJson(
        response.data!,
        (json) {
          if (json is List) {
            return json.cast<Map<String, dynamic>>();
          }
          throw const LDKServerException('Expected list in response data');
        },
      );
    } catch (e) {
      if (e is LDKException) rethrow;
      throw LDKServerException('Failed to fetch entries: ${e.toString()}');
    }
  }

  /// Fetches a single entry by ID.
  Future<Map<String, dynamic>> getById(
    dynamic id, {
    LDKQueryBuilder? query,
  }) async {
    try {
      final queryParams = query?.toQueryParameters() ?? <String, String>{};

      final response = await _httpClient.get<Map<String, dynamic>>(
        '$_endpoint/$id',
        queryParameters: queryParams,
      );

      if (response.data == null) {
        throw const LDKServerException('Invalid response from server');
      }

      final strapiResponse = StrapiResponse<Map<String, dynamic>>.fromJson(
        response.data!,
        (json) => json as Map<String, dynamic>,
      );

      return strapiResponse.data;
    } catch (e) {
      if (e is LDKException) rethrow;
      throw LDKServerException('Failed to fetch entry: ${e.toString()}');
    }
  }

  /// Creates a new entry in the collection.
  Future<Map<String, dynamic>> create(Map<String, dynamic> data) async {
    try {
      final response = await _httpClient.post<Map<String, dynamic>>(
        _endpoint,
        data: {'data': data},
      );

      if (response.data == null) {
        throw const LDKServerException('Invalid response from server');
      }

      final strapiResponse = StrapiResponse<Map<String, dynamic>>.fromJson(
        response.data!,
        (json) => json as Map<String, dynamic>,
      );

      return strapiResponse.data;
    } catch (e) {
      if (e is LDKException) rethrow;
      throw LDKServerException('Failed to create entry: ${e.toString()}');
    }
  }

  /// Updates an existing entry by ID.
  Future<Map<String, dynamic>> update(
    dynamic id,
    Map<String, dynamic> data,
  ) async {
    try {
      final response = await _httpClient.put<Map<String, dynamic>>(
        '$_endpoint/$id',
        data: {'data': data},
      );

      if (response.data == null) {
        throw const LDKServerException('Invalid response from server');
      }

      final strapiResponse = StrapiResponse<Map<String, dynamic>>.fromJson(
        response.data!,
        (json) => json as Map<String, dynamic>,
      );

      return strapiResponse.data;
    } catch (e) {
      if (e is LDKException) rethrow;
      throw LDKServerException('Failed to update entry: ${e.toString()}');
    }
  }

  /// Deletes an entry by ID.
  Future<Map<String, dynamic>> delete(dynamic id) async {
    try {
      final response = await _httpClient.delete<Map<String, dynamic>>(
        '$_endpoint/$id',
      );

      if (response.data == null) {
        throw const LDKServerException('Invalid response from server');
      }

      final strapiResponse = StrapiResponse<Map<String, dynamic>>.fromJson(
        response.data!,
        (json) => json as Map<String, dynamic>,
      );

      return strapiResponse.data;
    } catch (e) {
      if (e is LDKException) rethrow;
      throw LDKServerException('Failed to delete entry: ${e.toString()}');
    }
  }

  /// Creates a new query builder for this collection.
  LDKQueryBuilder query() => LDKQueryBuilder();

  /// Convenience method to create a query with a where condition.
  LDKQueryBuilder where(
    String field, {
    dynamic equals,
    dynamic notEquals,
    dynamic contains,
    dynamic notContains,
    dynamic containsi,
    dynamic notContainsi,
    dynamic startsWith,
    dynamic endsWith,
    dynamic greaterThan,
    dynamic greaterThanOrEqual,
    dynamic lessThan,
    dynamic lessThanOrEqual,
    List<dynamic>? isIn,
    List<dynamic>? notIn,
    bool? isNull,
    bool? isNotNull,
  }) {
    return query().where(
      field,
      equals: equals,
      notEquals: notEquals,
      contains: contains,
      notContains: notContains,
      containsi: containsi,
      notContainsi: notContainsi,
      startsWith: startsWith,
      endsWith: endsWith,
      greaterThan: greaterThan,
      greaterThanOrEqual: greaterThanOrEqual,
      lessThan: lessThan,
      lessThanOrEqual: lessThanOrEqual,
      isIn: isIn,
      notIn: notIn,
      isNull: isNull,
      isNotNull: isNotNull,
    );
  }

  /// Convenience method to create a query with sorting.
  LDKQueryBuilder sort(String field, {bool descending = false}) {
    return query().sort(field, descending: descending);
  }

  /// Convenience method to create a query with population.
  LDKQueryBuilder populate(String field) {
    return query().populate(field);
  }

  /// Convenience method to create a query with limit.
  LDKQueryBuilder limit(int count) {
    return query().limit(count);
  }

  /// Convenience method to create a query with pagination.
  LDKQueryBuilder paginate({required int page, required int pageSize}) {
    return query().paginate(page: page, pageSize: pageSize);
  }

  /// Counts the total number of entries in the collection.
  Future<int> count({LDKQueryBuilder? query}) async {
    try {
      final queryParams = query?.toQueryParameters() ?? <String, String>{};

      final response = await _httpClient.get<Map<String, dynamic>>(
        _endpoint,
        queryParameters: {
          ...queryParams,
          'pagination[limit]': '0', // Don't return data, just count
        },
      );

      if (response.data == null) {
        throw const LDKServerException('Invalid response from server');
      }

      final strapiResponse =
          StrapiResponse<List<Map<String, dynamic>>>.fromJson(
        response.data!,
        (json) => <Map<String, dynamic>>[],
      );

      return strapiResponse.meta?.pagination?.total ?? 0;
    } catch (e) {
      if (e is LDKException) rethrow;
      throw LDKServerException('Failed to count entries: ${e.toString()}');
    }
  }

  /// Checks if any entries exist matching the query.
  Future<bool> exists({LDKQueryBuilder? query}) async {
    final count = await this.count(query: query);
    return count > 0;
  }

  /// Finds the first entry matching the query.
  Future<Map<String, dynamic>?> findFirst({LDKQueryBuilder? query}) async {
    final queryBuilder = query ?? LDKQueryBuilder();
    queryBuilder.limit(1);

    final response = await get(query: queryBuilder);
    final data = response.data;

    return data.isNotEmpty ? data.first : null;
  }

  /// Finds the first entry matching the query or throws an exception.
  Future<Map<String, dynamic>> findFirstOrThrow(
      {LDKQueryBuilder? query}) async {
    final result = await findFirst(query: query);
    if (result == null) {
      throw const LDKServerException('No entry found matching the query');
    }
    return result;
  }

  @override
  String toString() {
    return 'LDKCollection(collectionName: $collectionName)';
  }
}
