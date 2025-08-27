import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:rxdart/rxdart.dart';

import 'exceptions.dart';
import 'models/responses.dart';
import 'models/user.dart';
import 'utils/http_client.dart';

/// Authentication service for Strapi integration.
class LDKAuth {
  /// Creates a new [LDKAuth] instance.
  LDKAuth(this._httpClient) {
    _init();
  }

  final LDKHttpClient _httpClient;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  static const String _tokenKey = 'ldk_auth_token';
  static const String _userKey = 'ldk_user_data';

  final BehaviorSubject<LDKUser?> _userSubject = BehaviorSubject<LDKUser?>();
  final BehaviorSubject<bool> _isAuthenticatedSubject =
      BehaviorSubject<bool>.seeded(false);

  /// Stream of the current user.
  Stream<LDKUser?> get userStream => _userSubject.stream;

  /// Stream of authentication state.
  Stream<bool> get authStateStream => _isAuthenticatedSubject.stream;

  /// Current user (null if not authenticated).
  LDKUser? get currentUser => _userSubject.valueOrNull;

  /// Whether the user is currently authenticated.
  bool get isAuthenticated => _isAuthenticatedSubject.value;

  /// Initializes the auth service by checking for stored credentials.
  Future<void> _init() async {
    try {
      final token = await _storage.read(key: _tokenKey);
      final userData = await _storage.read(key: _userKey);

      if (token != null && userData != null) {
        _httpClient.setAuthToken(token);

        // Try to parse stored user data
        try {
          final userMap = Map<String, dynamic>.from(
            jsonDecode(userData) as Map<String, dynamic>,
          );
          final user = LDKUser.fromJson(userMap);
          _userSubject.add(user);
          _isAuthenticatedSubject.add(true);
        } catch (e) {
          // If user data is corrupted, clear it
          await _clearStoredAuth();
        }
      }
    } catch (e) {
      // If there's any error during initialization, clear stored auth
      await _clearStoredAuth();
    }
  }

  /// Signs up a new user.
  Future<LDKUser> signUp({
    required String email,
    required String password,
    String? username,
    Map<String, dynamic>? additionalData,
  }) async {
    try {
      final data = {
        'email': email,
        'password': password,
        if (username != null) 'username': username,
        ...?additionalData,
      };

      final response = await _httpClient.post<Map<String, dynamic>>(
        '/api/auth/local/register',
        data: data,
      );

      if (response.data == null) {
        throw const LDKAuthException('Invalid response from server');
      }

      final authResponse = AuthResponse.fromJson(response.data!);
      final user = LDKUser.fromJson(authResponse.user);

      await _storeAuthData(authResponse.jwt, user);
      _httpClient.setAuthToken(authResponse.jwt);
      _userSubject.add(user);
      _isAuthenticatedSubject.add(true);

      return user;
    } catch (e) {
      if (e is LDKException) rethrow;
      throw LDKAuthException('Sign up failed: ${e.toString()}');
    }
  }

  /// Signs in an existing user.
  Future<LDKUser> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _httpClient.post<Map<String, dynamic>>(
        '/api/auth/local',
        data: {
          'identifier': email,
          'password': password,
        },
      );

      if (response.data == null) {
        throw const LDKAuthException('Invalid response from server');
      }

      final authResponse = AuthResponse.fromJson(response.data!);
      final user = LDKUser.fromJson(authResponse.user);

      await _storeAuthData(authResponse.jwt, user);
      _httpClient.setAuthToken(authResponse.jwt);
      _userSubject.add(user);
      _isAuthenticatedSubject.add(true);

