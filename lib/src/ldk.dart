import 'dart:async';

import 'auth.dart';
import 'collection.dart';
import 'exceptions.dart';
import 'storage.dart';
import 'utils/http_client.dart';

/// Main entry point for the Lazy Development Kit (LDK) for Strapi.
class LDK {
  LDK._internal();

  static LDK? _instance;
  LDKHttpClient? _httpClient;
  LDKAuth? _auth;
  LDKStorage? _storage;

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

  /// Initializes the LDK with the given configuration.
  static Future<void> initialize({
    required String baseUrl,
    String? authToken,
    bool enableLogging = false,
    Duration? connectTimeout,
    Duration? receiveTimeout,
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

      // Initialize services
      ldk._auth = LDKAuth(ldk._httpClient!);
      ldk._storage = LDKStorage(ldk._httpClient!);

      // Auth service will initialize itself automatically
    } catch (e) {
      throw LDKConfigurationException(
          'Failed to initialize LDK: ${e.toString()}');
    }
  }

  /// Creates a collection reference for the given collection name.
  static LDKCollection collection(String collectionName) {
    final ldk = instance;
    ldk._ensureInitialized();

    if (collectionName.isEmpty) {
      throw const LDKConfigurationException('Collection name cannot be empty');
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

  /// Disposes of all resources and resets the instance.
  static Future<void> dispose() async {
    final ldk = instance;

    if (ldk.isInitialized) {
      ldk._auth?.dispose();
      ldk._httpClient?.close();

      ldk._auth = null;
      ldk._storage = null;
      ldk._httpClient = null;
    }

    _instance = null;
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
