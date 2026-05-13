// ════════════════════════════════════════════════════════════════════
//  Meetings — full-page premium "all meetings" view
//  ────────────────────────────────────────────────────────────────────
//  Two segmented sections:
//    • Upcoming (schedulesProvider)
//    • Recent   (recentMeetingsProvider — REST snapshot overlaid
//               with live socket presence; see
//               docs/MEETING_PRESENCE_PROTOCOL.md)
//  Reuses the home screen's data sources so invalidation in one place
//  refreshes both views. The recent list separately subscribes to
//  meeting-updated socket events so cards downgrade from LIVE to
//  ended without a manual refresh.
// ════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/ui/mizdah_design.dart';
import '../../../core/utils/meeting_utils.dart';
import '../../../data/models/models.dart';
import '../../auth/auth_provider.dart';
import '../../home/presentation/home_screen.dart' show
    schedulesProvider,
    callHistoryProvider;
import '../../meeting/recent_meetings_provider.dart';
import 'rejoin_sheet.dart';

class MeetingsScreen extends ConsumerStatefulWidget {
  /// Optional initial segment — `0` for Upcoming, `1` for Recent.
  /// The router populates this from `?tab=recent` so the home
  /// screen's "View all" link can drop the user straight onto the
  /// recent list.
  final int initialSegment;
  const MeetingsScreen({super.key, this.initialSegment = 0});

  @override
  ConsumerState<MeetingsScreen> createState() => _MeetingsScreenState();
}

