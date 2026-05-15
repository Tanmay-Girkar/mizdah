import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import '../models/models.dart';
import '../../core/network/api_client.dart';
import '../../core/config/api_config.dart';

class AuthRepository {
  final ApiClient _apiClient = ApiClient();

  Future<Map<String, dynamic>> signup(
    String email,
    String password,
    String name, {
    required String phone,
    required String phoneCountry,
  }) async {
    try {
      final response = await _apiClient.post(ApiConfig.authSignup, data: {
        'email': email,
        'password': password,
        'name': name,
        // Per docs/PHONE_AND_CONTACTS_BACKEND.md §2.1 — required on
        // every new signup. E.164 + ISO-3166-1 alpha-2.
        'phone': phone,
        'phone_country': phoneCountry,
      });

      if (response.data is! Map) throw Exception('Invalid server response format');
      Map<String, dynamic> data = Map<String, dynamic>.from(response.data);

      // Extract token from header if not in body.
      //
      // NOTE: when the backend has email verification enabled, signup
      // intentionally returns NO token (only `requiresVerification:
      // true`). The caller (AuthNotifier.signup) detects that case
      // and surfaces a "check your email" UX instead of failing.
      if (data['token'] == null) {
        data['token'] = _extractTokenFromHeaders(response.headers);
      }

      return data;
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> login(String email, String password) async {
    try {
      final response = await _apiClient.post(ApiConfig.authLogin, data: {
        'email': email,
        'password': password,
      });
      
      if (response.data is! Map) throw Exception('Invalid server response format');
      Map<String, dynamic> data = Map<String, dynamic>.from(response.data);
      
      // Extract token from header if not in body
      if (data['token'] == null) {
        data['token'] = _extractTokenFromHeaders(response.headers);
      }
      
      return data;
    } catch (e) {
      rethrow;
    }
  }

  String? _extractTokenFromHeaders(Headers headers) {
    final cookies = headers['set-cookie'];
    if (cookies == null || cookies.isEmpty) return null;

    for (var cookie in cookies) {
      if (cookie.contains('auth_token=')) {
        final start = cookie.indexOf('auth_token=') + 'auth_token='.length;
        var end = cookie.indexOf(';', start);
        if (end == -1) end = cookie.length;
        return cookie.substring(start, end);
      }
    }
    return null;
  }

  Future<User?> getMe() async {
    try {
      final response = await _apiClient.get(ApiConfig.authMe);
      final dynamic data = response.data;
      if (data is Map && data['user'] != null) {
        return User.fromJson(data['user']);
      }
    } catch (e) {
      debugPrint('Error fetching current user: $e');
    }
    return null;
  }

  Future<User> updateProfile({
    String? name,
    String? password,
    String? currentPassword,
    String? avatarUrl,
    String? phone,
    String? phoneCountry,
  }) async {
    try {
      final response = await _apiClient.post(ApiConfig.authUpdate, data: {
        if (name != null) 'name': name,
        if (password != null) 'password': password,
        // Per docs/PASSWORD_CHANGE_AND_RESET_BACKEND.md §3, every
        // password change MUST carry the user's current password.
        // Backend rejects with INVALID_CURRENT_PASSWORD (403) when
        // it's wrong or MISSING_CURRENT_PASSWORD (400) when absent
        // alongside `password`. Other update kinds (name, avatar,
        // phone) don't need it.
        if (currentPassword != null) 'current_password': currentPassword,
        // Backend exposes `avatar_url` on the user object (verified
        // live in /signup response 2026-05-09). Whether
        // /api/auth/update accepts an `avatar_url` field is documented
        // as the one outstanding backend confirmation in
        // docs/PROFILE_API.md — if the server ignores this key the
        // name/password parts of the patch still go through.
        if (avatarUrl != null) 'avatar_url': avatarUrl,
        // Per docs/PHONE_LINK_BACKEND.md §2.2 — phone + phone_country
        // travel as a pair. The Settings → Link phone screen sends
        // both together; backend rejects with INVALID_PHONE_COUNTRY
        // if one is present without the other.
        if (phone != null) 'phone': phone,
        if (phoneCountry != null) 'phone_country': phoneCountry,
      });
      return User.fromJson(response.data['user']);
    } catch (e) {
      rethrow;
    }
  }

  /// Upload an image (or any file) via the gateway's file service.
  /// Returns the public `fileUrl` on success — that URL can be passed
  /// to `updateProfile(avatarUrl: ...)` to set the user's photo.
  ///
  /// Endpoint: `POST /api/file/upload`, multipart/form-data, field
  /// name `file`. See "Edit Profile — Flutter Integration Guide" §2
  /// (the canonical contract shared by the backend team 2026-05-15).
  ///
  /// `uploaderId` is documented as optional — the backend extracts
  /// the uploader from the JWT — but we still pass it so the row
  /// is correctly attributed without depending on JWT-extraction
  /// behaviour the file-service controller has flip-flopped on. The
  /// older 500 ("Argument `uploaderId` is missing.") regression that
  /// `docs/FILE_UPLOAD_UPLOADER_ID_BACKEND.md` was written against
  /// is no longer reachable as long as we keep sending the field.
  ///
  /// Returns the canonical `fileUrl` field from the JSON response;
  /// also accepts `url` / `file_url` as legacy fallbacks for older
  /// server builds.
  Future<String> uploadFile({
    required String filePath,
    String? fileName,
    String? uploaderId,
  }) async {
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath, filename: fileName),
      if (uploaderId != null && uploaderId.isNotEmpty)
        'uploaderId': uploaderId,
    });
    final response = await _apiClient.postMultipart(
      ApiConfig.fileUpload,
      form,
    );
    final data = response.data;
    if (data is Map) {
      final url = data['fileUrl'] ?? data['url'] ?? data['file_url'];
      if (url is String && url.isNotEmpty) return url;
    }
    throw Exception('Upload succeeded but server returned no fileUrl');
  }

  /// Search the directory for users matching `q` (name or email
  /// substring). Backed by `GET /api/auth/users/search?q=<q>`.
  /// Returns an empty list on network errors so the UI can stay
  /// interactive instead of throwing on every keystroke.
  Future<List<User>> searchUsers(String query) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    try {
      final response = await _apiClient.get(
        '${ApiConfig.baseUrl}/api/auth/users/search',
        queryParameters: {'q': q},
      );
      final dynamic data = response.data;
      final List<dynamic> rawList;
      if (data is Map && data['users'] is List) {
        rawList = data['users'] as List<dynamic>;
      } else if (data is List) {
        rawList = data;
      } else {
        return const [];
      }
      return rawList
          .whereType<Map>()
          .map((m) => User.fromJson(Map<String, dynamic>.from(m)))
          .toList();
    } catch (e) {
      debugPrint('searchUsers failed: $e');
      return const [];
    }
  }

  // ── Forgot / reset password ───────────────────────────────────────
  // See docs/PASSWORD_CHANGE_AND_RESET_BACKEND.md §4 + §5. Both are
  // PUBLIC endpoints (no JWT). The first one always returns 200 with
  // the same body whether the email exists or not — kills email
  // enumeration. The second consumes the single-use token from the
  // email link.

  /// Request a password-reset email. Backend always returns 200
  /// regardless of whether the email exists; UI shows the same
  /// "If an account exists for that email, we sent a reset link"
  /// copy either way. Rethrows on transport errors so the caller
  /// can show "Couldn't send. Try again."
  Future<void> forgotPassword(String email) async {
    await _apiClient.post(
      ApiConfig.authForgotPassword,
      data: {'email': email.trim()},
    );
  }

  /// Consume a reset token from the email link + set a new password.
  /// On success returns the refreshed `User` and the fresh JWT —
  /// caller saves both and the user lands on Home logged-in.
  ///
  /// Error codes the caller should surface:
  ///   TOKEN_INVALID        → "Reset link isn't valid."
  ///   TOKEN_ALREADY_USED   → "This reset link has already been used."
  ///   TOKEN_EXPIRED        → "Reset link has expired. Request a new one."
  ///   WEAK_PASSWORD        → "Password must be at least 8 characters."
  Future<({User user, String token})> resetPassword({
    required String token,
    required String newPassword,
  }) async {
    final response = await _apiClient.post(
      ApiConfig.authResetPassword,
      data: {
        'token': token,
        'password': newPassword,
      },
    );
    final data = response.data;
    if (data is! Map) {
      throw Exception('reset-password: invalid server response');
    }
    final jwt = data['token']?.toString() ??
        _extractTokenFromHeaders(response.headers);
    if (jwt == null || jwt.isEmpty) {
      throw Exception('reset-password: no token in response');
    }
    final user = User.fromJson(
      Map<String, dynamic>.from(data['user'] as Map),
    );
    return (user: user, token: jwt);
  }
}
