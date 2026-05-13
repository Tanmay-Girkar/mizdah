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
      // ── Timezone wire contract ────────────────────────────────
      // Always send the absolute instant in UTC (ISO string ending
      // in `Z`). The previous code sent `startTime.toIso8601String()`
      // which for a local DateTime produces a naive string like
      // `2026-05-11T16:00:00.000` — no timezone marker at all.
      //
      // What that did wrong: most backends storing into a TIMESTAMPTZ
      // column interpret a naive string as UTC, so 4PM IST got stored
      // as 4PM UTC. When the row came back the client parsed the
      // (now Z-suffixed) string as UTC and DateFormat rendered it in
      // the local clock — turning 4PM IST into 9:30 PM IST (or
      // whatever the local offset happens to flip it into). That's
      // exactly what the "wrong time on Upcoming Meetings" bug was.
      //
      // Sending UTC fixes it deterministically: the backend stores
      // the right instant, the client parses Z → UTC and `.toLocal()`
      // converts back to wall-clock 4PM regardless of host TZ. The
      // separate `timezone` field is preserved (Google Calendar wants
      // it for the event description) but no longer load-bearing for
      // time accuracy.
      final response = await _apiClient.post(
        ApiConfig.scheduling,
        data: {
          'hostId': hostId,
          // Backend renamed `title` → `topic`; send both for
          // forwards/backwards compat with the meeting service.
          'topic': title,
          'title': title,
          'startTime': startTime.toUtc().toIso8601String(),
          'endTime': endTime.toUtc().toIso8601String(),
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
