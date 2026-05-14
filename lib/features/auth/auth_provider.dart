import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/models/models.dart';
import '../../core/services/push_notification_service.dart';
import '../../core/services/storage_service.dart';

/// DEV-ONLY auth bypass — when true, the app skips the login flow
/// entirely and boots with a fake authenticated user. Used while
/// the backend is offline so we can test screens that need a
/// signed-in user (chats, push notification token registration,
/// edit profile, etc.) without hitting `/api/auth/login`.
///
/// **Flip back to `false` before shipping** — the fake user has a
/// hardcoded id/email and can't actually authenticate against any
/// real endpoint. While true, login/signup screens never show.
const bool kBypassAuth = false;

enum AuthStatus { authenticated, unauthenticated, authenticating, initial }

class AuthState {
  final AuthStatus status;
  final String? token;
  final User? user;
  final String? errorMessage;
  /// One-shot signal raised when login hits `404 USER_NOT_FOUND` —
  /// the login screen listens for this, auto-routes to /register
  /// with the typed email + password in `GoRouterState.extra`, then
  /// calls `clearRegisterRedirect()` to drop it back to false.
  /// Avoids the previous "Create new account →" intermediate tap.
  final bool needsRegister;

  AuthState({
    this.status = AuthStatus.initial,
    this.token,
    this.user,
    this.errorMessage,
    this.needsRegister = false,
  });

  AuthState copyWith({
    AuthStatus? status,
    String? token,
    User? user,
    String? errorMessage,
    bool? needsRegister,
    bool clearError = false,
  }) {
    return AuthState(
      status: status ?? this.status,
      token: token ?? this.token,
      user: user ?? this.user,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      needsRegister: needsRegister ?? this.needsRegister,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthRepository _authRepository = AuthRepository();

  AuthNotifier() : super(AuthState()) {
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    // ── DEV-ONLY: skip the entire auth flow when kBypassAuth is on.
    //    See the constant's doc-comment at the top of this file.
    if (kBypassAuth) {
      final fakeUser = User(
        id: 'f2a59e06-316f-4717-8794-89d9e06e9e6c',
        email: 'test3@mizdah.dev',
        name: 'Test User 3',
        role: 'USER',
      );
      state = state.copyWith(
        status: AuthStatus.authenticated,
        token: 'dev_bypass_token',
        user: fakeUser,
      );
      return;
    }

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
    state = state.copyWith(
      status: AuthStatus.authenticating,
      clearError: true,
      needsRegister: false,
    );

    try {
      final data = await _authRepository.login(email, password);

      if (data['token'] == null) {
        if (data['requires2FA'] == true ||
            data['message']?.toString().contains('OTP') == true) {
          state = state.copyWith(
            status: AuthStatus.unauthenticated,
            errorMessage: "2FA required. Please verify your OTP.",
          );
          return;
        }
        throw Exception("Login failed: missing token in response");
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
      state = state.copyWith(
        status: AuthStatus.authenticated,
        token: token,
        user: user,
      );
      // Push the FCM token to the backend now that we have an auth
      // token. Best-effort; backend rejection is non-fatal.
      // ignore: discarded_futures
      PushNotificationService.instance.registerCurrentToken();
    } catch (e) {
      debugPrint("Login error: $e");
      // Map backend response → friendly UX. The backend distinguishes:
      //   404 + code USER_NOT_FOUND       → no account exists
      //   401 + Invalid credentials       → account exists, wrong pw
      //   403 + code EMAIL_NOT_VERIFIED   → account exists, unverified
      //   other                           → generic fallback
      String? message;
      bool routeToRegister = false;
      if (e is DioException) {
        final status = e.response?.statusCode;
        final body = e.response?.data;
        final code = body is Map ? body['code']?.toString() : null;
        final humanError = body is Map
            ? (body['error']?.toString() ?? body['message']?.toString())
            : null;

        if (status == 404 || code == 'USER_NOT_FOUND') {
          // Don't show a red error — we're about to auto-route. The
          // login screen reacts to `needsRegister` and pushes
          // /register with the email + password prefilled.
          routeToRegister = true;
        } else if (status == 401) {
          message = 'Incorrect password. Try again.';
        } else if (status == 403 && code == 'EMAIL_NOT_VERIFIED') {
          message = 'Verify your email first, then sign in.';
        } else if (humanError != null && humanError.isNotEmpty) {
          message = humanError;
        } else {
          message = 'Could not sign in. Check your connection and retry.';
        }
      } else {
        message = 'Could not sign in. Check your connection and retry.';
      }
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        errorMessage: message,
        needsRegister: routeToRegister,
        clearError: message == null,
      );
    }
  }

  /// Consume the one-shot `needsRegister` flag after the login screen
  /// has navigated to /register. Without this, a back-navigation that
  /// landed on /login again would immediately re-route to /register.
  void clearRegisterRedirect() {
    if (state.needsRegister) {
      state = state.copyWith(needsRegister: false);
    }
  }

  Future<void> signup(
    String email,
    String password,
    String name, {
    required String phone,
    required String phoneCountry,
  }) async {
    state = state.copyWith(status: AuthStatus.authenticating, errorMessage: null);

    try {
      final data = await _authRepository.signup(
        email,
        password,
        name,
        phone: phone,
        phoneCountry: phoneCountry,
      );

      // When the backend has email verification enabled, signup
      // intentionally returns NO token + `requiresVerification: true`.
      // Drop back to the unauthenticated state with a banner the
      // register screen can show ("Check your inbox to verify"),
      // not an error — this is the happy path, not a failure.
      final token = data['token'];
      if (token == null) {
        final needsVerification = data['requiresVerification'] == true ||
            (data['emailSent'] == true);
        state = state.copyWith(
          status: AuthStatus.unauthenticated,
          errorMessage: needsVerification
              ? "Account created. Check your inbox to verify your email, "
                  "then sign in."
              : "Signup succeeded but server returned no token.",
        );
        return;
      }

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
      // Surface the backend's structured error code where possible so
      // the user sees "Phone already in use" instead of a generic
      // "Signup failed". Backend error shape:
      //   { "error": "human readable", "code": "MACHINE_READABLE" }
      String message = "Signup failed. Email or phone might already exist.";
      if (e is DioException) {
        final body = e.response?.data;
        if (body is Map) {
          final humanReadable = body['error']?.toString() ??
              body['message']?.toString();
          if (humanReadable != null && humanReadable.isNotEmpty) {
            message = humanReadable;
          }
        } else {
          message = e.message ?? message;
        }
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
    String? phone,
    String? phoneCountry,
  }) async {
    try {
      final updatedUser = await _authRepository.updateProfile(
        name: name,
        password: password,
        avatarUrl: avatarUrl,
        phone: phone,
        phoneCountry: phoneCountry,
      );
      // Persist the fresh user data so a later restart doesn't fall
      // back to a stale name / email / avatar. Phone is propagated
      // via the in-memory `state.user` update below — StorageService
      // doesn't currently persist phone, but the next getMe() round-
      // trip rehydrates it from the server, and the in-memory User
      // is enough for the Settings screen and the Mizdah-contacts
      // matchability check.
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
