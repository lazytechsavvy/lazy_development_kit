import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:logger/logger.dart';
import 'package:rxdart/rxdart.dart';

import 'package:ldk/src/exceptions.dart';
import 'package:ldk/src/models/responses.dart';

/// Offline storage service for caching and synchronization.
class LDKOfflineStorage {
  /// Creates a new [LDKOfflineStorage] instance.
  LDKOfflineStorage() {
    _logger = Logger();
    _connectivity = Connectivity();
    _isOnlineController = BehaviorSubject<bool>.seeded(true);
    _pendingOperationsController =
        BehaviorSubject<List<OfflineOperation>>.seeded([]);

    _initializeConnectivity();
  }

  late final Logger _logger;
  late final Connectivity _connectivity;
  late final BehaviorSubject<bool> _isOnlineController;
  late final BehaviorSubject<List<OfflineOperation>>
      _pendingOperationsController;

  static const String _cacheBoxName = 'ldk_cache';
  static const String _operationsBoxName = 'ldk_pending_operations';
  static const String _metadataBoxName = 'ldk_metadata';

  Box<dynamic>? _cacheBox;
  Box<Map<dynamic, dynamic>>? _operationsBox;
  Box<dynamic>? _metadataBox;

  /// Stream of online/offline status.
  Stream<bool> get isOnlineStream => _isOnlineController.stream;

  /// Stream of pending operations.
  Stream<List<OfflineOperation>> get pendingOperationsStream =>
      _pendingOperationsController.stream;

  /// Current online status.
  bool get isOnline => _isOnlineController.value;

  /// Current pending operations.
  List<OfflineOperation> get pendingOperations =>
      _pendingOperationsController.value;

  /// Initializes the offline storage.
  Future<void> initialize() async {
    try {
      await Hive.initFlutter();

      // Register adapters if not already registered
      if (!Hive.isAdapterRegistered(OfflineOperationAdapter().typeId)) {
        Hive.registerAdapter(OfflineOperationAdapter());
      }

      // Open boxes
      _cacheBox = await Hive.openBox(_cacheBoxName);
      _operationsBox =
          await Hive.openBox<Map<dynamic, dynamic>>(_operationsBoxName);
      _metadataBox = await Hive.openBox(_metadataBoxName);

      // Load pending operations
      await _loadPendingOperations();

      _logger.i('Offline storage initialized');
    } catch (e) {
      throw LDKConfigurationException(
          'Failed to initialize offline storage: ${e.toString()}');
    }
  }

  /// Initializes connectivity monitoring.
  void _initializeConnectivity() {
    _connectivity.onConnectivityChanged.listen((ConnectivityResult result) {
      final isConnected = result != ConnectivityResult.none;
      _isOnlineController.add(isConnected);

      if (isConnected) {
        _logger.i('Connection restored, syncing pending operations');
        _syncPendingOperations();
      } else {
        _logger.w('Connection lost, switching to offline mode');
      }
    });

    // Check initial connectivity
    _checkInitialConnectivity();
  }

  /// Checks initial connectivity status.
  Future<void> _checkInitialConnectivity() async {
    try {
      final result = await _connectivity.checkConnectivity();
      final isConnected = result != ConnectivityResult.none;
      _isOnlineController.add(isConnected);
    } catch (e) {
      _logger.e('Failed to check initial connectivity: $e');
    }
  }

  /// Caches data for a specific key.
  Future<void> cacheData(
    String key,
    dynamic data, {
    Duration? ttl,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      _ensureInitialized();

      final cacheEntry = CacheEntry(
        key: key,
        data: data,
        timestamp: DateTime.now(),
        ttl: ttl,
        metadata: metadata,
      );

      await _cacheBox!.put(key, cacheEntry.toJson());

      // Store metadata separately for efficient querying
      if (metadata != null) {
        await _metadataBox!.put('$key:metadata', metadata);
      }

      _logger.d('Cached data for key: $key');
    } catch (e) {
      throw LDKServerException('Failed to cache data: ${e.toString()}');
    }
  }

