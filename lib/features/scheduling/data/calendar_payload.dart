// ════════════════════════════════════════════════════════════════════
//  CalendarPayload — wire-format for the calendar scheduling layer
// ════════════════════════════════════════════════════════════════════
//  Pure data class. All fields are immutable; optional fields are
//  nullable so the calling site doesn't have to invent placeholders.
//
//  Designed to outlive the v1 Google-Calendar-only impl: when we add
//  Apple Calendar / Outlook / .ics export, the same payload feeds
//  every target, so callers don't have to know which backend the
//  user has installed.

import 'package:intl/intl.dart';

/// One scheduled-meeting payload, ready to hand to any calendar
/// provider. The `title`, `meetingLink`, `startTime`, and `endTime`
/// are required — everything else is best-effort.
class CalendarPayload {
  /// Headline for the event. Shown at the top of the calendar entry.
  /// Keep short — `MizdahMeeting`, `Team Sync`, etc.
  final String title;

  /// Direct join URL — placed in the event's `location` field so most
  /// calendar UIs render it as a tappable button at the top of the
  /// event detail view.
  final String meetingLink;

  /// Human-readable meeting code (e.g. `abcdefghij`). Embedded in
  /// the description as `Meeting ID: <code>` so the user can copy /
  /// paste it without parsing the link.
  final String? meetingId;

  /// Optional passcode if the host enabled one. Surfaced as
  /// `Passcode: <code>` in the description.
  final String? passcode;

  /// Display name of whoever's hosting. Surfaces as
  /// `Hosted by <name>` at the bottom of the description.
  final String? hostName;

  /// Free-form additional context appended *before* the link block.
  /// Use this for "Quarterly review", "Weekly stand-up", etc. when
  /// the title alone isn't descriptive.
  final String? agenda;

  /// Wall-clock event start (local time). The service converts to
  /// UTC for the calendar URL itself.
  final DateTime startTime;

  /// Wall-clock event end. Defaults to `startTime + 1 hour` at the
  /// service level when null, but callers should pass an explicit
  /// value when they have one.
  final DateTime endTime;

  /// IANA timezone name (`America/Los_Angeles`, `Asia/Kolkata`).
  /// Some providers honour this; Google's `render?ctz=` param does.
  final String? timezone;

  /// Email addresses to pre-populate as guests. Google Calendar
  /// reads `&add=` for these on the render URL.
  final List<String> attendeeEmails;

  /// Recurrence rule in the standard iCal RRULE format
  /// (`RRULE:FREQ=WEEKLY;BYDAY=TU`). Currently passed through to
  /// Google Calendar's `&recur=` param. Null = single occurrence.
  final String? recurrenceRule;

  const CalendarPayload({
    required this.title,
    required this.meetingLink,
    required this.startTime,
    required this.endTime,
    this.meetingId,
    this.passcode,
    this.hostName,
    this.agenda,
    this.timezone,
    this.attendeeEmails = const [],
    this.recurrenceRule,
  });

  /// Renders the description block placed in the calendar entry.
  /// Mirrors the format Google Meet / Zoom / Teams use — link first
  /// (most-tapped action), then meeting metadata, then the host.
  String formatDescription() {
    final buf = StringBuffer();
    if (agenda != null && agenda!.trim().isNotEmpty) {
      buf
        ..writeln(agenda!.trim())
        ..writeln();
    }
    buf
      ..writeln('Join Meeting:')
      ..writeln(meetingLink);
    if (meetingId != null && meetingId!.trim().isNotEmpty) {
      buf
        ..writeln()
        ..writeln('Meeting ID: ${meetingId!.trim()}');
    }
    if (passcode != null && passcode!.trim().isNotEmpty) {
      buf.writeln('Passcode: ${passcode!.trim()}');
    }
    if (hostName != null && hostName!.trim().isNotEmpty) {
      buf
        ..writeln()
        ..writeln('Hosted by ${hostName!.trim()}');
    }
    return buf.toString().trimRight();
  }

  /// `yyyyMMdd'T'HHmmss'Z'` — the format Google Calendar's
  /// `&dates=<start>/<end>` parameter expects. UTC.
  String startUtcCompact() => _utcCompact.format(startTime.toUtc());
  String endUtcCompact() => _utcCompact.format(endTime.toUtc());

  static final DateFormat _utcCompact =
      DateFormat("yyyyMMdd'T'HHmmss'Z'");
}
