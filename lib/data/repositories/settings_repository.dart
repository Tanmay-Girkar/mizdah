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

  /// Submit a problem / abuse report. Backed by `POST /api/abuse/report`
  /// which is the dedicated endpoint for issue reporting (verified
  /// live with curl against the dev backend on 2026-05-09 — schema
  /// is snake_case, required fields are `abuse_type` + `description`,
  /// optional `user_id` / `user_email` / `severity` / `steps`).
  ///
  /// Returns the server-issued `reportId` (UUID) so the UI can
  /// surface a reference number in the success snackbar; users can
  /// quote it when emailing support.
  Future<String> reportAbuse({
    required String abuseType,
    required String description,
    String? severity,
    String? steps,
    String? userId,
    String? userEmail,
  }) async {
    try {
      final response = await _apiClient.post(
        '/api/abuse/report',
        data: {
          'abuse_type': abuseType,
          'description': description,
          if (severity != null && severity.isNotEmpty) 'severity': severity,
          if (steps != null && steps.isNotEmpty) 'steps': steps,
          if (userId != null && userId.isNotEmpty) 'user_id': userId,
          if (userEmail != null && userEmail.isNotEmpty)
            'user_email': userEmail,
        },
      );
      // Server returns { "status": "received", "reportId": "<uuid>" }
      final data = response.data;
      if (data is Map && data['reportId'] is String) {
        return data['reportId'] as String;
      }
      // Some deployments may rename to id/report_id — fall back gracefully.
      if (data is Map) {
        for (final key in const ['id', 'report_id']) {
          final v = data[key];
          if (v is String && v.isNotEmpty) return v;
        }
      }
      return '';
    } on DioException catch (e) {
      final body = e.response?.data;
      final msg = body is Map
          ? (body['error'] ?? body['message'])
          : null;
      throw Exception(msg ?? 'Failed to send report: ${e.message}');
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
