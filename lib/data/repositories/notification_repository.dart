import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import '../../core/network/api_client.dart';
import '../../core/config/api_config.dart';
import '../models/models.dart';

final notificationRepositoryProvider =
    Provider((ref) => NotificationRepository(ApiClient()));

/// Wraps the five `/api/notifications` endpoints documented in
/// docs/NOTIFICATIONS_BACKEND.md. Every read returns a structured
/// `NotificationsPage` so callers don't have to guess the response
/// envelope shape themselves.
///
/// Errors are swallowed and logged on the list / count paths so a
/// transient network blip doesn't blank the bell or the screen —
/// the UI just keeps showing the last successful payload. Mutating
/// calls (markAsRead, markAllAsRead, dismiss) re-throw so callers
/// can surface a snackbar.
class NotificationRepository {
  final ApiClient _apiClient;

  NotificationRepository(this._apiClient);

  /// `GET /api/notifications/user/:userId` — newest-first list.
  ///
  /// [limit] caps the page size (server hard-caps at 200).
  /// [before] is the ISO-8601 cursor from the previous page's
  ///   `nextCursor` — pass it to fetch older rows.
  /// [unreadOnly] flips the server-side `?unread=true` filter for
  ///   the bell-badge fast path.
  Future<NotificationsPage> getUserNotifications(
    String userId, {
    int? limit,
    String? before,
    bool unreadOnly = false,
  }) async {
    try {
      final response = await _apiClient.get(
        '${ApiConfig.notificationUser}/$userId',
        queryParameters: {
          if (limit != null) 'limit': limit,
          if (before != null) 'before': before,
          if (unreadOnly) 'unread': 'true',
        },
      );
      return NotificationsPage.fromAny(response.data);
    } catch (e) {
      debugPrint('getUserNotifications failed: $e');
      return const NotificationsPage(items: []);
    }
  }

  /// `GET /api/notifications/unread-count` — cheap badge fast path.
  /// Returns 0 on any failure so the bell defaults to "no dot"
  /// rather than crashing the header.
  Future<int> getUnreadCount() async {
    try {
      final response = await _apiClient.get(
        '${ApiConfig.notifications}/unread-count',
      );
      final data = response.data;
      if (data is Map) {
        final v = data['unreadCount'] ?? data['unread_count'];
        if (v is int) return v;
        if (v is num) return v.toInt();
      }
      return 0;
    } catch (e) {
      debugPrint('getUnreadCount failed: $e');
      return 0;
    }
  }

  /// `PATCH /api/notifications/:id/read` — mark a single row read.
  /// Idempotent — re-calling on an already-read row is a 200 no-op.
  Future<void> markAsRead(String notificationId) async {
    try {
      await _apiClient
          .patch('${ApiConfig.notifications}/$notificationId/read');
    } on DioException catch (e) {
      throw Exception(e.response?.data is Map
          ? (e.response?.data['error'] ?? 'Failed to mark as read')
          : 'Failed to mark as read: ${e.message}');
    }
  }

  /// `PATCH /api/notifications/read-all` — clear the unread badge.
  /// Returns the count the server says it just marked.
  Future<int> markAllAsRead() async {
    try {
      final response = await _apiClient
          .patch('${ApiConfig.notifications}/read-all');
      final data = response.data;
      if (data is Map) {
        final v = data['markedReadCount'] ?? data['marked_read_count'];
        if (v is int) return v;
        if (v is num) return v.toInt();
      }
      return 0;
    } on DioException catch (e) {
      throw Exception(e.response?.data is Map
          ? (e.response?.data['error'] ?? 'Failed to mark all as read')
          : 'Failed to mark all as read: ${e.message}');
    }
  }

  /// `DELETE /api/notifications/:id` — soft-dismiss one row.
  Future<void> dismiss(String notificationId) async {
    try {
      await _apiClient.delete('${ApiConfig.notifications}/$notificationId');
    } on DioException catch (e) {
      throw Exception(e.response?.data is Map
          ? (e.response?.data['error'] ?? 'Failed to dismiss')
          : 'Failed to dismiss: ${e.message}');
    }
  }
}
