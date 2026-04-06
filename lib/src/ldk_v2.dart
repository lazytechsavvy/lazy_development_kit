import 'dart:async';

import 'package:strapi_ldk/src/auth.dart';
import 'package:strapi_ldk/src/enhanced_auth.dart';
import 'package:strapi_ldk/src/enhanced_collection.dart';
import 'package:strapi_ldk/src/exceptions.dart';
import 'package:strapi_ldk/src/graphql_client.dart';
import 'package:strapi_ldk/src/intelligent_cache.dart';
import 'package:strapi_ldk/src/offline_storage.dart';
import 'package:strapi_ldk/src/realtime.dart';
import 'package:strapi_ldk/src/utils/http_client.dart';

/// Phase 2 implementation of LDK with advanced features.
class LDKV2 {
  LDKV2._internal();

  static LDKV2? _instance;
  LDKHttpClient? _httpClient;
  LDKAuth? _auth;
  LDKGraphQLClient? _graphqlClient;
  LDKIntelligentCache? _cache;
  LDKRealtime? _realtime;
  LDKOfflineStorage? _offlineStorage;
  LDKEnhancedAuth? _enhancedAuth;

  /// Gets the singleton instance of LDKV2.
  static LDKV2 get instance {
    _instance ??= LDKV2._internal();
    return _instance!;
  }

  /// Whether LDK has been initialized.
  bool get isInitialized => _httpClient != null;

  /// Gets the GraphQL client.
  LDKGraphQLClient get graphql {
    _ensureInitialized();
    if (_graphqlClient == null) {
      throw const LDKConfigurationException('GraphQL client not configured');
    }
    return _graphqlClient!;
  }

  /// Gets the intelligent cache.
  LDKIntelligentCache get cache {
    _ensureInitialized();
    if (_cache == null) {
      throw const LDKConfigurationException('Cache not configured');
    }
    return _cache!;
  }

  /// Gets the realtime service.
  LDKRealtime get realtime {
    _ensureInitialized();
    if (_realtime == null) {
      throw const LDKConfigurationException('Realtime service not configured');
    }
    return _realtime!;
  }

  /// Gets the offline storage.
  LDKOfflineStorage get offlineStorage {
    _ensureInitialized();
    if (_offlineStorage == null) {
      throw const LDKConfigurationException('Offline storage not configured');
    }
    return _offlineStorage!;
  }

  /// Gets the enhanced authentication service.
  LDKEnhancedAuth get enhancedAuth {
    _ensureInitialized();
    if (_enhancedAuth == null) {
      throw const LDKConfigurationException('Enhanced auth not configured');
    }
    return _enhancedAuth!;
  }

  /// Ensures that LDK has been initialized.
  void _ensureInitialized() {
    if (!isInitialized) {
      throw const LDKConfigurationException(
        'LDK V2 has not been initialized. Call LDKV2.initializeV2() first.',
      );
    }
  }

  /// Initializes LDK V2 with all Phase 2 features.
  static Future<void> initializeV2({
    required String baseUrl,
    String? authToken,
    bool enableLogging = false,
    bool enableGraphQL = true,
    bool enableRealtime = true,
    bool enableOfflineStorage = true,
    bool enableIntelligentCache = true,
    bool enableEnhancedAuth = true,
    Duration? connectTimeout,
    Duration? receiveTimeout,
    Map<String, dynamic>? cacheConfig,
  }) async {
    final ldk = instance;

    if (ldk.isInitialized) {
      throw const LDKConfigurationException('LDK V2 is already initialized');
    }

    if (baseUrl.isEmpty) {
      throw const LDKConfigurationException('Base URL cannot be empty');
    }

    // Ensure baseUrl doesn't end with a slash
    final cleanBaseUrl = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;

    try {
      // Initialize HTTP client (from parent)
      ldk._httpClient = LDKHttpClient(
        baseUrl: cleanBaseUrl,
        authToken: authToken,
        enableLogging: enableLogging,
        connectTimeout: connectTimeout,
        receiveTimeout: receiveTimeout,
      );

      // Initialize offline storage first (required by cache)
      if (enableOfflineStorage) {
        ldk._offlineStorage = LDKOfflineStorage();
        await ldk._offlineStorage!.initialize();
      }

      // Initialize intelligent cache
      if (enableIntelligentCache && ldk._offlineStorage != null) {
        ldk._cache = LDKIntelligentCache(ldk._offlineStorage!);

        // Apply custom cache configuration
        if (cacheConfig != null) {
          _applyCacheConfig(ldk._cache!, cacheConfig);
        }
      }

      // Initialize GraphQL client
      if (enableGraphQL) {
        ldk._graphqlClient = LDKGraphQLClient(
          baseUrl: cleanBaseUrl,
          authToken: authToken,
          enableLogging: enableLogging,
          connectTimeout: connectTimeout,
        );
      }

      // Initialize realtime service
      if (enableRealtime && ldk._graphqlClient != null) {
        ldk._realtime = LDKRealtime(ldk._graphqlClient!);
      }

      // Initialize enhanced authentication
      if (enableEnhancedAuth) {
        ldk
          .._enhancedAuth = LDKEnhancedAuth(ldk._httpClient!)
          .._auth = LDKAuth(ldk._httpClient!);
      } else {
        // Use basic auth service
        ldk._auth = LDKAuth(ldk._httpClient!);
      }
    } catch (e) {
      throw LDKConfigurationException(
          'Failed to initialize LDK V2: ${e.toString()}');
    }
  }

