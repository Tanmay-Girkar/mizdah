// ════════════════════════════════════════════════════════════════════
//  Meetings — full-page premium "all meetings" view
//  ────────────────────────────────────────────────────────────────────
//  Two segmented sections:
//    • Upcoming (schedulesProvider)
//    • Recent   (callHistoryProvider)
//  Reuses the home screen's data sources so invalidation in one place
//  refreshes both views.
// ════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/ui/mizdah_design.dart';
import '../../../core/utils/meeting_utils.dart';
import '../../../data/models/models.dart';
import '../../home/presentation/home_screen.dart' show
    schedulesProvider,
    callHistoryProvider;

class MeetingsScreen extends ConsumerStatefulWidget {
  const MeetingsScreen({super.key});

  @override
  ConsumerState<MeetingsScreen> createState() => _MeetingsScreenState();
}

class _MeetingsScreenState extends ConsumerState<MeetingsScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entryCtrl;
  // 0 = Upcoming, 1 = Recent. Local UI state only.
  int _segment = 0;

  @override
  void initState() {
    super.initState();
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
      activeIndex: 1,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(schedulesProvider);
            ref.invalidate(callHistoryProvider);
            await Future<void>.delayed(const Duration(milliseconds: 350));
          },
          color: MizdahTokens.primary,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics()),
            padding: const EdgeInsets.only(bottom: 110),
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
    final start = DateTime.tryParse(schedule['startTime']?.toString() ?? '') ??
        DateTime.now();
    final end = DateTime.tryParse(schedule['endTime']?.toString() ?? '');
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
    final async = ref.watch(callHistoryProvider);
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
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Column(
            children: [
              for (var i = 0; i < history.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _RecentCard(item: history[i], colorIndex: i),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _RecentCard extends StatelessWidget {
  final CallHistory item;
  final int colorIndex;
  const _RecentCard({required this.item, required this.colorIndex});

  String _formatRelative(DateTime when) {
    final now = DateTime.now();
    final diff = now.difference(when);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat('MMM d, h:mm a').format(when);
  }

  String _formatDuration(Duration d) {
    if (d.inSeconds == 0) return '—';
    if (d.inMinutes < 1) return '${d.inSeconds}s';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    final h = d.inHours;
    final m = d.inMinutes % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }

  @override
  Widget build(BuildContext context) {
    final palette = MizdahTokens.rowColors[colorIndex % 5];
    final code = item.meetingCode?.isNotEmpty == true
        ? MeetingUtils.extractCode(item.meetingCode!)
        : null;

    return MizdahCard(
      padding: const EdgeInsets.all(14),
      onTap: code == null
          ? null
          : () => context.push('/pre-join/$code'),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: palette[0],
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.video_call_rounded,
                color: palette[1], size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: MizdahTokens.inkOf(context),
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Icon(Icons.schedule_rounded,
                        color: MizdahTokens.mutedOf(context), size: 12),
                    const SizedBox(width: 4),
                    Text(
                      _formatRelative(item.timestamp),
                      style: TextStyle(
                        color: MizdahTokens.mutedOf(context),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 10),
                    if (item.duration > Duration.zero) ...[
                      Icon(Icons.timer_outlined,
                          color: MizdahTokens.mutedOf(context), size: 12),
                      const SizedBox(width: 4),
                      Text(
                        _formatDuration(item.duration),
                        style: TextStyle(
                          color: MizdahTokens.mutedOf(context),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (code != null)
            Icon(Icons.chevron_right_rounded,
                color: MizdahTokens.mutedOf(context), size: 22),
        ],
      ),
    );
  }
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
