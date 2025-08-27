import 'dart:async';

import 'package:ldk/src/collection.dart';
import 'package:ldk/src/exceptions.dart';
import 'package:ldk/src/graphql_client.dart';
import 'package:ldk/src/intelligent_cache.dart';
import 'package:ldk/src/models/responses.dart';
import 'package:ldk/src/offline_storage.dart';
import 'package:ldk/src/realtime.dart';
import 'package:ldk/src/utils/query_builder.dart';

/// Enhanced collection with advanced querying, caching, and real-time features.
class LDKEnhancedCollection extends LDKCollection {
  /// Creates a new [LDKEnhancedCollection] instance.
  LDKEnhancedCollection(
    super.httpClient,
    super.collectionName, {
    LDKGraphQLClient? graphqlClient,
    LDKIntelligentCache? cache,
    LDKRealtime? realtime,
    LDKOfflineStorage? offlineStorage,
  })  : _graphqlClient = graphqlClient,
        _cache = cache,
        _realtime = realtime,
        _offlineStorage = offlineStorage;

  final LDKGraphQLClient? _graphqlClient;
  final LDKIntelligentCache? _cache;
  final LDKRealtime? _realtime;
  final LDKOfflineStorage? _offlineStorage;

  /// Fetches entries with intelligent caching.
  @override
  Future<StrapiResponse<List<Map<String, dynamic>>>> get({
    LDKQueryBuilder? query,
    bool useCache = true,
    bool forceRefresh = false,
  }) async {
    final queryParams = query?.toQueryParameters() ?? <String, String>{};

    // Try cache first if enabled
    if (useCache && !forceRefresh && _cache != null) {
      final cached = await _cache!.getCachedCollectionQuery(
        collectionName,
        queryParams,
        refreshFunction: () => _fetchFromNetwork(queryParams),
      );

      if (cached != null) {
        return cached;
      }
    }

    // Fetch from network
    final result = await _fetchFromNetwork(queryParams);

    // Cache the result
    if (useCache && _cache != null) {
      await _cache!.cacheCollectionQuery(collectionName, queryParams, result);
    }

    return result;
  }

  /// Fetches a single entry with intelligent caching.
  @override
  Future<Map<String, dynamic>> getById(
    dynamic id, {
    LDKQueryBuilder? query,
    bool useCache = true,
    bool forceRefresh = false,
  }) async {
    // Try cache first if enabled
    if (useCache && !forceRefresh && _cache != null) {
      final cached = await _cache!.getCachedEntry(
        collectionName,
        id,
        refreshFunction: () => _fetchEntryFromNetwork(id, query),
      );

      if (cached != null) {
        return cached;
      }
    }

    // Fetch from network
    final result = await _fetchEntryFromNetwork(id, query);

    // Cache the result
    if (useCache && _cache != null) {
      await _cache!.cacheEntry(collectionName, id, result);
    }

    return result;
  }

  /// Creates an entry with optimistic updates and offline support.
  @override
  Future<Map<String, dynamic>> create(
    Map<String, dynamic> data, {
    bool optimistic = true,
  }) async {
    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';

    // Optimistic update
    if (optimistic) {
      final optimisticData = {
        'id': tempId,
        'attributes': data,
        '_isOptimistic': true,
      };

      // Cache optimistic data
      if (_cache != null) {
        await _cache!.cacheEntry(collectionName, tempId, optimisticData);
        // Invalidate related queries
        await _cache!.invalidateCollection(collectionName);
      }
    }

    try {
      // Try to create online
      if (_offlineStorage?.isOnline ?? true) {
        final result = await super.create(data);

        // Replace optimistic data with real data
        if (optimistic && _cache != null) {
          await _cache!.invalidate('entry:$collectionName:$tempId');
          await _cache!.cacheEntry(collectionName, result['id'], result);
          await _cache!.invalidateCollection(collectionName);
        }

        return result;
      } else {
        // Queue for offline sync
        if (_offlineStorage != null) {
          await _offlineStorage!.addPendingOperation(
            OfflineOperation(
              id: 'create_${DateTime.now().millisecondsSinceEpoch}',
              type: OperationType.create,
              collection: collectionName,
              data: data,
              timestamp: DateTime.now(),
            ),
          );
        }

        // Return optimistic data for offline
        return {
          'id': tempId,
          'attributes': data,
          '_isPending': true,
        };
      }
    } catch (e) {
      // Remove optimistic data on error
      if (optimistic && _cache != null) {
        await _cache!.invalidate('entry:$collectionName:$tempId');
        await _cache!.invalidateCollection(collectionName);
      }
      rethrow;
    }
  }

