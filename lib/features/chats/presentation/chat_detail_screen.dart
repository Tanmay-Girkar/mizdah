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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/ui/mizdah_design.dart';
import '../../auth/auth_provider.dart';
import '../chats_provider.dart';
import '../data/chat_models.dart';

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
  ProviderSubscription<AsyncValue<ChatMessage>>? _deltaSub;

  @override
  void initState() {
    super.initState();
    // Mark conversation read on enter — fire after first frame so the
    // provider tree is mounted.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(chatRepositoryProvider)
          .markRead(widget.conversationId);
    });
  }

  @override
  void dispose() {
    _deltaSub?.close();
    _scrollCtrl.dispose();
    _textCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _applyDelta(ChatMessage m) {
    final i = _messages.indexWhere((existing) =>
        existing.id == m.id ||
        // Optimistic temp-id was replaced — drop it.
        (existing.status == MessageStatus.sending &&
            existing.body == m.body &&
            existing.senderEmail == m.senderEmail));
    setState(() {
      if (i >= 0) {
        _messages[i] = m;
      } else {
        _messages.add(m);
      }
    });
    _scrollToBottom();
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
    final repo = ref.read(chatRepositoryProvider);
    final optimistic = await repo.sendMessage(
      conversationId: widget.conversationId,
      body: body,
    );
    setState(() => _messages.add(optimistic));
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(authProvider).user;
    final selfEmail = me?.email ?? '';
    final selfUserId = me?.id ?? '';
    final history =
        ref.watch(conversationHistoryProvider(widget.conversationId));

    // Subscribe to live deltas exactly once.
    _deltaSub ??= ref.listenManual(
      conversationDeltasProvider(widget.conversationId),
      (prev, next) {
        next.whenData(_applyDelta);
      },
    );

    // Find peer info from the conversations list (already loaded).
    final allConvs = ref.watch(conversationsProvider).asData?.value ?? const [];
    final conv = allConvs.firstWhere(
      (c) => c.id == widget.conversationId,
      orElse: () => Conversation(
        id: widget.conversationId,
        participants: [selfEmail, ''],
        lastMessage: null,
        unreadCount: 0,
        updatedAt: DateTime.now(),
      ),
    );
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
              child: history.when(
                loading: () => const Center(
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
                error: (_, __) => Center(
                  child: Text(
                    'Could not load messages',
                    style: TextStyle(
                      color: MizdahTokens.mutedOf(context),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                data: (initial) {
                  if (!_hydrated) {
                    _hydrated = true;
                    _messages
                      ..clear()
                      ..addAll(initial);
                    WidgetsBinding.instance
                        .addPostFrameCallback((_) => _scrollToBottom());
                  }
                  if (_messages.isEmpty) {
                    return Center(
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
                    );
                  }
                  return ListView.builder(
                    controller: _scrollCtrl,
                    physics: const ClampingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                    itemCount: _messages.length,
                    itemBuilder: (ctx, i) {
                      final m = _messages[i];
                      // Compare by user-id first (case-exact UUID),
                      // then case-insensitive email — works whether
                      // the backend wires sender_email, sender_id,
                      // or both. Fixes the all-on-the-left bug when
                      // the email casing differs between auth and
                      // the message payload.
                      final mine = m.isMine(
                        selfUserId: selfUserId,
                        selfEmail: selfEmail,
                      );
                      // Group bubbles from the same sender in close
                      // succession — only show a tail on the last one.
                      final next =
                          i + 1 < _messages.length ? _messages[i + 1] : null;
                      final tailing = next == null ||
                          next.senderEmail != m.senderEmail ||
                          next.sentAt.difference(m.sentAt).inMinutes >= 5;
                      return Padding(
                        padding: EdgeInsets.only(top: tailing ? 6 : 2),
                        child: _Bubble(
                          message: m,
                          mine: mine,
                          tailing: tailing,
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            _Composer(
              controller: _textCtrl,
              focusNode: _focusNode,
              onSend: _send,
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final String peerName;
  final String peerEmail;
  const _TopBar({required this.peerName, required this.peerEmail});

  @override
  Widget build(BuildContext context) {
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
          MizdahAvatar(name: peerName, size: 38),
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
            icon: Icons.videocam_rounded,
            onTap: () {
              // Future: kick a /pre-join with a fresh code.
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Video call from chat — coming soon'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),
          const SizedBox(width: 8),
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
  final VoidCallback onSend;
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: BoxDecoration(
          color: MizdahTokens.surface(context),
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
                    const BoxConstraints(minHeight: 44, maxHeight: 140),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: MizdahTokens.bg(context),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                      color: MizdahTokens.border(context), width: 1),
                ),
                child: Row(
                  children: [
                    Icon(Icons.emoji_emotions_outlined,
                        color: MizdahTokens.mutedOf(context), size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: controller,
                        focusNode: focusNode,
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
                              const EdgeInsets.symmetric(vertical: 12),
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
                    const SizedBox(width: 8),
                    Icon(Icons.attach_file_rounded,
                        color: MizdahTokens.mutedOf(context), size: 20),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            MizdahPressScale(
              scaleTo: 0.92,
              onTap: onSend,
              child: Container(
                width: 44,
                height: 44,
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
