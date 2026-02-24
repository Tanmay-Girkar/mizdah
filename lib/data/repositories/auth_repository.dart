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
      return response.data;
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
      return response.data;
    } catch (e) {
      rethrow;
    }
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
