// ════════════════════════════════════════════════════════════════════
//  Rejoin bottom sheet — tap an active recent meeting card to land here
// ────────────────────────────────────────────────────────────────────
//  Shown via showModalBottomSheet from `_RecentCard.onTap` when the
//  card is for an ACTIVE meeting (presence.isActive == true).
//  Displays the meeting's current live state and offers a single
//  Rejoin button that reuses the existing pre-join flow.
//
//  Real-time behaviour:
//    • Sheet watches `meetingPresenceStreamProvider` for the same
//      meetingId/code the user tapped. If the meeting deactivates
//      while the sheet is open, the Rejoin button disables and
//      flips to "Meeting ended" — handles the race described in
//      protocol §8.3 where the last participant leaves between
//      tap and confirm.
//    • Sheet self-dismisses after a short delay once it goes to
//      the ended state, so the user doesn't get stuck.
// ════════════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ui/mizdah_design.dart';
import '../../../data/models/models.dart';
import '../../meeting/data/meeting_presence.dart';
import '../../meeting/meeting_presence_provider.dart';

/// Convenience entry point — pops a rounded-top modal sheet with the
/// rejoin UI. Returns once the sheet is dismissed (no return value;
/// navigation happens internally via `context.push('/pre-join/...')`).
Future<void> showRejoinSheet(
  BuildContext context, {
  required CallHistory meeting,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _RejoinSheet(meeting: meeting),
  );
}

class _RejoinSheet extends ConsumerStatefulWidget {
  final CallHistory meeting;
  const _RejoinSheet({required this.meeting});

  @override
  ConsumerState<_RejoinSheet> createState() => _RejoinSheetState();
}

class _RejoinSheetState extends ConsumerState<_RejoinSheet> {
  Timer? _autoDismiss;

  @override
  void dispose() {
    _autoDismiss?.cancel();
    super.dispose();
  }

  void _scheduleAutoDismiss() {
    _autoDismiss ??= Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      Navigator.of(context).maybePop();
    });
  }

  void _rejoin() {
    final code = widget.meeting.meetingCode;
    if (code == null || code.isEmpty) return;
    Navigator.of(context).pop();
    // Reuse the existing join-by-code path — pre-join screen handles
    // device-permission prompts, mic/camera preview, and the actual
    // `join-meeting` socket emit. The meeting code lives unchanged
    // through this flow.
    context.push('/pre-join/$code');
  }

  @override
  Widget build(BuildContext context) {
    // Watch the live presence map. The meeting we're sheet'ing about
    // may flip to inactive between tap and the user reading the
    // sheet — protocol §8.3.
    final presenceAsync = ref.watch(meetingPresenceStreamProvider);
    final live = presenceAsync.maybeWhen<MeetingPresence?>(
      data: (m) => m[widget.meeting.id] ??
          (widget.meeting.meetingCode != null
              ? m[widget.meeting.meetingCode!]
              : null),
      orElse: () => null,
    );

    // Source-of-truth for "is this meeting still alive right now":
    // prefer the live overlay, fall back to whatever the snapshot
    // said. Same precedence rule as the merged provider.
    final isActive = live?.isActive ?? widget.meeting.isActive ?? false;
    final members = live?.membersCount ?? widget.meeting.membersCount ?? 0;

    if (!isActive) _scheduleAutoDismiss();

    final ink = MizdahTokens.inkOf(context);
    final surface = MizdahTokens.surface(context);
    // Mizdah's floating bottom nav sits ABOVE the system safe-area
    // inset (~12 + 72 + 6 + systemInset px). A regular SafeArea on
    // its own doesn't clear it — the sheet would render UNDER the
    // nav and the Rejoin button gets hidden behind it. Use
    // navBarBottomInset for the bottom padding so the action row
    // always sits comfortably above the nav (with a small extra
    // buffer for breathing room).
    final navInset = MizdahTokens.navBarBottomInset(context);

    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(20, 14, 20, navInset + 8),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Grabber
            Center(
              child: Container(
                width: 44,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: ink.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Status pill — live or ended
            Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                child: isActive
                    ? const _LivePill(key: ValueKey('live'))
                    : const _EndedPill(key: ValueKey('ended')),
              ),
            ),
            const SizedBox(height: 18),
            // Title
            Text(
              widget.meeting.title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: ink,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 6),
            if (widget.meeting.meetingCode != null)
              Text(
                widget.meeting.meetingCode!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: ink.withValues(alpha: 0.55),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.4,
                ),
              ),
            const SizedBox(height: 18),
            // Live participant count (only when active)
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              child: isActive
                  ? _MembersLine(
                      key: ValueKey('members-$members'),
                      count: members,
                    )
                  : const SizedBox(key: ValueKey('no-members')),
            ),
            const SizedBox(height: 22),
            // Action row
            Row(
              children: [
                Expanded(
                  child: _SheetButton(
                    label: 'Cancel',
                    tone: _SheetTone.neutral,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: _SheetButton(
                    label: isActive ? 'Rejoin meeting' : 'Meeting ended',
                    tone: isActive
                        ? _SheetTone.primary
                        : _SheetTone.disabled,
                    onTap: isActive ? _rejoin : null,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
  }
}

// ────────────────────────────────────────────────────────────────────

class _LivePill extends StatelessWidget {
  const _LivePill({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        gradient: MizdahTokens.heroGradient,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: MizdahTokens.primary.withValues(alpha: 0.35),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PulsingDot(),
          SizedBox(width: 8),
          Text(
            'LIVE NOW',
            style: TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _EndedPill extends StatelessWidget {
  const _EndedPill({super.key});

  @override
  Widget build(BuildContext context) {
    final ink = MizdahTokens.inkOf(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: ink.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: ink.withValues(alpha: 0.14)),
      ),
      child: Text(
        'MEETING ENDED',
        style: TextStyle(
          color: ink.withValues(alpha: 0.7),
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.4,
        ),
      ),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  const _PulsingDot();

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.6 + t * 0.4),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.white.withValues(alpha: t * 0.7),
                blurRadius: 6,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MembersLine extends StatelessWidget {
  final int count;
  const _MembersLine({super.key, required this.count});

  @override
  Widget build(BuildContext context) {
    final ink = MizdahTokens.inkOf(context);
    final label = count <= 1
        ? '1 person in meeting'
        : '$count people in meeting';
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.group_rounded,
          size: 16,
          color: ink.withValues(alpha: 0.6),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            color: ink.withValues(alpha: 0.75),
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }
}

enum _SheetTone { neutral, primary, disabled }

class _SheetButton extends StatelessWidget {
  final String label;
  final _SheetTone tone;
  final VoidCallback? onTap;
  const _SheetButton({
    required this.label,
    required this.tone,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ink = MizdahTokens.inkOf(context);
    final disabled = tone == _SheetTone.disabled || onTap == null;
    final isPrimary = tone == _SheetTone.primary && !disabled;

    final bg = isPrimary
        ? null
        : (disabled
            ? ink.withValues(alpha: 0.08)
            : ink.withValues(alpha: 0.06));
    final gradient = isPrimary ? MizdahTokens.heroGradient : null;
    final fg = isPrimary
        ? Colors.white
        : ink.withValues(alpha: disabled ? 0.4 : 0.85);

    return MizdahPressScale(
      onTap: disabled ? () {} : onTap!,
      scaleTo: 0.96,
      child: Container(
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          gradient: gradient,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: fg,
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }
}