  /// Updates an entry with optimistic updates and offline support.
  @override
  Future<Map<String, dynamic>> update(
    dynamic id,
    Map<String, dynamic> data, {
    bool optimistic = true,
  }) async {
    Map<String, dynamic>? originalData;

    // Store original data for rollback
    if (optimistic && _cache != null) {
      originalData = await _cache!.getCachedEntry(collectionName, id);
    }

    // Optimistic update
    if (optimistic && _cache != null) {
      final originalAttributes =
          originalData?['attributes'] as Map<String, dynamic>?;
      final optimisticData = {
        'id': id,
        'attributes': {
          ...?originalAttributes,
          ...data,
        },
        '_isOptimistic': true,
      };

      await _cache!.cacheEntry(collectionName, id, optimisticData);
      await _cache!.invalidateCollection(collectionName);
    }

    try {
      // Try to update online
      if (_offlineStorage?.isOnline ?? true) {
        final result = await super.update(id, data);

        // Update cache with real data
        if (_cache != null) {
          await _cache!.cacheEntry(collectionName, id, result);
          await _cache!.invalidateCollection(collectionName);
        }

        return result;
      } else {
        // Queue for offline sync
        if (_offlineStorage != null) {
          await _offlineStorage!.addPendingOperation(
            OfflineOperation(
              id: 'update_${id}_${DateTime.now().millisecondsSinceEpoch}',
              type: OperationType.update,
              collection: collectionName,
              entityId: id,
              data: data,
              timestamp: DateTime.now(),
            ),
          );
        }

        // Return optimistic data for offline
        final originalAttributes =
            originalData?['attributes'] as Map<String, dynamic>?;
        return {
          'id': id,
          'attributes': {
            ...?originalAttributes,
            ...data,
          },
          '_isPending': true,
        };
      }
    } catch (e) {
      // Rollback optimistic update on error
      if (optimistic && _cache != null) {
        if (originalData != null) {
          await _cache!.cacheEntry(collectionName, id, originalData);
        } else {
          await _cache!.invalidate('entry:$collectionName:$id');
        }
        await _cache!.invalidateCollection(collectionName);
      }
      rethrow;
    }
  }

  /// Deletes an entry with optimistic updates and offline support.
  @override
  Future<Map<String, dynamic>> delete(
    dynamic id, {
    bool optimistic = true,
  }) async {
    Map<String, dynamic>? originalData;

    // Store original data for rollback
    if (optimistic && _cache != null) {
      originalData = await _cache!.getCachedEntry(collectionName, id);
    }

    // Optimistic delete
    if (optimistic && _cache != null) {
      await _cache!.invalidate('entry:$collectionName:$id');
      await _cache!.invalidateCollection(collectionName);
    }

    try {
      // Try to delete online
      if (_offlineStorage?.isOnline ?? true) {
        final result = await super.delete(id);

        // Ensure cache is cleared
        if (_cache != null) {
          await _cache!.invalidate('entry:$collectionName:$id');
          await _cache!.invalidateCollection(collectionName);
        }

        return result;
      } else {
        // Queue for offline sync
        if (_offlineStorage != null) {
          await _offlineStorage!.addPendingOperation(
            OfflineOperation(
              id: 'delete_${id}_${DateTime.now().millisecondsSinceEpoch}',
              type: OperationType.delete,
              collection: collectionName,
              entityId: id,
              data: {},
              timestamp: DateTime.now(),
            ),
          );
        }

        // Return success for offline
        return {'id': id, '_isDeleted': true, '_isPending': true};
      }
    } catch (e) {
      // Rollback optimistic delete on error
      if (optimistic && _cache != null && originalData != null) {
        await _cache!.cacheEntry(collectionName, id, originalData);
        await _cache!.invalidateCollection(collectionName);
      }
      rethrow;
    }
  }

  /// Executes a GraphQL query.
  Future<T?> graphql<T>(
    String query, {
    Map<String, dynamic>? variables,
    T Function(Map<String, dynamic>)? parseData,
  }) async {
    if (_graphqlClient == null) {
      throw const LDKConfigurationException('GraphQL client not configured');
    }

    final result = await _graphqlClient!.query<T>(
      query,
      variables: variables,
      parseData: parseData,
    );

    return result.data;
  }

  /// Executes a GraphQL mutation.
  Future<T?> graphqlMutation<T>(
    String mutation, {
    Map<String, dynamic>? variables,
    T Function(Map<String, dynamic>)? parseData,
  }) async {
    if (_graphqlClient == null) {
      throw const LDKConfigurationException('GraphQL client not configured');
    }

    final result = await _graphqlClient!.mutate<T>(
      mutation,
      variables: variables,
      parseData: parseData,
    );

    return result.data;
  }

  /// Subscribes to real-time updates for this collection.
  Stream<CollectionEvent<Map<String, dynamic>>> subscribeToUpdates({
    Map<String, dynamic>? variables,
  }) {
    if (_realtime == null) {
      throw const LDKConfigurationException('Realtime client not configured');
    }

    return _realtime!.subscribeToCollection<Map<String, dynamic>>(
      collectionName,
      variables: variables,
    );
  }

  /// Subscribes to real-time updates for a specific entry.
  Stream<EntryEvent<Map<String, dynamic>>> subscribeToEntry(dynamic entryId) {
    if (_realtime == null) {
      throw const LDKConfigurationException('Realtime client not configured');
    }

    return _realtime!.subscribeToEntry<Map<String, dynamic>>(
      collectionName,
      entryId,
    );
  }

