// ════════════════════════════════════════════════════════════════════
//  Call hub — the "Call" tab
//  ────────────────────────────────────────────────────────────────────
//  Two stacked sections:
//
//    1. Search bar — type an email or name to find a Mizdah user.
//       Live-debounced lookup against
//       `GET /api/auth/users/search?q=...`. Each result row exposes
//       audio + video call buttons that fire
//       `p2pCallProvider.startCall(...)`.
//
//    2. Call log — WhatsApp-style chronological log of actual P2P
//       call events grouped by date (Today / Yesterday / weekday /
//       date). Each row shows the peer name, a status icon
//       (Outgoing / Incoming / Missed / Declined / Cancelled), time,
//       and duration. Tap a row to call that peer back.
//
//  Data source: `callLogProvider` — backed by `LocalCallLogRepository`
//  (SharedPreferences). Entries are appended by `P2PCallNotifier`
//  whenever a P2P call reaches a terminal state (declined / missed /
//  answered+ended / cancelled / failed). This is local-only for v1;
//  the server-backed multi-device version is specified in
//  docs/CALL_HISTORY_API.md.
// ════════════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/ui/mizdah_design.dart';
import '../../../data/models/models.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../auth/auth_provider.dart';
import '../call_log_provider.dart';
import '../data/call_log_models.dart';
import '../p2p_call_provider.dart';

class CallHubScreen extends ConsumerStatefulWidget {
  const CallHubScreen({super.key});

  @override
  ConsumerState<CallHubScreen> createState() => _CallHubScreenState();
}

