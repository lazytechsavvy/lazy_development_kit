# LDK (Lazy Development Kit) for Strapi

[![pub package](https://img.shields.io/pub/v/lazy_development_kit.svg)](https://pub.dev/packages/lazy_development_kit)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A Flutter SDK that wraps Strapi's REST APIs into a simple, type-safe, and intuitive client-side library. LDK provides a Firebase-like experience while retaining Strapi's flexibility.

## Features

- 🚀 **Easy Setup**: Initialize with just a few lines of code
- 🔐 **Authentication**: JWT-based auth with automatic token management
- 📊 **CRUD Operations**: Intuitive interface for Create, Read, Update, Delete
- 🔍 **Advanced Querying**: Fluent query builder with filters, sorting, and pagination
- 📁 **File Upload**: Simple file and media upload with progress tracking
- 🛡️ **Type Safety**: Full TypeScript-like type safety with Dart
- 🔄 **Auto Retry**: Built-in error handling and retry mechanisms
- 📱 **Cross Platform**: Works on Android, iOS, Web, and Desktop

## Getting Started

Add LDK to your `pubspec.yaml`:

```yaml
dependencies:
  lazy_development_kit: ^1.0.0
```

## Quick Start

### 1. Initialize LDK

```dart
import 'package:lazy_development_kit/lazy_development_kit.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await LDK.initialize(
    baseUrl: 'https://your-strapi-app.com',
    enableLogging: true, // Enable for development
  );
  
  runApp(MyApp());
}
```

### 2. Authentication

```dart
// Sign up a new user
try {
  final user = await LDK.authService.signUp(
    email: 'user@example.com',
    password: 'securePassword123',
    username: 'johndoe',
  );
  print('User created: ${user.email}');
} catch (e) {
  print('Sign up failed: $e');
}

// Sign in existing user
try {
  final user = await LDK.authService.signIn(
    email: 'user@example.com',
    password: 'securePassword123',
  );
  print('Signed in: ${user.email}');
} catch (e) {
  print('Sign in failed: $e');
}

// Listen to auth state changes
LDK.authService.authStateStream.listen((isAuthenticated) {
  if (isAuthenticated) {
    print('User is signed in');
  } else {
    print('User is signed out');
  }
});

// Sign out
await LDK.authService.signOut();
```

### 3. CRUD Operations

```dart
// Get a collection reference
final posts = LDK.collection('posts');

// Create a new post
final newPost = await posts.create({
  'title': 'My First Post',
  'content': 'This is the content of my first post.',
  'status': 'published',
});

// Get all posts
final allPosts = await posts.get();
print('Found ${allPosts.data.length} posts');

// Get a specific post by ID
final post = await posts.getById(1);
print('Post title: ${post['title']}');

// Update a post
final updatedPost = await posts.update(1, {
  'title': 'Updated Post Title',
});

// Delete a post
await posts.delete(1);
```

### 4. Advanced Querying

```dart
final posts = LDK.collection('posts');

// Complex query with filters, sorting, and pagination
final response = await posts
    .where('status', equals: 'published')
    .where('title', contains: 'Flutter')
    .where('createdAt', greaterThan: '2023-01-01')
    .sort('createdAt', descending: true)
    .populate('author')
    .populate('category')
    .paginate(page: 1, pageSize: 10)
    .get();

// Using query builder directly
final query = LDKQueryBuilder()
    .where('category', equals: 'technology')
    .or([
      LDKQueryBuilder().where('featured', equals: true),
      LDKQueryBuilder().where('views', greaterThan: 1000),
    ])
    .sort('publishedAt', descending: true)
    .limit(5);

final featuredPosts = await posts.get(query: query);
```

### 5. File Upload

```dart
import 'dart:io';

// Upload a single file
final file = File('path/to/image.jpg');
try {
  final uploadedFile = await LDK.storageService.upload(
    file,
    alternativeText: 'Profile picture',
    caption: 'User profile image',
  );
  print('File uploaded: ${uploadedFile.url}');
} catch (e) {
  print('Upload failed: $e');
}

// Upload multiple files with progress tracking
final files = [File('image1.jpg'), File('image2.jpg')];
try {
  final uploadedFiles = await LDK.storageService.uploadMultiple(
    files,
    onProgress: (sent, total) {
      print('Progress: ${(sent / total * 100).toStringAsFixed(1)}%');
    },
  );
  print('Uploaded ${uploadedFiles.length} files');
} catch (e) {
  print('Upload failed: $e');
}

// Validate file before upload
final isValid = LDK.storageService.validateFile(
  file,
  maxSizeBytes: 5 * 1024 * 1024, // 5MB
  allowedMimeTypes: ['image/jpeg', 'image/png'],
  allowedExtensions: ['jpg', 'jpeg', 'png'],
);

if (isValid) {
  // Proceed with upload
}
```

## Advanced Usage

### Custom Query Conditions

```dart
final products = LDK.collection('products');

// Multiple filter conditions
final expensiveProducts = await products
    .where('price', greaterThanOrEqual: 100)
    .where('price', lessThan: 1000)
    .where('category', isIn: ['electronics', 'gadgets'])
    .where('inStock', equals: true)
    .get();

// Text search
final searchResults = await products
    .where('name', containsi: 'iphone') // Case-insensitive
    .where('description', contains: 'smartphone')
    .get();

// Null checks
final productsWithoutImages = await products
    .where('image', isNull: true)
    .get();
```

### Error Handling

```dart
try {
  final posts = await LDK.collection('posts').get();
} on LDKAuthException catch (e) {
  print('Authentication error: ${e.message}');
  // Redirect to login
} on LDKNetworkException catch (e) {
  print('Network error: ${e.message}');
  // Show retry option
} on LDKValidationException catch (e) {
  print('Validation error: ${e.message}');
  print('Field errors: ${e.errors}');
  // Show field-specific errors
} on LDKServerException catch (e) {
  print('Server error: ${e.message}');
  // Show generic error message
} catch (e) {
  print('Unexpected error: $e');
}
```

### Working with Relations

```dart
// Populate related data
final postsWithAuthors = await LDK.collection('posts')
    .populate('author')
    .populate('category')
    .populate('tags')
    .get();

// Deep population
final postsWithAuthorProfile = await LDK.collection('posts')
    .populate('author.profile')
    .get();
```

## Configuration Options

```dart
await LDK.initialize(
  baseUrl: 'https://your-strapi-app.com',
  authToken: 'optional-existing-jwt-token',
  enableLogging: true,
  connectTimeout: Duration(seconds: 30),
  receiveTimeout: Duration(seconds: 30),
);
```

## Models

LDK provides built-in models for common Strapi entities:

```dart
// User model
final user = LDKUser(
  id: 1,
  email: 'user@example.com',
  username: 'johndoe',
  confirmed: true,
  blocked: false,
);

// File model
final file = StrapiFile(
  id: 1,
  name: 'image.jpg',
  url: 'https://example.com/uploads/image.jpg',
  mime: 'image/jpeg',
  size: 1024.0,
  // ... other properties
);
```

## Testing

LDK is thoroughly tested. To run tests:

```bash
flutter test
```

## Contributing

Contributions are welcome! Please read our [contributing guide](CONTRIBUTING.md) for details on our code of conduct and the process for submitting pull requests.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Support

- 📖 [Documentation](https://github.com/subhajitkar/lazy_development_kit/wiki)
- 🐛 [Issue Tracker](https://github.com/subhajitkar/lazy_development_kit/issues)
- 💬 [Discussions](https://github.com/subhajitkar/lazy_development_kit/discussions)

## Roadmap

- [ ] GraphQL support
- [ ] Real-time subscriptions
- [ ] Offline caching
- [ ] CLI for code generation
- [ ] Advanced caching strategies

---

Made with ❤️ for the Flutter and Strapi communities.