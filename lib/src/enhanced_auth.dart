import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:logger/logger.dart';
import 'package:rxdart/rxdart.dart';

import 'package:strapi_ldk/src/auth.dart';
import 'package:strapi_ldk/src/exceptions.dart';
import 'package:strapi_ldk/src/models/responses.dart';
import 'package:strapi_ldk/src/models/user.dart';
import 'package:strapi_ldk/src/utils/http_client.dart';

/// Enhanced authentication service with token refresh and improved security.
class LDKEnhancedAuth {
  /// Creates a new [LDKEnhancedAuth] instance.
  LDKEnhancedAuth(this._httpClient) {
    _auth = LDKAuth(_httpClient);
    _logger = Logger();
    _storage = const FlutterSecureStorage();
    _tokenRefreshController = BehaviorSubject<bool>.seeded(false);
    _securityEventsController = BehaviorSubject<SecurityEvent?>();

    _initializeTokenRefresh();
  }

  final LDKHttpClient _httpClient;
  late final LDKAuth _auth;
  late final Logger _logger;
  late final FlutterSecureStorage _storage;
  late final BehaviorSubject<bool> _tokenRefreshController;
  late final BehaviorSubject<SecurityEvent?> _securityEventsController;

  Timer? _tokenRefreshTimer;
  String? _refreshToken;
  DateTime? _tokenExpiryTime;

  static const String _refreshTokenKey = 'ldk_refresh_token';
  static const String _tokenExpiryKey = 'ldk_token_expiry';
  static const String _deviceIdKey = 'ldk_device_id';
  static const String _biometricHashKey = 'ldk_biometric_hash';
  static const String _tokenKey = 'ldk_auth_token';
  static const String _userKey = 'ldk_user_data';

  /// Stream of the current user.
  Stream<LDKUser?> get userStream => _auth.userStream;

  /// Stream of authentication state.
  Stream<bool> get authStateStream => _auth.authStateStream;

  /// Current user (null if not authenticated).
  LDKUser? get currentUser => _auth.currentUser;

  /// Whether the user is currently authenticated.
  bool get isAuthenticated => _auth.isAuthenticated;

  /// Stream of token refresh status.
  Stream<bool> get tokenRefreshStream => _tokenRefreshController.stream;

  /// Stream of security events.
  Stream<SecurityEvent?> get securityEventsStream =>
      _securityEventsController.stream;

  /// Whether token is currently being refreshed.
  bool get isRefreshingToken => _tokenRefreshController.value;

  /// Initializes token refresh mechanism.
  void _initializeTokenRefresh() {
    // Listen to auth state changes to setup token refresh
    authStateStream.listen((isAuthenticated) {
      if (isAuthenticated && currentUser != null) {
        _scheduleTokenRefresh();
      } else {
        _cancelTokenRefresh();
      }
    });
  }

  /// Signs in a user with enhanced security features.
  Future<LDKUser> signIn({
    required String email,
    required String password,
    bool rememberMe = false,
    String? deviceName,
  }) async {
    try {
      // Generate device fingerprint
      final deviceId = await _getOrCreateDeviceId();

      final response = await _httpClient.post<Map<String, dynamic>>(
        '/api/auth/local',
        data: {
          'identifier': email,
          'password': password,
          'deviceId': deviceId,
          'deviceName': deviceName ?? 'Flutter App',
          'rememberMe': rememberMe,
        },
      );

      if (response.data == null) {
        throw const LDKAuthException('Invalid response from server');
      }

      final authResponse = EnhancedAuthResponse.fromJson(response.data!);
      final user = LDKUser.fromJson(authResponse.user);

      // Store tokens and user data
      await _storeEnhancedAuthData(authResponse, user, rememberMe);

      // Set up token refresh
      _httpClient.setAuthToken(authResponse.jwt);
      _scheduleTokenRefresh();

      // Emit security event
      _securityEventsController.add(SecurityEvent(
        type: SecurityEventType.login,
        timestamp: DateTime.now(),
        deviceId: deviceId,
        userAgent: 'Flutter LDK',
      ));

      _logger.i('User signed in successfully: ${user.email}');
      return user;
    } catch (e) {
      if (e is LDKException) rethrow;
      throw LDKAuthException('Enhanced sign in failed: ${e.toString()}');
    }
  }

