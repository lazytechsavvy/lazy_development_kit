import 'package:json_annotation/json_annotation.dart';

part 'user.g.dart';

/// Represents a Strapi user with authentication information.
@JsonSerializable()
class LDKUser {
  /// Creates a new [LDKUser] instance.
  const LDKUser({
    required this.id,
    required this.email,
    this.username,
    this.firstName,
    this.lastName,
    this.provider,
    this.confirmed,
    this.blocked,
    this.createdAt,
    this.updatedAt,
  });

  /// Creates a [LDKUser] from a JSON map.
  factory LDKUser.fromJson(Map<String, dynamic> json) =>
      _$LDKUserFromJson(json);

  /// The unique identifier for the user.
  final int id;

  /// The user's email address.
  final String email;

  /// The user's username (optional).
  final String? username;

  /// The user's first name (optional).
  @JsonKey(name: 'first_name')
  final String? firstName;

  /// The user's last name (optional).
  @JsonKey(name: 'last_name')
  final String? lastName;

  /// The authentication provider used (e.g., 'local', 'google').
  final String? provider;

  /// Whether the user's email has been confirmed.
  final bool? confirmed;

  /// Whether the user account is blocked.
  final bool? blocked;

  /// When the user account was created.
  @JsonKey(name: 'created_at')
  final DateTime? createdAt;

  /// When the user account was last updated.
  @JsonKey(name: 'updated_at')
  final DateTime? updatedAt;

  /// Converts the user to a JSON map.
  Map<String, dynamic> toJson() => _$LDKUserToJson(this);

  /// Creates a copy of this user with the given fields replaced.
  LDKUser copyWith({
    int? id,
    String? email,
    String? username,
    String? firstName,
    String? lastName,
    String? provider,
    bool? confirmed,
    bool? blocked,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return LDKUser(
      id: id ?? this.id,
      email: email ?? this.email,
      username: username ?? this.username,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      provider: provider ?? this.provider,
      confirmed: confirmed ?? this.confirmed,
      blocked: blocked ?? this.blocked,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LDKUser && other.id == id && other.email == email;
  }

  @override
  int get hashCode => Object.hash(id, email);

  @override
  String toString() {
    return 'LDKUser(id: $id, email: $email, username: $username)';
  }
}
