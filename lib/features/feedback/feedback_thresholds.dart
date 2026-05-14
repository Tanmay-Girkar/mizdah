// ════════════════════════════════════════════════════════════════════
//  Post-call rating eligibility thresholds — all in one place
//  ────────────────────────────────────────────────────────────────────
//  Tweaking these does NOT require any other file to change. The
//  rating provider reads each constant by name; the UI doesn't read
//  any of them. Keep this file small + un-imported by anything other
//  than `call_rating_provider.dart`.
// ════════════════════════════════════════════════════════════════════

/// Minimum call/meeting duration in seconds before the rating
/// prompt is even considered. Anything shorter is treated as a
/// butt-dial / wrong-number / instant decline and gets no prompt.
const int kRatingMinDurationSeconds = 30;

/// Fraction of eligible calls/meetings that actually surface the
/// prompt. Rolling a uniform `Random().nextDouble()` against this
/// threshold prevents the user from being asked after every long
/// call (which is the #1 reason apps get uninstalled). Value in
/// `[0.0, 1.0]`. 1.0 = always ask, 0.0 = never ask.
const double kRatingSampleRate = 0.40;

/// Minimum hours between two prompts on the same device. A second
/// long call within this window is silently skipped regardless of
/// the sample roll. 24h is the "comfortable for the user" middle
/// ground — long enough to avoid pestering, short enough to still
/// capture issues the day after they happen.
const int kRatingCooldownHours = 24;

/// Star value at or below which the sheet reveals the issue tags
/// + free-form text field. 4-5 = happy (no extras), 3 = neutral
/// (stars alone), 1-2 = "tell us what went wrong".
const int kRatingLowThreshold = 2;

/// Hard cap on the free-form comment length — matches the
/// backend's `comment <= 500` validation rule (per
/// docs/CALL_FEEDBACK_BACKEND.md §3.2). Used by the sheet's
/// character counter and TextField `maxLength`.
const int kRatingCommentMaxLength = 500;
