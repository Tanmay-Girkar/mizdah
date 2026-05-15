import '../../core/utils/meeting_utils.dart';

class User {
  final String id;
  final String email;
  final String name;
  final String role;
  /// HTTPS URL to the user's profile photo, or null when none is set.
  /// Backend field is `avatar_url`; verified live in the signup
  /// response on the dev server (2026-05-09).
  final String? avatarUrl;
  /// E.164 phone number, e.g. `+919876543210`. Optional because
  /// legacy accounts created before docs/PHONE_AND_CONTACTS_BACKEND.md
  /// shipped don't have one. New signups via the post-2026-05-14
  /// register screen always do.
  final String? phone;
  /// ISO-3166-1 alpha-2 country code (`IN`, `US`, ...) the user
  /// selected when entering the phone number. Stored alongside
  /// `phone` so we can re-validate without re-deriving from the
  /// dialing prefix. Optional, same reasoning as `phone`.
  final String? phoneCountry;

  User({
    required this.id,
    required this.email,
    required this.name,
    this.role = 'USER',
    this.avatarUrl,
    this.phone,
    this.phoneCountry,
  });

  User copyWith({
    String? id,
    String? email,
    String? name,
    String? role,
    String? avatarUrl,
    String? phone,
    String? phoneCountry,
    bool clearAvatar = false,
    bool clearPhone = false,
  }) {
    return User(
      id: id ?? this.id,
      email: email ?? this.email,
      name: name ?? this.name,
      role: role ?? this.role,
      avatarUrl: clearAvatar ? null : (avatarUrl ?? this.avatarUrl),
      phone: clearPhone ? null : (phone ?? this.phone),
      phoneCountry: clearPhone ? null : (phoneCountry ?? this.phoneCountry),
    );
  }

  factory User.fromJson(Map<String, dynamic> json) {
    final rawAvatar = (json['avatar_url'] ?? json['avatarUrl']) as String?;
    final rawPhone = (json['phone'] ?? json['phoneNumber']) as String?;
    final rawPhoneCountry =
        (json['phone_country'] ?? json['phoneCountry']) as String?;
    return User(
      id: json['id'] ?? '',
      email: json['email'] ?? '',
      name: json['name'] ?? '',
      role: json['role'] ?? 'USER',
      avatarUrl: (rawAvatar != null && rawAvatar.trim().isNotEmpty)
          ? rawAvatar
          : null,
      phone: (rawPhone != null && rawPhone.trim().isNotEmpty)
          ? rawPhone
          : null,
      phoneCountry:
          (rawPhoneCountry != null && rawPhoneCountry.trim().isNotEmpty)
              ? rawPhoneCountry.toUpperCase()
              : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'name': name,
      'role': role,
      if (avatarUrl != null) 'avatar_url': avatarUrl,
    };
  }
}

class Contact {
  final String id;
  final String name;
  final String? avatarUrl;
  final String email;

  Contact({
    required this.id,
    required this.name,
    this.avatarUrl,
    required this.email,
  });

  factory Contact.fromJson(Map<String, dynamic> json) {
    return Contact(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      avatarUrl: json['avatarUrl'],
      email: json['email'] ?? '',
    );
  }
}

/// Host-controlled permission flags that gate what non-host
/// participants can do during a live meeting. See
/// docs/ADD_PARTICIPANT_BACKEND.md §2a. Stored as a JSONB blob
/// server-side so adding the next toggle (allowScreenShare,
/// muteOnJoin, lockMeeting, …) is a key-add, not a migration.
///
/// Tolerant `fromJson`: missing keys default to `true` so a
/// pre-feature meeting row (or a server that hasn't included the
/// blob yet) reads as "permissive" rather than locking the room
/// down accidentally.
class MeetingPermissions {
  final bool allowParticipantsToInvite;

  const MeetingPermissions({
    this.allowParticipantsToInvite = true,
  });

  factory MeetingPermissions.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const MeetingPermissions();
    return MeetingPermissions(
      allowParticipantsToInvite: json['allowParticipantsToInvite'] as bool? ??
          json['allow_participants_to_invite'] as bool? ??
          true,
    );
  }

  Map<String, dynamic> toJson() => {
        'allowParticipantsToInvite': allowParticipantsToInvite,
      };

  MeetingPermissions copyWith({bool? allowParticipantsToInvite}) {
    return MeetingPermissions(
      allowParticipantsToInvite:
          allowParticipantsToInvite ?? this.allowParticipantsToInvite,
    );
  }
}

class Meeting {
  final String id;
  final String title;
  final DateTime dateTime;
  final String code;
  final List<String> participants;
  final String? hostId;
  final MeetingPermissions permissions;

  Meeting({
    required this.id,
    required this.title,
    required this.dateTime,
    required this.code,
    required this.participants,
    this.hostId,
    this.permissions = const MeetingPermissions(),
  });

