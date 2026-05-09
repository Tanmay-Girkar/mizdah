// ════════════════════════════════════════════════════════════════════
//  ChatRepository — single point of contact between UI and chat data
// ════════════════════════════════════════════════════════════════════
//  The default `MockChatRepository` returns deterministic in-memory
//  data so the screens are demoable today. When the backend lands
//  per docs/CHATS_API.md, swap the provider to a real implementation
//  (REST + WebSocket) without touching any UI file.

import 'dart:async';
import 'dart:math';

import 'chat_models.dart';

abstract class ChatRepository {
  /// Streams the conversation list for the current user. Emits a
  /// fresh snapshot whenever any conversation's last_message,
  /// unread_count or updated_at changes.
  Stream<List<Conversation>> watchConversations();

  /// One-shot fetch of the message thread, oldest first. Pagination
  /// is reverse-cursor: pass the oldest known message id as `before`.
  Future<List<ChatMessage>> fetchMessages({
    required String conversationId,
    String? before,
    int limit = 50,
  });

  /// Streams new messages and status updates for an open conversation
  /// — driven by the WebSocket. Already-loaded history comes from
  /// `fetchMessages`; this stream is for live deltas only.
  Stream<ChatMessage> watchMessages(String conversationId);

  /// Sends a message. Returns the optimistic message with status
  /// `sending`; once the server acks, the same id is re-emitted on
  /// `watchMessages` with status `sent`.
  Future<ChatMessage> sendMessage({
    required String conversationId,
    required String body,
    String? replyToId,
  });

  /// Mark all unread messages in a conversation as read. Server
  /// pushes a status update to the sender on the WebSocket.
  Future<void> markRead(String conversationId);

  /// Send a typing-indicator ping. The backend rebroadcasts to the
  /// peer for ~5 seconds (no explicit "stopped typing" needed).
  void sendTyping(String conversationId);

  /// Stream of `email is typing in conversationId` pings. Each
  /// emission is a (conversationId, senderEmail) tuple — UI fades the
  /// hint after 5s if no fresh ping arrives.
  Stream<({String conversationId, String senderEmail})> watchTyping();

  /// Search registered users by email prefix or display name.
  Future<List<ChatUser>> searchUsers(String query);

  /// Open or create a 1:1 conversation with `peerEmail`. Backend
  /// upserts so calling twice is idempotent.
  Future<Conversation> openConversationWith(String peerEmail);
}

// ════════════════════════════════════════════════════════════════════
//  MockChatRepository — deterministic fake data for the UI demo
// ════════════════════════════════════════════════════════════════════
//  Generates a handful of fake conversations seeded against a list
//  of made-up gmail addresses and pretends to receive replies after
//  a short delay so the optimistic-send animation can play.

class MockChatRepository implements ChatRepository {
  MockChatRepository(this._selfEmail);

  final String _selfEmail;
  final _rng = Random(42);

  late final List<Conversation> _conversations = _seedConversations();
  final Map<String, List<ChatMessage>> _threads = {};

  final _conversationsCtrl =
      StreamController<List<Conversation>>.broadcast();
  final _messagesCtrl = StreamController<ChatMessage>.broadcast();
  final _typingCtrl =
      StreamController<({String conversationId, String senderEmail})>.broadcast();

  bool _seeded = false;

