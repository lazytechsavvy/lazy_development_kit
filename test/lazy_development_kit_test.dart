import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lazy_development_kit/lazy_development_kit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Mock the secure storage methods for testing
  const MethodChannel('plugins.it_nomads.com/flutter_secure_storage')
      .setMockMethodCallHandler((MethodCall methodCall) async {
    switch (methodCall.method) {
      case 'read':
        return null; // Return null for all read operations
      case 'write':
        return null; // Success for write operations
      case 'delete':
        return null; // Success for delete operations
      case 'deleteAll':
        return null; // Success for deleteAll operations
      default:
        return null;
    }
  });
  group('LDK Core Tests', () {
    tearDown(() async {
      // Clean up after each test
      await LDK.dispose();
    });

    test('should initialize successfully with valid configuration', () async {
      await LDK.initialize(
        baseUrl: 'https://test-strapi.com',
        enableLogging: false,
      );

      expect(LDK.instance.isInitialized, isTrue);
    });

    test('should throw exception when initializing with empty base URL',
        () async {
      expect(
        () => LDK.initialize(baseUrl: ''),
        throwsA(isA<LDKConfigurationException>()),
      );
    });

    test('should throw exception when accessing services before initialization',
        () {
      expect(
        () => LDK.instance.auth,
        throwsA(isA<LDKConfigurationException>()),
      );

      expect(
        () => LDK.instance.storage,
        throwsA(isA<LDKConfigurationException>()),
      );
    });

    test('should create collection with valid name', () async {
      await LDK.initialize(baseUrl: 'https://test-strapi.com');

      final collection = LDK.collection('posts');
      expect(collection.collectionName, equals('posts'));
    });

    test('should throw exception when creating collection with empty name',
        () async {
      await LDK.initialize(baseUrl: 'https://test-strapi.com');

      expect(
        () => LDK.collection(''),
        throwsA(isA<LDKConfigurationException>()),
      );
    });
  });

  group('Query Builder Tests', () {
    test('should build basic query with filters', () {
      final query = LDKQueryBuilder()
          .where('title', contains: 'Flutter')
          .sort('createdAt', descending: true)
          .limit(10);

      final built = query.build();

      expect(built['filters'], isNotNull);
      expect(built['sort'], equals(['createdAt:desc']));
      expect(built['pagination']['limit'], equals(10));
    });

    test('should build query with multiple conditions', () {
      final query = LDKQueryBuilder()
          .where('status', equals: 'published')
          .where('author', equals: 'john')
          .populate('category')
          .paginate(page: 1, pageSize: 20);

      final built = query.build();

      expect(built['filters'], isNotNull);
      expect(built['populate'], equals(['category']));
      expect(built['pagination']['page'], equals(1));
      expect(built['pagination']['pageSize'], equals(20));
    });
  });

  group('Exception Tests', () {
    test('should create LDKAuthException with message', () {
      const exception = LDKAuthException('Authentication failed');
      expect(exception.message, equals('Authentication failed'));
      expect(exception.toString(), contains('LDKAuthException'));
    });

    test('should create LDKNetworkException with status code', () {
      const exception = LDKNetworkException('Network error', statusCode: 500);
      expect(exception.message, equals('Network error'));
      expect(exception.statusCode, equals(500));
    });

    test('should create LDKValidationException with errors', () {
      const errors = {
        'email': ['Email is required']
      };
      const exception =
          LDKValidationException('Validation failed', errors: errors);
      expect(exception.message, equals('Validation failed'));
      expect(exception.errors, equals(errors));
    });
  });

  group('Model Tests', () {
    test('should create LDKUser from JSON', () {
      final json = {
        'id': 1,
        'email': 'test@example.com',
        'username': 'testuser',
        'confirmed': true,
        'blocked': false,
      };

      final user = LDKUser.fromJson(json);

      expect(user.id, equals(1));
      expect(user.email, equals('test@example.com'));
      expect(user.username, equals('testuser'));
      expect(user.confirmed, isTrue);
      expect(user.blocked, isFalse);
    });

    test('should convert LDKUser to JSON', () {
      const user = LDKUser(
        id: 1,
        email: 'test@example.com',
        username: 'testuser',
        confirmed: true,
        blocked: false,
      );

      final json = user.toJson();

      expect(json['id'], equals(1));
      expect(json['email'], equals('test@example.com'));
      expect(json['username'], equals('testuser'));
      expect(json['confirmed'], isTrue);
      expect(json['blocked'], isFalse);
    });

    test('should create user copy with updated fields', () {
      const user = LDKUser(
        id: 1,
        email: 'test@example.com',
        username: 'testuser',
      );

      final updatedUser = user.copyWith(username: 'newusername');

      expect(updatedUser.id, equals(1));
      expect(updatedUser.email, equals('test@example.com'));
      expect(updatedUser.username, equals('newusername'));
    });
  });
}
