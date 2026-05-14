class ApiConfig {
  // ── Local dev server ────────────────────────────────────────────
  // Point at the backend dev's machine on the local network. The
  // server runs media + signaling + REST on a single port (3001) and
  // exposes the same `/signaling-fresh` and `/media-fresh` engine.io
  // paths as production, so only the host:port needs to change.
  //
  // Self-signed cert handling: the override in main.dart's
  // _DevHttpOverrides accepts certs from this host in debug builds
  // so the mkcert / local CA cert doesn't trip CERTIFICATE_VERIFY_FAILED.
  // Release builds enforce full TLS validation.
  static const String _devHost = 'https://192.168.1.20:3001';

  static const String baseUrl = _devHost;
  static const String signalingUrl = _devHost;
  static const String signalingPath = '/signaling-fresh';
  static const String chatSocketUrl = _devHost;
  // Per docs/CHATS_API.md §3 the chat namespace `/chats` lives on the
  // SAME socket.io server that hosts meeting signaling — so the
  // engine.io mount path is identical. Without this, socket.io_client
  // falls back to the default `/socket.io/` path and the chat socket
  // silently fails to connect (no chat:message deltas → recipients
  // only see new messages after the 4s REST poll fallback, which
  // looks like "messages aren't instant"). Keep aliased rather than
  // duplicating the literal — if the backend ever splits chats onto
  // its own engine.io instance, flip this single line.
  static const String chatSocketPath = signalingPath;
  static const String mediaPath = '/media-fresh';

  // API Endpoints
  static const String authSignup = '$baseUrl/api/auth/signup';
  static const String authLogin = '$baseUrl/api/auth/login';
  static const String authMe = '$baseUrl/api/auth/me';
  static const String authUpdate = '$baseUrl/api/auth/update';

  // Password reset flow — see docs/PASSWORD_CHANGE_AND_RESET_BACKEND.md.
  // `forgotPassword` is public (no JWT) and triggers the reset email;
  // `resetPassword` consumes the single-use token from that email.
  static const String authForgotPassword =
      '$baseUrl/api/auth/forgot-password';
  static const String authResetPassword =
      '$baseUrl/api/auth/reset-password';

  // Post-call / post-meeting rating — see docs/CALL_FEEDBACK_BACKEND.md.
  static const String feedbackCallRating =
      '$baseUrl/api/feedback/call-rating';

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
