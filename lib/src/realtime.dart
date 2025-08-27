import 'dart:async';

import 'package:logger/logger.dart';
import 'package:rxdart/rxdart.dart';

import 'package:ldk/src/exceptions.dart';
import 'package:ldk/src/graphql_client.dart';

/// Real-time service for live data updates via WebSocket and GraphQL subscriptions.
class LDKRealtime {
  /// Creates a new [LDKRealtime] instance.
  LDKRealtime(this._graphqlClient) {
    _logger = Logger();
    _subscriptionsController =
        BehaviorSubject<Map<String, StreamSubscription>>.seeded({});
    _connectionController = BehaviorSubject<RealtimeConnectionState>.seeded(
      RealtimeConnectionState.disconnected,
    );
  }

  final LDKGraphQLClient _graphqlClient;
  late final Logger _logger;
  late final BehaviorSubject<Map<String, StreamSubscription>>
      _subscriptionsController;
  late final BehaviorSubject<RealtimeConnectionState> _connectionController;

  /// Stream of active subscriptions.
  Stream<Map<String, StreamSubscription>> get subscriptionsStream =>
      _subscriptionsController.stream;

  /// Stream of connection state changes.
  Stream<RealtimeConnectionState> get connectionStateStream =>
      _connectionController.stream;

  /// Current connection state.
  RealtimeConnectionState get connectionState => _connectionController.value;

  /// Current active subscriptions.
  Map<String, StreamSubscription> get activeSubscriptions =>
      _subscriptionsController.value;

  /// Subscribes to real-time updates for a specific collection.
  Stream<CollectionEvent<T>> subscribeToCollection<T>(
    String collectionName, {
    Map<String, dynamic>? variables,
    T Function(Map<String, dynamic>)? parseData,
  }) {
    final subscriptionQuery = '''
      subscription ${collectionName}Updated(\$where: ${collectionName.capitalize()}FiltersInput) {
        ${collectionName}Updated(where: \$where) {
          mutation
          data {
            id
            attributes
          }
          previousData {
            id
            attributes
          }
        }
      }
    ''';

    return _graphqlClient
        .subscribe<Map<String, dynamic>>(
      subscriptionQuery,
      variables: variables,
    )
        .map((result) {
      if (result.hasErrors) {
        throw LDKServerException('Subscription error: ${result.errors}');
      }

      final data = result.data;
      if (data == null) {
        throw const LDKServerException('No data received from subscription');
      }

      final mutationType = data['mutation'] as String?;
      final eventData = data['data'] as Map<String, dynamic>?;
      final previousData = data['previousData'] as Map<String, dynamic>?;

      return CollectionEvent<T>(
        collection: collectionName,
        mutation: _parseMutationType(mutationType),
        data: eventData != null && parseData != null
            ? parseData(eventData)
            : eventData as T?,
        previousData: previousData != null && parseData != null
            ? parseData(previousData)
            : previousData as T?,
        timestamp: DateTime.now(),
      );
    });
  }

  /// Subscribes to real-time updates for a specific entry by ID.
  Stream<EntryEvent<T>> subscribeToEntry<T>(
    String collectionName,
    dynamic entryId, {
    T Function(Map<String, dynamic>)? parseData,
  }) {
    final subscriptionQuery = '''
      subscription ${collectionName}EntryUpdated(\$id: ID!) {
        ${collectionName}EntryUpdated(id: \$id) {
          mutation
          data {
            id
            attributes
          }
          previousData {
            id
            attributes
          }
        }
      }
    ''';

    return _graphqlClient.subscribe<Map<String, dynamic>>(
      subscriptionQuery,
      variables: {'id': entryId},
    ).map((result) {
      if (result.hasErrors) {
        throw LDKServerException('Subscription error: ${result.errors}');
      }

      final data = result.data;
      if (data == null) {
        throw const LDKServerException('No data received from subscription');
      }

      final mutationType = data['mutation'] as String?;
      final eventData = data['data'] as Map<String, dynamic>?;
      final previousData = data['previousData'] as Map<String, dynamic>?;

      return EntryEvent<T>(
        collection: collectionName,
        entryId: entryId,
        mutation: _parseMutationType(mutationType),
        data: eventData != null && parseData != null
            ? parseData(eventData)
            : eventData as T?,
        previousData: previousData != null && parseData != null
            ? parseData(previousData)
            : previousData as T?,
        timestamp: DateTime.now(),
      );
    });
  }

