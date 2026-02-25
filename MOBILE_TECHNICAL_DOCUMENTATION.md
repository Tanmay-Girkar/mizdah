# Mizdah Mobile App & Backend Integration Technical Documentation

This document provides a comprehensive technical overview of the Mizdah mobile application (built with Flutter) and its integration with the Google Meet clone backend services.

---

## 🏗️ 1. Mobile Architecture

The Mizdah mobile app follows a **Feature-First Clean Architecture** approach, ensuring scalability and maintainability.

### 📁 Folder Structure
- `lib/core/`: Contains cross-cutting concerns like global configuration, navigation, theme, and shared network clients.
- `lib/data/`: Data layer containing models (JSON serialization) and repositories (abstracting API calls).
- `lib/features/`: UI and business logic organized by feature (Auth, Home, Meeting, Call, Settings).
- `lib/core/network/`: Contains `ApiClient` using the `Dio` package.
- `lib/core/navigation/`: Navigation logic using `go_router`.

### 🧠 State Management
- **Framework**: `flutter_riverpod` (v2.x).
- **Pattern**: `StateNotifier` and `StateProvider` for managing authentication, meeting room state, and theme settings.
- **Providers**: `authProvider` for session management, `meetingProvider` for real-time call states.

### 🌐 Networking Layer
- **Package**: `Dio` v5.7.0.
- **Security**: Interceptors automatically inject `Authorization: Bearer <JWT>` headers for protected routes.
- **Handling**: Global error handling for 401 (Unauthorized) triggers automatic logout.

### 🔧 Service Layer
- **SignalingService**: Handles Socket.IO connections for WebRTC signaling.
- **WebRTCService**: Manages peer connections and media streams.
- **StorageService**: Wraps `flutter_secure_storage` for JWT and `shared_preferences` for non-sensitive settings.

### 🎥 Media Handling Layer
- **Package**: `flutter_webrtc`.
- **Logic**: Manages `MediaStream` (local and remote), `RTCVideoRenderer` initialization, and hardware toggles (camera/mic).

---

## 🌐 2. API Integration

All REST services are routed through a Gateway (Port 3000) or accessed via specific microservice ports.

### 🔐 Authentication Service (Port 4004)
| Endpoint | Method | Header | Description |
|---|---|---|---|
| `/api/auth/signup` | POST | Content-Type: json | Registers a new user |
| `/api/auth/login` | POST | Content-Type: json | Returns JWT and User object |
| `/api/auth/me` | GET | `Bearer <token>` | Returns current user profile |
| `/api/auth/update` | POST | `Bearer <token>` | Updates name or password |

### 📹 Meeting Service (Port 4001)
| Endpoint | Method | Description |
|---|---|---|
| `/api/meetings/create` | POST | Generates a new `meeting_code` |
| `/api/meeting/{code}` | GET | Validates and retrieves meeting details |
| `/api/meeting/{code}/settings` | PATCH| Updates feature flags (host only) |

### 👥 Participant Service (Port 4002)
| Endpoint | Method | Description |
|---|---|---|
| `/api/participant/join` | POST | Logs user entry into a meeting |
| `/api/participant/leave` | POST | Logs user exit from a meeting |
| `/api/participant/user/{userId}`| GET | Retrieves user's call history |

### 💬 Chat Service (Port 4005)
| Endpoint | Method | Description |
|---|---|---|
| `/api/chat/send` | POST | Persists a public or private message |
| `/api/chat/{meetingId}` | GET | Retrieves message history for a room |

### 📼 Recording Service (Port 4007)
| Endpoint | Method | Description |
|---|---|---|
| `/api/recording/upload` | POST | Uploads recorded blob (multipart/form-data) |
| `/api/recording/{meetingId}`| GET | List recordings for a meeting |

---

## 🔌 3. WebSocket / Real-time Communication

Mizdah uses **Socket.IO** for real-time signaling and chat synchronization.

### 🔗 Connection Settings
- **Signaling URL**: `http://<PC_IP>:4000`
- **Chat Socket URL**: `http://<PC_IP>:4005`
- **Transports**: `['websocket']`

### 📤 Events Emitted (Client → Server)
- `join-meeting`: `[meetingCode, userId, name, isNewMeeting]`
- `offer`: `{ to: socketId, offer: RTCSessionDescription }`
- `answer`: `{ to: socketId, answer: RTCSessionDescription }`
- `ice-candidate`: `{ to: socketId, candidate: RTCIceCandidate }`
- `chat:send`: `{ meetingId, senderId, content, recipientId? }`
- `request-recording`: `{}` (Host requests consent)

### 📥 Events Received (Server → Client)
- `join-confirmation`: Returns status (`JOINED`, `WAITING_FOR_APPROVAL`) and participant list.
- `user-joined`: Signals a new participant. Trigger: Start WebRTC offer.
- `offer/answer/ice-candidate`: WebRTC signaling payloads.
- `chat:receive`: Real-time message broadcast.
- `recording-started`: Signals all participants to begin capture.
- `meeting-ended`: Forced termination by host or time limit.

