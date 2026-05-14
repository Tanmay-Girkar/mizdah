// ════════════════════════════════════════════════════════════════════
//  Call rating sheet — WhatsApp / Zoom-style post-call rating
//  ────────────────────────────────────────────────────────────────────
//  Modal bottom sheet shown by CallRatingOverlay when the provider
//  flips to `promptRequested`. Three visual states by rating:
//
//    no selection → "Tap a star to rate"      , Submit disabled
//    rating ≥ 3   → "Thanks!"                  , Submit enabled
//    rating ≤ 2   → tag chips + comment field  , Submit enabled
//
//  Tags + comment animate in/out as the rating crosses the
//  kRatingLowThreshold boundary. Comment is optional even for
//  low ratings — making it required hurts submission rate without
//  improving signal quality.
// ════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui/mizdah_design.dart';
import '../../data/models/call_rating_models.dart';
import 'call_rating_provider.dart';
import 'feedback_thresholds.dart';

class CallRatingSheet extends ConsumerStatefulWidget {
  /// The context built up by the provider — peer/meeting name,
  /// duration, kind. Not the full `RatingPromptRequest` so the
  /// sheet can be invoked from a unit test with a hand-crafted
  /// request.
  final RatingPromptRequest request;
  const CallRatingSheet({super.key, required this.request});

  @override
  ConsumerState<CallRatingSheet> createState() => _CallRatingSheetState();
}

class _CallRatingSheetState extends ConsumerState<CallRatingSheet> {
  int? _rating;
  final Set<CallRatingTag> _tags = {};
  final TextEditingController _commentCtrl = TextEditingController();
  final FocusNode _commentFocus = FocusNode();

  bool get _isLowRating =>
      _rating != null && _rating! <= kRatingLowThreshold;

  @override
  void dispose() {
    _commentCtrl.dispose();
    _commentFocus.dispose();
    super.dispose();
  }

  void _onStarTap(int v) {
    final wasLow = _isLowRating;
    setState(() => _rating = v);
    // Clear the issue payload when the user dragged from a low
    // rating up to a happy one — a 5-star submission shouldn't
    // accidentally carry over "audio_echo" the user tapped before
    // changing their mind.
    if (wasLow && !_isLowRating) {
      _tags.clear();
      _commentCtrl.clear();
    }
    // Auto-focus the comment field the moment the issue area
    // first opens. Schedule for next frame so the AnimatedSwitcher
    // has mounted the new child.
    if (!wasLow && _isLowRating) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _commentFocus.requestFocus();
      });
    }
  }

  bool _isSubmitting() {
    return ref.watch(callRatingProvider).phase ==
        CallRatingPhase.submitting;
  }

  Future<void> _submit() async {
    final r = _rating;
    if (r == null) return;
    await ref.read(callRatingProvider.notifier).submit(
          rating: r,
          tags: _tags.toList(),
          comment: _isLowRating ? _commentCtrl.text : null,
        );
    if (!mounted) return;
    Navigator.of(context).maybePop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        duration: Duration(milliseconds: 1500),
        content: Text('Thanks for the feedback.'),
      ),
    );
  }

  Future<void> _skip() async {
    await ref.read(callRatingProvider.notifier).skip();
    if (!mounted) return;
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final req = widget.request;
    final mq = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: MizdahTokens.surface(context),
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: MizdahTokens.mutedOf(context)
                        .withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'How was your ${req.kind.uiNoun}?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: MizdahTokens.inkOf(context),
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'with ${req.peerOrMeetingName} · ${req.formattedDuration}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: MizdahTokens.mutedOf(context),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 22),
              _StarRow(rating: _rating, onTap: _onStarTap),
              const SizedBox(height: 10),
              _RatingHint(rating: _rating),
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  child: _isLowRating
                      ? _IssueArea(
                          key: const ValueKey('issue-area'),
                          kind: req.kind,
                          tags: _tags,
                          commentCtrl: _commentCtrl,
                          commentFocus: _commentFocus,
                          onToggleTag: (t) {
                            setState(() {
                              if (_tags.contains(t)) {
                                _tags.remove(t);
                              } else {
                                _tags.add(t);
                              }
                            });
                          },
                        )
                      : const SizedBox(
                          key: ValueKey('issue-area-empty'),
                          height: 12,
                        ),
                ),
              ),
              const SizedBox(height: 18),
              _ActionRow(
                submitting: _isSubmitting(),
                canSubmit: _rating != null && !_isSubmitting(),
                onSkip: _isSubmitting() ? null : _skip,
                onSubmit: (_rating != null && !_isSubmitting())
                    ? _submit
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────
//  Star row
// ────────────────────────────────────────────────────────────────────

class _StarRow extends StatelessWidget {
  final int? rating;
  final void Function(int) onTap;
  const _StarRow({required this.rating, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(5, (i) {
        final v = i + 1;
        final filled = rating != null && v <= rating!;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: MizdahPressScale(
            scaleTo: 0.85,
            onTap: () => onTap(v),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.all(4),
              child: Icon(
                filled
                    ? Icons.star_rounded
                    : Icons.star_outline_rounded,
                size: filled ? 40 : 36,
                color: filled
                    ? const Color(0xFFF59E0B)
                    : MizdahTokens.mutedOf(context),
              ),
            ),
          ),
        );
      }),
    );
  }
}

