import 'dart:async';

import 'package:ldk/src/auth.dart';
import 'package:ldk/src/collection.dart';
import 'package:ldk/src/enhanced_auth.dart';
import 'package:ldk/src/enhanced_collection.dart';
import 'package:ldk/src/exceptions.dart';
import 'package:ldk/src/graphql_client.dart';
import 'package:ldk/src/intelligent_cache.dart';
import 'package:ldk/src/offline_storage.dart';
import 'package:ldk/src/realtime.dart';
import 'package:ldk/src/storage.dart';
import 'package:ldk/src/utils/http_client.dart';

/// Main entry point for the Lazy Development Kit (LDK) for Strapi.
class LDK {
  LDK._internal();

  static LDK? _instance;
  LDKHttpClient? _httpClient;
  LDKAuth? _auth;
  LDKStorage? _storage;

  // V2 Features
  LDKGraphQLClient? _graphqlClient;
  LDKIntelligentCache? _cache;
  LDKRealtime? _realtime;
  LDKOfflineStorage? _offlineStorage;
  LDKEnhancedAuth? _enhancedAuth;

  /// Gets the singleton instance of LDK.
  static LDK get instance {
    _instance ??= LDK._internal();
    return _instance!;
  }

  /// Whether LDK has been initialized.
  bool get isInitialized => _httpClient != null;

  /// Gets the authentication service.
  LDKAuth get auth {
    _ensureInitialized();
    return _auth!;
  }

  /// Gets the storage service.
  LDKStorage get storage {
    _ensureInitialized();
    return _storage!;
  }

  /// Gets the GraphQL client (V2 feature).
  LDKGraphQLClient get graphql {
    _ensureInitialized();
    if (_graphqlClient == null) {
      throw const LDKConfigurationException(
          'GraphQL client not configured. Enable GraphQL in initialize()');
    }
    return _graphqlClient!;
  }

  /// Gets the intelligent cache (V2 feature).
  LDKIntelligentCache get cache {
    _ensureInitialized();
    if (_cache == null) {
      throw const LDKConfigurationException(
          'Cache not configured. Enable intelligent cache in initialize()');
    }
    return _cache!;
  }

  /// Gets the realtime service (V2 feature).
  LDKRealtime get realtime {
    _ensureInitialized();
    if (_realtime == null) {
      throw const LDKConfigurationException(
          'Realtime service not configured. Enable realtime in initialize()');
    }
    return _realtime!;
  }

  /// Gets the offline storage (V2 feature).
  LDKOfflineStorage get offlineStorage {
    _ensureInitialized();
    if (_offlineStorage == null) {
      throw const LDKConfigurationException(
          'Offline storage not configured. Enable offline storage in initialize()');
    }
    return _offlineStorage!;
  }

  /// Gets the enhanced authentication service (V2 feature).
  LDKEnhancedAuth get enhancedAuth {
    _ensureInitialized();
    if (_enhancedAuth == null) {
      throw const LDKConfigurationException(
          'Enhanced auth not configured. Enable enhanced auth in initialize()');
    }
    return _enhancedAuth!;
  }