  factory Meeting.fromJson(Map<String, dynamic> json) {
    return Meeting(
      id: json['id']?.toString() ?? json['dbId']?.toString() ?? json['meetingId']?.toString() ?? '',
      title: json['title'] ?? json['meeting_title'] ?? json['meeting_code'] ?? json['code'] ?? json['meetingId'] ?? 'Untitled Meeting',
      dateTime: (DateTime.tryParse(json['created_at'] ?? json['createdAt'] ?? '') ?? DateTime.now()).toLocal(),
      code: MeetingUtils.extractCode((json['meeting_code'] ?? json['code'] ?? json['meetingId'] ?? json['id']?.toString() ?? '').toString()),
      participants: (json['participants'] as List?)?.map((e) => e.toString()).toList() ?? [],
      hostId: json['host_id']?.toString() ?? json['hostId']?.toString() ?? json['creator_id']?.toString(),
      permissions: MeetingPermissions.fromJson(
          json['permissions'] as Map<String, dynamic>?),
    );
  }
}

class CallHistory {
  final String id;
  final String title;
  final DateTime timestamp;
  final Duration duration;
  final bool isMissed;
  final String? meetingCode;
  final String? hostId;

  /// Whether the meeting is currently live (≥1 active participant).
  /// Populated only when the REST payload carries the meeting-level
  /// `is_active` field — see docs/MEETING_PRESENCE_PROTOCOL.md §4.1.
  ///
  /// `null` means **unknown** from REST alone; the
  /// `meetingPresenceProvider` overlay supplies the live value when
  /// the `meeting-updated` socket event arrives. UI should treat
  /// `null` and `false` the same way (render as ended) until the
  /// presence overlay says otherwise.
  final bool? isActive;

  /// Current participant count. Mirrors `meetings.members_count` on
  /// the server. `null` when REST didn't carry it.
  final int? membersCount;

  /// Timestamp the meeting ended. Non-null iff `isActive == false`
  /// per the invariant in protocol §2.
  final DateTime? endedAt;

  CallHistory({
    required this.id,
    required this.title,
    required this.timestamp,
    required this.duration,
    required this.isMissed,
    this.meetingCode,
    this.hostId,
    this.isActive,
    this.membersCount,
    this.endedAt,
  });

  /// Copy with a presence overlay applied. Used by
  /// `recentMeetingsProvider` to merge live socket state into the
  /// REST snapshot without mutating the original.
  CallHistory copyWithPresence({
    bool? isActive,
    int? membersCount,
    DateTime? endedAt,
  }) {
    return CallHistory(
      id: id,
      title: title,
      timestamp: timestamp,
      duration: duration,
      isMissed: isMissed,
      meetingCode: meetingCode,
      hostId: hostId,
      isActive: isActive ?? this.isActive,
      membersCount: membersCount ?? this.membersCount,
      endedAt: endedAt ?? this.endedAt,
    );
  }

  factory CallHistory.fromJson(Map<String, dynamic> json) {
    String title = json['meeting_title'] ?? json['title'] ?? '';
    
    // Check nested meeting object
    if (title.isEmpty && json['meeting'] != null && json['meeting'] is Map) {
      title = json['meeting']['title'] ?? json['meeting']['meeting_title'] ?? '';
    }

    // Fallback to code/ID if title is still empty
    if (title.isEmpty) {
      final code = json['meeting_code'] ?? json['meetingCode'] ?? json['meeting_id'] ?? json['meetingId'] ?? json['id'] ?? '';
      title = code.toString();
    }

    // Clean up if title looks like a URL or a long system string
    if (title.contains('http') || title.length > 20) {
      // Try to extract code from URL
      try {
        final uri = Uri.tryParse(title);
        if (uri != null && uri.pathSegments.isNotEmpty) {
          title = 'Meeting: ${uri.pathSegments.last}';
        } else if (title.contains('meeting')) {
          // Handle concatenated strings like in the screenshot
          final parts = title.split('meeting');
          if (parts.length > 1 && parts.last.isNotEmpty) {
            title = 'Meeting: ${parts.last}';
          }
        }
      } catch (_) {}
      
      // If still looks like a URL/concatenated string without slashes
      if (title.startsWith('http') && !title.contains(':')) {
         // It's the weird string from the screenshot
         final possibleCode = title.replaceAll(RegExp(r'^https?mizdah[a-z]+cloudmeeting'), '');
         if (possibleCode.length > 3) {
           title = 'Meeting: $possibleCode';
         }
      }
    }

    if (title.isEmpty || title == 'null') title = 'Past Meeting';

    final meetingCode = (json['meeting_code'] ?? json['meetingCode'] ?? json['meeting_id'] ?? json['meetingId'] ?? json['id']?.toString() ?? '').toString().replaceAll('-', '');
    final hostId = json['host_id']?.toString() ?? json['hostId']?.toString() ?? json['creator_id']?.toString();

    // Live-state fields from protocol §4.1. All three are null on
    // payloads from the legacy `/api/participant/user/:userId`
    // endpoint (raw participation rows don't carry meeting-level
    // state) — they're only set when this row came from
    // `/api/meetings/user/:userId` or `/api/meeting/:code`, both of
    // which include the meeting's live state. The socket overlay
    // (`meetingPresenceProvider`) fills the gap for participation
    // rows. Accept both snake_case and camelCase to match every
    // other field in this model.
    bool? isActive;
    final rawIsActive = json['is_active'] ?? json['isActive'];
    if (rawIsActive is bool) {
      isActive = rawIsActive;
    } else if (rawIsActive is String) {
      final v = rawIsActive.toLowerCase();
      if (v == 'true') isActive = true;
      if (v == 'false') isActive = false;
    }

    int? membersCount;
    final rawMembers = json['members_count'] ?? json['membersCount'];
    if (rawMembers is num) membersCount = rawMembers.toInt();
    if (rawMembers is String) membersCount = int.tryParse(rawMembers);

    DateTime? endedAt;
    final rawEnded = json['ended_at'] ?? json['endedAt'];
    if (rawEnded is String && rawEnded.isNotEmpty) {
      endedAt = DateTime.tryParse(rawEnded)?.toLocal();
    }

    return CallHistory(
      id: json['meeting_id']?.toString() ?? json['meetingId']?.toString() ?? json['id']?.toString() ?? '',
      title: title,
      timestamp: (DateTime.tryParse(json['joined_at'] ?? json['joinedAt'] ?? json['createdAt'] ?? json['created_at'] ?? '') ?? DateTime.now()).toLocal(),
      duration: json['duration'] != null ? Duration(seconds: int.tryParse(json['duration'].toString()) ?? 0) : Duration.zero,
      isMissed: false,
      meetingCode: meetingCode,
      hostId: hostId,
      isActive: isActive,
      membersCount: membersCount,
      endedAt: endedAt,
    );
  }
}

