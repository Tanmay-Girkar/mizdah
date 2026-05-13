// ════════════════════════════════════════════════════════════════════
//  ScheduledMeeting — local-storage record of a user-scheduled meeting
// ════════════════════════════════════════════════════════════════════
//  The user's local source of truth for meetings scheduled via the
//  in-app "Schedule Meeting" sheet. We persist these locally
//  (SharedPreferences JSON) because Google Calendar is a one-way
//  hand-off: launching it via URL never round-trips a confirmation
//  back to us. Without local storage, scheduled meetings would
//  vanish from "Upcoming Meetings" the moment the user reopens the
//  app — the bug fix the user asked for.
//
//  The model also doubles as a shim into the existing
//  `_MeetingRow` widget (which reads `schedule['startTime']` etc.):
//  see `toScheduleMap()`.

import '../../../core/utils/meeting_utils.dart';

/// The kind of meeting being scheduled. Drives the icon + the join
/// route on the home Upcoming card. Webinar reserved for future.
enum MeetingType { video, audio, webinar }

extension MeetingTypeX on MeetingType {
  String get wire => switch (this) {
        MeetingType.video => 'video',
        MeetingType.audio => 'audio',
        MeetingType.webinar => 'webinar',
      };

  static MeetingType fromWire(String? s) => switch (s) {
        'audio' => MeetingType.audio,
        'webinar' => MeetingType.webinar,
        _ => MeetingType.video,
      };
}

class ScheduledMeeting {
  /// Local UUID — millis + random suffix; not the meeting join code.
  final String id;

  /// User-visible meeting title (`"Q1 review"`, `"Mizdah Meeting"`).
  final String title;

  /// Optional free-text description shown in the calendar invite
  /// and the meeting detail screen.
  final String description;

  /// Random shareable code (e.g. `abcdefghij`) used to construct
  /// the join URL. Distinct from `id` so the link is stable even
  /// if the user re-schedules. Auto-generated on construction.
  final String meetingCode;

  /// Wall-clock UTC start. Always stored UTC so display layers can
  /// `.toLocal()` consistently regardless of host timezone.
  final DateTime startTime;

  /// Wall-clock UTC end.
  final DateTime endTime;

  /// Email addresses to invite. Forwarded to Google Calendar as
  /// guests via `&add=`. Empty list = solo meeting.
  final List<String> participants;

  final MeetingType meetingType;

  /// Display name of whoever scheduled this — surfaces in the
  /// calendar description as `Hosted by …`.
  final String? createdBy;

  /// When the user tapped Save in the schedule sheet. UTC.
  final DateTime createdAt;

  /// Future: store the calendar provider's event id once we can
  /// retrieve it (Calendar API integration). For v1 this stays null
  /// because Google Calendar's URL-launch doesn't echo back an id.
  final String? calendarEventId;

  const ScheduledMeeting({
    required this.id,
    required this.title,
    required this.description,
    required this.meetingCode,
    required this.startTime,
    required this.endTime,
    required this.participants,
    required this.meetingType,
    required this.createdAt,
    this.createdBy,
    this.calendarEventId,
  });

  /// Convenience constructor for new schedules — auto-generates `id`
  /// and `meetingCode`, sets `createdAt` to now-UTC, normalises
  /// start/end to UTC. Callers pass local times.
  factory ScheduledMeeting.create({
    required String title,
    required String description,
    required DateTime startTime,
    required DateTime endTime,
    required MeetingType meetingType,
    List<String> participants = const [],
    String? createdBy,
  }) {
    final id =
        '${DateTime.now().millisecondsSinceEpoch}_${MeetingUtils.generateMeetingCode()}';
    return ScheduledMeeting(
      id: id,
      title: title,
      description: description,
      meetingCode: MeetingUtils.generateMeetingCode(),
      startTime: startTime.toUtc(),
      endTime: endTime.toUtc(),
      participants: List.unmodifiable(participants),
      meetingType: meetingType,
      createdBy: createdBy,
      createdAt: DateTime.now().toUtc(),
    );
  }

  /// Web fallback join link — matches the doc-spec
  /// `https://mizdah.app/join/<code>`. The deep-link scheme
  /// `mizdah://meeting/<code>` is handled by the existing router.
  String get joinLink => 'https://mizdah.app/join/$meetingCode';

  Duration get duration => endTime.difference(startTime);

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'meetingCode': meetingCode,
        'startTime': startTime.toUtc().toIso8601String(),
        'endTime': endTime.toUtc().toIso8601String(),
        'participants': participants,
        'meetingType': meetingType.wire,
        'createdBy': createdBy,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'calendarEventId': calendarEventId,
      };

  factory ScheduledMeeting.fromJson(Map<String, dynamic> j) {
    return ScheduledMeeting(
      id: j['id'] as String,
      title: (j['title'] as String?) ?? 'Untitled Meeting',
      description: (j['description'] as String?) ?? '',
      meetingCode: j['meetingCode'] as String,
      startTime: DateTime.parse(j['startTime'] as String).toUtc(),
      endTime: DateTime.parse(j['endTime'] as String).toUtc(),
      participants: ((j['participants'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(growable: false),
      meetingType: MeetingTypeX.fromWire(j['meetingType'] as String?),
      createdBy: j['createdBy'] as String?,
      createdAt: DateTime.parse(j['createdAt'] as String).toUtc(),
      calendarEventId: j['calendarEventId'] as String?,
    );
  }

  ScheduledMeeting copyWith({
    String? title,
    String? description,
    DateTime? startTime,
    DateTime? endTime,
    List<String>? participants,
    MeetingType? meetingType,
    String? calendarEventId,
  }) =>
      ScheduledMeeting(
        id: id,
        title: title ?? this.title,
        description: description ?? this.description,
        meetingCode: meetingCode,
        startTime: startTime?.toUtc() ?? this.startTime,
        endTime: endTime?.toUtc() ?? this.endTime,
        participants: participants ?? this.participants,
        meetingType: meetingType ?? this.meetingType,
        createdBy: createdBy,
        createdAt: createdAt,
        calendarEventId: calendarEventId ?? this.calendarEventId,
      );

  /// Convert to the loose `Map` shape the existing `_MeetingRow` /
  /// `_UpcomingMeetingCard` widgets expect (so we don't have to
  /// touch a single widget file to display local meetings alongside
  /// backend-fetched ones).
  Map<String, dynamic> toScheduleMap() => {
        'id': id,
        // Backend rows put the meeting code in `[ ]` at the title's
        // end so `_extractMeetingCode` can recover it. We also send
        // `meetingCode` explicitly so the recovery skips the regex.
        'title': title,
        'meetingCode': meetingCode,
        'startTime': startTime.toUtc().toIso8601String(),
        'endTime': endTime.toUtc().toIso8601String(),
        'timezone': DateTime.now().timeZoneName,
        // Tag the row so merge logic in schedulesProvider can tell
        // local vs. backend apart if it ever needs to.
        '__source': 'local',
      };
}
