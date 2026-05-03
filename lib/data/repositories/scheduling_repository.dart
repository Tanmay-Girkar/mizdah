import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/api_client.dart';
import '../../core/config/api_config.dart';

final schedulingRepositoryProvider = Provider((ref) => SchedulingRepository(ApiClient()));

class SchedulingRepository {
  final ApiClient _apiClient;

  SchedulingRepository(this._apiClient);

  /// Creates a schedule row. The optional [meetingId] / [meetingCode]
  /// should reference a Meeting that was already created (typically
  /// via `mizdahRepository.createMeeting()` moments before). The
  /// current production backend silently drops both fields — see
  /// docs/SCHEDULING_BACKEND.md — but we send them so this call
  /// becomes correct with zero frontend changes once the server is
  /// updated to persist them.
  Future<Map<String, dynamic>> scheduleMeeting({
    required String hostId,
    required String title,
    required DateTime startTime,
    required DateTime endTime,
    required String recurrence,
    required String timezone,
    String? meetingId,
    String? meetingCode,
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
          if (meetingId != null) 'meetingId': meetingId,
          // Some backends prefer one over the other — send both keys.
          if (meetingCode != null) 'meetingCode': meetingCode,
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
      debugPrint('Error fetching user schedules: $e');
      return []; // Return empty list instead of throwing to keep UI stable
    }
  }

  /// Deletes a schedule. The previous URL `/api/scheduling/schedule/<id>`
  /// returned 404 — the live backend route is `/api/scheduling/<id>`
  /// (verified against the deployed server). Build the URL by hand so
  /// the change is not coupled to ApiConfig.scheduling drifting.
  Future<void> cancelSchedule(String scheduleId) async {
    try {
      await _apiClient.delete(
        '${ApiConfig.baseUrl}/api/scheduling/$scheduleId',
      );
    } on DioException catch (e) {
      throw Exception(e.response?.data['message'] ?? 'Failed to cancel schedule: ${e.message}');
    }
  }
}
