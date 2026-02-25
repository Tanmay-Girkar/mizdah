class User {
  final String id;
  final String email;
  final String name;
  final String role;

  User({
    required this.id,
    required this.email,
    required this.name,
    required this.role,
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

  Meeting({
    required this.id,
    required this.title,
    required this.dateTime,
    required this.code,
    required this.participants,
  });

  factory Meeting.fromJson(Map<String, dynamic> json) {
    return Meeting(
      id: json['id'] ?? '',
      title: json['title'] ?? json['meeting_code'] ?? 'Untitled Meeting',
      dateTime: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
      code: json['meeting_code'] ?? '',
      participants: (json['participants'] as List?)?.map((e) => e.toString()).toList() ?? [],
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
      id: json['id'] ?? '',
      title: json['meeting_id'] ?? 'Past Meeting',
      timestamp: DateTime.tryParse(json['joined_at'] ?? '') ?? DateTime.now(),
      duration: json['duration'] != null ? Duration(seconds: json['duration']) : Duration.zero,
      isMissed: false, // Could be determined by duration or left_at
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
      id: json['id'] ?? '',
      title: json['title'] ?? 'Notification',
      body: json['body'] ?? '',
      type: json['type'] ?? 'info',
      createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
      isRead: json['isRead'] ?? false,
    );
  }
}
