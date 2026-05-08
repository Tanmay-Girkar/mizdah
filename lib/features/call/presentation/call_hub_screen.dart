// ════════════════════════════════════════════════════════════════════
//  Call hub — the "Call" tab
//  ────────────────────────────────────────────────────────────────────
//  Stripped down to two features per UX spec:
//
//    1. Search bar — type an email or name to find a Mizdah user.
//       Live-debounced lookup against
//       `GET /api/auth/users/search?q=...`. Each result row exposes
//       audio + video call buttons.
//
//    2. Recent contacts — the people you've spoken with before
//       (derived from `callHistoryProvider`). Same call buttons
//       inline so the row doubles as a quick-redial.
//
//  Tapping audio / video on either list fires
//  `p2pCallProvider.startCall(...)` which kicks off the signaling
//  handshake. Phase transitions are handled by the provider; this
//  screen just navigates to `/p2p-call` once `outgoing` is active.
// ════════════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ui/mizdah_design.dart';
import '../../../data/models/models.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/participant_repository.dart';
import '../../auth/auth_provider.dart';
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
    FocusScope.of(context).unfocus();
    ref
        .read(p2pCallProvider.notifier)
        .startCall(target, withVideo: withVideo);
    context.push('/p2p-call');
  }

  @override
  Widget build(BuildContext context) {
    return MizdahTabScaffold(
      activeIndex: 2,
      body: SafeArea(
        bottom: false,
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 110),
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

            // Body — search results win when there's a query, else
            // the recent-contacts list.
            MizdahFadeUp(
              controller: _entryCtrl,
              delay: 0.18,
              child: _query.isEmpty
                  ? _RecentContactsSection(onCall: _placeCall)
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
//  Recent contacts — derived from callHistoryProvider
// ────────────────────────────────────────────────────────────────────

class _RecentContactsSection extends ConsumerWidget {
  final void Function(User, {required bool withVideo}) onCall;
  const _RecentContactsSection({required this.onCall});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Build a stable list from call-history. Each entry becomes a
    // `User`-shaped row so the same _UserRow widget renders both
    // search hits and contacts.
    final history = ref.watch(_recentContactsProvider);

    return history.when(
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
            title: 'Could not load contacts',
            subtitle: 'Pull down to retry',
          ),
        ),
      ),
      data: (contacts) {
        if (contacts.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(horizontal: 18),
            child: MizdahCard(
              padding: EdgeInsets.zero,
              child: MizdahEmptyState(
                icon: Icons.contacts_rounded,
                title: 'No contacts yet',
                subtitle:
                    'Search anyone above to start a call. People you call show up here for quick redial.',
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
                child: Row(
                  children: [
                    Text(
                      'Contacts',
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
                        '${contacts.length}',
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
              for (final u in contacts)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _UserRow(user: u, onCall: onCall),
                ),
            ],
          ),
        );
      },
    );
  }
}

// Local provider — derives a deduped contacts list from the
// participant history. We don't have a dedicated "people I've met
// with" endpoint yet, so this is the closest approximation. Each
// history row becomes a synthetic `User` so the same `_UserRow`
// widget renders both search hits and contacts.
final _recentContactsProvider = FutureProvider<List<User>>((ref) async {
  final auth = ref.watch(authProvider);
  if (auth.user == null) return const [];
  final repo = ref.read(participantRepositoryProvider);
  final history = await repo.getUserHistory(auth.user!.id);
  final seen = <String>{};
  final out = <User>[];
  for (final h in history) {
    final key = h.title.trim().toLowerCase();
    if (key.isEmpty || seen.contains(key)) continue;
    seen.add(key);
    out.add(User(
      id: h.id,
      name: h.title.trim(),
      email: h.meetingCode ?? '',
    ));
  }
  return out;
});

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

