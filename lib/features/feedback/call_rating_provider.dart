// ════════════════════════════════════════════════════════════════════
//  Call rating provider — Riverpod glue for the post-call sheet
//  ────────────────────────────────────────────────────────────────────
//  Owns:
//    • the eligibility gates (duration, sample rate, cooldown)
//    • the one-shot `promptRequested(req)` signal the overlay
//      listens to
//    • the `lastPromptedAt` SharedPreferences timestamp that
//      enforces the 24-hour cooldown across launches
//    • the submission round-trip (best-effort POST via the
//      FeedbackRepository)
//
//  Triggered from:
//    • P2PCallNotifier.onCallEnded  (after answered call)
//    • MeetingNotifier on phase → ended  (after the user leaves)
//
//  Not responsible for showing the bottom sheet itself — that's
//  the CallRatingOverlay widget that watches this provider.
// ════════════════════════════════════════════════════════════════════

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/call_rating_models.dart';
import '../../data/repositories/feedback_repository.dart';
import 'feedback_thresholds.dart';

/// Discriminated-union via sealed-ish enum + nullable payload —
/// Riverpod prefers value classes for change detection, so we use
/// a plain class with a `phase` field instead of a Freezed union.
class CallRatingState {
  final CallRatingPhase phase;
  final RatingPromptRequest? request;

  const CallRatingState({
    this.phase = CallRatingPhase.idle,
    this.request,
  });

  CallRatingState copyWith({
    CallRatingPhase? phase,
    RatingPromptRequest? request,
    bool clearRequest = false,
  }) {
    return CallRatingState(
      phase: phase ?? this.phase,
      request: clearRequest ? null : (request ?? this.request),
    );
  }
}

enum CallRatingPhase {
  /// No rating in flight. Default. Resting state between calls.
  idle,
  /// `request` is set and the overlay should show the sheet.
  promptRequested,
  /// Submit POST is in flight. The sheet shows a loading spinner
  /// on the Submit button.
  submitting,
}

class CallRatingNotifier extends StateNotifier<CallRatingState> {
  CallRatingNotifier() : super(const CallRatingState());

  final FeedbackRepository _repo = FeedbackRepository();
  final math.Random _random = math.Random();

  /// SharedPreferences key for the persistent cooldown. Versioned
  /// so a future schema change can invalidate without colliding.
  static const _kLastPromptedAtKey = 'mizdah.rating.lastPromptedAt.v1';

  /// Called from each trigger site (P2P call end, meeting end).
  /// Runs the five eligibility gates, then either silently no-ops
  /// or flips `state.phase` to `promptRequested` for the overlay
  /// to pick up.
  Future<void> maybePromptFor(RatingPromptRequest req) async {
    // Gate 1: not already prompting/submitting.
    if (state.phase != CallRatingPhase.idle) {
      _log('SKIP: already in phase=${state.phase}');
      return;
    }
    // Gate 2: must have actually reached "media flowing" — rating
    // a missed/declined/offline call is noise, not signal.
    if (!req.wasAnswered) {
      _log('SKIP: wasAnswered=false');
      return;
    }
    // Gate 3: minimum duration (filters butt-dials / accidents).
    if (req.duration.inSeconds < kRatingMinDurationSeconds) {
      _log('SKIP: duration ${req.duration.inSeconds}s < $kRatingMinDurationSeconds s');
      return;
    }
    // Gate 4: cooldown (max once per kRatingCooldownHours).
    final last = await _readLastPromptedAt();
    if (last != null) {
      final age = DateTime.now().difference(last);
      if (age < const Duration(hours: kRatingCooldownHours)) {
        _log('SKIP: last prompt ${age.inMinutes}m ago '
            '< ${kRatingCooldownHours}h cooldown');
        return;
      }
    }
    // Gate 5: random sample. Drops kRatingSampleRate fraction of
    // otherwise-eligible calls. Keeps the user from being
    // surveyed every long call.
    final roll = _random.nextDouble();
    if (roll > kRatingSampleRate) {
      _log('SKIP: sample roll ${roll.toStringAsFixed(2)} > '
          '$kRatingSampleRate');
      return;
    }

    _log('SHOW: callId=${req.callId} kind=${req.kind.wire} '
        'duration=${req.duration.inSeconds}s');
    state = CallRatingState(
      phase: CallRatingPhase.promptRequested,
      request: req,
    );
  }

  /// User tapped Submit. Fires off the backend POST and resets
  /// state. The overlay closes the sheet the moment phase flips
  /// back to idle.
  Future<void> submit({
    required int rating,
    required List<CallRatingTag> tags,
    String? comment,
  }) async {
    final req = state.request;
    if (req == null) {
      _log('submit() called with no in-flight request — ignored');
      return;
    }
    state = state.copyWith(phase: CallRatingPhase.submitting);
    await _repo.submitCallRating(
      callId: req.callId,
      kind: req.kind,
      rating: rating,
      tags: tags,
      comment: comment,
      duration: req.duration,
    );
    await _markPromptedNow();
    // Reset to idle regardless of POST outcome — repository swallows
    // errors and the user has already seen the "Thanks" snackbar by
    // the time we get here.
    state = const CallRatingState();
  }

  /// User tapped Skip or dismissed by drag. Same effect on
  /// state as submit (back to idle, cooldown started), no POST.
  Future<void> skip() async {
    _log('skip');
    await _markPromptedNow();
    state = const CallRatingState();
  }

  // ── Persistent cooldown ───────────────────────────────────────────

  Future<DateTime?> _readLastPromptedAt() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ms = prefs.getInt(_kLastPromptedAtKey);
      if (ms == null) return null;
      return DateTime.fromMillisecondsSinceEpoch(ms);
    } catch (_) {
      return null;
    }
  }

  Future<void> _markPromptedNow() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        _kLastPromptedAtKey,
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {}
  }

  void _log(String s) {
    if (kDebugMode) debugPrint('[rating] $s');
  }
}

final callRatingProvider =
    StateNotifierProvider<CallRatingNotifier, CallRatingState>(
  (ref) => CallRatingNotifier(),
);
