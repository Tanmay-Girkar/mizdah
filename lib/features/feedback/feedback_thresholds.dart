// ════════════════════════════════════════════════════════════════════
//  Post-call rating eligibility thresholds — all in one place
//  ────────────────────────────────────────────────────────────────────
//  Tweaking these does NOT require any other file to change. The
//  rating provider reads each constant by name; the UI doesn't read
//  any of them. Keep this file small + un-imported by anything other
//  than `call_rating_provider.dart`.
// ════════════════════════════════════════════════════════════════════

/// Minimum call/meeting duration in seconds before the rating
/// prompt is even considered. **Currently 0** — every answered
/// call/meeting prompts, regardless of how short. Bump back up to
/// e.g. 30 if the team wants to filter out butt-dials and instant-
/// disconnects later.
const int kRatingMinDurationSeconds = 0;

/// Fraction of eligible calls/meetings that actually surface the
/// prompt. **Currently 1.0** — every answered call/meeting prompts.
/// Drop to e.g. 0.4 to sample only a fraction if user feedback ever
/// reports the prompt as too noisy.
const double kRatingSampleRate = 1.0;

/// Minimum hours between two prompts on the same device. **Currently
/// 0** — back-to-back calls each prompt independently. Bump back to
/// 24 if the team decides one rating per day is enough.
const int kRatingCooldownHours = 0;

/// Star value at or below which the sheet reveals the issue tags
/// + free-form text field. 4-5 = happy (no extras), 3 = neutral
/// (stars alone), 1-2 = "tell us what went wrong".
const int kRatingLowThreshold = 2;

/// Hard cap on the free-form comment length — matches the
/// backend's `comment <= 500` validation rule (per
/// docs/CALL_FEEDBACK_BACKEND.md §3.2). Used by the sheet's
/// character counter and TextField `maxLength`.
const int kRatingCommentMaxLength = 500;
