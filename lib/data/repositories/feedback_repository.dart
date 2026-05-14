// ════════════════════════════════════════════════════════════════════
//  Feedback repository — POST to /api/feedback/call-rating
//  ────────────────────────────────────────────────────────────────────
//  Fire-and-forget telemetry. Never throws. Never blocks the user.
//  If the backend is down or the JWT is bad, we swallow the error
//  and the user still saw "Thanks for the feedback" on their
//  screen — that's deliberate. The worst outcome is one missed
//  data point in analytics.
//
//  One retry on network failure (2s back-off) so a single flaky
//  Wi-Fi hop doesn't drop the rating.
// ════════════════════════════════════════════════════════════════════

import 'package:flutter/foundation.dart';

import '../../core/config/api_config.dart';
import '../../core/network/api_client.dart';
import '../models/call_rating_models.dart';

class FeedbackRepository {
  final ApiClient _apiClient = ApiClient();

  /// Submit a call/meeting rating. Returns nothing — the call is
  /// effectively `void` from the UI's perspective. Logs success
  /// and failure for analytics; never throws.
  Future<void> submitCallRating({
    required String callId,
    required RatingKind kind,
    required int rating,
    required List<CallRatingTag> tags,
    String? comment,
    required Duration duration,
  }) async {
    final payload = <String, dynamic>{
      'callId': callId,
      'callType': kind.wire,
      'rating': rating,
      'tags': tags.map((t) => t.wire).toList(),
      if (comment != null && comment.trim().isNotEmpty)
        'comment': comment.trim(),
      'durationSeconds': duration.inSeconds,
      'ratedAt': DateTime.now().toUtc().toIso8601String(),
    };
    debugPrint('[feedback] submitCallRating → $payload');

    try {
      await _post(payload);
      debugPrint('[feedback] submit OK');
      return;
    } catch (e) {
      debugPrint('[feedback] first attempt failed: $e — retrying once in 2s');
    }
    // Single retry: covers transient Wi-Fi handoffs / cellular
    // micro-blips. Anything beyond is a backend / config issue
    // not worth burning more cycles on.
    await Future<void>.delayed(const Duration(seconds: 2));
    try {
      await _post(payload);
      debugPrint('[feedback] submit OK (after retry)');
    } catch (e) {
      // Final swallow. Rating is fire-and-forget — user saw success
      // already; we don't surface a snackbar on second failure.
      debugPrint('[feedback] submit failed permanently: $e');
    }
  }

  Future<void> _post(Map<String, dynamic> payload) async {
    await _apiClient.post(ApiConfig.feedbackCallRating, data: payload);
  }
}
