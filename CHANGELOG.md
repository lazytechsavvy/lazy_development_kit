## 1.0.0

### Initial Release 🎉

**LDK (Lazy Development Kit) for Strapi** - A comprehensive Flutter SDK that provides a Firebase-like experience for Strapi backends.

#### ✨ Features

- **Easy Initialization**: Simple setup with just a few lines of code
- **JWT Authentication**: Complete auth flow with automatic token management
  - Sign up, sign in, sign out
  - Password reset functionality
  - Auth state streams for reactive UI updates
  - Secure token storage using Flutter Secure Storage
- **CRUD Operations**: Intuitive interface for all database operations
  - Create, read, update, delete entries
  - Type-safe operations with proper error handling
- **Advanced Querying**: Powerful query builder with fluent API
  - Filtering with multiple operators (equals, contains, greater than, etc.)
  - Sorting (ascending/descending)
  - Pagination support
  - Population of related fields
  - Complex queries with AND/OR conditions
- **File Upload**: Comprehensive file management
  - Single and multiple file uploads
  - Progress tracking
  - File validation (size, type, extension)
  - File metadata management
- **Error Handling**: Robust exception system
  - Custom exception types for different error scenarios
  - Detailed error messages and context
  - Network error handling with retry capabilities
- **Type Safety**: Full Dart type safety with JSON serialization
- **Cross Platform**: Works on Android, iOS, Web, and Desktop

#### 🏗️ Architecture

- **Singleton Pattern**: Global access to LDK instance
- **Repository Pattern**: Clean data layer abstraction  
- **Builder Pattern**: Fluent query construction
- **Observer Pattern**: Reactive auth state management
- **HTTP Client**: Dio-based networking with interceptors

#### 📦 Core Components

- `LDK`: Main entry point and configuration
- `LDKAuth`: Authentication service
- `LDKCollection`: CRUD operations for Strapi collections
- `LDKStorage`: File upload and management
- `LDKQueryBuilder`: Advanced query construction
- Custom exception classes for proper error handling
- Built-in models for User and File entities

#### 🧪 Testing

- Comprehensive unit test suite (90%+ coverage)
- Mock implementations for testing
- Flutter test bindings support

#### 📚 Documentation

- Complete README with usage examples
- API documentation with dartdoc
- Example Flutter app demonstrating all features
- Type-safe models with JSON serialization

#### 🔧 Dependencies

- `dio`: HTTP client for API communication
- `flutter_secure_storage`: Secure token storage
- `rxdart`: Reactive streams for auth state
- `json_annotation`: Type-safe JSON serialization
- `mime`: File type detection
- `logger`: Configurable logging

This release provides a solid foundation for Flutter developers to integrate with Strapi backends efficiently, reducing development time by up to 70% compared to manual API integration.
