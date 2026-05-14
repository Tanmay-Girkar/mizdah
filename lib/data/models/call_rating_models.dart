// ════════════════════════════════════════════════════════════════════
//  Call-rating domain models — mirrors docs/CALL_FEEDBACK_BACKEND.md
//  ────────────────────────────────────────────────────────────────────
//  Three concepts:
//    • RatingKind         — what was rated (p2p audio / video / meeting)
//    • CallRatingTag      — closed vocabulary of "what went wrong"
//                            issue tags surfaced to users with low
//                            star ratings.
//    • RatingPromptRequest — the input the rating provider needs to
//                            decide whether to prompt + what to put
//                            in the sheet header (peer name +
//                            duration formatted).
//
//  Backend wire vocabulary lives in §4 of the spec; this file
//  carries that vocabulary plus the user-facing labels.
// ════════════════════════════════════════════════════════════════════

import 'dart:math' as math;

/// What sort of session is being rated. Maps to the backend's
/// `callType` field per §3.3 of CALL_FEEDBACK_BACKEND.md.
enum RatingKind {
  p2pAudio('p2p_audio', 'audio call'),
  p2pVideo('p2p_video', 'video call'),
  meeting('meeting', 'meeting');

  const RatingKind(this.wire, this.uiNoun);

  /// Wire string sent to the backend.
  final String wire;

  /// Lower-case noun used in the sheet header: "How was your $uiNoun?"
  final String uiNoun;
}

/// Closed vocabulary of issue tags. Strings match the §4 list in
/// CALL_FEEDBACK_BACKEND.md exactly; backend rejects anything else
/// with 400 INVALID_TAG. Display labels are friendlier than the
/// wire strings; tweak them client-side without touching the
/// backend.
enum CallRatingTag {
  audioEcho('audio_echo', 'Audio echo'),
  audioMuffled('audio_muffled', 'Muffled audio'),
  audioDropped('audio_dropped', 'Audio dropped'),
  noRemoteAudio('no_remote_audio', "Couldn't hear them"),
  videoFrozen('video_frozen', 'Video froze'),
  videoPixelated('video_pixelated', 'Pixelated video'),
  videoDropped('video_dropped', 'Video dropped'),
  noRemoteVideo('no_remote_video', "Couldn't see them"),
  connectionFailed('connection_failed', "Couldn't connect"),
  disconnectedMidCall('disconnected_mid_call', 'Disconnected mid-call'),
  other('other', 'Other');

  const CallRatingTag(this.wire, this.label);

  /// Wire string sent to the backend.
  final String wire;

  /// Label shown on the chip.
  final String label;

  /// Subset of tags surfaced for a given RatingKind. Hide
  /// video-only tags on audio calls, etc. Saves clutter on the
  /// sheet without server-side changes.
  static List<CallRatingTag> visibleFor(RatingKind kind) {
    switch (kind) {
      case RatingKind.p2pAudio:
        return const [
          CallRatingTag.audioEcho,
          CallRatingTag.audioMuffled,
          CallRatingTag.audioDropped,
          CallRatingTag.noRemoteAudio,
          CallRatingTag.connectionFailed,
          CallRatingTag.disconnectedMidCall,
          CallRatingTag.other,
        ];
      case RatingKind.p2pVideo:
      case RatingKind.meeting:
        // All tags are valid for video calls / meetings.
        return CallRatingTag.values;
    }
  }
}

/// Single payload the rating provider needs to decide whether to
/// prompt, and what context to display in the sheet. Built by
/// each trigger site (P2P call notifier, meeting notifier).
class RatingPromptRequest {
  /// Backend `callId` — for P2P this is the same UUID the service
  /// generates and round-trips through `initiate-call`; for
  /// meetings, the meeting id.
  final String callId;
  final RatingKind kind;
  /// Peer name (P2P) or meeting title (meeting). Shown in the
  /// sheet subtitle: "with Test User 1 · 4m 12s".
  final String peerOrMeetingName;
  final Duration duration;
  /// True iff the session actually reached the "media flowing"
  /// state. Calls that never connected aren't eligible.
  final bool wasAnswered;

  const RatingPromptRequest({
    required this.callId,
    required this.kind,
    required this.peerOrMeetingName,
    required this.duration,
    required this.wasAnswered,
  });

  /// Human-readable duration for the header. `4m 12s`, `12s`,
  /// `1h 03m`. No leading zeros, no decimals.
  String get formattedDuration {
    final s = math.max(0, duration.inSeconds);
    if (s < 60) return '${s}s';
    final m = s ~/ 60;
    final ss = (s % 60).toString().padLeft(2, '0');
    if (m < 60) return '${m}m ${ss}s';
    final h = m ~/ 60;
    final mm = (m % 60).toString().padLeft(2, '0');
    return '${h}h ${mm}m';
  }
}
