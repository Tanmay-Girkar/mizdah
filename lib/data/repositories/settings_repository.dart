import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/api_client.dart';

final settingsRepositoryProvider = Provider((ref) => SettingsRepository(ApiClient()));

class SettingsRepository {
  final ApiClient _apiClient;

  SettingsRepository(this._apiClient);

  Future<void> sendFeedback({
    required String category,
    required String description,
    required String userEmail,
  }) async {
    try {
      await _apiClient.post(
        '/api/meeting/feedback',
        data: {
          'category': category,
          'description': description,
          'user_email': userEmail,
        },
      );
    } on DioException catch (e) {
      throw Exception(e.response?.data['message'] ?? 'Failed to send feedback: ${e.message}');
    }
  }

  Future<void> contactSupport({
    required String firstName,
    required String lastName,
    required String email,
    required String message,
  }) async {
    try {
      await _apiClient.post(
        '/api/meeting/contact',
        data: {
          'first_name': firstName,
          'last_name': lastName,
          'email': email,
          'message': message,
        },
      );
    } on DioException catch (e) {
      throw Exception(e.response?.data['message'] ?? 'Failed to contact support: ${e.message}');
    }
  }
}
