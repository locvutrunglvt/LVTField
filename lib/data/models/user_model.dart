import 'dart:convert';

/// User model for local authentication
/// Author: Lộc Vũ Trung
class UserModel {
  final String id;
  final String username;
  final String fullName;
  final String? email;
  final String? organization;
  final String passwordHash;
  final DateTime createdAt;
  final DateTime lastLoginAt;

  UserModel({
    required this.id,
    required this.username,
    required this.fullName,
    this.email,
    this.organization,
    required this.passwordHash,
    required this.createdAt,
    required this.lastLoginAt,
  });

  /// Simple hash password (local-only auth, not for server)
  static String hashPassword(String password) {
    final bytes = utf8.encode('lvtfield_salt_$password');
    final hash = base64.encode(bytes);
    return hash;
  }

  /// Display name for exports (fullName or username)
  String get displayName => fullName.isNotEmpty ? fullName : username;

  /// Create from database map
  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      id: map['id'] as String,
      username: map['username'] as String,
      fullName: map['full_name'] as String? ?? '',
      email: map['email'] as String?,
      organization: map['organization'] as String?,
      passwordHash: map['password_hash'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      lastLoginAt: DateTime.parse(map['last_login_at'] as String),
    );
  }

  /// Convert to database map
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'username': username,
      'full_name': fullName,
      'email': email,
      'organization': organization,
      'password_hash': passwordHash,
      'created_at': createdAt.toIso8601String(),
      'last_login_at': lastLoginAt.toIso8601String(),
    };
  }

  UserModel copyWith({
    String? fullName,
    String? email,
    String? organization,
    DateTime? lastLoginAt,
  }) {
    return UserModel(
      id: id,
      username: username,
      fullName: fullName ?? this.fullName,
      email: email ?? this.email,
      organization: organization ?? this.organization,
      passwordHash: passwordHash,
      createdAt: createdAt,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
    );
  }
}
