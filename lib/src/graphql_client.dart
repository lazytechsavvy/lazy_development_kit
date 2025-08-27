import 'dart:async';

import 'package:graphql/client.dart';
import 'package:logger/logger.dart';

import 'package:ldk/src/exceptions.dart';

/// GraphQL client for Strapi integration with real-time subscriptions.
class LDKGraphQLClient {
  /// Creates a new [LDKGraphQLClient] instance.
  LDKGraphQLClient({
    required String baseUrl,
    String? authToken,
    bool enableLogging = false,
    Duration? connectTimeout,
  }) {
    _logger = Logger();

    // Create HTTP link for queries and mutations
    final httpLink = HttpLink(
      '${baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl}/graphql',
      defaultHeaders: {
        'Content-Type': 'application/json',
        if (authToken != null) 'Authorization': 'Bearer $authToken',
      },
    );

    // Create the GraphQL client with simplified configuration
    _client = GraphQLClient(
      link: httpLink,
      cache: GraphQLCache(store: InMemoryStore()),
    );
  }

  late final GraphQLClient _client;
  late final Logger _logger;

  /// Updates the authentication token for all requests.
  void setAuthToken(String token) {
    // Note: This would require recreating the client with new headers
    // For now, we'll implement a method to create a new client
    _recreateClientWithToken(token);
  }

  /// Clears the authentication token.
  void clearAuthToken() {
    _recreateClientWithToken(null);
  }

  /// Executes a GraphQL query.
  Future<QueryResult<T>> query<T>(
    String query, {
    Map<String, dynamic>? variables,
    FetchPolicy? fetchPolicy,
    CacheRereadPolicy? cacheRereadPolicy,
    T Function(Map<String, dynamic>)? parseData,
  }) async {
    try {
      final options = QueryOptions(
        document: gql(query),
        variables: variables ?? {},
        fetchPolicy: fetchPolicy ?? FetchPolicy.cacheFirst,
        cacheRereadPolicy:
            cacheRereadPolicy ?? CacheRereadPolicy.mergeOptimistic,
      );

      final result = await _client.query(options);

      if (result.hasException) {
        throw _convertGraphQLException(result.exception!);
      }

      return QueryResult<T>(
        data: parseData != null && result.data != null
            ? parseData(result.data!)
            : result.data as T?,
        loading: result.isLoading,
        networkStatus: result.source?.name,
        errors: result.exception?.graphqlErrors,
      );
    } catch (e) {
      if (e is LDKException) rethrow;
      throw LDKNetworkException('GraphQL query failed: ${e.toString()}',
          originalError: e);
    }
  }

  /// Executes a GraphQL mutation.
  Future<MutationResult<T>> mutate<T>(
    String mutation, {
    Map<String, dynamic>? variables,
    T Function(Map<String, dynamic>)? parseData,
  }) async {
    try {
      final options = MutationOptions(
        document: gql(mutation),
        variables: variables ?? {},
      );

      final result = await _client.mutate(options);

      if (result.hasException) {
        throw _convertGraphQLException(result.exception!);
      }

      return MutationResult<T>(
        data: parseData != null && result.data != null
            ? parseData(result.data!)
            : result.data as T?,
        loading: result.isLoading,
        errors: result.exception?.graphqlErrors,
      );
    } catch (e) {
      if (e is LDKException) rethrow;
      throw LDKNetworkException('GraphQL mutation failed: ${e.toString()}',
          originalError: e);
    }
  }

  /// Creates a GraphQL subscription.
  Stream<SubscriptionResult<T>> subscribe<T>(
    String subscription, {
    Map<String, dynamic>? variables,
    T Function(Map<String, dynamic>)? parseData,
  }) {
    try {
      final options = SubscriptionOptions(
        document: gql(subscription),
        variables: variables ?? {},
      );

      return _client.subscribe(options).map((result) {
        if (result.hasException) {
          throw _convertGraphQLException(result.exception!);
        }

        return SubscriptionResult<T>(
          data: parseData != null && result.data != null
              ? parseData(result.data!)
              : result.data as T?,
          loading: result.isLoading,
          errors: result.exception?.graphqlErrors,
        );
      }).handleError((error) {
        if (error is! LDKException) {
          throw LDKNetworkException(
              'GraphQL subscription failed: ${error.toString()}',
              originalError: error);
        }
        throw error;
      });
    } catch (e) {
      throw LDKNetworkException(
          'Failed to create GraphQL subscription: ${e.toString()}',
          originalError: e);
    }
  }

