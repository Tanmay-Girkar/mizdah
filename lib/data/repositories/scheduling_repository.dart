import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/api_client.dart';
import '../../core/config/api_config.dart';

final schedulingRepositoryProvider = Provider((ref) => SchedulingRepository(ApiClient()));

class SchedulingRepository {
  final ApiClient _apiClient;

  SchedulingRepository(this._apiClient);

  Future<Map<String, dynamic>> scheduleMeeting({
    required String hostId,
    required String title,
    required DateTime startTime,
    required DateTime endTime,
    required String recurrence,
    required String timezone,
  }) async {
    try {
      final response = await _apiClient.post(
        ApiConfig.scheduling,
        data: {
          'hostId': hostId,
          'title': title,
          'startTime': startTime.toIso8601String(),
          'endTime': endTime.toIso8601String(),
          'recurrence': recurrence,
          'timezone': timezone,
        },
      );
      return response.data;
    } on DioException catch (e) {
      throw Exception(e.response?.data['message'] ?? 'Failed to schedule meeting: ${e.message}');
    }
  }

  Future<List<dynamic>> getUserSchedules(String userId) async {
    try {
      final response = await _apiClient.get('${ApiConfig.userSchedules}/$userId');
      // Robust handling for both { "data": [...] } and directly [...]
      final dynamic data = response.data;
      if (data is Map && data.containsKey('data')) {
        return data['data'] as List<dynamic>;
      } else if (data is List) {
        return data;
      }
      return [];
    } catch (e) {
      print('Error fetching user schedules: $e');
      return []; // Return empty list instead of throwing to keep UI stable
    }
  }

  Future<void> cancelSchedule(String scheduleId) async {
    try {
      await _apiClient.delete('${ApiConfig.scheduling}/$scheduleId');
    } on DioException catch (e) {
      throw Exception(e.response?.data['message'] ?? 'Failed to cancel schedule: ${e.message}');
    }
  }
}
