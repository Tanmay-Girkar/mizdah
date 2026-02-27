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

  static Future<void> saveToken(String token) async {
    await _storage.write(key: tokenKey, value: token);
  }

  static Future<String?> getToken() async {
    return await _storage.read(key: tokenKey);
  }

  static Future<void> deleteToken() async {
    await _storage.delete(key: tokenKey);
  }

  static Future<void> saveUserData({required String id, required String name}) async {
    await _storage.write(key: userIdKey, value: id);
    await _storage.write(key: userNameKey, value: name);
  }

  static Future<Map<String, String?>> getUserData() async {
    return {
      'id': await _storage.read(key: userIdKey),
      'name': await _storage.read(key: userNameKey),
    };
  }

  static Future<void> clearAll() async {
    await _storage.deleteAll();
  }
}
