import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/auth_service.dart';
import '../../data/models/user_model.dart';

/// Global auth service provider
final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService();
});

/// Current user state provider
final currentUserProvider = StateProvider<UserModel?>((ref) => null);
