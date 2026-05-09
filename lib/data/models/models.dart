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

  User({
    required this.id,
    required this.email,
    required this.name,
    this.role = 'USER',
    this.avatarUrl,
  });

  User copyWith({
    String? id,
    String? email,
    String? name,
    String? role,
    String? avatarUrl,
    bool clearAvatar = false,
  }) {
    return User(
      id: id ?? this.id,
      email: email ?? this.email,
      name: name ?? this.name,
      role: role ?? this.role,
      avatarUrl: clearAvatar ? null : (avatarUrl ?? this.avatarUrl),
    );
  }

  factory User.fromJson(Map<String, dynamic> json) {
    final rawAvatar = (json['avatar_url'] ?? json['avatarUrl']) as String?;
    return User(
      id: json['id'] ?? '',
      email: json['email'] ?? '',
      name: json['name'] ?? '',
      role: json['role'] ?? 'USER',
      avatarUrl: (rawAvatar != null && rawAvatar.trim().isNotEmpty)
          ? rawAvatar
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

class Meeting {
  final String id;
  final String title;
  final DateTime dateTime;
  final String code;
  final List<String> participants;
  final String? hostId;

  Meeting({
    required this.id,
    required this.title,
    required this.dateTime,
    required this.code,
    required this.participants,
    this.hostId,
  });

  factory Meeting.fromJson(Map<String, dynamic> json) {
    return Meeting(
      id: json['id']?.toString() ?? json['dbId']?.toString() ?? json['meetingId']?.toString() ?? '',
      title: json['title'] ?? json['meeting_title'] ?? json['meeting_code'] ?? json['code'] ?? json['meetingId'] ?? 'Untitled Meeting',
      dateTime: (DateTime.tryParse(json['created_at'] ?? json['createdAt'] ?? '') ?? DateTime.now()).toLocal(),
      code: MeetingUtils.extractCode((json['meeting_code'] ?? json['code'] ?? json['meetingId'] ?? json['id']?.toString() ?? '').toString()),
      participants: (json['participants'] as List?)?.map((e) => e.toString()).toList() ?? [],
      hostId: json['host_id']?.toString() ?? json['hostId']?.toString() ?? json['creator_id']?.toString(),
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

  CallHistory({
    required this.id,
    required this.title,
    required this.timestamp,
    required this.duration,
    required this.isMissed,
    this.meetingCode,
    this.hostId,
  });

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

    return CallHistory(
      id: json['meeting_id']?.toString() ?? json['meetingId']?.toString() ?? json['id']?.toString() ?? '',
      title: title,
      timestamp: (DateTime.tryParse(json['joined_at'] ?? json['joinedAt'] ?? json['createdAt'] ?? json['created_at'] ?? '') ?? DateTime.now()).toLocal(),
      duration: json['duration'] != null ? Duration(seconds: int.tryParse(json['duration'].toString()) ?? 0) : Duration.zero,
      isMissed: false,
      meetingCode: meetingCode,
      hostId: hostId,
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

  NotificationModel({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.createdAt,
    this.isRead = false,
  });

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    return NotificationModel(
      id: json['id']?.toString() ?? '',
      title: json['title'] ?? 'Notification',
      body: json['content'] ?? json['body'] ?? '',
      type: json['type'] ?? 'info',
      createdAt: (DateTime.tryParse(json['createdAt'] ?? json['created_at'] ?? '') ?? DateTime.now()).toLocal(),
      isRead: json['isRead'] ?? json['is_read'] ?? false,
    );
  }
}
