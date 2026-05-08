import 'package:flutter/foundation.dart';
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
}