  List<Conversation> _seedConversations() {
    final now = DateTime.now();
    final peers = const [
      ('alex.wong@gmail.com', 'Alex Wong'),
      ('priya.sharma@gmail.com', 'Priya Sharma'),
      ('marcus.lee@gmail.com', 'Marcus Lee'),
      ('jasmine.patel@gmail.com', 'Jasmine Patel'),
      ('nikhil.rao@gmail.com', 'Nikhil Rao'),
      ('emma.fischer@gmail.com', 'Emma Fischer'),
      ('liu.wei@gmail.com', 'Liu Wei'),
    ];
    final list = <Conversation>[];
    for (var i = 0; i < peers.length; i++) {
      final (email, name) = peers[i];
      final convId = 'conv_$i';
      final lastBody = const [
        'Did you push the build?',
        'Sounds good — talk in 10',
        'Sharing the deck after lunch 🎯',
        'Got it, thanks!',
        'Can we move the meeting to 4?',
        'Yep, on it',
        'Just sent the link',
      ][i];
      final last = ChatMessage(
        id: 'msg_${convId}_seed',
        conversationId: convId,
        senderEmail: i.isEven ? email : _selfEmail,
        body: lastBody,
        sentAt: now.subtract(Duration(minutes: 3 + i * 47)),
        status: i.isEven ? MessageStatus.delivered : MessageStatus.read,
      );
      list.add(Conversation(
        id: convId,
        participants: [_selfEmail, email],
        lastMessage: last,
        unreadCount: i == 0 ? 2 : (i == 2 ? 1 : 0),
        updatedAt: last.sentAt,
        title: name,
      ));
      _threads[convId] = _seedThread(convId, email, name);
    }
    list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  List<ChatMessage> _seedThread(String convId, String peerEmail, String name) {
    final now = DateTime.now();
    final base = now.subtract(const Duration(hours: 6));
    final lines = [
      (peerEmail, 'Hey! Free for a quick call?'),
      (_selfEmail, 'Yep — give me 5 min'),
      (peerEmail, 'No rush, ping when ready'),
      (_selfEmail, 'Ready, sending the link now'),
      (peerEmail, 'Got it 👍'),
    ];
    return [
      for (var i = 0; i < lines.length; i++)
        ChatMessage(
          id: 'msg_${convId}_$i',
          conversationId: convId,
          senderEmail: lines[i].$1,
          body: lines[i].$2,
          sentAt: base.add(Duration(minutes: i * 4)),
          status: lines[i].$1 == _selfEmail
              ? MessageStatus.read
              : MessageStatus.delivered,
        ),
    ];
  }

  void _emitConversations() {
    _conversationsCtrl.add(List.unmodifiable(_conversations));
  }

  @override
  Stream<List<Conversation>> watchConversations() async* {
    if (!_seeded) {
      _seeded = true;
      // First snapshot needs to be available to the first listener.
      scheduleMicrotask(_emitConversations);
    }
    yield List.unmodifiable(_conversations);
    yield* _conversationsCtrl.stream;
  }

  @override
  Future<List<ChatMessage>> fetchMessages({
    required String conversationId,
    String? before,
    int limit = 50,
  }) async {
    await Future.delayed(const Duration(milliseconds: 120));
    final all = _threads[conversationId] ?? const <ChatMessage>[];
    if (before == null) return List.of(all);
    final cutoff = all.indexWhere((m) => m.id == before);
    if (cutoff <= 0) return const [];
    final from = (cutoff - limit).clamp(0, cutoff);
    return all.sublist(from, cutoff);
  }

  @override
  Stream<ChatMessage> watchMessages(String conversationId) =>
      _messagesCtrl.stream.where((m) => m.conversationId == conversationId);

  @override
  Future<ChatMessage> sendMessage({
    required String conversationId,
    required String body,
    String? replyToId,
  }) async {
    final tempId = 'tmp_${DateTime.now().microsecondsSinceEpoch}';
    final optimistic = ChatMessage(
      id: tempId,
      conversationId: conversationId,
      senderEmail: _selfEmail,
      body: body,
      sentAt: DateTime.now(),
      status: MessageStatus.sending,
      replyToId: replyToId,
    );
    _threads.putIfAbsent(conversationId, () => []).add(optimistic);

    // Simulate server ack ~250ms later, then a fake reply ~1.4s later.
    Future.delayed(const Duration(milliseconds: 250), () {
      final ackId = 'msg_${DateTime.now().microsecondsSinceEpoch}';
      final acked = optimistic.copyWith(
        id: ackId,
        status: MessageStatus.sent,
      );
      final list = _threads[conversationId];
      if (list != null) {
        final i = list.indexWhere((m) => m.id == tempId);
        if (i >= 0) list[i] = acked;
      }
      _messagesCtrl.add(acked);
      _bumpConversation(conversationId, acked);
    });
    Future.delayed(const Duration(milliseconds: 1400), () {
      final conv = _conversations.firstWhere(
        (c) => c.id == conversationId,
        orElse: () => Conversation(
          id: conversationId,
          participants: const [],
          lastMessage: null,
          unreadCount: 0,
          updatedAt: DateTime.now(),
        ),
      );
      final peer = conv.peerOf(_selfEmail);
      if (peer.isEmpty) return;
      final replies = const ['Got it', 'On it 👍', 'Cool', 'Sounds good'];
      final reply = ChatMessage(
        id: 'msg_${DateTime.now().microsecondsSinceEpoch}_r',
        conversationId: conversationId,
        senderEmail: peer,
        body: replies[_rng.nextInt(replies.length)],
        sentAt: DateTime.now(),
        status: MessageStatus.delivered,
      );
      _threads.putIfAbsent(conversationId, () => []).add(reply);
      _messagesCtrl.add(reply);
      _bumpConversation(conversationId, reply);
    });

    return optimistic;
  }

  void _bumpConversation(String conversationId, ChatMessage last) {
    final i = _conversations.indexWhere((c) => c.id == conversationId);
    if (i < 0) return;
    final old = _conversations[i];
    final newUnread = last.senderEmail == _selfEmail
        ? old.unreadCount
        : old.unreadCount + 1;
    _conversations[i] = Conversation(
      id: old.id,
      participants: old.participants,
      lastMessage: last,
      unreadCount: newUnread,
      updatedAt: last.sentAt,
      title: old.title,
    );
    _conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    _emitConversations();
  }

  @override
  Future<void> markRead(String conversationId) async {
    final i = _conversations.indexWhere((c) => c.id == conversationId);
    if (i < 0) return;
    final old = _conversations[i];
    if (old.unreadCount == 0) return;
    _conversations[i] = Conversation(
      id: old.id,
      participants: old.participants,
      lastMessage: old.lastMessage,
      unreadCount: 0,
      updatedAt: old.updatedAt,
      title: old.title,
    );
    _emitConversations();
  }

  @override
  void sendTyping(String conversationId) {
    // No-op in mock; a real impl would emit on the WebSocket.
  }

  @override
  Stream<({String conversationId, String senderEmail})> watchTyping() =>
      _typingCtrl.stream;

  @override
  Future<List<ChatUser>> searchUsers(String query) async {
    await Future.delayed(const Duration(milliseconds: 200));
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final pool = const [
      ChatUser(email: 'alex.wong@gmail.com', displayName: 'Alex Wong'),
      ChatUser(email: 'priya.sharma@gmail.com', displayName: 'Priya Sharma'),
      ChatUser(email: 'marcus.lee@gmail.com', displayName: 'Marcus Lee'),
      ChatUser(email: 'jasmine.patel@gmail.com', displayName: 'Jasmine Patel'),
      ChatUser(email: 'nikhil.rao@gmail.com', displayName: 'Nikhil Rao'),
      ChatUser(email: 'emma.fischer@gmail.com', displayName: 'Emma Fischer'),
      ChatUser(email: 'liu.wei@gmail.com', displayName: 'Liu Wei'),
      ChatUser(email: 'sara.davis@gmail.com', displayName: 'Sara Davis'),
      ChatUser(email: 'tom.becker@gmail.com', displayName: 'Tom Becker'),
    ];
    return pool
        .where((u) =>
            u.email.toLowerCase().contains(q) ||
            (u.displayName ?? '').toLowerCase().contains(q))
        .toList();
  }

  @override
  Future<Conversation> openConversationWith(String peerEmail) async {
    await Future.delayed(const Duration(milliseconds: 80));
    final existing = _conversations.firstWhere(
      (c) => c.participants.contains(peerEmail),
      orElse: () => Conversation(
        id: '',
        participants: const [],
        lastMessage: null,
        unreadCount: 0,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
      ),
    );
    if (existing.id.isNotEmpty) return existing;
    final convId = 'conv_${DateTime.now().microsecondsSinceEpoch}';
    final fresh = Conversation(
      id: convId,
      participants: [_selfEmail, peerEmail],
      lastMessage: null,
      unreadCount: 0,
      updatedAt: DateTime.now(),
      title: peerEmail.split('@').first,
    );
    _conversations.insert(0, fresh);
    _threads[convId] = [];
    _emitConversations();
    return fresh;
  }

}
