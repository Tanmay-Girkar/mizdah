// ════════════════════════════════════════════════════════════════════
//  CalendarSchedulingService — single entry point for "open calendar
//  with this meeting prefilled"
// ════════════════════════════════════════════════════════════════════
//  Strategy:
//    1. Build a deep URL for the chosen target.
//    2. `launchUrl(externalApplication)` — Android / iOS Google
//       Calendar apps intercept the universal link and open straight
//       to the prefilled event editor; if the app isn't installed
//       the browser handles the same URL.
//    3. If `externalApplication` fails for any reason
//       (rare — usually a Web embed where externalApplication isn't
//       supported), retry with `platformDefault`.
//    4. Last-resort: return false so the caller can show a toast.
//
//  Zero backend round-trips. The user's calendar stores the event;
//  the meeting room is created on-demand the first time someone hits
//  the join link.

import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import 'data/calendar_payload.dart';
import 'data/calendar_target.dart';

class CalendarSchedulingService {
  const CalendarSchedulingService();

  /// Open the user's calendar with `payload` prefilled. Returns true
  /// when the launch succeeded; false when neither
  /// `externalApplication` nor `platformDefault` could open the URL.
  /// Does NOT throw — error reporting is the caller's concern.
  Future<bool> schedule(
    CalendarPayload payload, {
    CalendarTarget target = CalendarTarget.googleCalendar,
  }) async {
    final uri = _buildUri(payload, target);
    if (uri == null) return false;
    return _launch(uri);
  }

  /// Same as `schedule`, but exposes the resolved URL so callers can
  /// surface a "Copy link" affordance when the launch fails on
  /// platforms where url_launcher returns false (some sandboxed web
  /// environments).
  String resolveUrl(
    CalendarPayload payload, {
    CalendarTarget target = CalendarTarget.googleCalendar,
  }) {
    return _buildUri(payload, target)?.toString() ?? '';
  }

  // ── URL builders ────────────────────────────────────────────────

  Uri? _buildUri(CalendarPayload p, CalendarTarget target) {
    switch (target) {
      case CalendarTarget.googleCalendar:
        return _googleCalendarUri(p);
      case CalendarTarget.outlook:
        return _outlookUri(p);
      case CalendarTarget.appleCalendar:
      case CalendarTarget.ics:
        // Not yet implemented — fall through to Google Calendar so
        // the user still gets a usable flow rather than a dead tap.
        return _googleCalendarUri(p);
    }
  }

  /// Google Calendar's universal "create-event" template URL.
  /// See https://support.google.com/calendar/answer/41207?hl=en for
  /// the parameter set; everything is URL-encoded by `Uri.https`.
  Uri _googleCalendarUri(CalendarPayload p) {
    final dates = '${p.startUtcCompact()}/${p.endUtcCompact()}';
    final params = <String, String>{
      'action': 'TEMPLATE',
      'text': p.title,
      'details': p.formatDescription(),
      'location': p.meetingLink,
      'dates': dates,
      // ctz lets Google render the event in the host's local TZ even
      // when the start/end are UTC. Optional — Google falls back to
      // the viewer's calendar TZ if absent.
      if (p.timezone != null && p.timezone!.isNotEmpty) 'ctz': p.timezone!,
      // Pre-add invitees as guests if any.
      if (p.attendeeEmails.isNotEmpty) 'add': p.attendeeEmails.join(','),
      if (p.recurrenceRule != null && p.recurrenceRule!.isNotEmpty)
        'recur': p.recurrenceRule!,
    };
    return Uri.https('calendar.google.com', '/calendar/render', params);
  }

  /// Outlook deep-link compose URL. Kept for future use; currently
  /// unreachable through the public API (target.outlook isn't
  /// surfaced in any UI yet).
  Uri _outlookUri(CalendarPayload p) {
    return Uri.https(
      'outlook.live.com',
      '/calendar/0/deeplink/compose',
      <String, String>{
        'subject': p.title,
        'body': p.formatDescription(),
        'startdt': p.startTime.toUtc().toIso8601String(),
        'enddt': p.endTime.toUtc().toIso8601String(),
        'location': p.meetingLink,
        'path': '/calendar/action/compose',
        'rru': 'addevent',
      },
    );
  }

  // ── Launch helpers ──────────────────────────────────────────────

  Future<bool> _launch(Uri uri) async {
    // External application — on Android/iOS this routes through the
    // OS's universal-link / app-link layer, so an installed Google
    // Calendar app intercepts the URL and opens straight to the
    // event editor. If the app isn't installed, the browser handles
    // the same URL.
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (ok) return true;
    } catch (e) {
      debugPrint('[scheduling] externalApplication launch failed: $e');
    }
    // Fallback for sandboxed environments (some Web embeds, kiosk
    // browsers) where externalApplication isn't permitted.
    try {
      return await launchUrl(uri, mode: LaunchMode.platformDefault);
    } catch (e) {
      debugPrint('[scheduling] platformDefault launch failed: $e');
      return false;
    }
  }
}