  /// Signs up a new user with enhanced validation.
  Future<LDKUser> signUp({
    required String email,
    required String password,
    String? username,
    Map<String, dynamic>? additionalData,
    bool requireEmailVerification = true,
  }) async {
    try {
      // Validate password strength
      _validatePasswordStrength(password);

      final deviceId = await _getOrCreateDeviceId();

      final data = {
        'email': email,
        'password': password,
        'deviceId': deviceId,
        'requireEmailVerification': requireEmailVerification,
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

      final authResponse = EnhancedAuthResponse.fromJson(response.data!);
      final user = LDKUser.fromJson(authResponse.user);

      if (!requireEmailVerification) {
        await _storeEnhancedAuthData(authResponse, user, false);
        _httpClient.setAuthToken(authResponse.jwt);
        _scheduleTokenRefresh();
      }

      // Emit security event
      final deviceId2 = await _getOrCreateDeviceId();
      _securityEventsController.add(SecurityEvent(
        type: SecurityEventType.registration,
        timestamp: DateTime.now(),
        deviceId: deviceId2,
        userAgent: 'Flutter LDK',
      ));

      _logger.i('User signed up successfully: ${user.email}');
      return user;
    } catch (e) {
      if (e is LDKException) rethrow;
      throw LDKAuthException('Enhanced sign up failed: ${e.toString()}');
    }
  }

  /// Signs out the current user.
  Future<void> signOut() async {
    try {
      // Emit security event before signing out
      if (isAuthenticated) {
        final deviceId = await _getOrCreateDeviceId();
        _securityEventsController.add(SecurityEvent(
          type: SecurityEventType.logout,
          timestamp: DateTime.now(),
          deviceId: deviceId,
        ));
      }

      // Revoke refresh token on server
      if (_refreshToken != null) {
        try {
          await _httpClient.post<Map<String, dynamic>>(
            '/api/auth/revoke',
            data: {'refreshToken': _refreshToken},
          );
        } catch (e) {
          _logger.w('Failed to revoke refresh token: $e');
        }
      }

      _cancelTokenRefresh();
      await _clearStoredAuth();
      _httpClient.clearAuthToken();

      _refreshToken = null;
      _tokenExpiryTime = null;

      _logger.i('User signed out successfully');
    } catch (e) {
      throw LDKAuthException('Enhanced sign out failed: ${e.toString()}');
    }
  }

  /// Refreshes the authentication token.
  Future<void> refreshToken() async {
    if (isRefreshingToken) return;

    try {
      _tokenRefreshController.add(true);
      _logger.d('Refreshing authentication token');

      final refreshToken = await _storage.read(key: _refreshTokenKey);
      if (refreshToken == null) {
        throw const LDKAuthException('No refresh token available');
      }

      final deviceId = await _getOrCreateDeviceId();

      final response = await _httpClient.post<Map<String, dynamic>>(
        '/api/auth/refresh',
        data: {
          'refreshToken': refreshToken,
          'deviceId': deviceId,
        },
      );

      if (response.data == null) {
        throw const LDKAuthException('Invalid refresh response from server');
      }

      final authResponse = EnhancedAuthResponse.fromJson(response.data!);

      // Update stored tokens
      await _storage.write(key: _tokenKey, value: authResponse.jwt);
      if (authResponse.refreshToken != null) {
        await _storage.write(
            key: _refreshTokenKey, value: authResponse.refreshToken);
      }

      // Update expiry time
      if (authResponse.expiresIn != null) {
        final expiryTime =
            DateTime.now().add(Duration(seconds: authResponse.expiresIn!));
        await _storage.write(
            key: _tokenExpiryKey, value: expiryTime.toIso8601String());
        _tokenExpiryTime = expiryTime;
      }

      _httpClient.setAuthToken(authResponse.jwt);
      _scheduleTokenRefresh();

      // Emit security event
      _securityEventsController.add(SecurityEvent(
        type: SecurityEventType.tokenRefresh,
        timestamp: DateTime.now(),
        deviceId: deviceId,
      ));

      _logger.i('Token refreshed successfully');
    } catch (e) {
      _logger.e('Token refresh failed: $e');

      // If refresh fails, sign out the user
      await signOut();
      throw LDKAuthException('Token refresh failed: ${e.toString()}');
    } finally {
      _tokenRefreshController.add(false);
    }
  }

  /// Gets the current user information.
  Future<LDKUser?> getCurrentUser() async {
    return _auth.currentUser;
  }

  /// Updates the current user's information.
  Future<LDKUser> updateUser(Map<String, dynamic> userData) async {
    return _auth.updateUser(userData);
  }

  /// Requests a password reset.
  Future<void> forgotPassword(String email) async {
    return _auth.forgotPassword(email: email);
  }

  /// Enables biometric authentication.
  Future<void> enableBiometric({
    required String password,
    String? biometricPrompt,
  }) async {
    try {
      if (!isAuthenticated || currentUser == null) {
        throw const LDKAuthException(
            'User must be authenticated to enable biometric');
      }

      // Verify current password
      await _verifyPassword(password);

      // Generate biometric hash
      final biometricHash =
          _generateBiometricHash(currentUser!.email, password);

      // Store biometric hash
      await _storage.write(key: _biometricHashKey, value: biometricHash);

      _logger.i('Biometric authentication enabled');

      // Emit security event
      final deviceId = await _getOrCreateDeviceId();
      _securityEventsController.add(SecurityEvent(
        type: SecurityEventType.biometricEnabled,
        timestamp: DateTime.now(),
        deviceId: deviceId,
      ));
    } catch (e) {
      if (e is LDKException) rethrow;
      throw LDKAuthException('Failed to enable biometric: ${e.toString()}');
    }
  }

  /// Signs in using biometric authentication.
  Future<LDKUser> signInWithBiometric({
    required String email,
    String? biometricPrompt,
  }) async {
    try {
      final storedHash = await _storage.read(key: _biometricHashKey);
      if (storedHash == null) {
        throw const LDKAuthException('Biometric authentication not enabled');
      }

      final deviceId = await _getOrCreateDeviceId();

      final response = await _httpClient.post<Map<String, dynamic>>(
        '/api/auth/biometric',
        data: {
          'email': email,
          'biometricHash': storedHash,
          'deviceId': deviceId,
        },
      );

      if (response.data == null) {
        throw const LDKAuthException('Invalid biometric response from server');
      }

      final authResponse = EnhancedAuthResponse.fromJson(response.data!);
      final user = LDKUser.fromJson(authResponse.user);

      await _storeEnhancedAuthData(authResponse, user, true);
      _httpClient.setAuthToken(authResponse.jwt);
      _scheduleTokenRefresh();

      // Emit security event
      _securityEventsController.add(SecurityEvent(
        type: SecurityEventType.biometricLogin,
        timestamp: DateTime.now(),
        deviceId: deviceId,
      ));

      _logger.i('Biometric sign in successful: ${user.email}');
      return user;
    } catch (e) {
      if (e is LDKException) rethrow;
      throw LDKAuthException('Biometric sign in failed: ${e.toString()}');
    }
  }

  /// Verifies user's current password.
  Future<void> _verifyPassword(String password) async {
    if (!isAuthenticated || currentUser == null) {
      throw const LDKAuthException('User must be authenticated');
    }

    final response = await _httpClient.post<Map<String, dynamic>>(
      '/api/auth/verify-password',
      data: {
        'userId': currentUser!.id,
        'password': password,
      },
    );

    if (response.data?['valid'] != true) {
      throw const LDKAuthException('Invalid password');
    }
  }

  /// Validates password strength.
  void _validatePasswordStrength(String password) {
    if (password.length < 8) {
      throw const LDKValidationException(
          'Password must be at least 8 characters long');
    }

    if (!password.contains(RegExp(r'[A-Z]'))) {
      throw const LDKValidationException(
          'Password must contain at least one uppercase letter');
    }

    if (!password.contains(RegExp(r'[a-z]'))) {
      throw const LDKValidationException(
          'Password must contain at least one lowercase letter');
    }

    if (!password.contains(RegExp(r'[0-9]'))) {
      throw const LDKValidationException(
          'Password must contain at least one number');
    }

    if (!password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'))) {
      throw const LDKValidationException(
          'Password must contain at least one special character');
    }
  }

  /// Gets or creates a unique device ID.
  Future<String> _getOrCreateDeviceId() async {
    String? deviceId = await _storage.read(key: _deviceIdKey);

    if (deviceId == null) {
      // Generate a new device ID
      final bytes = utf8.encode(
          '${DateTime.now().millisecondsSinceEpoch}_${DateTime.now().microsecond}');
      final digest = sha256.convert(bytes);
      deviceId = digest.toString();

      await _storage.write(key: _deviceIdKey, value: deviceId);
    }

    return deviceId;
  }

  /// Generates a biometric hash.
  String _generateBiometricHash(String email, String password) {
    final combined =
        '$email:$password:${DateTime.now().millisecondsSinceEpoch}';
    final bytes = utf8.encode(combined);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Stores enhanced authentication data.
  Future<void> _storeEnhancedAuthData(
    EnhancedAuthResponse authResponse,
    LDKUser user,
    bool rememberMe,
  ) async {
    await Future.wait([
      _storage.write(key: _tokenKey, value: authResponse.jwt),
      _storage.write(key: _userKey, value: jsonEncode(user.toJson())),
      if (authResponse.refreshToken != null)
        _storage.write(key: _refreshTokenKey, value: authResponse.refreshToken),
    ]);

    // Store token expiry time
    if (authResponse.expiresIn != null) {
      final expiryTime =
          DateTime.now().add(Duration(seconds: authResponse.expiresIn!));
      await _storage.write(
          key: _tokenExpiryKey, value: expiryTime.toIso8601String());
      _tokenExpiryTime = expiryTime;
    }

    _refreshToken = authResponse.refreshToken;
  }

  /// Schedules automatic token refresh.
  void _scheduleTokenRefresh() {
    _cancelTokenRefresh();

    if (_tokenExpiryTime == null) return;

    // Refresh token 5 minutes before expiry
    final refreshTime = _tokenExpiryTime!.subtract(const Duration(minutes: 5));
    final now = DateTime.now();

    if (refreshTime.isBefore(now)) {
      // Token expires soon, refresh immediately
      refreshToken();
      return;
    }

    final duration = refreshTime.difference(now);
    _tokenRefreshTimer = Timer(duration, () {
      refreshToken();
    });

    _logger.d('Token refresh scheduled for ${refreshTime.toIso8601String()}');
  }

  /// Cancels automatic token refresh.
  void _cancelTokenRefresh() {
    _tokenRefreshTimer?.cancel();
    _tokenRefreshTimer = null;
  }

  /// Clears stored authentication data.
  Future<void> _clearStoredAuth() async {
    await Future.wait([
      _storage.delete(key: _tokenKey),
      _storage.delete(key: _userKey),
      _storage.delete(key: _refreshTokenKey),
      _storage.delete(key: _tokenExpiryKey),
    ]);
  }

  /// Disposes of resources.
  void dispose() {
    _cancelTokenRefresh();
    _tokenRefreshController.close();
    _securityEventsController.close();
    _auth.dispose();
  }
}

/// Enhanced authentication response with refresh token support.
class EnhancedAuthResponse extends AuthResponse {
  /// Creates a new [EnhancedAuthResponse].
  const EnhancedAuthResponse({
    required super.jwt,
    required super.user,
    this.refreshToken,
    this.expiresIn,
  });

  /// Creates an [EnhancedAuthResponse] from JSON data.
  factory EnhancedAuthResponse.fromJson(Map<String, dynamic> json) {
    return EnhancedAuthResponse(
      jwt: json['jwt'] as String,
      user: json['user'] as Map<String, dynamic>,
      refreshToken: json['refreshToken'] as String?,
      expiresIn: json['expiresIn'] as int?,
    );
  }

  /// Refresh token for automatic token renewal.
  final String? refreshToken;

  /// Token expiry time in seconds.
  final int? expiresIn;

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'refreshToken': refreshToken,
      'expiresIn': expiresIn,
    };
  }
}

/// Represents a security event.
class SecurityEvent {
  /// Creates a new [SecurityEvent].
  const SecurityEvent({
    required this.type,
    required this.timestamp,
    this.deviceId,
    this.userAgent,
    this.ipAddress,
    this.location,
  });

  /// Type of security event.
  final SecurityEventType type;

  /// When the event occurred.
  final DateTime timestamp;

  /// Device ID where the event occurred.
  final String? deviceId;

  /// User agent string.
  final String? userAgent;

  /// IP address (if available).
  final String? ipAddress;

  /// Location information (if available).
  final String? location;

  @override
  String toString() {
    return 'SecurityEvent(type: $type, timestamp: $timestamp, deviceId: $deviceId)';
  }
}

/// Types of security events.
enum SecurityEventType {
  /// User logged in.
  login,

  /// User logged out.
  logout,

  /// User registered.
  registration,

  /// Token was refreshed.
  tokenRefresh,

  /// Biometric authentication enabled.
  biometricEnabled,

  /// User signed in with biometric.
  biometricLogin,

  /// Password changed.
  passwordChanged,

  /// Account locked.
  accountLocked,

  /// Suspicious activity detected.
  suspiciousActivity,
}