// ────────────────────────────────────────────────────────────────────
//  One-line hint that follows the current rating
// ────────────────────────────────────────────────────────────────────

class _RatingHint extends StatelessWidget {
  final int? rating;
  const _RatingHint({required this.rating});

  @override
  Widget build(BuildContext context) {
    String label;
    if (rating == null) {
      label = 'Tap a star to rate';
    } else if (rating! <= kRatingLowThreshold) {
      label = 'What went wrong?';
    } else if (rating! == 3) {
      label = 'Thanks for letting us know.';
    } else {
      label = 'Glad it went well!';
    }
    return Text(
      label,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: MizdahTokens.mutedOf(context),
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────
//  Issue area — tag chips + free-form comment.
//  Only mounted when rating ≤ kRatingLowThreshold.
// ────────────────────────────────────────────────────────────────────

class _IssueArea extends StatelessWidget {
  final RatingKind kind;
  final Set<CallRatingTag> tags;
  final TextEditingController commentCtrl;
  final FocusNode commentFocus;
  final void Function(CallRatingTag) onToggleTag;
  const _IssueArea({
    super.key,
    required this.kind,
    required this.tags,
    required this.commentCtrl,
    required this.commentFocus,
    required this.onToggleTag,
  });

  @override
  Widget build(BuildContext context) {
    final visible = CallRatingTag.visibleFor(kind);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final t in visible)
              _TagChip(
                label: t.label,
                selected: tags.contains(t),
                onTap: () => onToggleTag(t),
              ),
          ],
        ),
        const SizedBox(height: 14),
        _CommentField(controller: commentCtrl, focus: commentFocus),
      ],
    );
  }
}

class _TagChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _TagChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MizdahPressScale(
      scaleTo: 0.94,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? MizdahTokens.primary.withValues(alpha: 0.16)
              : MizdahTokens.mutedOf(context).withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? MizdahTokens.primary.withValues(alpha: 0.6)
                : MizdahTokens.mutedOf(context).withValues(alpha: 0.25),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              Icon(Icons.check_rounded,
                  size: 14, color: MizdahTokens.primary),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                color: selected
                    ? MizdahTokens.primary
                    : MizdahTokens.inkOf(context),
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommentField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focus;
  const _CommentField({required this.controller, required this.focus});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fillColor = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.grey.shade100;
    return TextField(
      controller: controller,
      focusNode: focus,
      minLines: 2,
      maxLines: 4,
      maxLength: kRatingCommentMaxLength,
      style: TextStyle(
        color: MizdahTokens.inkOf(context),
        fontSize: 14,
      ),
      decoration: InputDecoration(
        hintText: 'Tell us more (optional)…',
        hintStyle: TextStyle(
          color: MizdahTokens.mutedOf(context).withValues(alpha: 0.7),
        ),
        filled: true,
        fillColor: fillColor,
        contentPadding: const EdgeInsets.all(12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        counterStyle: TextStyle(
          color: MizdahTokens.mutedOf(context),
          fontSize: 11,
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────
//  Action row — Skip + Submit
// ────────────────────────────────────────────────────────────────────

class _ActionRow extends StatelessWidget {
  final bool submitting;
  final bool canSubmit;
  final VoidCallback? onSkip;
  final VoidCallback? onSubmit;
  const _ActionRow({
    required this.submitting,
    required this.canSubmit,
    required this.onSkip,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _SecondaryButton(
            label: 'Skip',
            onTap: onSkip,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _PrimaryButton(
            label: submitting ? null : 'Submit',
            busy: submitting,
            onTap: onSubmit,
          ),
        ),
      ],
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  const _SecondaryButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return MizdahPressScale(
      scaleTo: 0.96,
      onTap: onTap,
      child: Container(
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: MizdahTokens.mutedOf(context).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: MizdahTokens.inkOf(context),
            fontSize: 14.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String? label;
  final bool busy;
  final VoidCallback? onTap;
  const _PrimaryButton({
    required this.label,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return MizdahPressScale(
      scaleTo: 0.96,
      onTap: onTap,
      child: Container(
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: enabled ? MizdahTokens.heroGradient : null,
          color: enabled
              ? null
              : MizdahTokens.mutedOf(context).withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(14),
        ),
        child: busy
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  valueColor: AlwaysStoppedAnimation(Colors.white),
                ),
              )
            : Text(
                label ?? '',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                ),
              ),
      ),
    );
  }
}
