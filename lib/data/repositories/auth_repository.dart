import 'package:dio/dio.dart';
import '../models/models.dart';
import '../../core/network/api_client.dart';
import '../../core/config/api_config.dart';

class AuthRepository {
  final ApiClient _apiClient = ApiClient();

  Future<Map<String, dynamic>> signup(String email, String password, String name) async {
    try {
      final response = await _apiClient.post(ApiConfig.authSignup, data: {
        'email': email,
        'password': password,
        'name': name,
      });
      
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

  Future<Map<String, dynamic>> login(String email, String password) async {
    try {
      final response = await _apiClient.post(ApiConfig.authLogin, data: {
        'email': email,
        'password': password,
      });
      
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
      if (response.data['user'] != null) {
        return User.fromJson(response.data['user']);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<User> updateProfile({String? name, String? password}) async {
    try {
      final response = await _apiClient.post(ApiConfig.authUpdate, data: {
        if (name != null) 'name': name,
        if (password != null) 'password': password,
      });
      return User.fromJson(response.data['user']);
    } catch (e) {
      rethrow;
    }
  }
}