  /// Initializes the LDK with the given configuration.
  static Future<void> initialize({
    required String baseUrl,
    String? authToken,
    bool enableLogging = false,
    Duration? connectTimeout,
    Duration? receiveTimeout,
    // V2 Features
    bool enableGraphQL = true,
    bool enableRealtime = true,
    bool enableOfflineStorage = true,
    bool enableIntelligentCache = true,
    bool enableEnhancedAuth = true,
    Map<String, dynamic>? cacheConfig,
  }) async {
    final ldk = instance;

    if (ldk.isInitialized) {
      throw const LDKConfigurationException('LDK is already initialized');
    }

    if (baseUrl.isEmpty) {
      throw const LDKConfigurationException('Base URL cannot be empty');
    }

    // Ensure baseUrl doesn't end with a slash
    final cleanBaseUrl = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;

    try {
      // Initialize HTTP client
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
        ldk._enhancedAuth = LDKEnhancedAuth(ldk._httpClient!);
        // Use basic auth service alongside enhanced auth
        ldk._auth = LDKAuth(ldk._httpClient!);
      } else {
        // Use basic auth service
        ldk._auth = LDKAuth(ldk._httpClient!);
      }

      // Initialize storage service
      ldk._storage = LDKStorage(ldk._httpClient!);

      // Auth service will initialize itself automatically
    } catch (e) {
      throw LDKConfigurationException(
          'Failed to initialize LDK: ${e.toString()}');
    }
  }

  /// Creates a collection reference for the given collection name.
  /// Returns an enhanced collection if V2 features are enabled.
  static LDKCollection collection(String collectionName) {
    final ldk = instance;
    ldk._ensureInitialized();

    if (collectionName.isEmpty) {
      throw const LDKConfigurationException('Collection name cannot be empty');
    }

    // Return enhanced collection if any V2 features are available
    if (ldk._graphqlClient != null ||
        ldk._cache != null ||
        ldk._realtime != null ||
        ldk._offlineStorage != null) {
      return LDKEnhancedCollection(
        ldk._httpClient!,
        collectionName,
        graphqlClient: ldk._graphqlClient,
        cache: ldk._cache,
        realtime: ldk._realtime,
        offlineStorage: ldk._offlineStorage,
      );
    }

    return LDKCollection(ldk._httpClient!, collectionName);
  }

  /// Gets the authentication service (static access).
  static LDKAuth get authService {
    return instance.auth;
  }

  /// Gets the storage service (static access).
  static LDKStorage get storageService {
    return instance.storage;
  }

  /// Updates the authentication token.
  static void setAuthToken(String token) {
    final ldk = instance;
    ldk._ensureInitialized();
    ldk._httpClient!.setAuthToken(token);
  }

  /// Clears the authentication token.
  static void clearAuthToken() {
    final ldk = instance;
    ldk._ensureInitialized();
    ldk._httpClient!.clearAuthToken();
  }

  /// Performs a global search across multiple collections (V2 feature).
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

    final futures = collectionsToSearch.map((collectionName) async {
      try {
        final collectionRef = collection(collectionName);
        if (collectionRef is LDKEnhancedCollection) {
          final searchResult = await collectionRef.search(
            searchTerm,
            searchFields: searchFields,
          );

          var data = searchResult.data;
          if (limit != null && data.length > limit) {
            data = data.take(limit).toList();
          }

          results[collectionName] = data;
        } else {
          results[collectionName] = [];
        }
      } catch (e) {
        // Log error but don't fail the entire search
        results[collectionName] = [];
      }
    });

    await Future.wait(futures);
    return results;
  }

  /// Disposes of all resources and resets the instance.
  static Future<void> dispose() async {
    final ldk = instance;

    if (ldk.isInitialized) {
      // Dispose V2 services
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
        .._storage = null
        .._httpClient = null;
    }

    _instance = null;
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

  /// Ensures that LDK has been initialized.
  void _ensureInitialized() {
    if (!isInitialized) {
      throw const LDKConfigurationException(
        'LDK has not been initialized. Call LDK.initialize() first.',
      );
    }
  }

  @override
  String toString() {
    return 'LDK(initialized: $isInitialized)';
  }
}

/// Configuration class for LDK initialization.
class LDKConfig {
  /// Creates a new [LDKConfig] instance.
  const LDKConfig({
    required this.baseUrl,
    this.authToken,
    this.enableLogging = false,
    this.connectTimeout,
    this.receiveTimeout,
  });

  /// The base URL of the Strapi server.
  final String baseUrl;

  /// Optional authentication token.
  final String? authToken;

  /// Whether to enable HTTP request/response logging.
  final bool enableLogging;

  /// Connection timeout duration.
  final Duration? connectTimeout;

  /// Response receive timeout duration.
  final Duration? receiveTimeout;

  /// Creates a copy of this config with the given fields replaced.
  LDKConfig copyWith({
    String? baseUrl,
    String? authToken,
    bool? enableLogging,
    Duration? connectTimeout,
    Duration? receiveTimeout,
  }) {
    return LDKConfig(
      baseUrl: baseUrl ?? this.baseUrl,
      authToken: authToken ?? this.authToken,
      enableLogging: enableLogging ?? this.enableLogging,
      connectTimeout: connectTimeout ?? this.connectTimeout,
      receiveTimeout: receiveTimeout ?? this.receiveTimeout,
    );
  }

  @override
  String toString() {
    return 'LDKConfig(baseUrl: $baseUrl, enableLogging: $enableLogging)';
  }
}
