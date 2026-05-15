// ════════════════════════════════════════════════════════════════════
//  Call history — full-screen call log
//  ────────────────────────────────────────────────────────────────────
//  Reached from the Call tab's history-icon button. Renders the same
//  chronological list the Call tab used to show inline, but now in
//  its own route so the hub stays focused on "find a person and ring
//  them" without the log eating the entire screen.
//
//  Tapping a row redials the same peer with the same media kind.
//  The repository emits newest-first; we just group by date so the
//  list reads like the WhatsApp Calls tab.
// ════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/ui/mizdah_design.dart';
import '../../../data/models/models.dart';
import '../call_log_provider.dart';
import '../data/call_log_models.dart';
import '../p2p_call_provider.dart';

class CallHistoryScreen extends ConsumerWidget {
  const CallHistoryScreen({super.key});

  void _placeCall(WidgetRef ref, BuildContext context, User target,
      {required bool withVideo}) {
    FocusScope.of(context).unfocus();
    ref
        .read(p2pCallProvider.notifier)
        .startCall(target, withVideo: withVideo);
    context.push('/p2p-call');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logAsync = ref.watch(callLogProvider);
    return Scaffold(
      backgroundColor: MizdahTokens.bg(context),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // ── Header with back button ──────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => context.pop(),
                    icon: Icon(
                      Icons.arrow_back_rounded,
                      color: MizdahTokens.inkOf(context),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Call history',
                      style: TextStyle(
                        color: MizdahTokens.inkOf(context),
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: logAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 60),
                  child: Center(
                    child: SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        valueColor:
                            AlwaysStoppedAnimation(MizdahTokens.primary),
                      ),
                    ),
                  ),
                ),
                error: (_, __) => const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 18),
                  child: MizdahCard(
                    padding: EdgeInsets.zero,
                    child: MizdahEmptyState(
                      icon: Icons.cloud_off_rounded,
                      title: 'Could not load call history',
                      subtitle: 'Pull down to retry',
                    ),
                  ),
                ),
                data: (entries) => _renderList(context, ref, entries),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _renderList(BuildContext context, WidgetRef ref,
      List<CallLogEntry> entries) {
    if (entries.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 18),
        child: MizdahCard(
          padding: EdgeInsets.zero,
          child: MizdahEmptyState(
            icon: Icons.call_rounded,
            title: 'No calls yet',
            subtitle:
                'Calls you place or receive will appear here.',
          ),
        ),
      );
    }
    final groups = <String, List<CallLogEntry>>{};
    for (final e in entries) {
      groups.putIfAbsent(_dateLabel(e.startedAt), () => []).add(e);
    }
    return ListView(
      physics: const ClampingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics()),
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Row(
            children: [
              Text(
                '${entries.length} ${entries.length == 1 ? 'call' : 'calls'}',
                style: TextStyle(
                  color: MizdahTokens.mutedOf(context),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
        for (final group in groups.entries) ...[
          Padding(
            padding:
                const EdgeInsets.only(left: 4, top: 14, bottom: 6),
            child: Text(
              group.key.toUpperCase(),
              style: TextStyle(
                color: MizdahTokens.mutedOf(context),
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.0,
              ),
            ),
          ),
          for (final entry in group.value)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _CallHistoryRow(
                entry: entry,
                onRedial: (target, {required bool withVideo}) =>
                    _placeCall(ref, context, target, withVideo: withVideo),
              ),
            ),
        ],
      ],
    );
  }

  /// "Today" / "Yesterday" / "Mon" / "Apr 22, 2026" — matches the
  /// header convention WhatsApp uses on its Calls tab.
  static String _dateLabel(DateTime when) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final whenDay = DateTime(when.year, when.month, when.day);
    final delta = today.difference(whenDay).inDays;
    if (delta == 0) return 'Today';
    if (delta == 1) return 'Yesterday';
    if (delta < 7) return DateFormat('EEEE').format(when);
    if (when.year == now.year) return DateFormat('MMM d').format(when);
    return DateFormat('MMM d, yyyy').format(when);
  }
}

