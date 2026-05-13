// ════════════════════════════════════════════════════════════════════
//  MeetingPresence — wire-format model for the `meeting-updated`
//                    socket event and the live fields on the
//                    meetings REST endpoint
// ────────────────────────────────────────────────────────────────────
//  Shape mirrors protocol §5.3:
//
//    { meetingId, meetingCode, isActive, membersCount, endedAt }
//
//  Parser is permissive on field names (camelCase OR snake_case) so
//  it works for both the socket payload (camelCase per the spec) and
//  the REST endpoints (snake_case per the existing convention).
// ════════════════════════════════════════════════════════════════════

import 'package:flutter/foundation.dart';

@immutable
class MeetingPresence {
  /// Meeting's UUID. Always present.
  final String meetingId;

  /// Human-readable join code. May be absent on the socket payload
  /// (server might only send id), so it's nullable. The recent-list
  /// UI uses code for display + rejoin routing, so we prefer it when
  /// available.
  final String? meetingCode;

  /// True while at least one participant is active, per the
  /// invariant in protocol §2.
  final bool isActive;

  /// Current participant count. `0` when `isActive == false`.
  final int membersCount;

  /// When the meeting deactivated. Non-null iff `isActive == false`.
  final DateTime? endedAt;

  const MeetingPresence({
    required this.meetingId,
    this.meetingCode,
    required this.isActive,
    required this.membersCount,
    this.endedAt,
  });

  /// Returns `null` when the payload is missing `meetingId` (or its
  /// equivalent) — we can't index without a key. Callers log and
  /// skip in that case rather than throwing, because dropping one
  /// malformed event is preferable to crashing the whole stream.
  static MeetingPresence? fromJson(Map<String, dynamic> data) {
    // meetingId may arrive under any of these names depending on
    // whether this is the socket event (camelCase) or a REST snapshot
    // row (snake_case + optional `id` for hosted-meeting rows).
    final rawId = data['meetingId'] ??
        data['meeting_id'] ??
        data['id'] ??
        data['meeting_code'] ??
        data['meetingCode'];
    if (rawId == null || rawId.toString().isEmpty) return null;
    final meetingId = rawId.toString();

    // meetingCode is best-effort. If only the UUID came through,
    // leave it null and let the consumer fall back to the UUID for
    // lookups (the service indexes both for that reason).
    String? meetingCode;
    final rawCode = data['meetingCode'] ?? data['meeting_code'];
    if (rawCode != null && rawCode.toString().isNotEmpty) {
      meetingCode = rawCode.toString().replaceAll('-', '');
    }

    final rawActive = data['isActive'] ?? data['is_active'];
    bool isActive;
    if (rawActive is bool) {
      isActive = rawActive;
    } else if (rawActive is String) {
      isActive = rawActive.toLowerCase() == 'true';
    } else {
      // Unknown / missing — default to false (safer than claiming a
      // ghost meeting is live). The server should always send the
      // field; if it doesn't, treat as ended.
      isActive = false;
    }

    int membersCount = 0;
    final rawCount = data['membersCount'] ?? data['members_count'];
    if (rawCount is num) {
      membersCount = rawCount.toInt();
    } else if (rawCount is String) {
      membersCount = int.tryParse(rawCount) ?? 0;
    }

    DateTime? endedAt;
    final rawEnded = data['endedAt'] ?? data['ended_at'];
    if (rawEnded is String && rawEnded.isNotEmpty) {
      endedAt = DateTime.tryParse(rawEnded)?.toLocal();
    }

    return MeetingPresence(
      meetingId: meetingId,
      meetingCode: meetingCode,
      isActive: isActive,
      membersCount: membersCount,
      endedAt: endedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MeetingPresence &&
          other.meetingId == meetingId &&
          other.meetingCode == meetingCode &&
          other.isActive == isActive &&
          other.membersCount == membersCount &&
          other.endedAt == endedAt);

  @override
  int get hashCode => Object.hash(
        meetingId,
        meetingCode,
        isActive,
        membersCount,
        endedAt,
      );

  @override
  String toString() =>
      'MeetingPresence(id=$meetingId code=$meetingCode '
      'isActive=$isActive members=$membersCount endedAt=$endedAt)';
}