class _CallHubScreenState extends ConsumerState<CallHubScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entryCtrl;
  final AuthRepository _authRepo = AuthRepository();
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  Timer? _debounceTimer;
  String _query = '';
  bool _searching = false;
  List<User> _results = const [];

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
    _debounceTimer?.cancel();
    _entryCtrl.dispose();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounceTimer?.cancel();
    final trimmed = value.trim();
    setState(() => _query = trimmed);
    if (trimmed.isEmpty) {
      setState(() {
        _results = const [];
        _searching = false;
      });
      return;
    }
    _debounceTimer = Timer(const Duration(milliseconds: 320), _runSearch);
  }

  Future<void> _runSearch() async {
    if (_query.isEmpty) return;
    final me = ref.read(authProvider).user?.id;
    setState(() => _searching = true);
    final users = await _authRepo.searchUsers(_query);
    if (!mounted) return;
    // Filter ourselves out — calling yourself is silly.
    final filtered = users.where((u) => u.id != me).toList();
    setState(() {
      _searching = false;
      _results = filtered;
    });
  }

  void _placeCall(User target, {required bool withVideo}) {
    // ─── STEP 1: CALL BUTTON LOGS ──────────────────────────────────
    // First chance to confirm the right intent left the UI. If this
    // line prints `audio` for a video-button tap, the bug is in the
    // button wiring (highly unlikely — see `_PersonRow` below where
    // the two buttons hardcode `withVideo: false` / `withVideo: true`).
    final auth = ref.read(authProvider);
    final callType = withVideo ? 'video' : 'audio';
    debugPrint('==============================');
    debugPrint('CALL BUTTON PRESSED');
    debugPrint('Selected call type: $callType');
    debugPrint('Caller ID: ${auth.user?.id}');
    debugPrint('Receiver ID: ${target.id}');
    debugPrint('Receiver Name: ${target.name}');
    debugPrint('==============================');
    FocusScope.of(context).unfocus();
    ref
        .read(p2pCallProvider.notifier)
        .startCall(target, withVideo: withVideo);
    context.push('/p2p-call');
  }

  @override
  Widget build(BuildContext context) {
    return MizdahTabScaffold(
      activeIndex: 3,
      body: SafeArea(
        bottom: false,
        // Pinned header + search field above a scrollable result
        // list. Crucial for this screen — when the keyboard pops
        // up to fill in the search query, the title and search
        // bar stay locked at the top while only the results
        // compress (WhatsApp / Telegram pattern).
        child: Column(
          children: [
            MizdahFadeUp(
              controller: _entryCtrl,
              delay: 0.0,
              child: const MizdahPageHeader(
                leading: 'Find &',
                accent: 'call',
                subtitle: 'Search anyone, ring instantly',
              ),
            ),
            const SizedBox(height: 16),
            MizdahFadeUp(
              controller: _entryCtrl,
              delay: 0.10,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: _SearchField(
                  controller: _searchCtrl,
                  focusNode: _searchFocus,
                  onChanged: _onQueryChanged,
                  busy: _searching,
                ),
              ),
            ),
            const SizedBox(height: 18),
            Expanded(
              child: ListView(
                physics: const ClampingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                padding: const EdgeInsets.only(bottom: 8),
                children: [
                  MizdahFadeUp(
                    controller: _entryCtrl,
                    delay: 0.18,
                    child: _query.isEmpty
                        ? _CallLogSection(onRedial: _placeCall)
                        : _SearchResultsSection(
                            results: _results,
                            busy: _searching,
                            query: _query,
                            onCall: _placeCall,
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────
//  Search field — premium pill with live debouncing
// ────────────────────────────────────────────────────────────────────

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final bool busy;
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.busy,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: MizdahTokens.surface(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: MizdahTokens.border(context), width: 1),
        boxShadow: MizdahTokens.shadow(context, elevation: 0.6),
      ),
      child: Row(
        children: [
          const SizedBox(width: 14),
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
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(Icons.search_rounded,
                color: Colors.white, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              onChanged: onChanged,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              textCapitalization: TextCapitalization.none,
              style: TextStyle(
                color: MizdahTokens.inkOf(context),
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                isCollapsed: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 18),
                border: InputBorder.none,
                hintText: 'Search by email or name',
                hintStyle: TextStyle(
                  color: MizdahTokens.mutedOf(context),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          if (busy)
            const Padding(
              padding: EdgeInsets.only(right: 14),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor:
                      AlwaysStoppedAnimation(MizdahTokens.primary),
                ),
              ),
            )
          else if (controller.text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: IconButton(
                tooltip: 'Clear',
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
                icon: Icon(Icons.close_rounded,
                    color: MizdahTokens.mutedOf(context), size: 18),
              ),
            ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────
//  Search results
// ────────────────────────────────────────────────────────────────────

class _SearchResultsSection extends StatelessWidget {
  final List<User> results;
  final bool busy;
  final String query;
  final void Function(User, {required bool withVideo}) onCall;
  const _SearchResultsSection({
    required this.results,
    required this.busy,
    required this.query,
    required this.onCall,
  });

  @override
  Widget build(BuildContext context) {
    if (busy && results.isEmpty) {
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
    if (results.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 18),
        child: MizdahCard(
          padding: EdgeInsets.zero,
          child: MizdahEmptyState(
            icon: Icons.person_search_rounded,
            title: 'No matches',
            subtitle: 'Try a different name or email.',
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              '${results.length} ${results.length == 1 ? 'match' : 'matches'} '
              'for "$query"',
              style: TextStyle(
                color: MizdahTokens.mutedOf(context),
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
          ),
          for (final u in results)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _UserRow(user: u, onCall: onCall),
            ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────
//  Call log — WhatsApp-style chronological call history
// ────────────────────────────────────────────────────────────────────

class _CallLogSection extends ConsumerWidget {
  final void Function(User, {required bool withVideo}) onRedial;
  const _CallLogSection({required this.onRedial});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logAsync = ref.watch(callLogProvider);

    return logAsync.when(
      loading: () => const Padding(
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
      data: (entries) {
        if (entries.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(horizontal: 18),
            child: MizdahCard(
              padding: EdgeInsets.zero,
              child: MizdahEmptyState(
                icon: Icons.call_rounded,
                title: 'No calls yet',
                subtitle:
                    'Search anyone above to start a call. Each call you place or receive will appear here.',
              ),
            ),
          );
        }
        // Repository emits newest-first already; group by date so the
        // list reads like the WhatsApp Calls tab.
        final groups = <String, List<CallLogEntry>>{};
        for (final e in entries) {
          final label = _dateLabel(e.startedAt);
          groups.putIfAbsent(label, () => []).add(e);
        }
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 6),
                child: Row(
                  children: [
                    Text(
                      'Call log',
                      style: TextStyle(
                        color: MizdahTokens.inkOf(context),
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        gradient: MizdahTokens.heroGradient,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${entries.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
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
                    child: _CallLogRow(entry: entry, onRedial: onRedial),
                  ),
              ],
            ],
          ),
        );
      },
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

/// One row in the call log. Visuals match the WhatsApp pattern:
/// avatar, peer name, status icon + label + time + duration on the
/// next line, and a tappable call-back glyph on the right.
class _CallLogRow extends StatelessWidget {
  final CallLogEntry entry;
  final void Function(User, {required bool withVideo}) onRedial;
  const _CallLogRow({required this.entry, required this.onRedial});

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

  void _redial(BuildContext context) {
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
      onTap: () => _redial(context),
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

// ────────────────────────────────────────────────────────────────────

class _UserRow extends StatelessWidget {
  final User user;
  final void Function(User, {required bool withVideo}) onCall;
  const _UserRow({required this.user, required this.onCall});

  @override
  Widget build(BuildContext context) {
    final hasEmail = user.email.isNotEmpty;
    return MizdahCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          MizdahAvatar(name: user.name, size: 46),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  user.name.isEmpty ? 'Unknown' : user.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: MizdahTokens.inkOf(context),
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                if (hasEmail) ...[
                  const SizedBox(height: 2),
                  Text(
                    user.email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: MizdahTokens.mutedOf(context),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Audio call
          _CallActionButton(
            icon: Icons.call_rounded,
            tone: _CallTone.audio,
            tooltip: 'Audio call',
            onTap: () => onCall(user, withVideo: false),
          ),
          const SizedBox(width: 8),
          // Video call
          _CallActionButton(
            icon: Icons.videocam_rounded,
            tone: _CallTone.video,
            tooltip: 'Video call',
            onTap: () => onCall(user, withVideo: true),
          ),
        ],
      ),
    );
  }
}

enum _CallTone { audio, video }

class _CallActionButton extends StatelessWidget {
  final IconData icon;
  final _CallTone tone;
  final String tooltip;
  final VoidCallback onTap;
  const _CallActionButton({
    required this.icon,
    required this.tone,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final gradient = tone == _CallTone.video
        ? MizdahTokens.heroGradient
        : const LinearGradient(
            colors: [Color(0xFF10B981), Color(0xFF059669)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          );
    final glow = tone == _CallTone.video
        ? MizdahTokens.primary
        : const Color(0xFF10B981);
    return Tooltip(
      message: tooltip,
      child: MizdahPressScale(
        scaleTo: 0.90,
        onTap: onTap,
        child: Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: gradient,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: glow.withValues(alpha: 0.36),
                blurRadius: 12,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Icon(icon, color: Colors.white, size: 19),
        ),
      ),
    );
  }
}

