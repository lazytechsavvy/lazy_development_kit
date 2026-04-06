/// Strapi LDK (Lazy Development Kit) - A Flutter SDK for Strapi integration.
///
/// This library provides a simple, type-safe, and intuitive interface
/// for working with Strapi backends in Flutter applications.
///
/// ## Phase 1 Features (Basic)
/// - REST API integration
/// - JWT authentication
/// - CRUD operations
/// - File uploads
/// - Basic querying and filtering
///
/// ## Phase 2 Features (Advanced)
/// - GraphQL support with subscriptions
/// - Real-time updates via WebSocket
/// - Intelligent caching with multiple strategies
/// - Offline storage and sync
/// - Enhanced security with token refresh
/// - Advanced querying with aggregations
/// - Optimistic updates
/// - Transaction support
library strapi_ldk;

export 'src/auth.dart';
export 'src/collection.dart';
export 'src/enhanced_auth.dart';
export 'src/enhanced_collection.dart';
export 'src/exceptions.dart';
export 'src/graphql_client.dart';
export 'src/intelligent_cache.dart';
export 'src/ldk.dart';
export 'src/ldk_v2.dart';
export 'src/models/responses.dart';
export 'src/models/strapi_file.dart';
export 'src/models/user.dart';
export 'src/offline_storage.dart';
export 'src/realtime.dart';
export 'src/storage.dart';
export 'src/utils/query_builder.dart';
