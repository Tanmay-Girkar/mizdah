import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

enum AuthStatus { authenticated, unauthenticated, authenticating, initial }

class AuthState {
  final AuthStatus status;
  final String? token;
  final String? errorMessage;

  AuthState({
    this.status = AuthStatus.initial,
    this.token,
    this.errorMessage,
  });

  AuthState copyWith({
    AuthStatus? status,
    String? token,
    String? errorMessage,
  }) {
    return AuthState(
      status: status ?? this.status,
      token: token ?? this.token,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  static const _tokenKey = 'auth_token';

  AuthNotifier() : super(AuthState()) {
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    final token = await _storage.read(key: _tokenKey);
    if (token != null) {
      state = state.copyWith(status: AuthStatus.authenticated, token: token);
    } else {
      state = state.copyWith(status: AuthStatus.unauthenticated);
    }
  }

  Future<void> login(String email, String password) async {
    state = state.copyWith(status: AuthStatus.authenticating);
    
    // Mock API call
    await Future.delayed(const Duration(seconds: 2));
    
    if (email == "test@mizdah.com" && password == "password") {
      const token = "mock_jwt_token";
      await _storage.write(key: _tokenKey, value: token);
      state = state.copyWith(status: AuthStatus.authenticated, token: token);
    } else {
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        errorMessage: "Invalid email or password",
      );
    }
  }

  Future<void> loginWithOAuth(String provider) async {
    state = state.copyWith(status: AuthStatus.authenticating);
    await Future.delayed(const Duration(seconds: 1));
    // Mock success
    const token = "mock_oauth_token";
    await _storage.write(key: _tokenKey, value: token);
    state = state.copyWith(status: AuthStatus.authenticated, token: token);
  }

  Future<void> logout() async {
    await _storage.delete(key: _tokenKey);
    state = state.copyWith(status: AuthStatus.unauthenticated, token: null);
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier();
});