      return user;
    } catch (e) {
      if (e is LDKException) rethrow;
      throw LDKAuthException('Sign in failed: ${e.toString()}');
    }
  }

  /// Signs out the current user.
  Future<void> signOut() async {
    try {
      await _clearStoredAuth();
      _httpClient.clearAuthToken();
      _userSubject.add(null);
      _isAuthenticatedSubject.add(false);
    } catch (e) {
      throw LDKAuthException('Sign out failed: ${e.toString()}');
    }
  }

  /// Sends a password reset email.
  Future<void> forgotPassword({required String email}) async {
    try {
      await _httpClient.post<Map<String, dynamic>>(
        '/api/auth/forgot-password',
        data: {'email': email},
      );
    } catch (e) {
      if (e is LDKException) rethrow;
      throw LDKAuthException('Password reset failed: ${e.toString()}');
    }
  }

  /// Resets password using reset token.
  Future<LDKUser> resetPassword({
    required String code,
    required String password,
    required String passwordConfirmation,
  }) async {
    try {
      final response = await _httpClient.post<Map<String, dynamic>>(
        '/api/auth/reset-password',
        data: {
          'code': code,
          'password': password,
          'passwordConfirmation': passwordConfirmation,
        },
      );

      if (response.data == null) {
        throw const LDKAuthException('Invalid response from server');
      }

      final authResponse = AuthResponse.fromJson(response.data!);
      final user = LDKUser.fromJson(authResponse.user);

      await _storeAuthData(authResponse.jwt, user);
      _httpClient.setAuthToken(authResponse.jwt);
      _userSubject.add(user);
      _isAuthenticatedSubject.add(true);

      return user;
    } catch (e) {
      if (e is LDKException) rethrow;
      throw LDKAuthException('Password reset failed: ${e.toString()}');
    }
  }

  /// Updates the current user's information.
  Future<LDKUser> updateUser(Map<String, dynamic> userData) async {
    if (!isAuthenticated || currentUser == null) {
      throw const LDKAuthException(
          'User must be authenticated to update profile');
    }

    try {
      final response = await _httpClient.put<Map<String, dynamic>>(
        '/api/users/${currentUser!.id}',
        data: userData,
      );

      if (response.data == null) {
        throw const LDKAuthException('Invalid response from server');
      }

      final updatedUser = LDKUser.fromJson(response.data!);

      // Update stored user data
      await _storage.write(
          key: _userKey, value: jsonEncode(updatedUser.toJson()));
      _userSubject.add(updatedUser);

      return updatedUser;
    } catch (e) {
      if (e is LDKException) rethrow;
      throw LDKAuthException('User update failed: ${e.toString()}');
    }
  }

  /// Changes the current user's password.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
    required String passwordConfirmation,
  }) async {
    if (!isAuthenticated) {
      throw const LDKAuthException(
          'User must be authenticated to change password');
    }

    try {
      await _httpClient.post<Map<String, dynamic>>(
        '/api/auth/change-password',
        data: {
          'currentPassword': currentPassword,
          'password': newPassword,
          'passwordConfirmation': passwordConfirmation,
        },
      );
    } catch (e) {
      if (e is LDKException) rethrow;
      throw LDKAuthException('Password change failed: ${e.toString()}');
    }
  }

  /// Refreshes the current user's data from the server.
  Future<LDKUser> refreshUser() async {
    if (!isAuthenticated) {
      throw const LDKAuthException(
          'User must be authenticated to refresh data');
    }

    try {
      final response =
          await _httpClient.get<Map<String, dynamic>>('/api/users/me');

      if (response.data == null) {
        throw const LDKAuthException('Invalid response from server');
      }

      final user = LDKUser.fromJson(response.data!);

      // Update stored user data
      await _storage.write(key: _userKey, value: jsonEncode(user.toJson()));
      _userSubject.add(user);

      return user;
    } catch (e) {
      if (e is LDKException) rethrow;
      throw LDKAuthException('User refresh failed: ${e.toString()}');
    }
  }

  /// Stores authentication data securely.
  Future<void> _storeAuthData(String token, LDKUser user) async {
    await Future.wait([
      _storage.write(key: _tokenKey, value: token),
      _storage.write(key: _userKey, value: jsonEncode(user.toJson())),
    ]);
  }

  /// Clears stored authentication data.
  Future<void> _clearStoredAuth() async {
    await Future.wait([
      _storage.delete(key: _tokenKey),
      _storage.delete(key: _userKey),
    ]);
  }

  /// Disposes of resources.
  void dispose() {
    _userSubject.close();
    _isAuthenticatedSubject.close();
  }
}