### 🔄 Reconnection Strategy
- **Auto-connect**: Enabled in `OptionBuilder`.
- **Reconnection Attempts**: Unlimited with exponential backoff (default Socket.IO behavior).
- **State Sync**: App re-emits `join-meeting` upon reconnection to restore session.

---

## 📡 4. WebRTC Handling

### 🏗️ Peer Connection Setup
1. **Local Media**: `getUserMedia` fetches local camera and mic tracks.
2. **PC Management**: A `Map<String, RTCPeerConnection>` tracks connections for every remote user (Mesh architecture).
3. **Configuration**: Uses Google STUN servers (`stun:stun.l.google.com:19302`).

### 🤝 Signaling Flow
1. **New Member Joins**: Server emits `user-joined`.
2. **Offer**: Existing members create a WebRTC Offer and send via `offer` socket event.
3. **Answer**: New member receives Offer, sets `RemoteDescription`, creates Answer, and sends via `answer` socket event.
4. **ICE**: Both sides exchange ICE Candidates via `ice-candidate` socket event as they are discovered.

### 🎥 Media Constraints
- **Video**: 1280x720 (720p) at 30fps (optimal bandwidth/quality balance).
- **Audio**: Echo cancellation and noise suppression enabled.

### 🔘 Control Logic
- **Camera Switch**: `stream.getVideoTracks().first.switchCamera()`.
- **Toggle Mic/Cam**: `track.enabled = !track.enabled`.

---

## 🔄 5. Meeting Lifecycle (Mobile Perspective)

1. **Create Meeting**: `POST /api/meetings/create` → UI displays room code.
2. **Join Meeting**:
   - `GET /api/meeting/{code}` (Validate).
   - `POST /api/participant/join` (Log entry).
   - Socket `join-meeting` (Signal intent).
3. **Handshake**: Wait for `join-confirmation`. If guest, wait for host `admit-user`.
4. **Active Session**: WebRTC Mesh established -> Chat/Video active.
5. **Host Controls**: Host can mute, kick, or end the meeting for everyone.
6. **Leave**: Stop local tracks -> Close peer connections -> `POST /api/participant/leave` -> Redirect to Home.

---

## 🎨 6. UI Mapping

| Mobile Screen | Web App Feature | Backend Dependency |
|---|---|---|
| **Splash Screen** | Branding/Initial Auth | `/api/auth/me` |
| **Login/Signup** | Account Management | `/api/auth/login`, `/api/auth/signup` |
| **Home Screen** | Dashboard / Landing | `/api/scheduling/user`, `/api/participant/user` |
| **Schedule Screen** | Calendar/Scheduler | `/api/scheduling/schedule` |
| **Pre-Join Screen** | Lobby / Preview | `/api/meeting/{code}`, `getUserMedia` |
| **Meeting Room** | Main Gallery View | Port 4000 (Signaling), Port 4005 (Chat) |
| **Meeting Settings**| Room Management | `/api/meeting/{code}/settings` |
| **Profile Screen** | User Settings | `/api/auth/update` |

---

## 🔐 7. Authentication

- **Flow**: User enters credentials -> API returns JWT -> JWT saved via `FlutterSecureStorage`.
- **Token Storage**: Encrypted storage on Android (Keystore) and iOS (Keychain).
- **Refresh Logic**: Currently stateless JWT. Future implementation: Refresh token rotation via `/api/auth/refresh`.
- **Persistence**: `_checkAuth()` on app launch verifies token validity against `/api/auth/me`.

---

## 🛡️ 8. Error Handling & Edge Cases

- **Network Drop**: Socket listeners detect `disconnect`. UI shows "Connecting..." overlay.
- **Backgrounding**: Video track disabled to save battery; Audio continues unless app is suspended.
- **Call Interruption**: Native phone calls pause WebRTC audio/video tracks.
- **Permission Denial**: App prompts `permission_handler`. Use of features is blocked if camera/mic denied.
- **Hardware Failure**: Try-catch blocks wrap `getUserMedia` to handle missing hardware or driver issues.

---

## 🔒 9. Security

- **Encryption**: Signaling and API calls use HTTPS/WSS in production. WebRTC media is encrypted by default (SRTP).
- **Token Handling**: Tokens never stored in `SharedPreferences`. Only `FlutterSecureStorage` is used.
- **Sanitization**: All chat inputs sanitized on backend; UI uses rich text rendering to avoid script execution.

---

## ⚡ 10. Performance Optimizations

- **Video Quality**: Bitrate adaptation based on RTCPeerConnection stats.
- **Memory**: Strict `dispose()` calls on `RTCVideoRenderer` and `MediaStream` when leaving meetings.
- **Battery**: Video rendering paused when UI is obscured or app is in background.
- **Data Usage**: Default to low-resolution video when on cellular data (optional setting).

---
*Documentation generated for Senior Mobile Systems Architecture Review.*
