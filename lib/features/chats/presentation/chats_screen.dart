// ════════════════════════════════════════════════════════════════════
//  Chats — WhatsApp-style conversation list (replaces the old People
//  tab). Reads `conversationsProvider`; tapping a row pushes the
//  detail thread; the FAB opens the New Chat search by gmail.
// ════════════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/ui/mizdah_design.dart';
import '../../../data/models/contact_models.dart';
import '../../auth/auth_provider.dart';
import '../../call/contacts_provider.dart';
import '../../call/invite_service.dart';
import '../chats_provider.dart';
import '../data/chat_models.dart';
import '../peer_profile_provider.dart';

class ChatsScreen extends ConsumerStatefulWidget {
  const ChatsScreen({super.key});

  @override
  ConsumerState<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends ConsumerState<ChatsScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _entryCtrl;
  String _query = '';
  /// Background poll that keeps each row's `lastMessage` preview
  /// fresh even when the WebSocket misses a `chat:message` event
  /// (or the backend hasn't mounted the `/chats` namespace yet).
  /// Without this, the list shows whatever the conversations cache
  /// held at last app start — which is why "test1" used to read
  /// `You: Hi` long after newer messages had arrived inside the
  /// thread; the conversation cache had no refresh path.
  Timer? _pollTimer;

  /// Debounce + result state for the in-search "Other Mizdah users"
  /// section. Empty until the user types something. Mirrors the Call
  /// tab's pattern so the two surfaces behave the same way.
  Timer? _searchDebounce;
  bool _userSearching = false;
  List<ChatUser> _userSearchResults = const [];

