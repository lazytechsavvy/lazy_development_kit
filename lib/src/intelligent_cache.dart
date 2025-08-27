import 'dart:async';
import 'dart:convert';

import 'package:logger/logger.dart';
import 'package:rxdart/rxdart.dart';

import 'package:ldk/src/exceptions.dart';
import 'package:ldk/src/models/responses.dart';
import 'package:ldk/src/offline_storage.dart';

/// Intelligent caching layer with smart cache strategies and automatic invalidation.
class LDKIntelligentCache {
  /// Creates a new [LDKIntelligentCache] instance.
  LDKIntelligentCache(this._offlineStorage) {
    _logger = Logger();
    _cacheStatsController =
        BehaviorSubject<CacheStats>.seeded(CacheStats.empty());
    _cacheEventsController = BehaviorSubject<CacheEvent?>();

    _initializeCache();
  }

  final LDKOfflineStorage _offlineStorage;
  late final Logger _logger;
  late final BehaviorSubject<CacheStats> _cacheStatsController;
  late final BehaviorSubject<CacheEvent?> _cacheEventsController;

  final Map<String, CacheStrategy> _cacheStrategies = {};
  final Map<String, Timer> _invalidationTimers = {};
  final Map<String, Set<String>> _taggedKeys = {};

  CacheStats _stats = CacheStats.empty();

  /// Stream of cache statistics.
  Stream<CacheStats> get cacheStatsStream => _cacheStatsController.stream;

  /// Stream of cache events.
  Stream<CacheEvent?> get cacheEventsStream => _cacheEventsController.stream;

  /// Current cache statistics.
  CacheStats get cacheStats => _stats;

  /// Initializes the intelligent cache.
  void _initializeCache() {
    // Set up default cache strategies
    _setupDefaultStrategies();

    // Start cache cleanup timer
    Timer.periodic(const Duration(minutes: 15), (_) {
      _performMaintenanceTasks();
    });

    _logger.i('Intelligent cache initialized');
  }

  /// Sets up default cache strategies for different data types.
  void _setupDefaultStrategies() {
    // User data - cache with medium TTL and refresh on access
    setCacheStrategy(
        'user',
        CacheStrategy(
          ttl: const Duration(minutes: 30),
          maxSize: 100,
          evictionPolicy: EvictionPolicy.lru,
          refreshOnAccess: true,
          backgroundRefresh: true,
        ));

    // Collection queries - cache with short TTL and refresh in background
    setCacheStrategy(
        'collection',
        CacheStrategy(
          ttl: const Duration(minutes: 15),
          maxSize: 500,
          evictionPolicy: EvictionPolicy.lfu,
          refreshOnAccess: false,
          backgroundRefresh: true,
        ));

    // Individual entries - cache with longer TTL
    setCacheStrategy(
        'entry',
        CacheStrategy(
          ttl: const Duration(hours: 1),
          maxSize: 1000,
          evictionPolicy: EvictionPolicy.lru,
          refreshOnAccess: true,
          backgroundRefresh: false,
        ));

    // File metadata - cache for long periods
    setCacheStrategy(
        'file',
        CacheStrategy(
          ttl: const Duration(hours: 6),
          maxSize: 200,
          evictionPolicy: EvictionPolicy.fifo,
          refreshOnAccess: false,
          backgroundRefresh: false,
        ));
  }

  /// Sets a cache strategy for a specific data type.
  void setCacheStrategy(String dataType, CacheStrategy strategy) {
    _cacheStrategies[dataType] = strategy;
    _logger.d('Cache strategy set for $dataType: ${strategy.toString()}');
  }

  /// Caches data with intelligent strategy selection.
  Future<void> set<T>(
    String key,
    T data, {
    String? dataType,
    Duration? customTtl,
    Set<String>? tags,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final strategy = _getCacheStrategy(dataType ?? _inferDataType(key));
      final ttl = customTtl ?? strategy.ttl;

      // Store data using offline storage
      await _offlineStorage.cacheData(
        key,
        data,
        ttl: ttl,
        metadata: {
          'dataType': dataType ?? _inferDataType(key),
          'strategy': strategy.toJson(),
          'tags': tags?.toList() ?? [],
          ...?metadata,
        },
      );

      // Update tags mapping
      if (tags != null) {
        for (final tag in tags) {
          _taggedKeys[tag] ??= <String>{};
          _taggedKeys[tag]!.add(key);
        }
      }

      // Schedule invalidation if needed
      if (strategy.autoInvalidate && ttl != null) {
        _scheduleInvalidation(key, ttl);
      }

      // Update statistics
      _updateStats(hit: false, write: true);

      // Emit cache event
      _cacheEventsController.add(CacheEvent(
        type: CacheEventType.set,
        key: key,
        dataType: dataType,
        timestamp: DateTime.now(),
      ));

      _logger
          .d('Cached data for key: $key with strategy: ${strategy.toString()}');
    } catch (e) {
      throw LDKServerException('Failed to cache data: ${e.toString()}');
    }
  }

