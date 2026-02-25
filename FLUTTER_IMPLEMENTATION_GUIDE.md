# 📱 Flutter Implementation Guide: Mizdah Backend Integration

This guide provides the step-by-step roadmap for a Flutter developer to implement the Mizdah (Google Meet Clone) APIs into a mobile application.

---

## 🛠️ Step 1: Project Setup

Add the following essential packages to your `pubspec.yaml`:

```yaml
dependencies:
  dio: ^5.4.0              # HTTP client for REST APIs
  flutter_secure_storage: ^9.0.0  # For secure JWT storage
  socket_io_client: ^3.0.0  # For real-time signaling (Port 4000)
  flutter_webrtc: ^0.10.x   # For video/audio streaming
  riverpod: ^2.x.x          # Optional: Recommended for state management
```

---

## 🌐 Step 2: Networking Configuration

Create a centralized `ApiClient` (using Dio) to handle the base configuration and token injection.

**Base URL**: `http://192.168.1.24:3000`

```dart
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ApiClient {
  final Dio dio = Dio(BaseOptions(
    baseUrl: 'http://192.168.1.24:3000',
    connectTimeout: const Duration(seconds: 5),
    receiveTimeout: const Duration(seconds: 3),
  ));

  final storage = const FlutterSecureStorage();

  ApiClient() {
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        // Automatically fetch token and add to header if it exists
        String? token = await storage.read(key: 'auth_token');
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        return handler.next(options);
      },
      onError: (e, handler) {
        if (e.response?.statusCode == 401) {
          // Trigger logout logic / Redirect to login screen
        }
        return handler.next(e);
      }
    ));
  }
}
```

---

## 🔐 Step 3: Authentication Flow

Implementing the core logic for user sessions.

1.  **Signup/Login**: Send credentials to `/api/auth/login`.
2.  **Token Storage**: Store the `token` from the response body.
3.  **Persistence**: On app launch, call `GET /api/auth/me`. If it returns a user, skip login.

```dart
Future<bool> login(String email, String password) async {
  try {
    final response = await dio.post('/api/auth/login', data: {
      'email': email,
      'password': password,
    });
    
    final token = response.data['token'];
    await storage.write(key: 'auth_token', value: token);
    return true;
  } catch (e) {
    return false;
  }
}
```

---

## 📹 Step 4: Meeting Lifecycle

The sequence for joining a video call correctly.

1.  **Room Discovery**: User enters a code. Call `GET /api/meeting/{code}` to fetch the room's Host and Settings.
2.  **Lobby/Preview**: Use `flutter_webrtc` to show the user their local camera view.
3.  **Join Log**: Call `POST /api/participant/join` BEFORE connecting to the signal server.
4.  **Signaling**: Connect to `http://192.168.1.24:4000` and emit `join-meeting`.

---

## 📡 Step 5: WebRTC & Signaling

Connect the Socket events to the `MediaStream` handling.

| Socket Event | Action |
|--------------|--------|
| `on: user-joined` | Create a new `RTCPeerConnection` for that user. |
| `on: offer` | Set Remote Description + Create/Send Answer. |
| `on: ice-candidate` | Add candidate to the specific Peer Connection. |
| `emit: send-caption` | Send transcription of native speech recognition. |

---

## ⚡ Step 6: Speeding Up Development

### 1. Automatic Data Models 
Instead of writing classes manually for the `~25` APIs, use the **`FLUTTER_API_SWAGGER.md`** file:
*   Copy JSON -> Go to [QuickType.io](https://app.quicktype.io/) -> Select **Dart**.
*   This generates all your `fromJson` and `toJson` methods instantly.

### 2. Testing with Postman
Use the **`Mizdah_Postman_Collection.json`** to verify that the server is working before you troubleshoot your Flutter code. If it works in Postman but not in the app, it's a code issue in Dart.

---

## ⚠️ Critical Connectivity Note
**The PC and the Phone must be on the same Network.**
*   Ensure your PC's firewall allows incoming connections on ports **3000, 4000, and 4001-4011**.
*   If using an Android Emulator, `127.0.0.1` refers to the emulator itself, NOT your PC. Always use the IP `192.168.1.24`.

---
*Generated for Mizdah Mobile Implementation Strategy — 2026*
