// ════════════════════════════════════════════════════════════════════
//  P2P call log models
// ════════════════════════════════════════════════════════════════════
//  One row per actual P2P call event — distinct from the meeting-
//  participation history the rest of the app reads from
//  `callHistoryProvider`. Field names mirror the contract in
//  docs/CALL_HISTORY_API.md so the future server-backed version can
//  hydrate the same shape with no UI changes.

enum CallDirection { outgoing, incoming }

enum CallOutcome {
  /// Both sides connected; `durationSeconds > 0`.
  answered,

  /// I called and the other side tapped decline.
  declined,

  /// I called and the other side never picked up (timeout / offline).
  missed,

  /// I (the caller) hung up before the other side answered.
  cancelled,

  /// Connection error / signaling failure.
  failed,
}

CallDirection _directionFromString(String s) {
  switch (s) {
    case 'incoming':
      return CallDirection.incoming;
    case 'outgoing':
    default:
      return CallDirection.outgoing;
  }
}

String _directionToString(CallDirection d) =>
    d == CallDirection.incoming ? 'incoming' : 'outgoing';

CallOutcome _outcomeFromString(String s) {
  switch (s) {
    case 'declined':
      return CallOutcome.declined;
    case 'missed':
      return CallOutcome.missed;
    case 'cancelled':
      return CallOutcome.cancelled;
    case 'failed':
      return CallOutcome.failed;
    case 'answered':
    default:
      return CallOutcome.answered;
  }
}

String _outcomeToString(CallOutcome o) {
  switch (o) {
    case CallOutcome.answered:
      return 'answered';
    case CallOutcome.declined:
      return 'declined';
    case CallOutcome.missed:
      return 'missed';
    case CallOutcome.cancelled:
      return 'cancelled';
    case CallOutcome.failed:
      return 'failed';
  }
}

/// A single call event. Each P2P call attempt produces exactly one
/// entry — appended when the call's terminal state is reached
/// (answered+ended, declined, missed, etc.).
class CallLogEntry {
  /// Local id, ULID-style timestamp + random suffix. Used to dedup if
  /// the same event fires twice in close succession.
  final String id;
  final String peerUserId;
  final String peerName;
  final String? peerEmail;
  final DateTime startedAt;
  final int durationSeconds;
  final CallDirection direction;
  final CallOutcome outcome;
  /// Whether the call was placed (or accepted) with video on.
  final bool withVideo;

  const CallLogEntry({
    required this.id,
    required this.peerUserId,
    required this.peerName,
    required this.peerEmail,
    required this.startedAt,
    required this.durationSeconds,
    required this.direction,
    required this.outcome,
    required this.withVideo,
  });

  Duration get duration => Duration(seconds: durationSeconds);

  Map<String, dynamic> toJson() => {
        'id': id,
        'peer_user_id': peerUserId,
        'peer_name': peerName,
        if (peerEmail != null) 'peer_email': peerEmail,
        'started_at': startedAt.toUtc().toIso8601String(),
        'duration_seconds': durationSeconds,
        'direction': _directionToString(direction),
        'outcome': _outcomeToString(outcome),
        'with_video': withVideo,
      };

  factory CallLogEntry.fromJson(Map<String, dynamic> j) => CallLogEntry(
        id: j['id'] as String,
        peerUserId: (j['peer_user_id'] ?? '') as String,
        peerName: (j['peer_name'] ?? '') as String,
        peerEmail: j['peer_email'] as String?,
        startedAt: DateTime.parse(j['started_at'] as String).toLocal(),
        durationSeconds: (j['duration_seconds'] ?? 0) as int,
        direction: _directionFromString((j['direction'] ?? 'outgoing') as String),
        outcome: _outcomeFromString((j['outcome'] ?? 'answered') as String),
        withVideo: (j['with_video'] ?? true) as bool,
      );
}
