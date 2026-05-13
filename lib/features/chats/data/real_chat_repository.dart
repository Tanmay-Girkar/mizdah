// ════════════════════════════════════════════════════════════════════
//  RealChatRepository — REST + WebSocket impl for the chat backend
// ════════════════════════════════════════════════════════════════════
//  Implements the contract in docs/CHATS_API.md against the live dev
//  gateway at https://192.168.1.100:3001. REST is the source of
//  truth; the `/chats` socket.io namespace pushes deltas
//  (chat:message, chat:status, chat:read, chat:typing) so the list
//  and threads stay live without polling.
//
//  Sockets are best-effort — if the connection drops or the namespace
//  isn't mounted, the app still works via REST (no live updates,
//  user can pull-to-refresh / re-open the screen).

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../../../core/config/api_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/services/storage_service.dart';
import 'chat_models.dart';
import 'chat_repository.dart';

class RealChatRepository implements ChatRepository {
  RealChatRepository({required String selfEmail, String? selfUserId})
      : _selfEmail = selfEmail,
        _selfUserId = selfUserId,
        _api = ApiClient();

  final String _selfEmail;
  final String? _selfUserId;
  final ApiClient _api;

  final List<Conversation> _conversationsCache = [];
  final _conversationsCtrl =
      StreamController<List<Conversation>>.broadcast();
  final _messagesCtrl = StreamController<ChatMessage>.broadcast();
  final _typingCtrl = StreamController<
      ({String conversationId, String senderEmail})>.broadcast();

  io.Socket? _socket;
  bool _socketConnecting = false;
  bool _conversationsInitialised = false;
  /// Cursor for `chat:resume` — set on every event we observe so the
  /// next reconnect can request only the diff.
  DateTime? _lastEventAt;
  /// Conversation ids the UI currently has open. We re-emit
  /// `chat:focus` for each on every (re)connect so the server knows
  /// to send `delivered` immediately for inbound messages.
  final Set<String> _focusedConversations = {};

  // ── REST helpers ────────────────────────────────────────────────

  Future<void> _refreshConversations() async {
    try {
      final r = await _api.get('/api/chats/conversations');
      final raw = r.data;
      final list = <Conversation>[];
      if (raw is Map && raw['conversations'] is List) {
        for (final j in (raw['conversations'] as List)) {
          if (j is Map) {
            list.add(Conversation.fromJson(
                Map<String, dynamic>.from(j)));
          }
        }
      }
      list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      _conversationsCache
        ..clear()
        ..addAll(list);
      _conversationsCtrl.add(List.unmodifiable(_conversationsCache));
    } catch (e) {
      debugPrint('[chats] refreshConversations failed: $e');
    }
  }

  void _upsertConversationFromMessage(ChatMessage m) {
    final i = _conversationsCache.indexWhere((c) => c.id == m.conversationId);
    if (i < 0) {
      // New conversation we hadn't loaded — refresh whole list. The
      // server has the canonical title + participants for it.
      _refreshConversations();
      return;
    }
    final old = _conversationsCache[i];
    final fromMe = m.isMine(selfUserId: _selfUserId, selfEmail: _selfEmail);
    _conversationsCache[i] = Conversation(
      id: old.id,
      participants: old.participants,
      lastMessage: m,
      unreadCount: fromMe ? old.unreadCount : old.unreadCount + 1,
      updatedAt: m.sentAt,
      title: old.title,
    );
    _conversationsCache.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    _conversationsCtrl.add(List.unmodifiable(_conversationsCache));
  }

  // ── Socket lifecycle ────────────────────────────────────────────

