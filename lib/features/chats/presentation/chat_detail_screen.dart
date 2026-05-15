// ════════════════════════════════════════════════════════════════════
//  Chat detail — WhatsApp-style 1:1 thread
// ════════════════════════════════════════════════════════════════════
//  Layout:
//    • Top bar: back, avatar, peer name + presence, video / audio call
//    • Bubble list — outgoing (purple gradient, right-aligned) vs
//      incoming (surface, left-aligned). Each outgoing bubble shows
//      its delivery status (sending / sent / delivered / read).
//    • Composer: emoji, expanding TextField, send / mic.
//
//  Live updates land via `conversationDeltasProvider`; the initial
//  page comes from `conversationHistoryProvider`. We merge the two
//  in a local list so the UI doesn't flicker on each ack.

import 'dart:async';

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/ui/mizdah_design.dart';
import '../../auth/auth_provider.dart';
import '../chats_provider.dart';
import '../data/chat_models.dart';
import '../peer_profile_provider.dart';

class ChatDetailScreen extends ConsumerStatefulWidget {
  final String conversationId;
  const ChatDetailScreen({super.key, required this.conversationId});

  @override
  ConsumerState<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends ConsumerState<ChatDetailScreen> {
  final _scrollCtrl = ScrollController();
  final _textCtrl = TextEditingController();
  final _focusNode = FocusNode();
  /// Local merged thread. Hydrated from `conversationHistoryProvider`
  /// on first build, then mutated in-place as deltas arrive from
  /// `conversationDeltasProvider`. We avoid rebuilding from scratch
  /// per delta so the bubble list is stable.
  final List<ChatMessage> _messages = [];
  bool _hydrated = false;
  bool _emojiOpen = false;
  ProviderSubscription<AsyncValue<ChatMessage>>? _deltaSub;
  /// Bulletproof "this is mine" tracker — every message id we
  /// produce locally via `_send` lands here, plus optimistic
  /// `tmp_*` ids that are later replaced with the server id.
  /// Used as the first leg of the bubble-alignment check, before
  /// `ChatMessage.isMine`, so even if the auth state momentarily
  /// reports an empty user (`session_superseded`), or the backend
  /// omits the sender field on the response, or the conversation
  /// isn't in the cache yet (brand-new chat), the message *we just
  /// typed* always renders on the right.
  final Set<String> _myMessageIds = {};
  /// Pulled out of `build` so the build path stays free of side-
  /// effects. Resolves once the history future first delivers data.
  ProviderSubscription<AsyncValue<List<ChatMessage>>>? _historySub;
  /// REST poll fallback — we still want sent/delivered/read tick
  /// updates even when the /chats socket isn't connected (or the
  /// backend doesn't emit chat:status). Polls every few seconds
  /// while this screen is on top.
  Timer? _pollTimer;

  void _toggleEmoji() {
    if (_emojiOpen) {
      // Closing the picker → re-focus the input so the keyboard
      // slides back up.
      setState(() => _emojiOpen = false);
      _focusNode.requestFocus();
    } else {
      // Opening the picker → drop the soft keyboard first so the
      // emoji panel takes its place rather than stacking on top.
      _focusNode.unfocus();
      setState(() => _emojiOpen = true);
    }
  }

  void _onComposerTap() {
    // Tapping the input dismisses the emoji panel — keyboard is the
    // active input, picker is the secondary mode.
    if (_emojiOpen) setState(() => _emojiOpen = false);
  }

  void _onBackspaceFromPicker() {
    final v = _textCtrl.value;
    final selection = v.selection;
    final text = v.text;
    if (text.isEmpty) return;
    if (selection.isCollapsed) {
      final cursor = selection.baseOffset;
      if (cursor <= 0) return;
      final newText =
          text.substring(0, cursor - 1) + text.substring(cursor);
      _textCtrl.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: cursor - 1),
      );
    } else {
      final newText =
          text.substring(0, selection.start) + text.substring(selection.end);
      _textCtrl.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: selection.start),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    // Mark conversation read AND tell the server we're actively
    // viewing this thread — fire after first frame so the provider
    // tree is mounted. `focusConversation` makes the server push
    // `delivered` acks for inbound messages immediately, which is
    // what closes the perceived gap between "peer sent" and "I see
    // it" to under a second on a healthy network.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final repo = ref.read(chatRepositoryProvider);
      repo.markRead(widget.conversationId);
      repo.focusConversation(widget.conversationId);
    });
    // Periodic REST refresh — picks up status changes (sent →
    // delivered → read) and any messages that arrived without a
    // socket event firing.
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      _refreshMessagesQuiet();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _deltaSub?.close();
    _historySub?.close();
    _scrollCtrl.dispose();
    _textCtrl.dispose();
    _focusNode.dispose();
    // Tell the server we backed out + pull a fresh conversations
    // list so the chats screen we're about to land on shows the
    // up-to-date `lastMessage` preview for THIS thread (the messages
    // we sent or received while inside). Best-effort — `read` was
    // already called via markRead on enter, so the server has the
    // authoritative read receipt regardless of whether this lands.
    try {
      final repo = ref.read(chatRepositoryProvider);
      repo.blurConversation(widget.conversationId);
      // ignore: discarded_futures
      repo.refreshConversations();
    } catch (_) {}
    super.dispose();
  }

  /// Background refresh that doesn't reset the scroll position or
  /// flicker the list. Merges server messages into `_messages` —
  /// optimistic temp messages survive until their server ack arrives.
  /// Also kicks a conversations-list refresh in parallel so the
  /// chats screen's `lastMessage` preview stays current while the
  /// user is inside a thread (without this, opening a chat, sending
  /// a few messages, and backing out shows a stale preview row).
  Future<void> _refreshMessagesQuiet() async {
    if (!mounted || !_hydrated) return;
    final repo = ref.read(chatRepositoryProvider);
    // Fire conversations refresh in parallel — don't await it from
    // the messages path so a slow conversations endpoint can't stall
    // message updates. Errors are swallowed inside the repo.
    // ignore: discarded_futures
    repo.refreshConversations();
    try {
      final fresh =
          await repo.fetchMessages(conversationId: widget.conversationId);
      if (!mounted) return;
      _mergeServerMessages(fresh);
    } catch (_) {
      // Quiet — next tick will retry.
    }
  }

  /// Reconcile a fresh server-side messages list with the local one
  /// without losing optimistic sends or scroll position.
  void _mergeServerMessages(List<ChatMessage> server) {
    bool changed = false;
    for (final s in server) {
      final i = _messages.indexWhere(
        (m) => m.id == s.id ||
            // Server might echo our message back under a fresh id
            // we've never seen — match by `tmp_` body to dedup.
            (m.id.startsWith('tmp_') &&
                m.body == s.body &&
                m.senderEmail == s.senderEmail),
      );
      if (i >= 0) {
        final existing = _messages[i];
        if (_myMessageIds.contains(existing.id) && existing.id != s.id) {
          _myMessageIds.add(s.id);
        }
        if (existing.status != s.status ||
            existing.body != s.body ||
            existing.id != s.id) {
          _messages[i] = s;
          changed = true;
        }
      } else if (!s.id.startsWith('tmp_')) {
        _messages.add(s);
        changed = true;
      }
    }
    // Drop any local server-id messages that the server no longer
    // returns (deleted on backend). Optimistic temps stay.
    final serverIds = server.map((m) => m.id).toSet();
    final beforeLen = _messages.length;
    _messages.removeWhere((m) =>
        !m.id.startsWith('tmp_') && !serverIds.contains(m.id));
    if (_messages.length != beforeLen) changed = true;
    if (changed) {
      // Re-sort by sentAt to keep ordering canonical.
      _messages.sort((a, b) => a.sentAt.compareTo(b.sentAt));
      setState(() {});
    }
  }

  void _applyDelta(ChatMessage m) {
    final i = _messages.indexWhere((existing) =>
        existing.id == m.id ||
        // Optimistic temp-id was replaced — drop it.
        (existing.status == MessageStatus.sending &&
            existing.body == m.body &&
            existing.senderEmail == m.senderEmail));
    var isStatusOnly = false;
    var shouldScroll = false;
    setState(() {
      if (i >= 0) {
        final existing = _messages[i];
        // Carry the "mine" tracker across an id change (optimistic
        // tmp_* → server uuid) so the bubble alignment doesn't flip
        // when the ack arrives.
        if (_myMessageIds.contains(existing.id) &&
            existing.id != m.id) {
          _myMessageIds.add(m.id);
        }
        // Status-only delta (e.g. chat:status flipping sent → read)
        // arrives with body=='' and a placeholder timestamp. Merge it
        // into the existing bubble — don't blow away the body or the
        // real sentAt with the synthetic event.
        isStatusOnly = m.body.isEmpty && existing.body.isNotEmpty;
        _messages[i] = isStatusOnly
            ? existing.copyWith(status: m.status)
            : m;
      } else if (m.body.isNotEmpty) {
        _messages.add(m);
        shouldScroll = true;
      }
    });
    // Only follow new content; don't yank the user back to bottom on
    // a tick flipping in the middle of the thread.
    if (shouldScroll && !isStatusOnly) _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent + 80,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<void> _send() async {
    final body = _textCtrl.text.trim();
    if (body.isEmpty) return;
    _textCtrl.clear();
    if (_emojiOpen) setState(() => _emojiOpen = false);

    // ── True optimistic UI ──────────────────────────────────────
    // Old code awaited the REST round-trip BEFORE adding the bubble,
    // which left the user staring at an empty composer for the
    // duration of the request — looks like "the app ate my message".
    //
    // New flow:
    //   1. Build a local `sending` message with a client-generated
    //      temp id. Render it instantly.
    //   2. Fire the REST call in the background.
    //   3. The repo's response (or the socket's `chat:message` echo
    //      — whichever arrives first) is matched against this temp
    //      by `_applyDelta` and replaces it in place. Bubble flips
    //      from clock-tick → single-tick → double / blue ticks as
    //      status events flow in.
    //   4. On error we flip the temp's status to `failed` so the
    //      bubble shows the retry affordance.
    final me = ref.read(authProvider).user;
    final selfEmail = ref.read(effectiveSelfEmailProvider);
    final tempId = 'tmp_${DateTime.now().microsecondsSinceEpoch}';
    final optimistic = ChatMessage(
      id: tempId,
      conversationId: widget.conversationId,
      senderEmail: selfEmail.isNotEmpty
          ? selfEmail
          : (me?.email ?? ''),
      senderUserId: me?.id,
      body: body,
      sentAt: DateTime.now(),
      status: MessageStatus.sending,
    );
    setState(() {
      _myMessageIds.add(tempId);
      _messages.add(optimistic);
    });
    _scrollToBottom();

    // Fire-and-forget the network call. The repo's `_applyDelta`
    // reconciliation handles both the REST ack and the socket echo.
    final repo = ref.read(chatRepositoryProvider);
    try {
      final server = await repo.sendMessage(
        conversationId: widget.conversationId,
        body: body,
      );
      // Manually reconcile the temp in case the socket echo doesn't
      // arrive (e.g. socket disconnected mid-send). `_applyDelta`'s
      // matcher already handles the temp→server id swap by body +
      // status:sending.
      _applyDelta(server);
    } catch (e) {
      debugPrint('[chats] send failed: $e');
      if (!mounted) return;
      setState(() {
        final i = _messages.indexWhere((m) => m.id == tempId);
        if (i >= 0) {
          _messages[i] = _messages[i].copyWith(status: MessageStatus.failed);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(authProvider).user;
    final selfUserId = me?.id ?? '';

    // Subscribe to live deltas exactly once.
    _deltaSub ??= ref.listenManual(
      conversationDeltasProvider(widget.conversationId),
      (prev, next) {
        next.whenData(_applyDelta);
      },
    );

    // Subscribe to the initial-history future once. When it
    // resolves we replace any seeded placeholder with the full
    // server-side thread. Doing this via listenManual instead of
    // ref.watch keeps build() free of `setState` side effects.
    _historySub ??= ref.listenManual(
      conversationHistoryProvider(widget.conversationId),
      (prev, next) {
        next.whenData((initial) {
          if (!mounted || _hydrated) return;
          setState(() {
            _hydrated = true;
            _messages
              ..clear()
              ..addAll(initial);
          });
          WidgetsBinding.instance
              .addPostFrameCallback((_) => _scrollToBottom());
        });
      },
      fireImmediately: true,
    );

    // Pull all conversations up front — they're authoritative for
    // both the peer name AND the self-email derivation below.
    final allConvs = ref.watch(conversationsProvider).asData?.value ?? const [];
    final conv = allConvs.firstWhere(
      (c) => c.id == widget.conversationId,
      orElse: () => Conversation(
        id: widget.conversationId,
        participants: [me?.email ?? '', ''],
        lastMessage: null,
        unreadCount: 0,
        updatedAt: DateTime.now(),
      ),
    );

    // Instant placeholder — show the conversation's last_message
    // bubble immediately on first build, before the FutureProvider's
    // history fetch completes. The full thread merges in over the
    // top once it lands. This is what makes opening a chat feel
    // instant rather than waiting on the network spinner.
    if (!_hydrated && _messages.isEmpty && conv.lastMessage != null) {
      _messages.add(conv.lastMessage!);
    }
    // Shared provider falls back to the participants-intersection
    // derivation when auth.user.email is blank.
    final selfEmail = ref.watch(effectiveSelfEmailProvider);
    final peerEmail = conv.peerOf(selfEmail);
    final peerName = (conv.title?.isNotEmpty ?? false)
        ? conv.title!
        : (peerEmail.contains('@')
            ? peerEmail.split('@').first
            : peerEmail);

    return Scaffold(
      backgroundColor: MizdahTokens.bg(context),
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(peerName: peerName, peerEmail: peerEmail),
            Expanded(
              child: _messages.isEmpty
                  ? _EmptyOrLoading(
                      historyAsync: ref.watch(
                          conversationHistoryProvider(widget.conversationId)),
                    )
                  : ListView.builder(
                    controller: _scrollCtrl,
                    physics: const ClampingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                    itemCount: _messages.length,
                    itemBuilder: (ctx, i) {
                      final m = _messages[i];
                      final prev = i > 0 ? _messages[i - 1] : null;
                      // Date divider when the day rolls over (or for
                      // the very first message in the thread). Mirrors
                      // the WhatsApp pattern: TODAY / YESTERDAY /
                      // weekday for this week / "Apr 22, 2026" older.
                      final showDateDivider =
                          prev == null || !_sameDay(prev.sentAt, m.sentAt);
                      // Bulletproof check first — anything we've sent
                      // locally during this session is definitively
                      // ours, regardless of what the server returned.
                      // Falls through to ChatMessage.isMine for
                      // hydrated history we didn't send ourselves.
                      final mine = _myMessageIds.contains(m.id) ||
                          m.isMine(
                            selfUserId: selfUserId,
                            selfEmail: selfEmail,
                            peerEmail: peerEmail,
                          );
                      assert(() {
                        debugPrint(
                          '[chat] body="${m.body}" '
                          'mine=$mine '
                          'sender=${m.senderEmail} '
                          'self=$selfEmail peer=$peerEmail',
                        );
                        return true;
                      }());
                      // Group bubbles from the same sender in close
                      // succession — only show a tail on the last one.
                      final next =
                          i + 1 < _messages.length ? _messages[i + 1] : null;
                      final tailing = next == null ||
                          next.senderEmail != m.senderEmail ||
                          next.sentAt.difference(m.sentAt).inMinutes >= 5;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (showDateDivider) _DateDivider(date: m.sentAt),
                          Padding(
                            padding: EdgeInsets.only(top: tailing ? 6 : 2),
                            child: _Bubble(
                              message: m,
                              mine: mine,
                              tailing: tailing,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
            ),
            _Composer(
              controller: _textCtrl,
              focusNode: _focusNode,
              emojiOpen: _emojiOpen,
              onSend: _send,
              onToggleEmoji: _toggleEmoji,
              onComposerTap: _onComposerTap,
            ),
            // Emoji panel — slides in below the composer when toggled.
            // Animates height to give a smooth transition between the
            // soft keyboard and the picker.
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              child: SizedBox(
                height: _emojiOpen ? 300 : 0,
                child: _emojiOpen
                    ? EmojiPicker(
                        textEditingController: _textCtrl,
                        onBackspacePressed: _onBackspaceFromPicker,
                        config: Config(
                          height: 300,
                          checkPlatformCompatibility: true,
                          emojiViewConfig: EmojiViewConfig(
                            backgroundColor:
                                MizdahTokens.surface(context),
                            columns: 8,
                            emojiSizeMax: 26,
                          ),
                          categoryViewConfig: CategoryViewConfig(
                            backgroundColor:
                                MizdahTokens.surface(context),
                            iconColor:
                                MizdahTokens.mutedOf(context),
                            iconColorSelected: MizdahTokens.primary,
                            indicatorColor: MizdahTokens.primary,
                          ),
                          bottomActionBarConfig: BottomActionBarConfig(
                            backgroundColor:
                                MizdahTokens.surface(context),
                            buttonColor: MizdahTokens.primary,
                            buttonIconColor: Colors.white,
                          ),
                          searchViewConfig: SearchViewConfig(
                            backgroundColor:
                                MizdahTokens.surface(context),
                          ),
                        ),
                      )
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

/// Renders the spinner / error / empty state shown when `_messages`
/// has no entries yet — so the parent can switch to a real list as
/// soon as a placeholder bubble or hydrated history is available.
class _EmptyOrLoading extends StatelessWidget {
  final AsyncValue<List<ChatMessage>> historyAsync;
  const _EmptyOrLoading({required this.historyAsync});

  @override
  Widget build(BuildContext context) {
    return historyAsync.when(
      loading: () => const Center(
        child: SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(
            strokeWidth: 2.4,
            valueColor: AlwaysStoppedAnimation(MizdahTokens.primary),
          ),
        ),
      ),
      error: (_, __) => Center(
        child: Text(
          'Could not load messages',
          style: TextStyle(
            color: MizdahTokens.mutedOf(context),
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      data: (_) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            'No messages yet — say hi 👋',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: MizdahTokens.mutedOf(context),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

/// Centered date chip placed between bubble groups when the day
/// rolls over. Matches the WhatsApp pattern — TODAY / YESTERDAY /
/// weekday for this week / `MMM d, yyyy` for older.
class _DateDivider extends StatelessWidget {
  final DateTime date;
  const _DateDivider({required this.date});

  String _label() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final whenDay = DateTime(date.year, date.month, date.day);
    final delta = today.difference(whenDay).inDays;
    if (delta == 0) return 'Today';
    if (delta == 1) return 'Yesterday';
    if (delta < 7) return DateFormat('EEEE').format(date);
    if (date.year == now.year) return DateFormat('MMM d').format(date);
    return DateFormat('MMM d, yyyy').format(date);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: MizdahTokens.surface(context),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(
                color: MizdahTokens.border(context), width: 1),
            boxShadow: MizdahTokens.shadow(context, elevation: 0.3),
          ),
          child: Text(
            _label().toUpperCase(),
            style: TextStyle(
              color: MizdahTokens.mutedOf(context),
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.0,
            ),
          ),
        ),
      ),
    );
  }
}

class _TopBar extends ConsumerWidget {
  final String peerName;
  final String peerEmail;
  const _TopBar({required this.peerName, required this.peerEmail});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Same peer-profile lookup the chat list row uses, so the
    // avatar in the conversation header matches the avatar in the
    // list (cache shared by email key).
    final peerProfile =
        ref.watch(peerProfileProvider(peerEmail.toLowerCase()));
    final peerAvatar = peerProfile.maybeWhen(
      data: (u) => (u?.avatarUrl?.trim().isNotEmpty ?? false)
          ? u!.avatarUrl
          : null,
      orElse: () => null,
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
      decoration: BoxDecoration(
        color: MizdahTokens.surface(context),
        border: Border(
          bottom: BorderSide(
              color: MizdahTokens.subtle(context), width: 1),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => context.pop(),
            icon: Icon(Icons.arrow_back_ios_new_rounded,
                color: MizdahTokens.inkOf(context), size: 18),
            splashRadius: 22,
          ),
          MizdahAvatar(name: peerName, avatarUrl: peerAvatar, size: 38),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  peerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: MizdahTokens.inkOf(context),
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  peerEmail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: MizdahTokens.mutedOf(context),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          _RoundIcon(
            icon: Icons.call_rounded,
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Audio call from chat — coming soon'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _RoundIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _RoundIcon({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: MizdahTokens.iconTileBg(context),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: MizdahTokens.primary, size: 18),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final ChatMessage message;
  final bool mine;
  final bool tailing;
  const _Bubble({
    required this.message,
    required this.mine,
    required this.tailing,
  });

  @override
  Widget build(BuildContext context) {
    final maxW = MediaQuery.of(context).size.width * 0.78;
    final timeLabel = DateFormat('h:mm a').format(message.sentAt);

    final radius = BorderRadius.only(
      topLeft: const Radius.circular(16),
      topRight: const Radius.circular(16),
      bottomLeft: Radius.circular(mine || !tailing ? 16 : 4),
      bottomRight: Radius.circular(!mine || !tailing ? 16 : 4),
    );

    final body = Column(
      crossAxisAlignment:
          mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          message.body,
          style: TextStyle(
            color: mine ? Colors.white : MizdahTokens.inkOf(context),
            fontSize: 14.5,
            fontWeight: FontWeight.w500,
            height: 1.32,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              timeLabel,
              style: TextStyle(
                color: mine
                    ? Colors.white.withValues(alpha: 0.78)
                    : MizdahTokens.mutedOf(context),
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (mine) ...[
              const SizedBox(width: 4),
              _StatusTicks(status: message.status),
            ],
          ],
        ),
      ],
    );

    final wrapped = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxW),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 9, 12, 7),
        decoration: BoxDecoration(
          gradient: mine ? MizdahTokens.heroGradient : null,
          color: mine ? null : MizdahTokens.surface(context),
          borderRadius: radius,
          border: mine
              ? null
              : Border.all(
                  color: MizdahTokens.border(context), width: 1),
          boxShadow: mine
              ? [
                  BoxShadow(
                    color:
                        MizdahTokens.primary.withValues(alpha: 0.18),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : MizdahTokens.shadow(context, elevation: 0.3),
        ),
        child: body,
      ),
    );

    return Row(
      mainAxisAlignment:
          mine ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: [wrapped],
    );
  }
}

class _StatusTicks extends StatelessWidget {
  final MessageStatus status;
  const _StatusTicks({required this.status});

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case MessageStatus.sending:
        return Icon(Icons.access_time_rounded,
            color: Colors.white.withValues(alpha: 0.78), size: 12);
      case MessageStatus.failed:
        return const Icon(Icons.error_outline_rounded,
            color: Color(0xFFFCA5A5), size: 12);
      case MessageStatus.sent:
        return Icon(Icons.done_rounded,
            color: Colors.white.withValues(alpha: 0.85), size: 13);
      case MessageStatus.delivered:
        return Icon(Icons.done_all_rounded,
            color: Colors.white.withValues(alpha: 0.85), size: 13);
      case MessageStatus.read:
        return const Icon(Icons.done_all_rounded,
            color: Color(0xFF4FC3F7), size: 13);
    }
  }
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool emojiOpen;
  final VoidCallback onSend;
  final VoidCallback onToggleEmoji;
  final VoidCallback onComposerTap;
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.emojiOpen,
    required this.onSend,
    required this.onToggleEmoji,
    required this.onComposerTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = MizdahTokens.isDark(context);
    return SafeArea(
      top: false,
      child: Container(
        // Slight tint behind the pill so the white pill reads as
        // elevated against the page background — matches WhatsApp's
        // "tray" feel rather than the previous flat outline.
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        decoration: BoxDecoration(
          color: isDark
              ? MizdahTokens.surface(context)
              : const Color(0xFFF6F4FB),
          border: Border(
            top: BorderSide(
                color: MizdahTokens.subtle(context), width: 1),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Container(
                constraints:
                    const BoxConstraints(minHeight: 46, maxHeight: 140),
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: MizdahTokens.surface(context),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                      color: MizdahTokens.border(context), width: 1),
                  boxShadow:
                      MizdahTokens.shadow(context, elevation: 0.4),
                ),
                child: Row(
                  children: [
                    // Emoji toggle — icon flips between smile and
                    // keyboard glyph so the user sees that the same
                    // tap closes the picker too.
                    InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: onToggleEmoji,
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Icon(
                          emojiOpen
                              ? Icons.keyboard_alt_outlined
                              : Icons.emoji_emotions_outlined,
                          color: emojiOpen
                              ? MizdahTokens.primary
                              : MizdahTokens.mutedOf(context),
                          size: 22,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: TextField(
                        controller: controller,
                        focusNode: focusNode,
                        onTap: onComposerTap,
                        minLines: 1,
                        maxLines: 6,
                        textCapitalization: TextCapitalization.sentences,
                        style: TextStyle(
                          color: MizdahTokens.inkOf(context),
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          height: 1.35,
                        ),
                        decoration: InputDecoration(
                          isCollapsed: true,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 13),
                          border: InputBorder.none,
                          hintText: 'Message',
                          hintStyle: TextStyle(
                            color: MizdahTokens.mutedOf(context),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        onSubmitted: (_) => onSend(),
                      ),
                    ),
                    const SizedBox(width: 4),
                    InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            behavior: SnackBarBehavior.floating,
                            duration: Duration(seconds: 2),
                            content: Text('Attachments — coming soon'),
                          ),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Icon(
                          Icons.attach_file_rounded,
                          color: MizdahTokens.mutedOf(context),
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            MizdahPressScale(
              scaleTo: 0.92,
              onTap: onSend,
              child: Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: MizdahTokens.heroGradient,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: MizdahTokens.primary.withValues(alpha: 0.40),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.send_rounded,
                  color: Colors.white,
                  size: 19,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
