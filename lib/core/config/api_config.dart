class ApiConfig {
  // ── Local dev server ────────────────────────────────────────────
  // Point at the backend dev's machine on the local network. The
  // server runs media + signaling + REST on a single port (3001) and
  // exposes the same `/signaling-fresh` and `/media-fresh` engine.io
  // paths as production, so only the host:port needs to change.
  //
  // Requires `android:usesCleartextTraffic="true"` in
  // AndroidManifest.xml (already set) since this is plain HTTP. iOS
  // Info.plist also needs `NSAllowsArbitraryLoads` if testing on iOS.
  //
  // To switch back to production, replace `_devHost` with the
  // production URL: `https://mizdah-backend.ogoul.cloud`.
  static const String _devHost = 'http://192.168.1.117:3001';

  // ── Production (kept for easy revert) ───────────────────────────
  // static const String _devHost = 'https://mizdah-backend.ogoul.cloud';

  static const String baseUrl = _devHost;
  static const String signalingUrl = _devHost;
  static const String signalingPath = '/signaling-fresh';
  static const String chatSocketUrl = _devHost;
  static const String mediaPath = '/media-fresh';

  // API Endpoints
  static const String authSignup = '$baseUrl/api/auth/signup';
  static const String authLogin = '$baseUrl/api/auth/login';
  static const String authMe = '$baseUrl/api/auth/me';
  static const String authUpdate = '$baseUrl/api/auth/update';

  static const String createMeeting = '$baseUrl/api/meetings/create';
  static const String getMeeting = '$baseUrl/api/meeting'; 
  static const String userMeetings = '$baseUrl/api/meetings/user'; // + /{userId}
  
  static const String participantJoin = '$baseUrl/api/participant/join';
  static const String participantLeave = '$baseUrl/api/participant/leave';
  static const String userParticipation = '$baseUrl/api/participant/user'; // + /{userId}
  static const String meetingParticipants = '$baseUrl/api/participant'; // + /{meetingId}

  static const String chatSend = '$baseUrl/api/chat/send';
  static const String chatHistory = '$baseUrl/api/chat'; // + /{meetingId}
  
  static const String scheduling = '$baseUrl/api/scheduling/schedule';
  static const String userSchedules = '$baseUrl/api/scheduling/user'; // + /{userId}
  
  static const String recordingUpload = '$baseUrl/api/recording/upload';
  static const String recordingStart = '$baseUrl/api/recording/start'; // + /{meetingId}
  static const String recordingStop = '$baseUrl/api/recording/stop'; // + /{meetingId}
  
  static const String notifications = '$baseUrl/api/notifications';
  static const String notificationUser = '$baseUrl/api/notifications/user'; // + /{userId}
  
  static const String fileUpload = '$baseUrl/api/files/upload';
  static const String files = '$baseUrl/api/files'; // + /{fileId}
  
  static const String adminUsers = '$baseUrl/api/admin/users';

  // Waiting Room
  static const String waitingRoomWaiting = '$baseUrl/api/waiting-room/waiting'; // + /{meetingId}
  static const String waitingRoomAdmit = '$baseUrl/api/waiting-room/admit';
  static const String waitingRoomDeny = '$baseUrl/api/waiting-room/deny';
}