  /// Retrieves cached data for a specific key.
  Future<T?> getCachedData<T>(String key) async {
    try {
      _ensureInitialized();

      final cachedJson = _cacheBox!.get(key);
      if (cachedJson == null) return null;

      final cacheEntry =
          CacheEntry.fromJson(Map<String, dynamic>.from(cachedJson as Map));

      // Check if cache has expired
      if (cacheEntry.isExpired) {
        await _cacheBox!.delete(key);
        await _metadataBox!.delete('$key:metadata');
        _logger.d('Cache expired for key: $key');
        return null;
      }

      return cacheEntry.data as T?;
    } catch (e) {
      _logger.e('Failed to get cached data for key $key: $e');
      return null;
    }
  }

  /// Caches a collection query result.
  Future<void> cacheCollectionQuery(
    String collection,
    Map<String, dynamic> queryParams,
    StrapiResponse<List<Map<String, dynamic>>> response, {
    Duration? ttl,
  }) async {
    final queryHash = _generateQueryHash(collection, queryParams);
    await cacheData(
      'collection:$collection:$queryHash',
      response.toJson((data) => data),
      ttl: ttl ?? const Duration(minutes: 30),
      metadata: {
        'type': 'collection_query',
        'collection': collection,
        'queryParams': queryParams,
      },
    );
  }

  /// Retrieves cached collection query result.
  Future<StrapiResponse<List<Map<String, dynamic>>>?> getCachedCollectionQuery(
    String collection,
    Map<String, dynamic> queryParams,
  ) async {
    final queryHash = _generateQueryHash(collection, queryParams);
    final cachedData = await getCachedData<Map<String, dynamic>>(
      'collection:$collection:$queryHash',
    );

    if (cachedData == null) return null;

    return StrapiResponse<List<Map<String, dynamic>>>.fromJson(
      cachedData,
      (json) => (json as List).cast<Map<String, dynamic>>(),
    );
  }

  /// Caches a single entry.
  Future<void> cacheEntry(
    String collection,
    dynamic id,
    Map<String, dynamic> data, {
    Duration? ttl,
  }) async {
    await cacheData(
      'entry:$collection:$id',
      data,
      ttl: ttl ?? const Duration(hours: 1),
      metadata: {
        'type': 'entry',
        'collection': collection,
        'id': id,
      },
    );
  }

  /// Retrieves cached entry.
  Future<Map<String, dynamic>?> getCachedEntry(
    String collection,
    dynamic id,
  ) async {
    return getCachedData<Map<String, dynamic>>('entry:$collection:$id');
  }

  /// Adds an operation to the pending queue for offline sync.
  Future<void> addPendingOperation(OfflineOperation operation) async {
    try {
      _ensureInitialized();

      final operations = List<OfflineOperation>.from(pendingOperations);
      operations.add(operation);

      await _operationsBox!.put(operation.id, operation.toJson());
      _pendingOperationsController.add(operations);

      _logger.d('Added pending operation: ${operation.type}');

      // Try to sync immediately if online
      if (isOnline) {
        _syncPendingOperations();
      }
    } catch (e) {
      throw LDKServerException(
          'Failed to add pending operation: ${e.toString()}');
    }
  }

  /// Removes a pending operation.
  Future<void> removePendingOperation(String operationId) async {
    try {
      _ensureInitialized();

      await _operationsBox!.delete(operationId);

      final operations = List<OfflineOperation>.from(pendingOperations);
      operations.removeWhere((op) => op.id == operationId);
      _pendingOperationsController.add(operations);

      _logger.d('Removed pending operation: $operationId');
    } catch (e) {
      _logger.e('Failed to remove pending operation: $e');
    }
  }

  /// Loads pending operations from storage.
  Future<void> _loadPendingOperations() async {
    try {
      _ensureInitialized();

      final operations = <OfflineOperation>[];
      for (final key in _operationsBox!.keys) {
        final operationJson = _operationsBox!.get(key);
        if (operationJson != null) {
          final operation = OfflineOperation.fromJson(
            Map<String, dynamic>.from(operationJson),
          );
          operations.add(operation);
        }
      }

      // Sort by timestamp
      operations.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      _pendingOperationsController.add(operations);

      _logger.i('Loaded ${operations.length} pending operations');
    } catch (e) {
      _logger.e('Failed to load pending operations: $e');
    }
  }