  /// Watches a query for changes with real-time updates.
  Stream<StrapiResponse<List<Map<String, dynamic>>>> watchQuery({
    LDKQueryBuilder? query,
    Duration refreshInterval = const Duration(seconds: 30),
  }) {
    final queryParams = query?.toQueryParameters() ?? <String, String>{};

    // Start with cached data if available
    final controller =
        StreamController<StrapiResponse<List<Map<String, dynamic>>>>();

    // Get initial data
    get(query: query).then((initialData) {
      controller.add(initialData);
    }).catchError((Object error) {
      controller.addError(error);
    });

    // Set up periodic refresh
    final timer = Timer.periodic(refreshInterval, (timer) {
      get(query: query, forceRefresh: true).then((refreshedData) {
        controller.add(refreshedData);
      }).catchError((Object error) {
        controller.addError(error);
      });
    });

    // Clean up on stream close
    controller.onCancel = () {
      timer.cancel();
    };

    return controller.stream;
  }

  /// Performs a full-text search.
  Future<StrapiResponse<List<Map<String, dynamic>>>> search(
    String searchTerm, {
    List<String>? searchFields,
    LDKQueryBuilder? additionalFilters,
    bool useCache = true,
  }) async {
    final searchQuery = LDKQueryBuilder();

    if (searchFields != null && searchFields.isNotEmpty) {
      // Search in specific fields
      final orConditions = searchFields
          .map((field) => LDKQueryBuilder().where(field, containsi: searchTerm))
          .toList();
      searchQuery.or(orConditions);
    } else {
      // Generic search (assumes a 'searchable' field or similar)
      searchQuery.where('searchable', containsi: searchTerm);
    }

    // Combine with additional filters
    if (additionalFilters != null) {
      searchQuery.and([additionalFilters]);
    }

    return get(query: searchQuery, useCache: useCache);
  }

  /// Aggregates data with grouping and calculations.
  Future<Map<String, dynamic>> aggregate({
    List<String>? groupBy,
    Map<String, AggregateFunction>? aggregates,
    LDKQueryBuilder? filters,
  }) async {
    if (_graphqlClient == null) {
      throw const LDKConfigurationException(
          'Aggregation requires GraphQL client');
    }

    // Build GraphQL aggregation query
    final aggregationFields = <String>[];

    if (groupBy != null) {
      aggregationFields.addAll(groupBy);
    }

    if (aggregates != null) {
      for (final entry in aggregates.entries) {
        final field = entry.key;
        final function = entry.value;
        aggregationFields.add('${function.name}($field)');
      }
    }

    final query = '''
      query ${collectionName}Aggregate {
        ${collectionName}Aggregate {
          ${aggregationFields.join('\n          ')}
        }
      }
    ''';

    final result = await _graphqlClient!.query<Map<String, dynamic>>(
      query,
      variables: filters?.build(),
    );

    return result.data ?? {};
  }

  /// Fetches data from network using REST API.
  Future<StrapiResponse<List<Map<String, dynamic>>>> _fetchFromNetwork(
    Map<String, String> queryParams,
  ) async {
    final response = await httpClient.get<Map<String, dynamic>>(
      '/api/$collectionName',
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
  }

  /// Fetches a single entry from network.
  Future<Map<String, dynamic>> _fetchEntryFromNetwork(
    dynamic id,
    LDKQueryBuilder? query,
  ) async {
    final queryParams = query?.toQueryParameters() ?? <String, String>{};

    final response = await httpClient.get<Map<String, dynamic>>(
      '/api/$collectionName/$id',
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
  }

  /// Invalidates all cached data for this collection.
  Future<void> invalidateCache() async {
    if (_cache != null) {
      await _cache!.invalidateCollection(collectionName);
    }
  }

  /// Preloads commonly accessed data.
  Future<void> preloadData({
    List<dynamic>? entryIds,
    List<LDKQueryBuilder>? commonQueries,
  }) async {
    if (_cache == null) return;

    final futures = <Future<void>>[];

    // Preload specific entries
    if (entryIds != null) {
      for (final id in entryIds) {
        futures.add(_cache!.preload(
          'entry:$collectionName:$id',
          () => getById(id, useCache: false),
        ));
      }
    }

    // Preload common queries
    if (commonQueries != null) {
      for (final query in commonQueries) {
        final queryParams = query.toQueryParameters();
        final key = 'collection:$collectionName:${queryParams.hashCode}';
        futures.add(_cache!.preload(
          key,
          () => get(query: query, useCache: false),
        ));
      }
    }

    await Future.wait(futures);
  }
}

/// Aggregate functions for data analysis.
enum AggregateFunction {
  /// Count of records.
  count,

  /// Sum of values.
  sum,

  /// Average of values.
  avg,

  /// Minimum value.
  min,

  /// Maximum value.
  max,

  /// Standard deviation.
  stddev,

  /// Variance.
  variance,
}
