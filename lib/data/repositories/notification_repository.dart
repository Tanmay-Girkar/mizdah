import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import '../../core/network/api_client.dart';
import '../../core/config/api_config.dart';

final notificationRepositoryProvider = Provider((ref) => NotificationRepository(ApiClient()));

class NotificationRepository {
  final ApiClient _apiClient;

  NotificationRepository(this._apiClient);

  Future<List<dynamic>> getUserNotifications(String userId) async {
    try {
      final response = await _apiClient.get('${ApiConfig.notificationUser}/$userId');
      final dynamic data = response.data;
      if (data is Map && data.containsKey('data')) {
        return data['data'] as List<dynamic>;
      } else if (data is List) {
        return data;
      }
      return [];
    } catch (e) {
      debugPrint('Error fetching notifications: $e');
      return [];
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
