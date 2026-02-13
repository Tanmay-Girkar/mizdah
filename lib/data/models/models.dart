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
}
