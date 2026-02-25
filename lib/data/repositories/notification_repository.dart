import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/api_client.dart';
import '../../core/config/api_config.dart';
import '../models/models.dart';

final notificationRepositoryProvider = Provider((ref) => NotificationRepository(ApiClient()));

class NotificationRepository {
  final ApiClient _apiClient;

  NotificationRepository(this._apiClient);

  Future<List<dynamic>> getUserNotifications(String userId) async {
    try {
      final response = await _apiClient.get('${ApiConfig.notificationUser}/$userId');
      return response.data['data'] ?? response.data; // Depending on actual API payload
    } on DioException catch (e) {
      throw Exception(e.response?.data['message'] ?? 'Failed to load notifications: ${e.message}');
    }
  }

  Future<void> markAsRead(String notificationId) async {
    try {
      await _apiClient.patch('${ApiConfig.notifications}/$notificationId/read');
    } on DioException catch (e) {
      throw Exception(e.response?.data['message'] ?? 'Failed to mark notification as read: ${e.message}');
    }
  }
}
