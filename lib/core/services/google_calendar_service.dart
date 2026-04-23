import 'package:google_sign_in/google_sign_in.dart' as gsi;
import 'package:googleapis/calendar/v3.dart' as calendar;
import 'package:googleapis_auth/googleapis_auth.dart' as auth;
import 'package:http/http.dart' as http;
import 'dart:io';

class GoogleCalendarService {
  final gsi.GoogleSignIn _googleSignIn = gsi.GoogleSignIn.instance;
  bool _isInitialized = false;

  Future<void> _ensureInitialized() async {
    if (_isInitialized) return;
    await _googleSignIn.initialize();
    _isInitialized = true;
  }

  Future<calendar.CalendarApi?> _getCalendarApi() async {
    try {
      print("🔑 GCal: Checking initialization...");
      await _ensureInitialized();
      
      print("🔑 GCal: Requesting authentication...");
      final gsi.GoogleSignInAccount googleUser = await _googleSignIn.authenticate();
      print("🔑 GCal: Authenticated as ${googleUser.email}");

      print("🔑 GCal: Requesting scope authorization...");
      final gsi.GoogleSignInClientAuthorization authInfo = await googleUser.authorizationClient.authorizeScopes([
        calendar.CalendarApi.calendarEventsScope,
      ]);
      print("🔑 GCal: Authorization successful");
      
      final authClient = auth.authenticatedClient(
        http.Client(),
        auth.AccessCredentials(
          auth.AccessToken(
            'Bearer',
            authInfo.accessToken,
            DateTime.now().add(const Duration(hours: 1)).toUtc(),
          ),
          null,
          [calendar.CalendarApi.calendarEventsScope],
        ),
      );

      return calendar.CalendarApi(authClient);
    } catch (e) {
      print("Google Auth Error: $e");
      return null;
    }
  }

  Future<String?> scheduleMeeting({
    required String title,
    required String description,
    required DateTime startTime,
    Duration duration = const Duration(hours: 1),
  }) async {
    final api = await _getCalendarApi();
    if (api == null) return null;

    var event = calendar.Event();
    event.summary = title;
    event.description = description;
    
    // Start Time
    var start = calendar.EventDateTime();
    start.dateTime = startTime.toUtc();
    event.start = start;

    // End Time
    var end = calendar.EventDateTime();
    end.dateTime = startTime.add(duration).toUtc();
    event.end = end;

    try {
      calendar.Event response = await api.events.insert(event, "primary");
      print("Event created: ${response.htmlLink}");
      return response.htmlLink;
    } catch (e) {
      print("Calendar API Error: $e");
      return null;
    }
  }
}
