// ════════════════════════════════════════════════════════════════════
//  Call hub — the "Call" tab
//  ────────────────────────────────────────────────────────────────────
//  Sections, top to bottom:
//
//    • Page header — "Find & call" + history-icon button on the
//      right that pushes /call-history (full chronological log).
//    • Search bar — debounced 320 ms lookup against
//      `GET /api/auth/users/search?q=...`, merged with the locally
//      synced Mizdah-contacts cache and the "not on Mizdah" device
//      contacts for an Invite chip.
//    • Resting state (no query) — Mizdah contacts list + invite
//      section + (if no phone linked yet) a nudge banner.
//
//  The call log used to live inline here but was moved to its own
//  /call-history route (see `call_history_screen.dart`) so the hub
//  stays focused on "find a person and ring them". CallLogEntry
//  records are still appended by `P2PCallNotifier` on every
//  terminal call state — the history screen just reads the same
//  `callLogProvider`.
// ════════════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ui/mizdah_design.dart';
import '../../../data/models/contact_models.dart';
import '../../../data/models/models.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../auth/auth_provider.dart';
import '../contacts_provider.dart';
import '../invite_service.dart';
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
    // Skip the staggered fade-up entry animation on tab switches.
    // Controller stays alive (children of MizdahFadeUp still listen
    // to it) but starts at 1.0 = fully visible / no offset, so tab
    // switches feel instant. The 700ms fade was perceived by users
    // as a 2-second blurry lag on the Call tab.
    _entryCtrl = AnimationController(
      duration: const Duration(milliseconds: 700),
      vsync: this,
      value: 1.0,
    );
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

  Future<void> _onRequestContactsPermission() async {
    final ok = await ref
        .read(contactsProvider.notifier)
        .requestAndSync();
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Contacts access denied. You can enable it in Settings.'),
        ),
      );
    }
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
              child: MizdahPageHeader(
                leading: 'Find &',
                accent: 'call',
                subtitle: 'Search anyone, ring instantly',
                // Tap → full-screen call history. Replaces the
                // inline call-log section that used to live below
                // the contacts; the hub is now focused on "find a
                // person and ring them" while the log is one tap
                // away on its own route.
                trailing: _HistoryIconButton(
                  onTap: () => context.push('/call-history'),
                ),
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
              child: RefreshIndicator(
                onRefresh: () =>
                    ref.read(contactsProvider.notifier).sync(),
                child: ListView(
                  physics: const ClampingScrollPhysics(
                      parent: AlwaysScrollableScrollPhysics()),
                  padding: const EdgeInsets.only(bottom: 8),
                  children: [
                    if (_query.isEmpty) ...[
                      // Soft nudge for users who haven't linked a phone
                      // yet — so their friends with this number in
                      // their address book can find them on Mizdah.
                      // Auto-hides once a phone is on file.
                      MizdahFadeUp(
                        controller: _entryCtrl,
                        delay: 0.13,
                        child: const _LinkPhoneBanner(),
                      ),
                      MizdahFadeUp(
                        controller: _entryCtrl,
                        delay: 0.16,
                        child: _MizdahContactsSection(
                          onCall: _placeCall,
                          onRequestPermission: _onRequestContactsPermission,
                        ),
                      ),
                      // Call log moved to its own /call-history
                      // route — reachable via the history icon in
                      // the page header. Keeps the hub focused on
                      // Mizdah-contacts + search results.
                      MizdahFadeUp(
                        controller: _entryCtrl,
                        delay: 0.24,
                        child: const _InviteSection(),
                      ),
                    ] else
                      MizdahFadeUp(
                        controller: _entryCtrl,
                        delay: 0.18,
                        child: _SearchResultsSection(
                          backendResults: _results,
                          busy: _searching,
                          query: _query,
                          onCall: _placeCall,
                        ),
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
                hintText: 'Search by name, email, or +91…',
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

class _SearchResultsSection extends ConsumerWidget {
  final List<User> backendResults;
  final bool busy;
  final String query;
  final void Function(User, {required bool withVideo}) onCall;
  const _SearchResultsSection({
    required this.backendResults,
    required this.busy,
    required this.query,
    required this.onCall,
  });

  /// Filter the locally-cached Mizdah contacts down to those whose
  /// name / phone / email substring-matches the query. Lets a user
  /// who synced contacts and then typed "mum" see their mom even
  /// before the backend's name index has indexed the saved-as name.
  List<MizdahContact> _localMizdahHits(
    List<MizdahContact> matched,
    String q,
  ) {
    final lower = q.toLowerCase();
    final isPhone = lower.startsWith('+') && lower.length >= 4;
    return matched.where((c) {
      if (isPhone) {
        return (c.phone ?? '').toLowerCase().contains(lower);
      }
      return c.displayName.toLowerCase().contains(lower) ||
          (c.email ?? '').toLowerCase().contains(lower);
    }).toList();
  }

  /// Filter the invitable (not-on-Mizdah) device contacts down to
  /// query matches so the search results offer "Invite to Mizdah"
  /// alongside registered users.
  List<DeviceContact> _localInviteHits(
    List<DeviceContact> invitable,
    String q,
  ) {
    final lower = q.toLowerCase();
    final isPhone = lower.startsWith('+') && lower.length >= 4;
    return invitable.where((c) {
      if (isPhone) {
        return c.phones.any((p) => p.toLowerCase().contains(lower));
      }
      return c.displayName.toLowerCase().contains(lower) ||
          c.emails.any((e) => e.contains(lower)) ||
          c.phones.any((p) => p.toLowerCase().contains(lower));
    }).toList();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contacts = ref.watch(contactsProvider);
    final me = ref.read(authProvider).user?.id;
    // Merge backend results + local Mizdah contact matches, deduped
    // by userId. Local hits help when the backend hasn't reindexed
    // a recently-renamed user or doesn't store the local "saved as"
    // name that the user actually searched by.
    final localMizdah = _localMizdahHits(contacts.matched, query);
    final knownIds = <String>{
      for (final u in backendResults) u.id,
      for (final m in localMizdah) m.userId,
    };
    final mergedUsers = <User>[
      for (final u in backendResults)
        if (u.id != me) u,
      for (final m in localMizdah)
        if (m.userId != me && !backendResults.any((u) => u.id == m.userId))
          m.toUser(),
    ];
    final inviteHits = _localInviteHits(contacts.invitable, query)
        // Hide entries whose userId would have shown above anyway —
        // shouldn't happen because invitable excludes matched users
        // already, but defensive.
        .where((_) => true)
        .toList();

    if (busy && mergedUsers.isEmpty && inviteHits.isEmpty) {
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
    if (mergedUsers.isEmpty && inviteHits.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 18),
        child: MizdahCard(
          padding: EdgeInsets.zero,
          child: MizdahEmptyState(
            icon: Icons.person_search_rounded,
            title: 'No matches',
            subtitle: 'Try a different name, email, or phone.',
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (mergedUsers.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Text(
                '${mergedUsers.length} on Mizdah',
                style: TextStyle(
                  color: MizdahTokens.mutedOf(context),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
            ),
            for (final u in mergedUsers)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _UserRow(user: u, onCall: onCall),
              ),
          ],
          if (inviteHits.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 14, bottom: 8),
              child: Text(
                '${inviteHits.length} not on Mizdah · invite them',
                style: TextStyle(
                  color: MizdahTokens.mutedOf(context),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
            ),
            for (final c in inviteHits)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _InviteRow(contact: c),
              ),
          ],
          // Suppress the unused-knownIds warning — defensive variable
          // we may want for future dedupe logic.
          if (knownIds.isEmpty) const SizedBox.shrink(),
        ],
      ),
    );
  }
}

/// Section shown above the call log when no search query is active.
/// Lists every Mizdah-registered contact synced from the device
/// address book. Tap a row to call (audio or video). When permission
/// hasn't been granted yet, shows an inline call-to-action instead.
class _MizdahContactsSection extends ConsumerWidget {
  final void Function(User, {required bool withVideo}) onCall;
  final VoidCallback onRequestPermission;
  const _MizdahContactsSection({
    required this.onCall,
    required this.onRequestPermission,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contacts = ref.watch(contactsProvider);
    final me = ref.read(authProvider).user?.id;
    // Hide self if somehow we matched our own phone (shouldn't happen
    // given backend uniqueness, but defensive).
    final visible = contacts.matched.where((c) => c.userId != me).toList();

    if (contacts.permission != ContactsPermissionState.granted) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
        child: MizdahCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: MizdahTokens.heroGradient,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.contacts_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Find your friends on Mizdah',
                      style: TextStyle(
                        color: MizdahTokens.inkOf(context),
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Allow Mizdah to read your contacts to see who you already '
                'know on the platform. Only phone numbers and emails are '
                'sent — no names — and they\'re discarded right after '
                'matching.',
                style: TextStyle(
                  color: MizdahTokens.mutedOf(context),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: onRequestPermission,
                  child: const Text('Allow contacts'),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (contacts.syncing && visible.isEmpty) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(18, 0, 18, 14),
        child: MizdahCard(
          padding: EdgeInsets.all(20),
          child: Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                valueColor: AlwaysStoppedAnimation(MizdahTokens.primary),
              ),
            ),
          ),
        ),
      );
    }

    if (visible.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Row(
              children: [
                Text(
                  'Mizdah contacts',
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
                    '${visible.length}',
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
          for (final m in visible)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _UserRow(user: m.toUser(), onCall: onCall),
            ),
        ],
      ),
    );
  }
}

/// "Invite to Mizdah" section shown under the call log. Always
/// expanded — the user explicitly asked for the contacts list to
/// render inline rather than hidden behind a chevron. For very large
/// address books (hundreds of entries) this means the outer ListView
/// builds them all eagerly; if that becomes a perf issue we can
/// switch to a SliverList.builder, but at typical contact counts
/// (a few hundred) it stays smooth on mid-range Android.
class _InviteSection extends ConsumerWidget {
  const _InviteSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contacts = ref.watch(contactsProvider);
    if (contacts.permission != ContactsPermissionState.granted ||
        contacts.invitable.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Row(
              children: [
                Text(
                  'Invite to Mizdah',
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
                    color: MizdahTokens.mutedOf(context)
                        .withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${contacts.invitable.length}',
                    style: TextStyle(
                      color: MizdahTokens.mutedOf(context),
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          for (final c in contacts.invitable)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _InviteRow(contact: c),
            ),
        ],
      ),
    );
  }
}

/// One device-contact row with an Invite button instead of call
/// buttons. Tapping Invite opens the OS share sheet with a prefilled
/// message + invite link.
class _InviteRow extends StatelessWidget {
  final DeviceContact contact;
  const _InviteRow({required this.contact});

  @override
  Widget build(BuildContext context) {
    final name = contact.displayName.isEmpty
        ? (contact.primaryPhone ?? 'Unknown')
        : contact.displayName;
    final subtitle = contact.primaryPhone ?? contact.primaryEmail ?? '';
    return MizdahCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          MizdahAvatar(name: name, size: 46),
          const SizedBox(width: 14),
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
                    color: MizdahTokens.inkOf(context),
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
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
          MizdahPressScale(
            scaleTo: 0.92,
            onTap: () => InviteService.invite(contact),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                gradient: MizdahTokens.heroGradient,
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.send_rounded, color: Colors.white, size: 14),
                  SizedBox(width: 6),
                  Text(
                    'Invite',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}



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

/// Dismissible / auto-hiding banner shown at the top of the Call tab
/// when the signed-in user hasn't linked a phone number yet. Tap →
/// /link-phone. Auto-disappears the moment the user links a number.
///
/// Kept lightweight on purpose: no per-session dismissal cache, just
/// reads `authProvider.user.phone`. Once the linked phone lands in
/// state the banner is gone forever for that user; if they later
/// unlink the phone (changing it back to null is unsupported but
/// theoretically possible via direct API) it would reappear.
class _LinkPhoneBanner extends ConsumerWidget {
  const _LinkPhoneBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final phone = ref.watch(authProvider).user?.phone;
    if (phone != null && phone.isNotEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
      child: MizdahCard(
        padding: const EdgeInsets.all(14),
        onTap: () => context.push('/link-phone'),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: MizdahTokens.heroGradient,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.phone_iphone_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Add your phone number',
                    style: TextStyle(
                      color: MizdahTokens.inkOf(context),
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'So friends with your number find you on Mizdah',
                    style: TextStyle(
                      color: MizdahTokens.mutedOf(context),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: MizdahTokens.mutedOf(context),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}


/// Header-trailing circular icon button that jumps to the full
/// call-history screen. Drawn with the hero gradient so it reads as
/// a primary affordance (not just a back-of-mind nav target).
class _HistoryIconButton extends StatelessWidget {
  final VoidCallback onTap;
  const _HistoryIconButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return MizdahPressScale(
      scaleTo: 0.90,
      onTap: onTap,
      child: Tooltip(
        message: 'Call history',
        child: Container(
          width: 40,
          height: 40,
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
          child: const Icon(
            Icons.history_rounded,
            color: Colors.white,
            size: 20,
          ),
        ),
      ),
    );
  }
}