  /// Subscribes to authentication events (user login/logout).
  Stream<AuthEvent> subscribeToAuth() {
    const subscriptionQuery = '''
      subscription AuthEvents {
        authEvents {
          type
          user {
            id
            email
            username
          }
          timestamp
        }
      }
    ''';

    return _graphqlClient
        .subscribe<Map<String, dynamic>>(
      subscriptionQuery,
    )
        .map((result) {
      if (result.hasErrors) {
        throw LDKServerException('Auth subscription error: ${result.errors}');
      }

      final data = result.data;
      if (data == null) {
        throw const LDKServerException('No auth data received');
      }

      return AuthEvent.fromJson(data);
    });
  }

  /// Creates a custom GraphQL subscription.
  Stream<T> subscribe<T>(
    String subscriptionQuery, {
    Map<String, dynamic>? variables,
    T Function(Map<String, dynamic>)? parseData,
  }) {
    return _graphqlClient
        .subscribe<T>(
      subscriptionQuery,
      variables: variables,
      parseData: parseData,
    )
        .map((result) {
      if (result.hasErrors) {
        throw LDKServerException('Custom subscription error: ${result.errors}');
      }

      if (result.data == null) {
        throw const LDKServerException(
            'No data received from custom subscription');
      }

      return result.data!;
    });
  }

  /// Subscribes to live query updates.
  Stream<T> subscribeLiveQuery<T>(
    String queryName,
    String query, {
    Map<String, dynamic>? variables,
    Duration refreshInterval = const Duration(seconds: 5),
    T Function(Map<String, dynamic>)? parseData,
  }) {
    // Use GraphQL subscription if available, otherwise fall back to polling
    try {
      return subscribeToLiveQuery<T>(
        queryName,
        query,
        variables: variables,
        parseData: parseData,
      );
    } catch (e) {
      // Fallback to polling if subscriptions are not available
      return _pollQuery<T>(
        query,
        variables: variables,
        interval: refreshInterval,
        parseData: parseData,
      );
    }
  }

  /// Subscribes to live query using GraphQL subscriptions.
  Stream<T> subscribeToLiveQuery<T>(
    String queryName,
    String query, {
    Map<String, dynamic>? variables,
    T Function(Map<String, dynamic>)? parseData,
  }) {
    final subscriptionQuery = '''
      subscription ${queryName}Live {
        $queryName {
          ${query.replaceAll('query', '').replaceAll('{', '').replaceAll('}', '')}
        }
      }
    ''';

    return _graphqlClient
        .subscribe<T>(
      subscriptionQuery,
      variables: variables,
      parseData: parseData,
    )
        .map((result) {
      if (result.hasErrors) {
        throw LDKServerException(
            'Live query subscription error: ${result.errors}');
      }

      if (result.data == null) {
        throw const LDKServerException('No data received from live query');
      }

      return result.data!;
    });
  }

  /// Polls a query at regular intervals.
  Stream<T> _pollQuery<T>(
    String query, {
    Map<String, dynamic>? variables,
    required Duration interval,
    T Function(Map<String, dynamic>)? parseData,
  }) {
    return Stream.periodic(interval).asyncMap((_) async {
      final result = await _graphqlClient.query<T>(
        query,
        variables: variables,
        parseData: parseData,
      );

      if (result.hasErrors) {
        throw LDKServerException('Polling query error: ${result.errors}');
      }

      if (result.data == null) {
        throw const LDKServerException('No data received from polling query');
      }

      return result.data!;
    });
  }

  /// Parses mutation type from string.
  MutationType _parseMutationType(String? mutationType) {
    switch (mutationType?.toLowerCase()) {
      case 'create':
      case 'created':
        return MutationType.create;
      case 'update':
      case 'updated':
        return MutationType.update;
      case 'delete':
      case 'deleted':
        return MutationType.delete;
      default:
        return MutationType.unknown;
    }
  }

