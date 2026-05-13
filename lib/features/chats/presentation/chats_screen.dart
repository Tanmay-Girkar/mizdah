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
import '../../auth/auth_provider.dart';
import '../chats_provider.dart';
import '../data/chat_models.dart';

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

  @override
  void initState() {
    super.initState();
    _entryCtrl = AnimationController(
      duration: const Duration(milliseconds: 700),
      vsync: this,
    )..forward();
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
    WidgetsBinding.instance.removeObserver(this);
    _entryCtrl.dispose();
    super.dispose();
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
                      onChanged: (v) => setState(() => _query = v),
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
                            if (filtered.isEmpty) {
                              return const Padding(
                                padding:
                                    EdgeInsets.symmetric(horizontal: 18),
                                child: MizdahCard(
                                  padding: EdgeInsets.zero,
                                  child: MizdahEmptyState(
                                    icon: Icons.search_off_rounded,
                                    title: 'No matches',
                                    subtitle: 'Try a different name or email.',
                                  ),
                                ),
                              );
                            }
                            return Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 18),
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
                hintText: 'Search chats',
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

class _ChatRow extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final peer = conversation.peerOf(selfEmail);
    final name = (conversation.title?.isNotEmpty ?? false)
        ? conversation.title!
        : (peer.contains('@') ? peer.split('@').first : peer);
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
          MizdahAvatar(name: name, size: 48),
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
