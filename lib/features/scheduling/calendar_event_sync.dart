// ════════════════════════════════════════════════════════════════════
//  CalendarEventSync — read back a meeting from the device calendar
// ════════════════════════════════════════════════════════════════════
//  After the user taps "Schedule Meeting" the app launches Google
//  Calendar (URL launch). Calendar opens in a separate process and
//  never reports back to us — there's no way to know whether the
//  user saved or cancelled.
//
//  Workaround: embed a unique tag in the event's description before
//  launching Calendar (e.g. "#mizdah:abcdefghij"), then after the
//  user returns to our app, poll the *device's native calendar
//  database* via the `device_calendar` plugin for any event whose
//  description contains that tag. If we find one, we now know:
//
//    • the user actually tapped Save (otherwise no row would exist)
//    • the *real* start / end times they set (we read them from
//      the calendar event, not the placeholder we passed to the URL)
//    • the calendar provider's event id (for de-dup)
//
//  If we never find a match within the polling window the user
//  cancelled — we do nothing.
//
//  This is the closest we can get to a true save-callback without
//  building Google Calendar API + OAuth from scratch.

import 'dart:async';

import 'package:device_calendar/device_calendar.dart' as dc;
import 'package:flutter/foundation.dart';

/// One event found in the device calendar, normalised so the
/// scheduling code doesn't have to know about device_calendar's
/// types.
class FoundCalendarEvent {
  final String eventId;
  final String? calendarId;
  final String title;
  final DateTime startTime; // local
  final DateTime endTime; // local
  final String? description;

  const FoundCalendarEvent({
    required this.eventId,
    required this.title,
    required this.startTime,
    required this.endTime,
    this.calendarId,
    this.description,
  });
}

class CalendarEventSync {
  CalendarEventSync({dc.DeviceCalendarPlugin? plugin})
      : _plugin = plugin ?? dc.DeviceCalendarPlugin();

  final dc.DeviceCalendarPlugin _plugin;

  /// Asks the OS for calendar read permission. Returns `true` if the
  /// user has (or now has) granted access; `false` otherwise. Safe to
  /// call repeatedly — the OS only prompts the first time.
  Future<bool> ensurePermissions() async {
    try {
      final perms = await _plugin.hasPermissions();
      if (perms.isSuccess && perms.data == true) return true;
      final request = await _plugin.requestPermissions();
      return request.isSuccess && request.data == true;
    } catch (e) {
      debugPrint('[calendar-sync] permission check failed: $e');
      return false;
    }
  }

  /// Poll the device's calendars for any event whose description
  /// contains [tag]. Returns the first match, or `null` if the
  /// [timeout] elapses with no match (i.e. user cancelled).
  ///
  /// The first poll waits [initialDelay] before running — Calendar
  /// providers usually need 1-3 seconds to commit + sync the new
  /// row, so polling immediately is wasteful.
  ///
  /// [searchWindow] sets how far in the future to look. Users
  /// typically schedule for "today" or "tomorrow"; 30 days covers
  /// the common case without making the query expensive.
  Future<FoundCalendarEvent?> waitForEventByTag(
    String tag, {
    Duration timeout = const Duration(seconds: 60),
    Duration pollInterval = const Duration(seconds: 2),
    Duration initialDelay = const Duration(seconds: 2),
    Duration searchWindow = const Duration(days: 30),
  }) async {
    await Future<void>.delayed(initialDelay);
    final start = DateTime.now();
    while (DateTime.now().difference(start) < timeout) {
      final found = await _findEventByTag(tag, searchWindow: searchWindow);
      if (found != null) return found;
      await Future<void>.delayed(pollInterval);
    }
    return null;
  }

  Future<FoundCalendarEvent?> _findEventByTag(
    String tag, {
    required Duration searchWindow,
  }) async {
    try {
      final calendarsResult = await _plugin.retrieveCalendars();
      final calendars = calendarsResult.data;
      if (calendarsResult.isSuccess != true || calendars == null) return null;

      final now = DateTime.now();
      final params = dc.RetrieveEventsParams(
        // Look back a little — if the user scheduled for `now` and
        // the wall clock ticks past during the polling delay, we'd
        // miss the event with a tight `startDate`.
        startDate: now.subtract(const Duration(minutes: 10)),
        endDate: now.add(searchWindow),
      );

      for (final cal in calendars) {
        if (cal.id == null) continue;
        final eventsResult = await _plugin.retrieveEvents(cal.id, params);
        final events = eventsResult.data;
        if (events == null) continue;
        for (final e in events) {
          final desc = e.description ?? '';
          if (!desc.contains(tag)) continue;
          // Match. Normalise + return.
          final dStart = e.start?.toLocal();
          final dEnd = e.end?.toLocal();
          if (dStart == null || dEnd == null || e.eventId == null) continue;
          return FoundCalendarEvent(
            eventId: e.eventId!,
            calendarId: cal.id,
            title: e.title ?? 'Mizdah Meeting',
            startTime: dStart,
            endTime: dEnd,
            description: e.description,
          );
        }
      }
    } catch (e) {
      debugPrint('[calendar-sync] poll failed: $e');
    }
    return null;
  }
}