/// One row in the call history. Visuals match the WhatsApp pattern:
/// avatar, peer name, status icon + label + time + duration on the
/// next line, and a tappable call-back glyph on the right.
class _CallHistoryRow extends StatelessWidget {
  final CallLogEntry entry;
  final void Function(User, {required bool withVideo}) onRedial;
  const _CallHistoryRow({required this.entry, required this.onRedial});

  bool get _isOutgoing => entry.direction == CallDirection.outgoing;

  bool get _isFailureLike =>
      entry.outcome == CallOutcome.missed ||
      entry.outcome == CallOutcome.declined ||
      entry.outcome == CallOutcome.failed ||
      entry.outcome == CallOutcome.cancelled;

  IconData get _statusIcon {
    switch (entry.outcome) {
      case CallOutcome.answered:
        return _isOutgoing
            ? Icons.call_made_rounded
            : Icons.call_received_rounded;
      case CallOutcome.declined:
        return Icons.call_end_rounded;
      case CallOutcome.missed:
        return _isOutgoing
            ? Icons.call_missed_outgoing_rounded
            : Icons.call_missed_rounded;
      case CallOutcome.cancelled:
        return Icons.call_made_rounded;
      case CallOutcome.failed:
        return Icons.error_outline_rounded;
    }
  }

  Color get _statusColor => entry.outcome == CallOutcome.answered
      ? const Color(0xFF10B981)
      : const Color(0xFFE54848);

  String get _statusLabel {
    switch (entry.outcome) {
      case CallOutcome.answered:
        return _isOutgoing ? 'Outgoing' : 'Incoming';
      case CallOutcome.declined:
        return _isOutgoing ? 'Declined' : 'You declined';
      case CallOutcome.missed:
        return _isOutgoing ? 'No answer' : 'Missed';
      case CallOutcome.cancelled:
        return 'Cancelled';
      case CallOutcome.failed:
        return 'Failed';
    }
  }

  String _formatDuration(Duration d) {
    if (d.inSeconds == 0) return '';
    if (d.inMinutes < 1) return '${d.inSeconds}s';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    final h = d.inHours;
    final m = d.inMinutes % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }

  void _redial() {
    final target = User(
      id: entry.peerUserId,
      name: entry.peerName.isEmpty ? 'Unknown' : entry.peerName,
      email: entry.peerEmail ?? '',
    );
    onRedial(target, withVideo: entry.withVideo);
  }

  @override
  Widget build(BuildContext context) {
    final time = DateFormat('h:mm a').format(entry.startedAt);
    final duration = _formatDuration(entry.duration);
    final name = entry.peerName.isNotEmpty ? entry.peerName : 'Unknown';

    return MizdahCard(
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
      onTap: _redial,
      child: Row(
        children: [
          MizdahAvatar(name: name, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _isFailureLike
                        ? const Color(0xFFE54848)
                        : MizdahTokens.inkOf(context),
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Icon(_statusIcon, color: _statusColor, size: 14),
                    const SizedBox(width: 5),
                    Text(
                      _statusLabel,
                      style: TextStyle(
                        color: MizdahTokens.mutedOf(context),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      ' · $time',
                      style: TextStyle(
                        color: MizdahTokens.mutedOf(context),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (duration.isNotEmpty)
                      Text(
                        ' · $duration',
                        style: TextStyle(
                          color: MizdahTokens.mutedOf(context),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          // Trailing call-back glyph — tap to redial that peer with
          // the same media kind (video/audio) as the original call.
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: _isFailureLike
                  ? const LinearGradient(
                      colors: [Color(0xFFE54848), Color(0xFFB91C1C)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : MizdahTokens.heroGradient,
              shape: BoxShape.circle,
            ),
            child: Icon(
              entry.withVideo
                  ? Icons.videocam_rounded
                  : Icons.call_rounded,
              color: Colors.white,
              size: 16,
            ),
          ),
        ],
      ),
    );
  }
}