class _MeetingsScreenState extends ConsumerState<MeetingsScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entryCtrl;
  // 0 = Upcoming, 1 = Recent. Local UI state only.
  late int _segment;

  @override
  void initState() {
    super.initState();
    _segment = widget.initialSegment.clamp(0, 1);
    _entryCtrl = AnimationController(
      duration: const Duration(milliseconds: 700),
      vsync: this,
    )..forward();
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MizdahTabScaffold(
      activeIndex: 0,
      body: SafeArea(
        bottom: false,
        // Pinned header + segment switcher above a scrollable body.
        // Drag only moves the list; title and tab toggle stay put
        // (WhatsApp / Telegram pattern).
        child: Column(
          children: [
            MizdahFadeUp(
              controller: _entryCtrl,
              delay: 0.0,
              child: const MizdahPageHeader(
                leading: 'Your',
                accent: 'meetings',
                subtitle: 'Schedules · History · Quick joins',
              ),
            ),
            const SizedBox(height: 12),
            MizdahFadeUp(
              controller: _entryCtrl,
              delay: 0.10,
              child: _SegmentSwitcher(
                segment: _segment,
                onChanged: (v) => setState(() => _segment = v),
              ),
            ),
            const SizedBox(height: 18),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(schedulesProvider);
                  ref.invalidate(callHistoryProvider);
                  await Future<void>.delayed(
                      const Duration(milliseconds: 350));
                },
                color: MizdahTokens.primary,
                displacement: 24,
                edgeOffset: 0,
                child: ListView(
                  physics: const ClampingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                  padding: const EdgeInsets.only(bottom: 8),
                  children: [
                    MizdahFadeUp(
                      controller: _entryCtrl,
                      delay: 0.20,
                      child: _segment == 0
                          ? const _UpcomingList()
                          : const _RecentList(),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────
//  Segment switcher — animated indicator slides between options
// ────────────────────────────────────────────────────────────────────

class _SegmentSwitcher extends StatelessWidget {
  final int segment;
  final ValueChanged<int> onChanged;
  const _SegmentSwitcher({required this.segment, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Container(
        height: 48,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: MizdahTokens.surface(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: MizdahTokens.border(context), width: 1),
          boxShadow: MizdahTokens.shadow(context, elevation: 0.4),
        ),
        child: LayoutBuilder(builder: (ctx, c) {
          final pillW = (c.maxWidth - 8) / 2;
          return Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                left: segment == 0 ? 0 : pillW,
                top: 0,
                bottom: 0,
                width: pillW,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: MizdahTokens.heroGradient,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: MizdahTokens.primary.withValues(alpha: 0.30),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: _SegmentLabel(
                      label: 'Upcoming',
                      active: segment == 0,
                      onTap: () => onChanged(0),
                    ),
                  ),
                  Expanded(
                    child: _SegmentLabel(
                      label: 'Recent',
                      active: segment == 1,
                      onTap: () => onChanged(1),
                    ),
                  ),
                ],
              ),
            ],
          );
        }),
      ),
    );
  }
}

class _SegmentLabel extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _SegmentLabel({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Center(
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 200),
          style: TextStyle(
            color: active
                ? Colors.white
                : MizdahTokens.mutedOf(context),
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.1,
          ),
          child: Text(label),
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────
//  Upcoming list — pulls schedulesProvider, renders premium cards
// ────────────────────────────────────────────────────────────────────

class _UpcomingList extends ConsumerWidget {
  const _UpcomingList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(schedulesProvider);
    return async.when(
      loading: () => const _Loader(),
      error: (_, __) => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 18),
        child: MizdahCard(
          child: MizdahEmptyState(
            icon: Icons.cloud_off_rounded,
            title: 'Could not load schedules',
            subtitle: 'Pull down to retry',
          ),
        ),
      ),
      data: (schedules) {
        if (schedules.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(horizontal: 18),
            child: MizdahCard(
              padding: EdgeInsets.zero,
              child: MizdahEmptyState(
                icon: Icons.event_available_rounded,
                title: 'No meetings scheduled',
                subtitle:
                    'Tap the Call tab to start an instant meeting or schedule one.',
              ),
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Column(
            children: [
              for (var i = 0; i < schedules.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _UpcomingMeetingCard(
                    schedule: schedules[i],
                    colorIndex: i,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _UpcomingMeetingCard extends StatelessWidget {
  final dynamic schedule;
  final int colorIndex;
  const _UpcomingMeetingCard({
    required this.schedule,
    required this.colorIndex,
  });

  static String? _extractCode(dynamic s) {
    final code = s['meetingCode']?.toString();
    if (code != null && code.isNotEmpty) return code;
    final mid = s['meetingId']?.toString();
    if (mid != null && mid.isNotEmpty) return mid;
    final title = s['title']?.toString() ?? '';
    final m = RegExp(r'\[([a-z0-9-]{6,})\]').firstMatch(title);
    return m?.group(1);
  }

  static String _displayTitle(String raw) {
    final stripped =
        raw.replaceAll(RegExp(r'\s*\[[a-z0-9-]{6,}\]\s*$'), '').trim();
    return stripped.isEmpty ? raw : stripped;
  }

  static String _formatDuration(Duration d) {
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    final h = d.inHours;
    final m = d.inMinutes % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }

  @override
  Widget build(BuildContext context) {
    // `.toLocal()` converts the UTC wire-format back to the user's
    // wall clock. See scheduling_repository.dart for the contract.
    final start =
        DateTime.tryParse(schedule['startTime']?.toString() ?? '')?.toLocal() ??
            DateTime.now();
    final end =
        DateTime.tryParse(schedule['endTime']?.toString() ?? '')?.toLocal();
    final rawTitle = schedule['title']?.toString() ?? 'Meeting';
    final title = _displayTitle(rawTitle);
    final code = _extractCode(schedule);
    final palette = MizdahTokens.rowColors[colorIndex % 5];
    final bg = palette[0];
    final fg = palette[1];

    final timeRange = end != null
        ? '${DateFormat('h:mm a').format(start)} – ${DateFormat('h:mm a').format(end)}'
        : DateFormat('h:mm a').format(start);
    final duration = end != null
        ? _formatDuration(end.difference(start))
        : (schedule['timezone']?.toString() ?? 'IST');

    return MizdahCard(
      padding: const EdgeInsets.all(14),
      onTap: () {
        if (code == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              behavior: SnackBarBehavior.floating,
              content: Text(
                  'No meeting code on this schedule yet — open it from the calendar invite.'),
            ),
          );
          return;
        }
        context.push('/pre-join/$code');
      },
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Date pill
          Container(
            width: 56,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                Text(
                  DateFormat('MMM').format(start).toUpperCase(),
                  style: TextStyle(
                    color: fg,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
                Text(
                  DateFormat('d').format(start),
                  style: TextStyle(
                    color: fg,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.6,
                    height: 1.05,
                  ),
                ),
                Text(
                  DateFormat('EEE').format(start).toUpperCase(),
                  style: TextStyle(
                    color: fg.withValues(alpha: 0.75),
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: MizdahTokens.inkOf(context),
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.schedule_rounded,
                        color: MizdahTokens.mutedOf(context), size: 13),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        timeRange,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: MizdahTokens.mutedOf(context),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: bg,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        duration,
                        style: TextStyle(
                          color: fg,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                if (code != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.link_rounded,
                          color: MizdahTokens.mutedOf(context), size: 12),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          code,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: MizdahTokens.primary,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 4),
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: MizdahTokens.heroGradient,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: MizdahTokens.primary.withValues(alpha: 0.30),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: const Icon(Icons.arrow_forward_rounded,
                color: Colors.white, size: 18),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────
//  Recent list — pulls callHistoryProvider
// ────────────────────────────────────────────────────────────────────

class _RecentList extends ConsumerWidget {
  const _RecentList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch the MERGED provider — REST snapshot overlaid with live
    // socket presence (see `recentMeetingsProvider`). Every
    // `meeting-updated` socket event rebuilds matching cards
    // without a refresh.
    final async = ref.watch(recentMeetingsProvider);
    final user = ref.watch(authProvider).user;
    return async.when(
      loading: () => const _Loader(),
      error: (_, __) => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 18),
        child: MizdahCard(
          child: MizdahEmptyState(
            icon: Icons.cloud_off_rounded,
            title: 'Could not load history',
            subtitle: 'Pull down to retry',
          ),
        ),
      ),
      data: (history) {
        if (history.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(horizontal: 18),
            child: MizdahCard(
              padding: EdgeInsets.zero,
              child: MizdahEmptyState(
                icon: Icons.history_rounded,
                title: 'No recent meetings',
                subtitle:
                    'Your past meetings will appear here once you join one.',
              ),
            ),
          );
        }
        // Single rounded card with diagonal-pattern wash + dividers
        // between rows — mirrors the Recent Activity design on home.
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: MizdahTokens.surface(context),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                  color: MizdahTokens.border(context), width: 1),
              boxShadow: MizdahTokens.shadow(context, elevation: 0.5),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(painter: _DiagonalPattern()),
                  ),
                  Column(
                    children: [
                      for (var i = 0; i < history.length; i++) ...[
                        _RecentCard(
                          item: history[i],
                          isHost: history[i].hostId != null &&
                              user != null &&
                              history[i].hostId == user.id,
                        ),
                        if (i < history.length - 1)
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 14),
                            child: Divider(
                              height: 1,
                              thickness: 1,
                              color: MizdahTokens.subtle(context),
                            ),
                          ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// One row in the Recent list. Mirrors the home Recent Activity row:
/// gradient pill icon (purple = hosted, emerald = joined) + role chip
/// + meeting code/title + absolute date.
///
/// Trailing widget swaps based on live state (protocol-driven):
///   • ACTIVE meeting   → LIVE pill + chevron, onTap opens rejoin sheet
///   • ENDED / unknown  → no chevron, dimmed, onTap is a no-op (and
///                        the card is not InkWell-rippling)
///
/// The AnimatedSwitcher on the trailing widget gives a smooth fade
/// when a meeting deactivates while the user is looking at the list —
/// matches the WhatsApp pattern of "live indicator just slid off".
class _RecentCard extends StatelessWidget {
  final CallHistory item;
  final bool isHost;
  const _RecentCard({required this.item, required this.isHost});

  @override
  Widget build(BuildContext context) {
    final palette = _palette(isHost);
    final code = item.meetingCode?.isNotEmpty == true
        ? MeetingUtils.extractCode(item.meetingCode!)
        : null;
    final displayTitle = (item.title.contains('http') ||
            item.title.length > 24)
        ? (item.meetingCode ?? 'Meeting')
        : item.title;

    // Source of truth for "is this meeting live right now": the
    // model's `isActive` field, which the merged provider patches
    // from the live presence socket. `null` is treated as ended
    // (protocol §1: null means unknown → render as ended).
    final isLive = item.isActive == true;
    final memberCount = item.membersCount ?? 0;

    final tap = !isLive || code == null
        ? null
        : () => showRejoinSheet(context, meeting: item);

    return InkWell(
      onTap: tap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Opacity(
          // Slight dim for ended meetings — emphasises live ones
          // without making ended cards look broken.
          opacity: isLive ? 1.0 : 0.78,
          child: Row(
            children: [
              _LeadingIcon(palette: palette, isHost: isHost, isLive: isLive),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: palette.chipBg,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            isHost ? 'HOSTED' : 'JOINED',
                            style: TextStyle(
                              color: palette.chipFg,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            displayTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: MizdahTokens.inkOf(context),
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Text(
                          DateFormat('MMM d, h:mm a').format(item.timestamp),
                          style: TextStyle(
                            color: MizdahTokens.mutedOf(context),
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        // When live and >1 person in the room, show
                        // the count next to the timestamp — gives the
                        // user a sense of how big the meeting is
                        // before they tap rejoin.
                        if (isLive && memberCount > 1) ...[
                          Text(
                            '  ·  ',
                            style: TextStyle(
                              color: MizdahTokens.mutedOf(context),
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            '$memberCount in meeting',
                            style: TextStyle(
                              color: MizdahTokens.primary,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              // Trailing widget — fades between LIVE pill+chevron and
              // a small "Ended" muted label. AnimatedSwitcher keeps
              // it visually stable as state flips mid-view.
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                transitionBuilder: (child, anim) =>
                    FadeTransition(opacity: anim, child: child),
                child: isLive && code != null
                    ? const _RecentTrailingLive(key: ValueKey('live'))
                    : const _RecentTrailingEnded(key: ValueKey('ended')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  _RolePalette _palette(bool isHost) {
    return isHost
        ? const _RolePalette(
            iconGradient: LinearGradient(
              colors: [Color(0xFF6C63FF), Color(0xFF8B5CF6)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            glow: Color(0xFF6C63FF),
            chipBg: Color(0xFFEDE9FE),
            chipFg: Color(0xFF6C63FF),
          )
        : const _RolePalette(
            iconGradient: LinearGradient(
              colors: [Color(0xFF10B981), Color(0xFF059669)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            glow: Color(0xFF10B981),
            chipBg: Color(0xFFD1FAE5),
            chipFg: Color(0xFF047857),
          );
  }
}

class _RolePalette {
  final LinearGradient iconGradient;
  final Color glow;
  final Color chipBg;
  final Color chipFg;
  const _RolePalette({
    required this.iconGradient,
    required this.glow,
    required this.chipBg,
    required this.chipFg,
  });
}

/// Leading 40×40 icon tile. For ACTIVE meetings we wrap the tile in
/// a soft pulsing ring so the user catches it at a glance — same
/// affordance as WhatsApp's call list "ongoing" indicator. For ended
/// meetings, just the gradient tile.
class _LeadingIcon extends StatelessWidget {
  final _RolePalette palette;
  final bool isHost;
  final bool isLive;
  const _LeadingIcon({
    required this.palette,
    required this.isHost,
    required this.isLive,
  });

  @override
  Widget build(BuildContext context) {
    final tile = Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: palette.iconGradient,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: palette.glow.withValues(alpha: isLive ? 0.45 : 0.30),
            blurRadius: isLive ? 14 : 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Icon(
        isHost ? Icons.video_call_rounded : Icons.call_received_rounded,
        color: Colors.white,
        size: 20,
      ),
    );
    if (!isLive) return tile;
    // Subtle outer pulsing ring — purely visual signal.
    return _PulseRing(color: palette.glow, child: tile);
  }
}

class _PulseRing extends StatefulWidget {
  final Color color;
  final Widget child;
  const _PulseRing({required this.color, required this.child});

  @override
  State<_PulseRing> createState() => _PulseRingState();
}

class _PulseRingState extends State<_PulseRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
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
      builder: (context, child) {
        final t = _c.value;
        return SizedBox(
          width: 48,
          height: 48,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Expanding ring — fades from solid to transparent as
              // it grows. Reads as a "heartbeat" without being noisy.
              Container(
                width: 40 + t * 14,
                height: 40 + t * 14,
                decoration: BoxDecoration(
                  shape: BoxShape.rectangle,
                  borderRadius: BorderRadius.circular(14 + t * 4),
                  border: Border.all(
                    color: widget.color.withValues(alpha: (1 - t) * 0.55),
                    width: 1.6,
                  ),
                ),
              ),
              child!,
            ],
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// Trailing widget for an ACTIVE recent meeting card — LIVE pill +
/// chevron, separated by spacing. The whole row is wrapped in the
/// card's InkWell so the user can tap anywhere.
class _RecentTrailingLive extends StatelessWidget {
  const _RecentTrailingLive({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            gradient: MizdahTokens.heroGradient,
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              BoxShadow(
                color: MizdahTokens.primary.withValues(alpha: 0.35),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _LiveDot(),
              SizedBox(width: 6),
              Text(
                'LIVE',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Icon(
          Icons.chevron_right_rounded,
          color: MizdahTokens.mutedOf(context),
          size: 18,
        ),
      ],
    );
  }
}

/// Trailing widget for an ENDED meeting card — small muted "Ended"
/// chip, no chevron. Card is non-tappable in this state.
class _RecentTrailingEnded extends StatelessWidget {
  const _RecentTrailingEnded({super.key});

  @override
  Widget build(BuildContext context) {
    final ink = MizdahTokens.inkOf(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: ink.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'Ended',
        style: TextStyle(
          color: ink.withValues(alpha: 0.5),
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _LiveDot extends StatefulWidget {
  const _LiveDot();

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
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
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.6 + 0.4 * t),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.white.withValues(alpha: t * 0.6),
                blurRadius: 4,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DiagonalPattern extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF6C63FF).withValues(alpha: 0.025)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;
    const step = 12.0;
    for (double x = -size.height; x < size.width; x += step) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x + size.height, size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DiagonalPattern old) => false;
}

class _Loader extends StatelessWidget {
  const _Loader();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 60),
      child: Center(
        child: SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(
            strokeWidth: 2.4,
            valueColor: AlwaysStoppedAnimation(MizdahTokens.primary),
          ),
        ),
      ),
    );
  }
}