  /// Syncs pending operations when online.
  Future<void> _syncPendingOperations() async {
    if (!isOnline || pendingOperations.isEmpty) return;

    _logger.i('Syncing ${pendingOperations.length} pending operations');

    final operations = List<OfflineOperation>.from(pendingOperations);

    for (final operation in operations) {
      try {
        // Execute the operation
        await _executeOperation(operation);

        // Remove from pending if successful
        await removePendingOperation(operation.id);

        _logger.d('Successfully synced operation: ${operation.id}');
      } catch (e) {
        _logger.e('Failed to sync operation ${operation.id}: $e');

        // Increment retry count
        final updatedOperation = operation.copyWith(
          retryCount: operation.retryCount + 1,
        );

        // Remove if max retries exceeded
        if (updatedOperation.retryCount >= 3) {
          await removePendingOperation(operation.id);
          _logger.w('Max retries exceeded for operation: ${operation.id}');
        } else {
          await _operationsBox!.put(operation.id, updatedOperation.toJson());
        }
      }
    }
  }

  /// Executes a pending operation.
  Future<void> _executeOperation(OfflineOperation operation) async {
    // This would typically delegate to the appropriate service
    // For now, we'll just simulate the operation
    await Future.delayed(const Duration(milliseconds: 100));

    switch (operation.type) {
      case OperationType.create:
        _logger.d('Executing CREATE operation for ${operation.collection}');
        break;
      case OperationType.update:
        _logger.d(
            'Executing UPDATE operation for ${operation.collection}:${operation.entityId}');
        break;
      case OperationType.delete:
        _logger.d(
            'Executing DELETE operation for ${operation.collection}:${operation.entityId}');
        break;
    }
  }

  /// Generates a hash for query parameters.
  String _generateQueryHash(
      String collection, Map<String, dynamic> queryParams) {
    final sortedParams = Map<String, dynamic>.from(queryParams);
    final keys = sortedParams.keys.toList()..sort();
    final normalizedParams = <String, dynamic>{};

    for (final key in keys) {
      normalizedParams[key] = sortedParams[key];
    }

    final paramsString = jsonEncode(normalizedParams);
    return paramsString.hashCode.toString();
  }

  /// Clears all cached data.
  Future<void> clearCache() async {
    try {
      _ensureInitialized();

      await _cacheBox!.clear();
      await _metadataBox!.clear();

      _logger.i('Cache cleared');
    } catch (e) {
      throw LDKServerException('Failed to clear cache: ${e.toString()}');
    }
  }

  /// Clears expired cache entries.
  Future<void> clearExpiredCache() async {
    try {
      _ensureInitialized();

      final keysToDelete = <String>[];

      for (final key in _cacheBox!.keys) {
        final cachedJson = _cacheBox!.get(key);
        if (cachedJson != null) {
          final cacheEntry = CacheEntry.fromJson(
            Map<String, dynamic>.from(cachedJson as Map),
          );

          if (cacheEntry.isExpired) {
            keysToDelete.add(key.toString());
          }
        }
      }

      for (final key in keysToDelete) {
        await _cacheBox!.delete(key);
        await _metadataBox!.delete('$key:metadata');
      }

      _logger.i('Cleared ${keysToDelete.length} expired cache entries');
    } catch (e) {
      _logger.e('Failed to clear expired cache: $e');
    }
  }

  /// Ensures that the storage is initialized.
  void _ensureInitialized() {
    if (_cacheBox == null || _operationsBox == null || _metadataBox == null) {
      throw const LDKConfigurationException('Offline storage not initialized');
    }
  }

  /// Disposes of resources.
  Future<void> dispose() async {
    await _cacheBox?.close();
    await _operationsBox?.close();
    await _metadataBox?.close();

    _isOnlineController.close();
    _pendingOperationsController.close();
  }
}

