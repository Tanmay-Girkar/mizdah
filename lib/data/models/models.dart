class User {
  final String id;
  final String email;
  final String name;
  final String role;

  User({
    required this.id,
    required this.email,
    required this.name,
    this.role = 'USER',
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] ?? '',
      email: json['email'] ?? '',
      name: json['name'] ?? '',
      role: json['role'] ?? 'USER',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'name': name,
      'role': role,
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
      dateTime: DateTime.tryParse(json['created_at'] ?? json['createdAt'] ?? '') ?? DateTime.now(),
      code: json['meeting_code'] ?? json['code'] ?? json['meetingId'] ?? json['id']?.toString() ?? '',
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

  CallHistory({
    required this.id,
    required this.title,
    required this.timestamp,
    required this.duration,
    required this.isMissed,
  });

  factory CallHistory.fromJson(Map<String, dynamic> json) {
    return CallHistory(
      id: json['id']?.toString() ?? '',
      title: json['meeting_title'] ?? json['title'] ?? json['meeting_code'] ?? json['meetingCode'] ?? json['meeting_id'] ?? json['meetingId'] ?? 'Past Meeting',
      timestamp: DateTime.tryParse(json['joined_at'] ?? json['joinedAt'] ?? '') ?? DateTime.now(),
      duration: json['duration'] != null ? Duration(seconds: int.tryParse(json['duration'].toString()) ?? 0) : Duration.zero,
      isMissed: false,
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
      createdAt: DateTime.tryParse(json['createdAt'] ?? json['created_at'] ?? '') ?? DateTime.now(),
      isRead: json['isRead'] ?? json['is_read'] ?? false,
    );
  }
}
