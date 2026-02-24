import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/models/models.dart';

enum AuthStatus { authenticated, unauthenticated, authenticating, initial }

class AuthState {
  final AuthStatus status;
  final String? token;
  final User? user;
  final String? errorMessage;

  AuthState({
    this.status = AuthStatus.initial,
    this.token,
    this.user,
    this.errorMessage,
  });

  AuthState copyWith({
    AuthStatus? status,
    String? token,
    User? user,
    String? errorMessage,
  }) {
    return AuthState(
      status: status ?? this.status,
      token: token ?? this.token,
      user: user ?? this.user,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthRepository _authRepository = AuthRepository();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  static const _tokenKey = 'auth_token';

  AuthNotifier() : super(AuthState()) {
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    // Mock authentication for UI development
    state = state.copyWith(
      status: AuthStatus.authenticated,
      token: 'mock_token',
      user: User(id: 'mock-1', name: 'Mustafa Omen', email: 'mustafa@example.com', role: 'USER'),
    );
  }

  Future<void> login(String email, String password) async {
    state = state.copyWith(status: AuthStatus.authenticating, errorMessage: null);
    
    try {
      final data = await _authRepository.login(email, password);
      final token = data['token'];
      final user = User.fromJson(data['user']);
      
      await _storage.write(key: _tokenKey, value: token);
      state = state.copyWith(status: AuthStatus.authenticated, token: token, user: user);
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        errorMessage: "Invalid email or password",
      );
    }
  }

  Future<void> signup(String email, String password, String name) async {
    state = state.copyWith(status: AuthStatus.authenticating, errorMessage: null);
    
    try {
      final data = await _authRepository.signup(email, password, name);
      final token = data['token'];
      final user = User.fromJson(data['user']);
      
      await _storage.write(key: _tokenKey, value: token);
      state = state.copyWith(status: AuthStatus.authenticated, token: token, user: user);
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        errorMessage: "Signup failed. Email might already exist.",
      );
    }
  }

  Future<void> loginWithOAuth(String provider) async {
    // Note: Swagger doesn't have OAuth endpoints yet. This remains a mock or placeholder.
    state = state.copyWith(status: AuthStatus.authenticating);
    await Future.delayed(const Duration(seconds: 1));
    const token = "mock_oauth_token";
    await _storage.write(key: _tokenKey, value: token);
    state = state.copyWith(status: AuthStatus.authenticated, token: token);
  }

  Future<void> logout() async {
    await _storage.delete(key: _tokenKey);
    state = state.copyWith(status: AuthStatus.unauthenticated, token: null, user: null);
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier();
});