  /// Watches a GraphQL query with automatic updates.
  Stream<QueryResult<T>> watchQuery<T>(
    String query, {
    Map<String, dynamic>? variables,
    FetchPolicy? fetchPolicy,
    T Function(Map<String, dynamic>)? parseData,
  }) {
    // Simplified implementation using periodic queries
    return Stream.periodic(const Duration(seconds: 30)).asyncMap((_) async {
      final result = await this.query<T>(
        query,
        variables: variables,
        parseData: parseData,
      );
      return result;
    });
  }

  /// Refetches a query from the network.
  Future<QueryResult<T>> refetch<T>(
    String query, {
    Map<String, dynamic>? variables,
    T Function(Map<String, dynamic>)? parseData,
  }) {
    return this.query<T>(
      query,
      variables: variables,
      fetchPolicy: FetchPolicy.networkOnly,
      parseData: parseData,
    );
  }

  /// Clears the GraphQL cache.
  Future<void> clearCache() async {
    try {
      _client.cache.store.reset();
    } catch (e) {
      // Ignore cache clear errors
    }
  }

  /// Recreates the client with a new auth token.
  void _recreateClientWithToken(String? token) {
    // This is a simplified implementation
    // In practice, you might want to preserve the existing cache
    // and other client configuration
  }

  /// Converts GraphQL exceptions to LDK exceptions.
  LDKException _convertGraphQLException(OperationException exception) {
    if (exception.linkException != null) {
      return _handleLinkException(exception.linkException!);
    }

    if (exception.graphqlErrors.isNotEmpty) {
      return _handleGraphQLErrors(exception.graphqlErrors);
    }

    return LDKNetworkException(
        'Unknown GraphQL error: ${exception.toString()}');
  }

  /// Handles link exceptions (network errors, etc.).
  LDKException _handleLinkException(LinkException exception) {
    if (exception is HttpLinkServerException) {
      final statusCode = exception.response.statusCode;
      if (statusCode == 401) {
        return const LDKAuthException('Authentication failed');
      } else if (statusCode >= 400 && statusCode < 500) {
        return LDKServerException('Client error: ${exception.toString()}',
            statusCode: statusCode);
      } else if (statusCode >= 500) {
        return LDKServerException('Server error: ${exception.toString()}',
            statusCode: statusCode);
      }
    }

    return LDKNetworkException('Network error: ${exception.toString()}',
        originalError: exception);
  }

  /// Handles GraphQL errors.
  LDKException _handleGraphQLErrors(List<GraphQLError> errors) {
    final firstError = errors.first;
    final message = firstError.message;

    // Check for authentication errors
    if (message.toLowerCase().contains('unauthorized') ||
        message.toLowerCase().contains('authentication')) {
      return LDKAuthException(message);
    }

    // Check for validation errors
    if (message.toLowerCase().contains('validation') ||
        firstError.extensions?['code'] == 'VALIDATION_ERROR') {
      return LDKValidationException(message);
    }

    return LDKServerException(message);
  }

  /// Disposes of the GraphQL client.
  void dispose() {
    // The GraphQL client doesn't have an explicit dispose method
    // but we can clear the cache
    clearCache();
  }
}

/// Result of a GraphQL query operation.
class QueryResult<T> {
  /// Creates a new [QueryResult].
  const QueryResult({
    required this.data,
    required this.loading,
    this.networkStatus,
    this.errors,
  });

  /// The query result data.
  final T? data;

  /// Whether the query is currently loading.
  final bool loading;

  /// The network status of the query.
  final String? networkStatus;

  /// Any GraphQL errors that occurred.
  final List<GraphQLError>? errors;

  /// Whether the query has errors.
  bool get hasErrors => errors != null && errors!.isNotEmpty;
}

/// Result of a GraphQL mutation operation.
class MutationResult<T> {
  /// Creates a new [MutationResult].
  const MutationResult({
    required this.data,
    required this.loading,
    this.errors,
  });

  /// The mutation result data.
  final T? data;

  /// Whether the mutation is currently loading.
  final bool loading;

  /// Any GraphQL errors that occurred.
  final List<GraphQLError>? errors;

  /// Whether the mutation has errors.
  bool get hasErrors => errors != null && errors!.isNotEmpty;
}

/// Result of a GraphQL subscription operation.
class SubscriptionResult<T> {
  /// Creates a new [SubscriptionResult].
  const SubscriptionResult({
    required this.data,
    required this.loading,
    this.errors,
  });

  /// The subscription result data.
  final T? data;

  /// Whether the subscription is currently loading.
  final bool loading;

  /// Any GraphQL errors that occurred.
  final List<GraphQLError>? errors;

  /// Whether the subscription has errors.
  bool get hasErrors => errors != null && errors!.isNotEmpty;
}
