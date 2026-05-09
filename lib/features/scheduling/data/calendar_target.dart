// ════════════════════════════════════════════════════════════════════
//  CalendarTarget — which calendar provider to dispatch a payload to
// ════════════════════════════════════════════════════════════════════
//  v1 ships Google Calendar only; the others are placeholders so the
//  service surface doesn't change when we add them.

enum CalendarTarget {
  /// Google Calendar. Resolves to the Android/iOS app via universal-
  /// link interception when installed; otherwise the browser-side
  /// `calendar.google.com/calendar/render` template.
  googleCalendar,

  /// Apple Calendar via the system event-sheet (iOS / macOS) or an
  /// `.ics` download elsewhere. Not implemented yet — falls back to
  /// Google Calendar so the user still gets a working flow.
  appleCalendar,

  /// Outlook web (`outlook.live.com/calendar/0/deeplink/compose`).
  /// Not implemented yet.
  outlook,

  /// Generate an `.ics` file and hand it to the platform share sheet.
  /// Lets the user pick whichever calendar app they prefer.
  /// Not implemented yet.
  ics,
}