  Future<void> _ensureSocket() async {
    if (_socket?.connected == true || _socketConnecting) return;
    _socketConnecting = true;
    try {
      final token = await StorageService.getToken();
      if (token == null) {
        debugPrint('[chats] no JWT — skipping socket');
        return;
      }
      // ── Engine.io connection contract ───────────────────────────
      // Per docs/CHATS_API.md §3 the `/chats` namespace lives on the
      // SAME socket.io server that hosts meeting signaling — so the
      // engine.io mount path is `ApiConfig.chatSocketPath` (currently
      // aliased to `signalingPath = /signaling-fresh`). Connecting
      // without an explicit `path:` falls back to the default
      // `/socket.io/` mount which doesn't exist on the dev backend,
      // so the socket would silently fail to attach and inbound
      // `chat:message` deltas never arrive — recipients only see
      // new messages after the 4s REST poll fallback. Hence the
      // explicit `path` option here, mirroring p2p_call_service /
      // meeting_provider's signaling socket setup.
      //
      // The namespace is set by appending `/chats` to the URL; the
      // engine.io path is set via the separate `path` option. These
      // are independent — namespace is the multiplexing label on
      // top of the engine.io transport.
      final url = '${ApiConfig.chatSocketUrl}/chats';
      debugPrint('[chats] opening socket → '
          '$url (path=${ApiConfig.chatSocketPath})');
      final socket = io.io(url, <String, dynamic>{
        'path': ApiConfig.chatSocketPath,
        'transports': ['websocket', 'polling'],
        'autoConnect': false,
        'forceNew': true,
        'reconnection': true,
        'reconnectionAttempts': 10,
        'reconnectionDelay': 2000,
        // Pass JWT via both `auth` payload (preferred per the doc)
        // AND `?token=` query string — some socket.io middleware
        // only reads one or the other. Belt and braces, no harm.
        'auth': {'token': token},
        'query': {'token': token},
      });
      _socket = socket;

      socket.onConnect((_) {
        debugPrint('[chats] ✅ socket connected sid=${socket.id}');
        // Re-establish "currently viewing" state on every (re)connect
        // so the server emits `delivered` for inbound messages even
        // after a brief disconnect.
        for (final convId in _focusedConversations) {
          socket.emit('chat:focus', {'conversation_id': convId});
        }
        if (_lastEventAt != null) {
          socket.emit('chat:resume', {
            'since': _lastEventAt!.toUtc().toIso8601String(),
          });
        }
      });
      socket.onConnectError((e) =>
          debugPrint('[chats] socket connect_error: $e'));
      socket.onDisconnect((_) =>
          debugPrint('[chats] socket disconnected'));
      socket.onError((e) => debugPrint('[chats] socket error: $e'));

      socket.on('chat:message', (data) {
        final j = _asMap(data?['message'] ?? data);
        if (j == null) return;
        try {
          final m = ChatMessage.fromJson(j);
          _lastEventAt = m.sentAt;
          _messagesCtrl.add(m);
          _upsertConversationFromMessage(m);
        } catch (e) {
          debugPrint('[chats] bad chat:message payload: $e');
        }
      });

      socket.on('chat:status', (data) {
        final j = _asMap(data);
        if (j == null) return;
        // Surface as a delta so UI can flip ticks. We synthesize a
        // ChatMessage with only id + status set; the UI's _applyDelta
        // matches by id and updates the existing row in place.
        final id = j['message_id'] as String?;
        final convId = j['conversation_id'] as String?;
        final status = j['status'] as String?;
        if (id == null || convId == null || status == null) return;
        // Find an existing message in any open thread — the deltas
        // listener picks it up by id and the UI updates the bubble.
        // We don't have direct access to the local thread cache, so
        // we publish a synthetic message; the UI is robust to it.
        final synthetic = ChatMessage.fromJson({
          'id': id,
          'conversation_id': convId,
          'sender_email': _selfEmail, // own message
          'body': '',
          'sent_at': DateTime.now().toUtc().toIso8601String(),
          'status': status,
        });
        _messagesCtrl.add(synthetic);
        _lastEventAt = DateTime.now();
      });

      socket.on('chat:read', (data) {
        // The peer read our messages — flip ticks via the UI's own
        // "the message id ≤ this one" rule. The deltas stream is the
        // hook; UI picks up via _applyDelta.
        final j = _asMap(data);
        if (j == null) return;
        // No-op at the repo level beyond keeping cursor fresh — UI
        // refreshes status via chat:status events for individual
        // messages. Backend emits per-message chat:status updates
        // when read receipts come in, so this listener is just for
        // logs / future "X read your message" UX.
        debugPrint('[chats] chat:read: $j');
        _lastEventAt = DateTime.now();
      });

      socket.on('chat:typing', (data) {
        final j = _asMap(data);
        if (j == null) return;
        final convId = j['conversation_id'] as String?;
        final sender = j['sender_email'] as String?;
        if (convId == null || sender == null) return;
        _typingCtrl.add((conversationId: convId, senderEmail: sender));
      });

      socket.connect();
    } finally {
      _socketConnecting = false;
    }
  }

  Map<String, dynamic>? _asMap(Object? raw) {
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return null;
  }

  // ── ChatRepository contract ─────────────────────────────────────

  @override
  Stream<List<Conversation>> watchConversations() async* {
    if (!_conversationsInitialised) {
      _conversationsInitialised = true;
      // First emission comes from the REST fetch; sockets only push
      // deltas once we already have a baseline cached.
      await _refreshConversations();
      // Spin up the socket lazily once someone is watching the chat
      // surface — no point holding it open if the user never visits
      // the Chats tab in this session.
      // ignore: discarded_futures
      _ensureSocket();
    } else {
      _conversationsCtrl.add(List.unmodifiable(_conversationsCache));
    }
    yield List.unmodifiable(_conversationsCache);
    yield* _conversationsCtrl.stream;
  }

  @override
  Future<List<ChatMessage>> fetchMessages({
    required String conversationId,
    String? before,
    int limit = 50,
  }) async {
    final r = await _api.get(
      '/api/chats/conversations/$conversationId/messages',
      queryParameters: {
        if (before != null) 'before': before,
        'limit': limit,
      },
    );
    final raw = r.data;
    final out = <ChatMessage>[];
    if (raw is Map && raw['messages'] is List) {
      for (final j in (raw['messages'] as List)) {
        if (j is Map) {
          out.add(ChatMessage.fromJson(Map<String, dynamic>.from(j)));
        }
      }
    }
    if (out.isNotEmpty) _lastEventAt = out.last.sentAt;
    return out;
  }

