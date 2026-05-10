import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/models/models.dart';
import '../../core/services/push_notification_service.dart';
import '../../core/services/storage_service.dart';

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

  AuthNotifier() : super(AuthState()) {
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    final token = await StorageService.getToken();
    final userData = await StorageService.getUserData();

    if (token != null) {
      if (userData['id'] != null && userData['name'] != null) {
        // Rehydrate the full user from secure storage — including
        // email and avatarUrl. These are essential for chat sender
        // matching, scheduling, and avatar rendering when
        // /api/auth/me is later unreachable or returns null
        // (`session_superseded`).
        state = state.copyWith(
          status: AuthStatus.authenticated,
          token: token,
          user: User(
            id: userData['id']!,
            name: userData['name']!,
            email: userData['email'] ?? '',
            role: 'USER',
            avatarUrl: userData['avatarUrl'],
          ),
        );
      } else {
        state = state.copyWith(status: AuthStatus.authenticating, token: token);
      }

      try {
        final user = await _authRepository.getMe();
        if (user != null) {
          await StorageService.saveUserData(
            id: user.id,
            name: user.name,
            email: user.email,
            avatarUrl: user.avatarUrl,
          );
          state = state.copyWith(status: AuthStatus.authenticated, user: user);
        } else if (userData['id'] == null) {
          // No cached user AND /me said null — actually logged out.
          await logout();
        }
        // ELSE: /me returned null but we have a cached user. Could
        // be `session_superseded` while another device holds the
        // active session, or a transient backend hiccup. Keep the
        // cached user in state so the UI keeps working — the token
        // is still valid for the other backend services that don't
        // gate on /me.
      } catch (e) {
        debugPrint("Initial auth check network error: $e");
      }
    } else {
      state = state.copyWith(status: AuthStatus.unauthenticated);
    }
  }

  Future<void> login(String email, String password) async {
    state = state.copyWith(status: AuthStatus.authenticating, errorMessage: null);
    
    try {
      final data = await _authRepository.login(email, password);
      
      if (data['token'] == null) {
        if (data['requires2FA'] == true || data['message']?.toString().contains('OTP') == true) {
          state = state.copyWith(
            status: AuthStatus.unauthenticated,
            errorMessage: "2FA Required. Please verify your OTP.",
          );
          return;
        }
        throw Exception("Login failed: Missing token in response");
      }

      final token = data['token'];
      final user = User.fromJson(data['user'] ?? {});

      await StorageService.saveToken(token);
      await StorageService.saveUserData(
        id: user.id,
        name: user.name,
        email: user.email,
        avatarUrl: user.avatarUrl,
      );
      state = state.copyWith(status: AuthStatus.authenticated, token: token, user: user);
      // Push the FCM token to the backend now that we have an auth
      // token. Best-effort; backend rejection is non-fatal.
      // ignore: discarded_futures
      PushNotificationService.instance.registerCurrentToken();
    } catch (e) {
      debugPrint("Login error: $e");
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

      await StorageService.saveToken(token);
      await StorageService.saveUserData(
        id: user.id,
        name: user.name,
        email: user.email,
        avatarUrl: user.avatarUrl,
      );
      state = state.copyWith(status: AuthStatus.authenticated, token: token, user: user);
      // Push the FCM token to the backend now that we have an auth
      // token. Best-effort; backend rejection is non-fatal.
      // ignore: discarded_futures
      PushNotificationService.instance.registerCurrentToken();
    } catch (e) {
      debugPrint("Signup error: $e");
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
    state = state.copyWith(status: AuthStatus.authenticating);
    await Future.delayed(const Duration(seconds: 1));
    const token = "mock_oauth_token";
    await StorageService.saveToken(token);
    state = state.copyWith(status: AuthStatus.authenticated, token: token);
  }

  Future<void> updateProfile({
    String? name,
    String? password,
    String? avatarUrl,
  }) async {
    try {
      final updatedUser = await _authRepository.updateProfile(
        name: name,
        password: password,
        avatarUrl: avatarUrl,
      );
      // Persist the fresh user data so a later restart doesn't fall
      // back to a stale name / email / avatar.
      await StorageService.saveUserData(
        id: updatedUser.id,
        name: updatedUser.name,
        email: updatedUser.email,
        avatarUrl: updatedUser.avatarUrl,
      );
      state = state.copyWith(user: updatedUser);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> logout() async {
    // Tell the backend to stop pushing to this device for the
    // soon-to-be-departed user. Best-effort — happens before we
    // wipe the JWT so the request can authenticate.
    try {
      await PushNotificationService.instance.unregister();
    } catch (_) {}
    await StorageService.clearAll();
    state = state.copyWith(status: AuthStatus.unauthenticated, token: null, user: null);
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier();
});