  /// Retrieves cached data with intelligent refresh logic.
  Future<T?> get<T>(
    String key, {
    String? dataType,
    Future<T> Function()? refreshFunction,
  }) async {
    try {
      final strategy = _getCacheStrategy(dataType ?? _inferDataType(key));

      // Try to get from cache
      final cachedData = await _offlineStorage.getCachedData<T>(key);

      if (cachedData != null) {
        _updateStats(hit: true, write: false);

        // Check if we should refresh in background
        if (strategy.backgroundRefresh && refreshFunction != null) {
          _refreshInBackground(key, refreshFunction, strategy);
        }

        // Emit cache event
        _cacheEventsController.add(CacheEvent(
          type: CacheEventType.hit,
          key: key,
          dataType: dataType,
          timestamp: DateTime.now(),
        ));

        return cachedData;
      }

      // Cache miss
      _updateStats(hit: false, write: false);

      // Try to refresh if function provided
      if (refreshFunction != null) {
        final freshData = await refreshFunction();

        // Cache the fresh data
        await set<T>(key, freshData, dataType: dataType);

        return freshData;
      }

      // Emit cache event
      _cacheEventsController.add(CacheEvent(
        type: CacheEventType.miss,
        key: key,
        dataType: dataType,
        timestamp: DateTime.now(),
      ));

      return null;
    } catch (e) {
      _logger.e('Failed to get cached data for key $key: $e');
      return null;
    }
  }

  /// Caches a collection query with intelligent strategies.
  Future<void> cacheCollectionQuery(
    String collection,
    Map<String, dynamic> queryParams,
    StrapiResponse<List<Map<String, dynamic>>> response, {
    Duration? customTtl,
  }) async {
    final key = _generateCollectionKey(collection, queryParams);
    await set(
      key,
      response,
      dataType: 'collection',
      customTtl: customTtl,
      tags: {'collection:$collection', 'query'},
      metadata: {
        'collection': collection,
        'queryParams': queryParams,
        'resultCount': response.data.length,
      },
    );
  }

  /// Retrieves cached collection query.
  Future<StrapiResponse<List<Map<String, dynamic>>>?> getCachedCollectionQuery(
    String collection,
    Map<String, dynamic> queryParams, {
    Future<StrapiResponse<List<Map<String, dynamic>>>> Function()?
        refreshFunction,
  }) async {
    final key = _generateCollectionKey(collection, queryParams);
    return get<StrapiResponse<List<Map<String, dynamic>>>>(
      key,
      dataType: 'collection',
      refreshFunction: refreshFunction,
    );
  }

  /// Caches an individual entry.
  Future<void> cacheEntry(
    String collection,
    dynamic id,
    Map<String, dynamic> data, {
    Duration? customTtl,
  }) async {
    final key = 'entry:$collection:$id';
    await set(
      key,
      data,
      dataType: 'entry',
      customTtl: customTtl,
      tags: {'collection:$collection', 'entry', 'entry:$collection:$id'},
      metadata: {
        'collection': collection,
        'entryId': id,
      },
    );
  }

  /// Retrieves cached entry.
  Future<Map<String, dynamic>?> getCachedEntry(
    String collection,
    dynamic id, {
    Future<Map<String, dynamic>> Function()? refreshFunction,
  }) async {
    final key = 'entry:$collection:$id';
    return get<Map<String, dynamic>>(
      key,
      dataType: 'entry',
      refreshFunction: refreshFunction,
    );
  }

  /// Invalidates cache by key.
  Future<void> invalidate(String key) async {
    try {
      await _offlineStorage.getCachedData(key); // This will remove if expired

      // Cancel scheduled invalidation
      _invalidationTimers[key]?.cancel();
      _invalidationTimers.remove(key);

      // Remove from tag mappings
      _removeFromTagMappings(key);

      _logger.d('Invalidated cache for key: $key');

      // Emit cache event
      _cacheEventsController.add(CacheEvent(
        type: CacheEventType.invalidate,
        key: key,
        timestamp: DateTime.now(),
      ));
    } catch (e) {
      _logger.e('Failed to invalidate cache for key $key: $e');
    }
  }

