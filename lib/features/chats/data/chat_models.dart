// ════════════════════════════════════════════════════════════════════
//  Chat models — shared between the Flutter UI and the future backend
// ════════════════════════════════════════════════════════════════════
//  Field names and semantics here match the contract in
//  docs/CHATS_API.md so the backend developer and the Flutter app
//  agree on the wire format. Anything that changes here should be
//  changed in the API doc in the same PR.

enum MessageStatus {
  sending, // optimistic — not yet acknowledged by server
  sent, // single tick — server stored it
  delivered, // double tick — recipient's device received it
  read, // blue ticks — recipient opened the conversation
  failed, // local-only — send retry available
}

MessageStatus _statusFromString(String? s) {
  switch (s) {
    case 'sent':
      return MessageStatus.sent;
    case 'delivered':
      return MessageStatus.delivered;
    case 'read':
      return MessageStatus.read;
    case 'failed':
      return MessageStatus.failed;
    default:
      return MessageStatus.sending;
  }
}

String statusToString(MessageStatus s) {
  switch (s) {
    case MessageStatus.sending:
      return 'sending';
    case MessageStatus.sent:
      return 'sent';
    case MessageStatus.delivered:
      return 'delivered';
    case MessageStatus.read:
      return 'read';
    case MessageStatus.failed:
      return 'failed';
  }
}

/// One chat message. Identified by the server-issued `id`; while the
/// message is still in `MessageStatus.sending` the id is a client-
/// generated UUID that the server will replace on ack.
class ChatMessage {
  final String id;
  final String conversationId;
  /// Sender's email — primary identity in the wire format. May be
  /// empty if the backend only carries `sender_id` / `sender_user_id`
  /// (UUID); use `isMine(...)` to test ownership without depending on
  /// either field being populated.
  final String senderEmail;
  /// Sender's user UUID — secondary identity, used as a fallback when
  /// `senderEmail` is missing or the case differs from the local user.
  final String? senderUserId;
  final String body;
  final DateTime sentAt;
  final MessageStatus status;
  /// Optional reply parent — points at another message id in the
  /// same conversation. Null when this is a top-level message.
  final String? replyToId;

  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderEmail,
    this.senderUserId,
    required this.body,
    required this.sentAt,
    required this.status,
    this.replyToId,
  });

  /// True when this message was sent by the local user. Three lines
  /// of defence so the comparison never silently fails:
  ///   1. Case-exact UUID match against `selfUserId`.
  ///   2. Case-insensitive email match against `selfEmail`.
  ///   3. Peer-elimination: in a 1:1 chat, if the sender's email is
  ///      *not* the peer's email, it has to be the local user.
  ///      This rescues the common dev-backend gotcha where auth
  ///      state momentarily reports an empty email and (1) + (2)
  ///      both come back false despite the message being mine.
  bool isMine({
    String? selfUserId,
    String? selfEmail,
    String? peerEmail,
  }) {
    if (selfUserId != null &&
        selfUserId.isNotEmpty &&
        senderUserId != null &&
        senderUserId!.isNotEmpty &&
        senderUserId == selfUserId) {
      return true;
    }
    if (selfEmail != null &&
        selfEmail.isNotEmpty &&
        senderEmail.isNotEmpty &&
        senderEmail.toLowerCase() == selfEmail.toLowerCase()) {
      return true;
    }
    if (peerEmail != null &&
        peerEmail.isNotEmpty &&
        senderEmail.isNotEmpty &&
        senderEmail.toLowerCase() != peerEmail.toLowerCase()) {
      return true;
    }
    return false;
  }

  ChatMessage copyWith({
    String? id,
    MessageStatus? status,
  }) =>
      ChatMessage(
        id: id ?? this.id,
        conversationId: conversationId,
        senderEmail: senderEmail,
        senderUserId: senderUserId,
        body: body,
        sentAt: sentAt,
        status: status ?? this.status,
        replyToId: replyToId,
      );

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        id: (j['id'] ?? j['_id'] ?? '') as String,
        conversationId:
            (j['conversation_id'] ?? j['conversationId'] ?? '') as String,
        // `sender_email` is the doc-spec key; tolerate `senderEmail`
        // (camelCase) and a missing field — `isMine` falls back to
        // `senderUserId` when email is empty.
        senderEmail:
            (j['sender_email'] ?? j['senderEmail'] ?? '') as String,
        senderUserId: (j['sender_user_id'] ??
                j['senderUserId'] ??
                j['sender_id'] ??
                j['senderId']) as String?,
        body: (j['body'] ?? '') as String,
        sentAt: DateTime.parse(
          (j['sent_at'] ?? j['sentAt'] ?? j['created_at']) as String,
        ).toLocal(),
        status: _statusFromString(j['status'] as String?),
        replyToId: (j['reply_to_id'] ?? j['replyToId']) as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'conversation_id': conversationId,
        'sender_email': senderEmail,
        if (senderUserId != null) 'sender_user_id': senderUserId,
        'body': body,
        'sent_at': sentAt.toUtc().toIso8601String(),
        'status': statusToString(status),
        if (replyToId != null) 'reply_to_id': replyToId,
      };
}

/// One conversation row. For 1:1 chats, `participants` has exactly
/// two emails — the current user's and the peer's. Group chats are
/// not in the v1 spec but the model carries a list so the upgrade
/// is non-breaking.
class Conversation {
  final String id;
  final List<String> participants; // email addresses
  final ChatMessage? lastMessage;
  final int unreadCount;
  final DateTime updatedAt;
  /// Optional display name override (used for groups; for 1:1 we
  /// fall back to the peer's email-derived display name).
  final String? title;

  const Conversation({
    required this.id,
    required this.participants,
    required this.lastMessage,
    required this.unreadCount,
    required this.updatedAt,
    this.title,
  });

  /// The other participant's email in a 1:1 conversation. Comparison
  /// is case-insensitive — backends sometimes normalise email casing
  /// inconsistently between sign-up and the chat participants list.
  String peerOf(String selfEmail) {
    final selfLc = selfEmail.toLowerCase();
    return participants.firstWhere(
      (e) => e.toLowerCase() != selfLc,
      orElse: () => participants.isNotEmpty ? participants.first : '',
    );
  }

  factory Conversation.fromJson(Map<String, dynamic> j) => Conversation(
        id: j['id'] as String,
        participants: (j['participants'] as List).cast<String>(),
        lastMessage: j['last_message'] == null
            ? null
            : ChatMessage.fromJson(
                (j['last_message'] as Map).cast<String, dynamic>()),
        unreadCount: (j['unread_count'] ?? 0) as int,
        updatedAt: DateTime.parse(j['updated_at'] as String).toLocal(),
        title: j['title'] as String?,
      );
}

/// Result row for the "search users by email" endpoint, used on the
/// New Chat screen.
class ChatUser {
  final String email;
  final String? displayName;
  final String? avatarUrl;

  const ChatUser({
    required this.email,
    this.displayName,
    this.avatarUrl,
  });

  /// Best-effort human label: "Alex Wong" when the server gave us a
  /// name, otherwise the local-part of the email ("alex.wong").
  String get label {
    if (displayName != null && displayName!.trim().isNotEmpty) {
      return displayName!.trim();
    }
    final at = email.indexOf('@');
    return at <= 0 ? email : email.substring(0, at);
  }

  factory ChatUser.fromJson(Map<String, dynamic> j) => ChatUser(
        email: j['email'] as String,
        displayName: j['display_name'] as String?,
        avatarUrl: j['avatar_url'] as String?,
      );
}
