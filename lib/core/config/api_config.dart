class ApiConfig {
  // Replace with your local machine's IP address (run `ipconfig` on Windows)
  static const String pcIp = '192.168.1.24'; 

  // Ports as defined in FLUTTER_API_SWAGGER.md
  static const String gatewayPort = '3000';
  static const String signalingPort = '4000';
  static const String chatSocketPort = '4005';

  static const String baseUrl = 'http://$pcIp:$gatewayPort';
  static const String signalingUrl = 'http://$pcIp:$signalingPort';
  static const String chatSocketUrl = 'http://$pcIp:$chatSocketPort';

  // API Endpoints
  static const String authSignup = '$baseUrl/api/auth/signup';
  static const String authLogin = '$baseUrl/api/auth/login';
  static const String authMe = '$baseUrl/api/auth/me';
  static const String authUpdate = '$baseUrl/api/auth/update';

  static const String createMeeting = '$baseUrl/api/meetings/create';
  static const String getMeeting = '$baseUrl/api/meeting'; // + /{meetingCode}
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
}