  /// Invalidates cache by tag.
  Future<void> invalidateByTag(String tag) async {
    final keys = _taggedKeys[tag];
    if (keys == null) return;

    final futures = keys.map((key) => invalidate(key));
    await Future.wait(futures);

    _taggedKeys.remove(tag);

    _logger.d('Invalidated ${keys.length} cache entries with tag: $tag');
  }

  /// Invalidates all cache entries for a collection.
  Future<void> invalidateCollection(String collection) async {
    await invalidateByTag('collection:$collection');
  }

  /// Invalidates all cache entries.
  Future<void> invalidateAll() async {
    await _offlineStorage.clearCache();

    // Cancel all timers
    for (final timer in _invalidationTimers.values) {
      timer.cancel();
    }
    _invalidationTimers.clear();
    _taggedKeys.clear();

    // Reset stats
    _stats = CacheStats.empty();
    _cacheStatsController.add(_stats);

    _logger.i('All cache invalidated');

    // Emit cache event
    _cacheEventsController.add(CacheEvent(
      type: CacheEventType.clear,
      timestamp: DateTime.now(),
    ));
  }

  /// Preloads data into cache.
  Future<void> preload<T>(
    String key,
    Future<T> Function() loadFunction, {
    String? dataType,
    Duration? customTtl,
  }) async {
    try {
      final data = await loadFunction();
      await set(key, data, dataType: dataType, customTtl: customTtl);

      _logger.d('Preloaded data for key: $key');
    } catch (e) {
      _logger.e('Failed to preload data for key $key: $e');
    }
  }

  /// Warms up cache with commonly accessed data.
  Future<void> warmUp(
      Map<String, Future<dynamic> Function()> preloadMap) async {
    final futures =
        preloadMap.entries.map((entry) => preload(entry.key, entry.value));

    await Future.wait(futures);
    _logger.i('Cache warmed up with ${preloadMap.length} entries');
  }

  /// Gets cache strategy for a data type.
  CacheStrategy _getCacheStrategy(String dataType) {
    return _cacheStrategies[dataType] ?? CacheStrategy.defaultStrategy();
  }

  /// Infers data type from cache key.
  String _inferDataType(String key) {
    if (key.startsWith('user:')) return 'user';
    if (key.startsWith('collection:')) return 'collection';
    if (key.startsWith('entry:')) return 'entry';
    if (key.startsWith('file:')) return 'file';
    return 'unknown';
  }

  /// Generates a cache key for collection queries.
  String _generateCollectionKey(
      String collection, Map<String, dynamic> queryParams) {
    final sortedParams = Map<String, dynamic>.from(queryParams);
    final keys = sortedParams.keys.toList()..sort();
    final normalizedParams = <String, dynamic>{};

    for (final key in keys) {
      normalizedParams[key] = sortedParams[key];
    }

    final paramsString = jsonEncode(normalizedParams);
    final hash = paramsString.hashCode.toString();

    return 'collection:$collection:$hash';
  }

  /// Refreshes data in background.
  void _refreshInBackground<T>(
    String key,
    Future<T> Function() refreshFunction,
    CacheStrategy strategy,
  ) {
    // Don't refresh too frequently
    if (_invalidationTimers.containsKey('${key}_refresh')) return;

    _invalidationTimers['${key}_refresh'] = Timer(
      const Duration(seconds: 5),
      () async {
        try {
          final freshData = await refreshFunction();
          await set(key, freshData);

          _logger.d('Background refresh completed for key: $key');
        } catch (e) {
          _logger.e('Background refresh failed for key $key: $e');
        } finally {
          _invalidationTimers.remove('${key}_refresh');
        }
      },
    );
  }

  /// Schedules cache invalidation.
  void _scheduleInvalidation(String key, Duration ttl) {
    _invalidationTimers[key]?.cancel();

    _invalidationTimers[key] = Timer(ttl, () {
      invalidate(key);
    });
  }

  /// Removes key from tag mappings.
  void _removeFromTagMappings(String key) {
    for (final tagSet in _taggedKeys.values) {
      tagSet.remove(key);
    }
  }

  /// Updates cache statistics.
  void _updateStats({required bool hit, required bool write}) {
    if (hit) {
      _stats = _stats.copyWith(hits: _stats.hits + 1);
    } else {
      _stats = _stats.copyWith(misses: _stats.misses + 1);
    }

    if (write) {
      _stats = _stats.copyWith(writes: _stats.writes + 1);
    }

    _cacheStatsController.add(_stats);
  }

  /// Performs maintenance tasks.
  Future<void> _performMaintenanceTasks() async {
    try {
      // Clean expired entries
      await _offlineStorage.clearExpiredCache();

      // Update statistics
      _stats = _stats.copyWith(lastCleanup: DateTime.now());
      _cacheStatsController.add(_stats);

      _logger.d('Cache maintenance completed');
    } catch (e) {
      _logger.e('Cache maintenance failed: $e');
    }
  }

