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

// === PHASE 1 EXPORTS ===

// Authentication
export 'src/auth.dart';

// Collections and querying
export 'src/collection.dart';

// Exceptions
export 'src/exceptions.dart';

// Core exports
export 'src/ldk.dart';

// Models
export 'src/models/responses.dart';
export 'src/models/strapi_file.dart';
export 'src/models/user.dart';

// File storage
export 'src/storage.dart';

export 'src/utils/query_builder.dart';

// === PHASE 2 EXPORTS ===

// Enhanced authentication with security features
export 'src/enhanced_auth.dart';

// Enhanced collections with caching and real-time
export 'src/enhanced_collection.dart';

// GraphQL support
export 'src/graphql_client.dart';

// Intelligent caching
export 'src/intelligent_cache.dart';

// Core V2 exports
export 'src/ldk_v2.dart';

// Offline storage and sync
export 'src/offline_storage.dart';

// Real-time features
export 'src/realtime.dart';
