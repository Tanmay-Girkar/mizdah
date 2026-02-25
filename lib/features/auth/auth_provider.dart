import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:dio/dio.dart';
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
    final token = await _storage.read(key: _tokenKey);
    if (token != null) {
      state = state.copyWith(status: AuthStatus.authenticating, token: token);
      final user = await _authRepository.getMe();
      if (user != null) {
        state = state.copyWith(status: AuthStatus.authenticated, user: user);
      } else {
        await logout();
      }
    } else {
      state = state.copyWith(status: AuthStatus.unauthenticated);
    }
  }

  Future<void> login(String email, String password) async {
    state = state.copyWith(status: AuthStatus.authenticating, errorMessage: null);
    
    try {
      final data = await _authRepository.login(email, password);
      
      // Handle 2FA or missing token
      if (data['token'] == null) {
        if (data['requires2FA'] == true || data['message']?.toString().contains('OTP') == true) {
          state = state.copyWith(
            status: AuthStatus.unauthenticated,
            errorMessage: "2FA Required. Please verify your OTP.",
          );
          // In a real app, we would navigate to 2FA screen here
          return;
        }
        throw Exception("Login failed: Missing token in response");
      }

      final token = data['token'];
      final user = User.fromJson(data['user'] ?? {});
      
      await _storage.write(key: _tokenKey, value: token);
      state = state.copyWith(status: AuthStatus.authenticated, token: token, user: user);
    } catch (e) {
      print("Login error: $e");
      String message = "Invalid email or password";
      if (e is DioException) {
        message = e.response?.data['message'] ?? e.message ?? message;
      }
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        errorMessage: message,
      );
    }
  }

  Future<void> signup(String email, String password, String name) async {
    state = state.copyWith(status: AuthStatus.authenticating, errorMessage: null);
    
    try {
      final data = await _authRepository.signup(email, password, name);
      
      if (data['token'] == null) {
        throw Exception("Signup failed: Missing token in response");
      }

      final token = data['token'];
      final user = User.fromJson(data['user'] ?? {});
      
      await _storage.write(key: _tokenKey, value: token);
      state = state.copyWith(status: AuthStatus.authenticated, token: token, user: user);
    } catch (e) {
      print("Signup error: $e");
      String message = "Signup failed. Email might already exist.";
      if (e is DioException) {
        message = e.response?.data['message'] ?? e.message ?? message;
      }
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        errorMessage: message,
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

  Future<void> updateProfile({String? name, String? password}) async {
    try {
      final updatedUser = await _authRepository.updateProfile(name: name, password: password);
      state = state.copyWith(user: updatedUser);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> logout() async {
    await _storage.delete(key: _tokenKey);
    state = state.copyWith(status: AuthStatus.unauthenticated, token: null, user: null);
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier();
});
