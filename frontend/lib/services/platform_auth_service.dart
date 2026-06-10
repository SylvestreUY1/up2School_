import '../models/user.dart';
import 'auth_service.dart';

class PlatformAuthService {
  final AuthService _authService = AuthService();

  Stream<UserModel?> get authStateChanges => _authService.authStateChanges;

  Future<UserModel?> signUpWithEmail({
    required String email,
    required String password,
    required String name,
    String? phone,
    required String faculty,
    required String level,
    required String field,
  }) {
    return _authService.registerWithEmail(
      email: email,
      password: password,
      name: name,
      phone: phone,
      faculty: faculty,
      level: level,
      field: field,
    );
  }

  Future<UserModel?> signInWithEmail({
    required String email,
    required String password,
  }) {
    return _authService.signInWithEmail(email, password);
  }

  Future<void> signOut() => _authService.signOut();

  void dispose() {}
}