  /// Creates an enhanced collection reference.
  static LDKEnhancedCollection enhancedCollection(String collectionName) {
    final ldk = instance;
    ldk._ensureInitialized();

    if (collectionName.isEmpty) {
      throw const LDKConfigurationException('Collection name cannot be empty');
    }

    return LDKEnhancedCollection(
      ldk._httpClient!,
      collectionName,
      graphqlClient: ldk._graphqlClient,
      cache: ldk._cache,
      realtime: ldk._realtime,
      offlineStorage: ldk._offlineStorage,
    );
  }

  /// Subscribes to global authentication events.
  static Stream<AuthEvent> subscribeToAuthEvents() {
    final ldk = instance;

    if (ldk._realtime == null) {
      throw const LDKConfigurationException('Realtime service not configured');
    }

    return ldk._realtime!.subscribeToAuth();
  }

  /// Subscribes to connection state changes.
  static Stream<RealtimeConnectionState> subscribeToConnectionState() {
    final ldk = instance;

    if (ldk._realtime == null) {
      throw const LDKConfigurationException('Realtime service not configured');
    }

    return ldk._realtime!.connectionStateStream;
  }

  /// Subscribes to cache events.
  static Stream<CacheEvent?> subscribeToCacheEvents() {
    final ldk = instance;

    if (ldk._cache == null) {
      throw const LDKConfigurationException('Cache not configured');
    }

    return ldk._cache!.cacheEventsStream;
  }

  /// Subscribes to offline status changes.
  static Stream<bool> subscribeToOfflineStatus() {
    final ldk = instance;

    if (ldk._offlineStorage == null) {
      throw const LDKConfigurationException('Offline storage not configured');
    }

    return ldk._offlineStorage!.isOnlineStream;
  }

  /// Subscribes to security events.
  static Stream<SecurityEvent?> subscribeToSecurityEvents() {
    final ldk = instance;

    if (ldk._enhancedAuth == null) {
      throw const LDKConfigurationException('Enhanced auth not configured');
    }

    return ldk._enhancedAuth!.securityEventsStream;
  }

  /// Performs a global search across multiple collections.
  static Future<Map<String, List<Map<String, dynamic>>>> globalSearch(
    String searchTerm, {
    List<String>? collections,
    List<String>? searchFields,
    int? limit,
  }) async {
    final ldk = instance;
    ldk._ensureInitialized();

    final collectionsToSearch = collections ?? ['posts', 'pages', 'articles'];
    final results = <String, List<Map<String, dynamic>>>{};

    final futures = collectionsToSearch.map((collection) async {
      try {
        final collectionRef = enhancedCollection(collection);
        final searchResult = await collectionRef.search(
          searchTerm,
          searchFields: searchFields,
        );

        var data = searchResult.data;
        if (limit != null && data.length > limit) {
          data = data.take(limit).toList();
        }

        results[collection] = data;
      } catch (e) {
        // Log error but don't fail the entire search
        results[collection] = [];
      }
    });

    await Future.wait(futures);
    return results;
  }