class NotificationModel {
  final String id;
  final String title;
  final String body;
  final String type;
  final DateTime createdAt;
  final bool isRead;
  final DateTime? readAt;
  /// Structured payload for deep-linking the row tap. Shape varies
  /// by `type` — see docs/NOTIFICATIONS_BACKEND.md §3 for the per-
  /// type contract (e.g. `meetingId` + `meetingCode` for
  /// meeting_invite, `callerId` + `callType` for missed_call, …).
  /// Plain map so callers can pull whichever keys they need
  /// without paying for a strongly-typed sealed-class hierarchy.
  final Map<String, dynamic> data;

  NotificationModel({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.createdAt,
    this.isRead = false,
    this.readAt,
    this.data = const {},
  });

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    final rawData = json['data'];
    return NotificationModel(
      id: json['id']?.toString() ?? '',
      title: json['title'] ?? 'Notification',
      body: json['content'] ?? json['body'] ?? '',
      type: json['type'] ?? 'info',
      createdAt:
          (DateTime.tryParse(json['createdAt'] ?? json['created_at'] ?? '') ??
                  DateTime.now())
              .toLocal(),
      isRead: json['isRead'] ?? json['is_read'] ?? false,
      readAt: DateTime.tryParse(
              (json['readAt'] ?? json['read_at'] ?? '').toString())
          ?.toLocal(),
      data: rawData is Map ? Map<String, dynamic>.from(rawData) : const {},
    );
  }
}

/// One page of notifications — what GET /api/notifications/user/:id
/// returns wrapped. Carries the unread count alongside the rows so
/// the bell badge doesn't need a second round-trip to /unread-count
/// for the common "user opened home" path.
///
/// `nextCursor` is the `created_at` of the oldest row in `items` —
/// pass it back as `?before=<cursor>` to fetch the next page. Null
/// when the server has no more rows.
class NotificationsPage {
  final List<NotificationModel> items;
  final String? nextCursor;
  final int unreadCount;

  const NotificationsPage({
    required this.items,
    this.nextCursor,
    this.unreadCount = 0,
  });

  /// Tolerates three response shapes for backwards compatibility:
  ///
  ///   1. `{ "data": [...], "nextCursor": "...", "unreadCount": N }`
  ///      — the canonical shape per docs/NOTIFICATIONS_BACKEND.md §4.1
  ///   2. `{ "data": [...] }`                — older server build
  ///   3. `[ ... ]`                          — bare-array legacy
  ///
  /// `unreadCount` falls back to "count items where !isRead" when
  /// the server didn't include it, so callers always have a number
  /// they can render.
  factory NotificationsPage.fromAny(dynamic raw) {
    List<dynamic> rows;
    String? next;
    int? count;

    if (raw is List) {
      rows = raw;
    } else if (raw is Map) {
      final maybeRows = raw['data'];
      rows = maybeRows is List ? maybeRows : const [];
      final c = raw['nextCursor'] ?? raw['next_cursor'];
      next = c is String ? c : null;
      final u = raw['unreadCount'] ?? raw['unread_count'];
      count = u is int ? u : (u is num ? u.toInt() : null);
    } else {
      rows = const [];
    }

    final items = rows
        .whereType<Map>()
        .map((m) => NotificationModel.fromJson(Map<String, dynamic>.from(m)))
        .toList();

    return NotificationsPage(
      items: items,
      nextCursor: next,
      unreadCount: count ?? items.where((n) => !n.isRead).length,
    );
  }
}