  @override
  void initState() {
    super.initState();
    // Skip the staggered fade-up — see CallHubScreen for the
    // rationale. Children of MizdahFadeUp render fully on first
    // frame so tab switches feel instant.
    _entryCtrl = AnimationController(
      duration: const Duration(milliseconds: 700),
      vsync: this,
      value: 1.0,
    );
    WidgetsBinding.instance.addObserver(this);
    // Pull once now and then every 8s while we're on this screen.
    // Cancelled in dispose. Errors are swallowed inside the repo;
    // failures are non-fatal — the next tick retries.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(chatRepositoryProvider).refreshConversations();
    });
    _pollTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (!mounted) return;
      ref.read(chatRepositoryProvider).refreshConversations();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Pull fresh the moment the app comes back to the foreground —
    // we may have missed socket events while backgrounded.
    if (state == AppLifecycleState.resumed && mounted) {
      ref.read(chatRepositoryProvider).refreshConversations();
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _searchDebounce?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _entryCtrl.dispose();
    super.dispose();
  }

  /// Debounced wrapper around the search bar. Same 320 ms threshold
  /// as the Call tab — typing slowly doesn't fire a backend request
  /// per keystroke. Empty query clears the in-flight results so the
  /// "other Mizdah users" section disappears.
  void _onQueryChanged(String v) {
    setState(() => _query = v);
    _searchDebounce?.cancel();
    final trimmed = v.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _userSearchResults = const [];
        _userSearching = false;
      });
      return;
    }
    _searchDebounce =
        Timer(const Duration(milliseconds: 320), () => _runUserSearch(trimmed));
  }

  Future<void> _runUserSearch(String q) async {
    if (_query.trim() != q) return; // user typed more in the meantime
    setState(() => _userSearching = true);
    final repo = ref.read(chatRepositoryProvider);
    final out = await repo.searchUsers(q);
    if (!mounted || _query.trim() != q) return;
    setState(() {
      _userSearchResults = out;
      _userSearching = false;
    });
  }

  Future<void> _openChatWith(String email) async {
    final repo = ref.read(chatRepositoryProvider);
    try {
      final conv = await repo.openConversationWith(email);
      if (!mounted) return;
      context.push('/chats/${conv.id}');
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't start chat. Try again.")),
      );
    }
  }

  bool _matches(Conversation c, String selfEmail, String q) {
    if (q.isEmpty) return true;
    final ql = q.toLowerCase();
    final peer = c.peerOf(selfEmail).toLowerCase();
    final title = (c.title ?? '').toLowerCase();
    final lastBody = (c.lastMessage?.body ?? '').toLowerCase();
    return peer.contains(ql) || title.contains(ql) || lastBody.contains(ql);
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(authProvider).user;
    // selfEmail goes through the shared provider that falls back to
    // the participants intersection when auth.user.email is blank
    // (session_superseded / pre-email-storage cache). Without this
    // fallback, peerOf returns the *first* participant — which is
    // actually the local user — and chat rows render with the
    // user's own name instead of the peer's.
    final selfEmail = ref.watch(effectiveSelfEmailProvider);
    final selfUserId = me?.id ?? '';
    final async = ref.watch(conversationsProvider);

    return MizdahTabScaffold(
      activeIndex: 1,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Column(
              children: [
                MizdahFadeUp(
                  controller: _entryCtrl,
                  delay: 0.0,
                  child: const MizdahPageHeader(
                    leading: 'Your',
                    accent: 'chats',
                    subtitle: 'Direct messages · Real-time',
                  ),
                ),
                const SizedBox(height: 14),
                MizdahFadeUp(
                  controller: _entryCtrl,
                  delay: 0.10,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: _SearchBar(
                      onChanged: _onQueryChanged,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: ListView(
                    physics: const ClampingScrollPhysics(
                        parent: AlwaysScrollableScrollPhysics()),
                    // Clear the floating nav AND the new-chat FAB.
                    // FAB is anchored at `navBarBottomInset + 8` and is
                    // 56 tall, so the last card needs at least
                    // `navBarBottomInset + 56 + 8 + 8` of bottom padding
                    // to never overlap the FAB.
                    padding: EdgeInsets.only(
                      bottom:
                          MizdahTokens.navBarBottomInset(context) + 80,
                    ),
                    children: [
                      MizdahFadeUp(
                        controller: _entryCtrl,
                        delay: 0.20,
                        child: async.when(
                          loading: () => const _LoaderRow(),
                          error: (_, __) => const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 18),
                            child: MizdahCard(
                              padding: EdgeInsets.zero,
                              child: MizdahEmptyState(
                                icon: Icons.cloud_off_rounded,
                                title: 'Could not load chats',
                                subtitle: 'Pull down to retry',
                              ),
                            ),
                          ),
                          data: (all) {
                            if (all.isEmpty) {
                              return const Padding(
                                padding:
                                    EdgeInsets.symmetric(horizontal: 18),
                                child: MizdahCard(
                                  padding: EdgeInsets.zero,
                                  child: MizdahEmptyState(
                                    icon: Icons.chat_bubble_outline_rounded,
                                    title: 'No chats yet',
                                    subtitle:
                                        'Tap the + button to start a chat with a Gmail address.',
                                  ),
                                ),
                              );
                            }
                            final filtered = all
                                .where((c) =>
                                    _matches(c, selfEmail, _query))
                                .toList();
                            // Resting (no search) state — render the
                            // chat list as before.
                            if (_query.trim().isEmpty) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 18),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.only(
                                          left: 4, bottom: 8),
                                      child: Text(
                                        '${filtered.length} ${filtered.length == 1 ? 'chat' : 'chats'}',
                                        style: TextStyle(
                                          color:
                                              MizdahTokens.mutedOf(context),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: 0.2,
                                        ),
                                      ),
                                    ),
                                    for (final c in filtered)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                            bottom: 10),
                                        child: _ChatRow(
                                          conversation: c,
                                          selfEmail: selfEmail,
                                          selfUserId: selfUserId,
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            }
                            // Searching — render up to three sections:
                            //   1) Existing chats that match.
                            //   2) Other Mizdah users that match
                            //      (backend search + synced contacts,
                            //      deduped against existing chats).
                            //   3) Invitable device contacts that
                            //      match the query (mirrors the Call
                            //      tab pattern).
                            return _SearchView(
                              query: _query.trim(),
                              filteredChats: filtered,
                              backendResults: _userSearchResults,
                              backendBusy: _userSearching,
                              selfEmail: selfEmail,
                              selfUserId: selfUserId,
                              onTapChatWith: _openChatWith,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            // Floating "new chat" button — anchored to the bottom-
            // right corner, sitting just above the floating nav.
            //
            // Coordinate space note: this Stack lives inside
            // `MizdahTabScaffold`, whose body is itself constrained
            // above the floating nav (Positioned(bottom: navInset)).
            // So `bottom: 8` here ALREADY clears the nav — adding
            // navInset on top would push the FAB to the vertical
            // centre of the screen, which was the previous bug.
            //
            // 24 px from the right edge + 8 px from the inner
            // stack's bottom = WhatsApp-style "anchored to the nav"
            // placement that respects safe area automatically (the
            // inner stack's bottom is already safe-area-aware via
            // navBarBottomInset).
            Positioned(
              right: 24,
              bottom: 8,
              child: MizdahFadeUp(
                controller: _entryCtrl,
                // Slight delay so the FAB lands after the list /
                // empty-state chrome — feels like it's "settling
                // in" once the rest of the screen is ready.
                delay: 0.32,
                child: _NewChatFab(
                  onTap: () => context.push('/chats/new'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  final ValueChanged<String> onChanged;
  const _SearchBar({required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: MizdahTokens.surface(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MizdahTokens.border(context), width: 1),
        boxShadow: MizdahTokens.shadow(context, elevation: 0.4),
      ),
      child: Row(
        children: [
          Icon(Icons.search_rounded,
              color: MizdahTokens.mutedOf(context), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              onChanged: onChanged,
              style: TextStyle(
                color: MizdahTokens.inkOf(context),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: 'Search chats, people, or +91…',
                hintStyle: TextStyle(
                  color: MizdahTokens.mutedOf(context),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatRow extends ConsumerWidget {
  final Conversation conversation;
  final String selfEmail;
  final String selfUserId;
  const _ChatRow({
    required this.conversation,
    required this.selfEmail,
    required this.selfUserId,
  });

  String _formatRelative(DateTime when) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final whenDay = DateTime(when.year, when.month, when.day);
    final dayDiff = today.difference(whenDay).inDays;
    if (dayDiff == 0) return DateFormat('h:mm a').format(when);
    if (dayDiff == 1) return 'Yesterday';
    if (dayDiff < 7) return DateFormat('EEE').format(when);
    return DateFormat('MMM d').format(when);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final peer = conversation.peerOf(selfEmail);
    // The conversations endpoint only ships email addresses for
    // participants — no avatar, no display name. Resolve the peer's
    // profile via the search endpoint so the tile shows their photo
    // instead of just initials. Cached cross-tab so we don't refetch
    // on every chats-tab open. See peer_profile_provider.dart.
    final peerProfile = ref.watch(peerProfileProvider(peer.toLowerCase()));
    final peerAvatar = peerProfile.maybeWhen(
      data: (u) => (u?.avatarUrl?.trim().isNotEmpty ?? false)
          ? u!.avatarUrl
          : null,
      orElse: () => null,
    );
    final peerDisplayName = peerProfile.maybeWhen(
      data: (u) => u?.displayName?.trim().isNotEmpty == true
          ? u!.displayName!.trim()
          : null,
      orElse: () => null,
    );
    final name = (conversation.title?.isNotEmpty ?? false)
        ? conversation.title!
        : (peerDisplayName ??
            (peer.contains('@') ? peer.split('@').first : peer));
    final last = conversation.lastMessage;
    final lastFromMe = last != null &&
        last.isMine(selfUserId: selfUserId, selfEmail: selfEmail);
    final preview = last == null
        ? 'Say hi 👋'
        : (lastFromMe ? 'You: ${last.body}' : last.body);
    final unread = conversation.unreadCount;
    final hasUnread = unread > 0;

    return MizdahCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      onTap: () => context.push('/chats/${conversation.id}'),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          MizdahAvatar(name: name, avatarUrl: peerAvatar, size: 48),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
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
                    ),
                    const SizedBox(width: 8),
                    Text(
                      last == null ? '' : _formatRelative(last.sentAt),
                      style: TextStyle(
                        color: hasUnread
                            ? MizdahTokens.primary
                            : MizdahTokens.mutedOf(context),
                        fontSize: 11,
                        fontWeight:
                            hasUnread ? FontWeight.w800 : FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        preview,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: hasUnread
                              ? MizdahTokens.inkOf(context)
                              : MizdahTokens.mutedOf(context),
                          fontSize: 12.5,
                          fontWeight: hasUnread
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                    if (hasUnread) ...[
                      const SizedBox(width: 8),
                      Container(
                        constraints: const BoxConstraints(minWidth: 20),
                        height: 20,
                        padding:
                            const EdgeInsets.symmetric(horizontal: 6),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          gradient: MizdahTokens.heroGradient,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: MizdahTokens.primary
                                  .withValues(alpha: 0.30),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Text(
                          unread > 99 ? '99+' : '$unread',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NewChatFab extends StatelessWidget {
  final VoidCallback onTap;
  const _NewChatFab({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return MizdahPressScale(
      scaleTo: 0.94,
      onTap: onTap,
      child: Container(
        width: 56,
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: MizdahTokens.heroGradient,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: MizdahTokens.primary.withValues(alpha: 0.40),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: const Icon(
          Icons.chat_rounded,
          color: Colors.white,
          size: 24,
        ),
      ),
    );
  }
}

class _LoaderRow extends StatelessWidget {
  const _LoaderRow();

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

// ────────────────────────────────────────────────────────────────────
//  Search view — surfaces when the query is non-empty
//  ────────────────────────────────────────────────────────────────────
//  Three sections rendered top-to-bottom:
//
//    1. Existing chats matching the query (using the same matcher as
//       the resting state).
//    2. Mizdah users matching the query but NOT already in the chat
//       list (backend search + synced contacts cache, deduped).
//       Tap → openConversationWith + go to /chats/<id>.
//    3. Device contacts that DON'T match a Mizdah user. Invite chip
//       mirrors the Call tab UX so the two feel consistent.
//
//  Each section is hidden when its source is empty; if all three are
//  empty we show a "No matches" empty state.
// ────────────────────────────────────────────────────────────────────

class _SearchView extends ConsumerWidget {
  final String query;
  final List<Conversation> filteredChats;
  final List<ChatUser> backendResults;
  final bool backendBusy;
  final String selfEmail;
  final String selfUserId;
  final void Function(String email) onTapChatWith;
  const _SearchView({
    required this.query,
    required this.filteredChats,
    required this.backendResults,
    required this.backendBusy,
    required this.selfEmail,
    required this.selfUserId,
    required this.onTapChatWith,
  });

  /// Emails of users we already have a chat with — used to dedupe
  /// section 2's "other Mizdah users" against section 1's existing
  /// chats. Lower-cased so we match the existing-chats peer string
  /// regardless of case in the backend response.
  Set<String> _existingChatPeerEmails() {
    return filteredChats
        .map((c) => c.peerOf(selfEmail).toLowerCase())
        .toSet();
  }

  /// Merge backend search hits with the locally-cached Mizdah
  /// contacts (the same list the Call tab shows). Local hits help
  /// when the backend's name index hasn't reindexed a fresh
  /// rename, or when the user typed a name they saved their friend
  /// under that doesn't match the friend's Mizdah display name.
  List<_StartChatHit> _mergedHits(WidgetRef ref) {
    final lower = query.toLowerCase();
    final existing = _existingChatPeerEmails();
    final byEmail = <String, _StartChatHit>{};
    // Backend hits first — they win on tiebreaks (have real
    // display_name from the server).
    for (final u in backendResults) {
      final emailLower = u.email.toLowerCase();
      if (emailLower == selfEmail.toLowerCase()) continue;
      if (existing.contains(emailLower)) continue;
      byEmail[emailLower] = _StartChatHit(
        email: u.email,
        label: u.label,
        avatarUrl: u.avatarUrl,
      );
    }
    // Local Mizdah contacts cache — append only when the backend
    // didn't already include this email.
    final contacts = ref.watch(contactsProvider).matched;
    for (final m in contacts) {
      final email = m.email;
      if (email == null || email.isEmpty) continue;
      if (email.toLowerCase() == selfEmail.toLowerCase()) continue;
      if (existing.contains(email.toLowerCase())) continue;
      if (byEmail.containsKey(email.toLowerCase())) continue;
      final hay = '${m.displayName.toLowerCase()} ${email.toLowerCase()} '
          '${(m.phone ?? '').toLowerCase()}';
      if (!hay.contains(lower)) continue;
      byEmail[email.toLowerCase()] = _StartChatHit(
        email: email,
        label: m.displayName,
        avatarUrl: m.avatarUrl,
      );
    }
    return byEmail.values.toList();
  }

  /// Device contacts that DIDN'T resolve to a Mizdah account but do
  /// match the typed query. Surface them with an Invite chip so
  /// search-by-phone-or-name in the Chats tab can still help a user
  /// reach someone who isn't on Mizdah yet.
  List<DeviceContact> _inviteHits(WidgetRef ref) {
    final lower = query.toLowerCase();
    final isPhone = lower.startsWith('+') && lower.length >= 4;
    final invitable = ref.watch(contactsProvider).invitable;
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
    final mergedHits = _mergedHits(ref);
    final inviteHits = _inviteHits(ref);
    final anyContent =
        filteredChats.isNotEmpty || mergedHits.isNotEmpty || inviteHits.isNotEmpty;

    if (!anyContent && !backendBusy) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 18),
        child: MizdahCard(
          padding: EdgeInsets.zero,
          child: MizdahEmptyState(
            icon: Icons.search_off_rounded,
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
          if (filteredChats.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Text(
                '${filteredChats.length} ${filteredChats.length == 1 ? 'chat' : 'chats'}',
                style: TextStyle(
                  color: MizdahTokens.mutedOf(context),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
            ),
            for (final c in filteredChats)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _ChatRow(
                  conversation: c,
                  selfEmail: selfEmail,
                  selfUserId: selfUserId,
                ),
              ),
          ],
          if (mergedHits.isNotEmpty || backendBusy) ...[
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 14, bottom: 8),
              child: Text(
                '${mergedHits.length} on Mizdah · start a chat',
                style: TextStyle(
                  color: MizdahTokens.mutedOf(context),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
            ),
            if (mergedHits.isEmpty && backendBusy)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      valueColor:
                          AlwaysStoppedAnimation(MizdahTokens.primary),
                    ),
                  ),
                ),
              ),
            for (final h in mergedHits)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _StartChatRow(
                  hit: h,
                  onTap: () => onTapChatWith(h.email),
                ),
              ),
          ],
          if (inviteHits.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 14, bottom: 8),
              child: Text(
                '${inviteHits.length} not on Mizdah · invite',
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
        ],
      ),
    );
  }
}

/// One result in the "Start a chat" section — an email + label +
/// optional avatar URL, plus a tap-to-chat icon on the right.
class _StartChatHit {
  final String email;
  final String label;
  final String? avatarUrl;
  const _StartChatHit({
    required this.email,
    required this.label,
    this.avatarUrl,
  });
}

class _StartChatRow extends StatelessWidget {
  final _StartChatHit hit;
  final VoidCallback onTap;
  const _StartChatRow({required this.hit, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return MizdahCard(
      padding: const EdgeInsets.all(14),
      onTap: onTap,
      child: Row(
        children: [
          MizdahAvatar(name: hit.label, avatarUrl: hit.avatarUrl, size: 46),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  hit.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: MizdahTokens.inkOf(context),
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hit.email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: MizdahTokens.mutedOf(context),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: 'Start chat',
            child: MizdahPressScale(
              scaleTo: 0.90,
              onTap: onTap,
              child: Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: MizdahTokens.heroGradient,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: MizdahTokens.primary.withValues(alpha: 0.36),
                      blurRadius: 12,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: const Icon(Icons.chat_bubble_rounded,
                    color: Colors.white, size: 18),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Device-contact row with an Invite chip — same widget shape as the
/// Call tab's invite section, locally re-implemented so we don't
/// couple the two presentation layers.
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
