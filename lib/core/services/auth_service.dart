import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../../data/database/app_database.dart';
import '../../data/models/user_model.dart';

/// Local authentication service
/// Manages user registration, login, and session
/// Author: Lộc Vũ Trung
class AuthService {
  UserModel? _currentUser;

  /// Get current logged-in user
  UserModel? get currentUser => _currentUser;

  /// Check if user is logged in
  bool get isLoggedIn => _currentUser != null;

  /// Register a new user
  Future<UserModel?> register({
    required String username,
    required String password,
    required String fullName,
    String? email,
    String? organization,
  }) async {
    try {
      final db = await AppDatabase.database;

      // Check if username already exists
      final existing = await db.query(
        'users',
        where: 'username = ?',
        whereArgs: [username.toLowerCase().trim()],
      );

      if (existing.isNotEmpty) {
        debugPrint('Auth: Username already exists');
        return null;
      }

      final now = DateTime.now();
      final user = UserModel(
        id: const Uuid().v4(),
        username: username.toLowerCase().trim(),
        fullName: fullName.trim(),
        email: email?.trim(),
        organization: organization?.trim(),
        passwordHash: UserModel.hashPassword(password),
        createdAt: now,
        lastLoginAt: now,
      );

      await db.insert('users', user.toMap());
      _currentUser = user;
      debugPrint('Auth: User registered - ${user.displayName}');
      return user;
    } catch (e) {
      debugPrint('Auth: Registration failed - $e');
      return null;
    }
  }

  /// Login with username and password
  Future<UserModel?> login(String username, String password) async {
    try {
      final db = await AppDatabase.database;

      final results = await db.query(
        'users',
        where: 'username = ? AND password_hash = ?',
        whereArgs: [
          username.toLowerCase().trim(),
          UserModel.hashPassword(password),
        ],
      );

      if (results.isEmpty) {
        debugPrint('Auth: Invalid credentials');
        return null;
      }

      final user = UserModel.fromMap(results.first);

      // Update last login
      await db.update(
        'users',
        {'last_login_at': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [user.id],
      );

      _currentUser = user.copyWith(lastLoginAt: DateTime.now());
      debugPrint('Auth: Login successful - ${user.displayName}');
      return _currentUser;
    } catch (e) {
      debugPrint('Auth: Login failed - $e');
      return null;
    }
  }

  /// Logout current user
  void logout() {
    debugPrint('Auth: User logged out - ${_currentUser?.displayName}');
    _currentUser = null;
  }

  /// Get all registered users
  Future<List<UserModel>> getAllUsers() async {
    try {
      final db = await AppDatabase.database;
      final results = await db.query('users', orderBy: 'full_name ASC');
      return results.map((m) => UserModel.fromMap(m)).toList();
    } catch (e) {
      debugPrint('Auth: Get users failed - $e');
      return [];
    }
  }

  /// Check if any users exist (for first-time setup)
  Future<bool> hasUsers() async {
    try {
      final db = await AppDatabase.database;
      final result = await db.rawQuery('SELECT COUNT(*) as count FROM users');
      return (result.first['count'] as int) > 0;
    } catch (e) {
      return false;
    }
  }
}
