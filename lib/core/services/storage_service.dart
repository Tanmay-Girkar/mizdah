import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class StorageService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock,
    ),
  );

  static const String tokenKey = 'auth_token';
  static const String userIdKey = 'auth_user_id';
  static const String userNameKey = 'auth_user_name';
  static const String userEmailKey = 'auth_user_email';
  static const String userAvatarKey = 'auth_user_avatar_url';

  static Future<void> saveToken(String token) async {
    await _storage.write(key: tokenKey, value: token);
  }

  static Future<String?> getToken() async {
    return await _storage.read(key: tokenKey);
  }

  static Future<void> deleteToken() async {
    await _storage.delete(key: tokenKey);
  }

  /// Persist enough of the user object to rehydrate auth state at
  /// startup even when /api/auth/me is unreachable or returns null
  /// (e.g. `session_superseded`). Email is essential — every chat /
  /// scheduling / "is this mine" comparison needs it.
  static Future<void> saveUserData({
    required String id,
    required String name,
    String? email,
    String? avatarUrl,
  }) async {
    await _storage.write(key: userIdKey, value: id);
    await _storage.write(key: userNameKey, value: name);
    if (email != null) {
      await _storage.write(key: userEmailKey, value: email);
    }
    if (avatarUrl != null) {
      await _storage.write(key: userAvatarKey, value: avatarUrl);
    }
  }

  static Future<Map<String, String?>> getUserData() async {
    return {
      'id': await _storage.read(key: userIdKey),
      'name': await _storage.read(key: userNameKey),
      'email': await _storage.read(key: userEmailKey),
      'avatarUrl': await _storage.read(key: userAvatarKey),
    };
  }

  static Future<void> clearAll() async {
    await _storage.deleteAll();
  }
}