/// Represents a cache entry with metadata.
class CacheEntry {
  /// Creates a new [CacheEntry].
  const CacheEntry({
    required this.key,
    required this.data,
    required this.timestamp,
    this.ttl,
    this.metadata,
  });

  /// Creates a [CacheEntry] from JSON data.
  factory CacheEntry.fromJson(Map<String, dynamic> json) {
    return CacheEntry(
      key: json['key'] as String,
      data: json['data'],
      timestamp: DateTime.parse(json['timestamp'] as String),
      ttl: json['ttl'] != null
          ? Duration(milliseconds: json['ttl'] as int)
          : null,
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }

  /// The cache key.
  final String key;

  /// The cached data.
  final dynamic data;

  /// When the data was cached.
  final DateTime timestamp;

  /// Time to live for the cache entry.
  final Duration? ttl;

  /// Additional metadata.
  final Map<String, dynamic>? metadata;

  /// Whether the cache entry has expired.
  bool get isExpired {
    if (ttl == null) return false;
    return DateTime.now().difference(timestamp) > ttl!;
  }

  /// Converts the cache entry to JSON.
  Map<String, dynamic> toJson() {
    return {
      'key': key,
      'data': data,
      'timestamp': timestamp.toIso8601String(),
      'ttl': ttl?.inMilliseconds,
      'metadata': metadata,
    };
  }
}

/// Represents an offline operation that needs to be synced.
class OfflineOperation {
  /// Creates a new [OfflineOperation].
  const OfflineOperation({
    required this.id,
    required this.type,
    required this.collection,
    this.entityId,
    required this.data,
    required this.timestamp,
    this.retryCount = 0,
  });

  /// Creates an [OfflineOperation] from JSON data.
  factory OfflineOperation.fromJson(Map<String, dynamic> json) {
    return OfflineOperation(
      id: json['id'] as String,
      type: OperationType.values.firstWhere(
        (e) => e.toString() == json['type'],
      ),
      collection: json['collection'] as String,
      entityId: json['entityId'],
      data: json['data'] as Map<String, dynamic>,
      timestamp: DateTime.parse(json['timestamp'] as String),
      retryCount: json['retryCount'] as int? ?? 0,
    );
  }

  /// Unique identifier for the operation.
  final String id;

  /// Type of operation.
  final OperationType type;

  /// Collection name.
  final String collection;

  /// Entity ID (for update/delete operations).
  final dynamic entityId;

  /// Operation data.
  final Map<String, dynamic> data;

  /// When the operation was created.
  final DateTime timestamp;

  /// Number of retry attempts.
  final int retryCount;

  /// Creates a copy with updated fields.
  OfflineOperation copyWith({
    String? id,
    OperationType? type,
    String? collection,
    dynamic entityId,
    Map<String, dynamic>? data,
    DateTime? timestamp,
    int? retryCount,
  }) {
    return OfflineOperation(
      id: id ?? this.id,
      type: type ?? this.type,
      collection: collection ?? this.collection,
      entityId: entityId ?? this.entityId,
      data: data ?? this.data,
      timestamp: timestamp ?? this.timestamp,
      retryCount: retryCount ?? this.retryCount,
    );
  }

  /// Converts the operation to JSON.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.toString(),
      'collection': collection,
      'entityId': entityId,
      'data': data,
      'timestamp': timestamp.toIso8601String(),
      'retryCount': retryCount,
    };
  }
}

/// Types of offline operations.
enum OperationType {
  /// Create operation.
  create,

  /// Update operation.
  update,

  /// Delete operation.
  delete,
}

/// Hive adapter for OfflineOperation.
class OfflineOperationAdapter extends TypeAdapter<OfflineOperation> {
  @override
  final int typeId = 0;

  @override
  OfflineOperation read(BinaryReader reader) {
    return OfflineOperation.fromJson(
      Map<String, dynamic>.from(reader.readMap()),
    );
  }

  @override
  void write(BinaryWriter writer, OfflineOperation obj) {
    writer.writeMap(obj.toJson());
  }
}