  /// Disposes of all resources.
  void dispose() {
    // Cancel all active subscriptions
    for (final subscription in activeSubscriptions.values) {
      subscription.cancel();
    }

    _subscriptionsController.close();
    _connectionController.close();
  }
}

/// Represents the connection state of the real-time service.
enum RealtimeConnectionState {
  /// Not connected.
  disconnected,

  /// Connecting to the server.
  connecting,

  /// Connected and ready.
  connected,

  /// Connection lost, attempting to reconnect.
  reconnecting,

  /// Connection failed.
  failed,
}

/// Types of mutations that can occur.
enum MutationType {
  /// Entry was created.
  create,

  /// Entry was updated.
  update,

  /// Entry was deleted.
  delete,

  /// Unknown mutation type.
  unknown,
}

/// Event representing a change to a collection.
class CollectionEvent<T> {
  /// Creates a new [CollectionEvent].
  const CollectionEvent({
    required this.collection,
    required this.mutation,
    required this.data,
    this.previousData,
    required this.timestamp,
  });

  /// The collection that changed.
  final String collection;

  /// The type of mutation.
  final MutationType mutation;

  /// The new/current data.
  final T? data;

  /// The previous data (for updates).
  final T? previousData;

  /// When the event occurred.
  final DateTime timestamp;

  @override
  String toString() {
    return 'CollectionEvent(collection: $collection, mutation: $mutation, data: $data)';
  }
}

/// Event representing a change to a specific entry.
class EntryEvent<T> {
  /// Creates a new [EntryEvent].
  const EntryEvent({
    required this.collection,
    required this.entryId,
    required this.mutation,
    required this.data,
    this.previousData,
    required this.timestamp,
  });

  /// The collection containing the entry.
  final String collection;

  /// The ID of the entry that changed.
  final dynamic entryId;

  /// The type of mutation.
  final MutationType mutation;

  /// The new/current data.
  final T? data;

  /// The previous data (for updates).
  final T? previousData;

  /// When the event occurred.
  final DateTime timestamp;

  @override
  String toString() {
    return 'EntryEvent(collection: $collection, entryId: $entryId, mutation: $mutation)';
  }
}

/// Event representing an authentication change.
class AuthEvent {
  /// Creates a new [AuthEvent].
  const AuthEvent({
    required this.type,
    this.user,
    required this.timestamp,
  });

  /// Creates an [AuthEvent] from JSON data.
  factory AuthEvent.fromJson(Map<String, dynamic> json) {
    return AuthEvent(
      type: _parseAuthEventType(json['type'] as String?),
      user: json['user'] as Map<String, dynamic>?,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }

  /// The type of authentication event.
  final AuthEventType type;

  /// User data (if applicable).
  final Map<String, dynamic>? user;

  /// When the event occurred.
  final DateTime timestamp;

  /// Parses auth event type from string.
  static AuthEventType _parseAuthEventType(String? type) {
    switch (type?.toLowerCase()) {
      case 'login':
      case 'signin':
        return AuthEventType.login;
      case 'logout':
      case 'signout':
        return AuthEventType.logout;
      case 'register':
      case 'signup':
        return AuthEventType.register;
      case 'refresh':
        return AuthEventType.refresh;
      default:
        return AuthEventType.unknown;
    }
  }

  @override
  String toString() {
    return 'AuthEvent(type: $type, user: ${user?['email']})';
  }
}

/// Types of authentication events.
enum AuthEventType {
  /// User logged in.
  login,

  /// User logged out.
  logout,

  /// User registered.
  register,

  /// Token was refreshed.
  refresh,

  /// Unknown event type.
  unknown,
}

/// Extension to capitalize strings for realtime.
extension StringExtensionRealtime on String {
  /// Capitalizes the first letter of the string.
  String capitalize() {
    if (isEmpty) return this;
    return this[0].toUpperCase() + substring(1);
  }
}

/// Fetch policy for GraphQL queries.
enum FetchPolicy {
  /// Use cache first, then network if not found.
  cacheFirst,

  /// Use cache only.
  cacheOnly,

  /// Use network only.
  networkOnly,

  /// Use cache and network simultaneously.
  cacheAndNetwork,
}