  /// Disposes of resources.
  void dispose() {
    for (final timer in _invalidationTimers.values) {
      timer.cancel();
    }
    _invalidationTimers.clear();
    _taggedKeys.clear();

    _cacheStatsController.close();
    _cacheEventsController.close();
  }
}

/// Cache strategy configuration.
class CacheStrategy {
  /// Creates a new [CacheStrategy].
  const CacheStrategy({
    required this.ttl,
    required this.maxSize,
    required this.evictionPolicy,
    this.refreshOnAccess = false,
    this.backgroundRefresh = false,
    this.autoInvalidate = true,
  });

  /// Creates a default cache strategy.
  factory CacheStrategy.defaultStrategy() {
    return const CacheStrategy(
      ttl: Duration(minutes: 30),
      maxSize: 100,
      evictionPolicy: EvictionPolicy.lru,
      refreshOnAccess: false,
      backgroundRefresh: false,
      autoInvalidate: true,
    );
  }

  /// Time to live for cached entries.
  final Duration? ttl;

  /// Maximum number of entries to cache.
  final int maxSize;

  /// Eviction policy when cache is full.
  final EvictionPolicy evictionPolicy;

  /// Whether to refresh data when accessed.
  final bool refreshOnAccess;

  /// Whether to refresh data in background.
  final bool backgroundRefresh;

  /// Whether to automatically invalidate expired entries.
  final bool autoInvalidate;

  /// Converts strategy to JSON.
  Map<String, dynamic> toJson() {
    return {
      'ttl': ttl?.inMilliseconds,
      'maxSize': maxSize,
      'evictionPolicy': evictionPolicy.toString(),
      'refreshOnAccess': refreshOnAccess,
      'backgroundRefresh': backgroundRefresh,
      'autoInvalidate': autoInvalidate,
    };
  }

  @override
  String toString() {
    return 'CacheStrategy(ttl: $ttl, maxSize: $maxSize, evictionPolicy: $evictionPolicy)';
  }
}

/// Cache eviction policies.
enum EvictionPolicy {
  /// Least Recently Used.
  lru,

  /// Least Frequently Used.
  lfu,

  /// First In, First Out.
  fifo,

  /// Last In, First Out.
  lifo,
}

/// Cache statistics.
class CacheStats {
  /// Creates new [CacheStats].
  const CacheStats({
    required this.hits,
    required this.misses,
    required this.writes,
    this.lastCleanup,
  });

  /// Creates empty cache stats.
  factory CacheStats.empty() {
    return const CacheStats(hits: 0, misses: 0, writes: 0);
  }

  /// Number of cache hits.
  final int hits;

  /// Number of cache misses.
  final int misses;

  /// Number of cache writes.
  final int writes;

  /// Last cleanup timestamp.
  final DateTime? lastCleanup;

  /// Cache hit ratio.
  double get hitRatio {
    final total = hits + misses;
    return total > 0 ? hits / total : 0.0;
  }

  /// Total requests.
  int get totalRequests => hits + misses;

  /// Creates a copy with updated fields.
  CacheStats copyWith({
    int? hits,
    int? misses,
    int? writes,
    DateTime? lastCleanup,
  }) {
    return CacheStats(
      hits: hits ?? this.hits,
      misses: misses ?? this.misses,
      writes: writes ?? this.writes,
      lastCleanup: lastCleanup ?? this.lastCleanup,
    );
  }

  @override
  String toString() {
    return 'CacheStats(hits: $hits, misses: $misses, hitRatio: ${(hitRatio * 100).toStringAsFixed(1)}%)';
  }
}

/// Cache event for monitoring.
class CacheEvent {
  /// Creates a new [CacheEvent].
  const CacheEvent({
    required this.type,
    this.key,
    this.dataType,
    required this.timestamp,
  });

  /// Type of cache event.
  final CacheEventType type;

  /// Cache key (if applicable).
  final String? key;

  /// Data type (if applicable).
  final String? dataType;

  /// When the event occurred.
  final DateTime timestamp;

  @override
  String toString() {
    return 'CacheEvent(type: $type, key: $key, timestamp: $timestamp)';
  }
}

/// Types of cache events.
enum CacheEventType {
  /// Data was stored in cache.
  set,

  /// Cache hit occurred.
  hit,

  /// Cache miss occurred.
  miss,

  /// Cache entry was invalidated.
  invalidate,

  /// Cache was cleared.
  clear,

  /// Background refresh occurred.
  refresh,
}