  @override
  Stream<ChatMessage> watchMessages(String conversationId) {
    // Spin the socket up if the user opens a thread directly without
    // first hitting the list (deep link / push tap).
    // ignore: discarded_futures
    _ensureSocket();
    return _messagesCtrl.stream
        .where((m) => m.conversationId == conversationId);
  }

  @override
  Future<ChatMessage> sendMessage({
    required String conversationId,
    required String body,
    String? replyToId,
  }) async {
    final clientId = 'tmp_${DateTime.now().microsecondsSinceEpoch}';
    final r = await _api.post(
      '/api/chats/conversations/$conversationId/messages',
      data: {
        'client_id': clientId,
        'body': body,
        if (replyToId != null) 'reply_to_id': replyToId,
      },
    );
    final raw = r.data;
    if (raw is Map && raw['message'] is Map) {
      final m = ChatMessage.fromJson(
          Map<String, dynamic>.from(raw['message'] as Map));
      _lastEventAt = m.sentAt;
      _upsertConversationFromMessage(m);
      return m;
    }
    // Server returned an unexpected shape — fall back to an
    // optimistic-style entry so the UI still renders immediately.
    return ChatMessage(
      id: clientId,
      conversationId: conversationId,
      senderEmail: _selfEmail,
      senderUserId: _selfUserId,
      body: body,
      sentAt: DateTime.now(),
      status: MessageStatus.sent,
      replyToId: replyToId,
    );
  }

  @override
  Future<void> markRead(String conversationId) async {
    try {
      await _api.post(
        '/api/chats/conversations/$conversationId/read',
        data: const <String, dynamic>{},
      );
      // Optimistically reset the local unread counter for this conv.
      final i =
          _conversationsCache.indexWhere((c) => c.id == conversationId);
      if (i >= 0 && _conversationsCache[i].unreadCount > 0) {
        final old = _conversationsCache[i];
        _conversationsCache[i] = Conversation(
          id: old.id,
          participants: old.participants,
          lastMessage: old.lastMessage,
          unreadCount: 0,
          updatedAt: old.updatedAt,
          title: old.title,
        );
        _conversationsCtrl.add(List.unmodifiable(_conversationsCache));
      }
    } catch (e) {
      debugPrint('[chats] markRead failed: $e');
    }
  }

  @override
  void sendTyping(String conversationId) {
    final s = _socket;
    if (s == null || !s.connected) return;
    s.emit('chat:typing', {'conversation_id': conversationId});
  }

  @override
  void focusConversation(String conversationId) {
    _focusedConversations.add(conversationId);
    final s = _socket;
    if (s != null && s.connected) {
      s.emit('chat:focus', {'conversation_id': conversationId});
    }
    // Make sure the socket is up — opening a thread via deep link
    // (push tap) can land us here before the conversations list ever
    // mounted, in which case _ensureSocket hasn't been kicked yet.
    // ignore: discarded_futures
    _ensureSocket();
  }

  @override
  void blurConversation(String conversationId) {
    _focusedConversations.remove(conversationId);
    final s = _socket;
    if (s != null && s.connected) {
      s.emit('chat:blur', {'conversation_id': conversationId});
    }
  }

  @override
  Future<void> refreshConversations() => _refreshConversations();

  @override
  Stream<({String conversationId, String senderEmail})> watchTyping() =>
      _typingCtrl.stream;

  @override
  Future<List<ChatUser>> searchUsers(String query) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    try {
      final r = await _api.get(
        '/api/chats/users/search',
        queryParameters: {'q': q, 'limit': 10},
      );
      final raw = r.data;
      final out = <ChatUser>[];
      if (raw is Map && raw['users'] is List) {
        for (final j in (raw['users'] as List)) {
          if (j is Map) {
            out.add(ChatUser.fromJson(Map<String, dynamic>.from(j)));
          }
        }
      }
      return out;
    } catch (e) {
      debugPrint('[chats] searchUsers failed: $e');
      return const [];
    }
  }

  @override
  Future<Conversation> openConversationWith(String peerEmail) async {
    final r = await _api.post(
      '/api/chats/conversations',
      data: {'peer_email': peerEmail},
    );
    final raw = r.data;
    Map<String, dynamic>? convJson;
    if (raw is Map) {
      // Allow either `{conversation: {...}}` or a bare `{id, ...}`.
      if (raw['conversation'] is Map) {
        convJson = Map<String, dynamic>.from(raw['conversation'] as Map);
      } else if (raw['id'] is String) {
        convJson = Map<String, dynamic>.from(raw);
      }
    }
    if (convJson == null) {
      throw Exception('openConversation: unexpected response shape');
    }
    final conv = Conversation.fromJson(convJson);
    final i = _conversationsCache.indexWhere((c) => c.id == conv.id);
    if (i < 0) {
      _conversationsCache.insert(0, conv);
    } else {
      _conversationsCache[i] = conv;
    }
    _conversationsCtrl.add(List.unmodifiable(_conversationsCache));
    return conv;
  }
}