  /// Executes multiple operations in a transaction-like manner.
  static Future<List<Map<String, dynamic>>> executeTransaction(
    List<TransactionOperation> operations,
  ) async {
    final ldk = instance;
    ldk._ensureInitialized();

    if (ldk._graphqlClient == null) {
      throw const LDKConfigurationException(
          'Transactions require GraphQL client');
    }

    // Build GraphQL mutation for all operations
    final mutations = <String>[];
    final variables = <String, dynamic>{};

    for (int i = 0; i < operations.length; i++) {
      final op = operations[i];
      final mutationName = '${op.type}_${op.collection}_$i';

      switch (op.type) {
        case TransactionType.create:
          mutations.add(
              '$mutationName: create${op.collection._capitalize()}(data: \$data_$i)');
          variables['data_$i'] = op.data;
          break;
        case TransactionType.update:
          mutations.add(
              '$mutationName: update${op.collection._capitalize()}(id: \$id_$i, data: \$data_$i)');
          variables['id_$i'] = op.entityId;
          variables['data_$i'] = op.data;
          break;
        case TransactionType.delete:
          mutations.add(
              '$mutationName: delete${op.collection._capitalize()}(id: \$id_$i)');
          variables['id_$i'] = op.entityId;
          break;
      }
    }

    final mutation = '''
      mutation ExecuteTransaction {
        ${mutations.join('\n        ')}
      }
    ''';

    final result = await ldk._graphqlClient!.mutate<Map<String, dynamic>>(
      mutation,
      variables: variables,
    );

    if (result.data == null) {
      throw const LDKServerException('Transaction failed');
    }

    // Extract results
    final results = <Map<String, dynamic>>[];
    for (int i = 0; i < operations.length; i++) {
      final op = operations[i];
      final mutationName = '${op.type}_${op.collection}_$i';
      final operationResult =
          result.data![mutationName] as Map<String, dynamic>?;

      if (operationResult != null) {
        results.add(operationResult);
      }
    }

    return results;
  }

  /// Applies custom cache configuration.
  static void _applyCacheConfig(
    LDKIntelligentCache cache,
    Map<String, dynamic> config,
  ) {
    // Apply strategies for different data types
    final strategies = config['strategies'] as Map<String, dynamic>?;
    if (strategies != null) {
      for (final entry in strategies.entries) {
        final dataType = entry.key;
        final strategyConfig = entry.value as Map<String, dynamic>;

        final strategy = CacheStrategy(
          ttl: strategyConfig['ttl'] != null
              ? Duration(milliseconds: strategyConfig['ttl'] as int)
              : const Duration(minutes: 30),
          maxSize: strategyConfig['maxSize'] as int? ?? 100,
          evictionPolicy: _parseEvictionPolicy(
            strategyConfig['evictionPolicy'] as String?,
          ),
          refreshOnAccess: strategyConfig['refreshOnAccess'] as bool? ?? false,
          backgroundRefresh:
              strategyConfig['backgroundRefresh'] as bool? ?? false,
          autoInvalidate: strategyConfig['autoInvalidate'] as bool? ?? true,
        );

        cache.setCacheStrategy(dataType, strategy);
      }
    }
  }

  /// Parses eviction policy from string.
  static EvictionPolicy _parseEvictionPolicy(String? policy) {
    switch (policy?.toLowerCase()) {
      case 'lru':
        return EvictionPolicy.lru;
      case 'lfu':
        return EvictionPolicy.lfu;
      case 'fifo':
        return EvictionPolicy.fifo;
      case 'lifo':
        return EvictionPolicy.lifo;
      default:
        return EvictionPolicy.lru;
    }
  }

  /// Disposes of all V2 resources.
  static Future<void> disposeV2() async {
    final ldk = instance;

    if (ldk.isInitialized) {
      // Dispose Phase 2 services
      ldk._realtime?.dispose();
      ldk._cache?.dispose();
      await ldk._offlineStorage?.dispose();
      ldk._graphqlClient?.dispose();

      // Dispose Phase 1 services
      ldk._enhancedAuth?.dispose();
      ldk._auth?.dispose();
      ldk._httpClient?.close();

      // Clear references
      ldk
        .._realtime = null
        .._cache = null
        .._offlineStorage = null
        .._graphqlClient = null
        .._enhancedAuth = null
        .._auth = null
        .._httpClient = null;
    }

    _instance = null;
  }
}

/// Represents a transaction operation.
class TransactionOperation {
  /// Creates a new [TransactionOperation].
  const TransactionOperation({
    required this.type,
    required this.collection,
    this.entityId,
    required this.data,
  });

  /// Type of operation.
  final TransactionType type;

  /// Collection name.
  final String collection;

  /// Entity ID (for update/delete).
  final dynamic entityId;

  /// Operation data.
  final Map<String, dynamic> data;
}

/// Types of transaction operations.
enum TransactionType {
  /// Create operation.
  create,

  /// Update operation.
  update,

  /// Delete operation.
  delete,
}

/// Extension to capitalize strings for V2.
extension StringCapitalizationV2 on String {
  /// Capitalizes the first letter of the string.
  String _capitalize() {
    if (isEmpty) return this;
    return this[0].toUpperCase() + substring(1);
  }
}
