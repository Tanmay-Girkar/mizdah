# 🏗️ Mizdah Flutter — End-to-End Implementation Plan
> Updated: 2026-02-24 | Core Flow: **FUNCTIONAL** ✅

---

## ✅ Completed Phases

| Phase | Feature | Status |
|---|---|---|
| **Phase 0** | API Configuration & Core Client | ✅ Done |
| **Phase 1** | Real Authentication (Login/Signup/Me) | ✅ Done |
| **Phase 2** | Home Screen Data (History/Meetings) | ✅ Done |
| **Phase 3** | Meeting Creation & Join Logic | ✅ Done |
| **Phase 4** | Real-time Signaling (Socket.IO) | ✅ Done |
| **Phase 5** | In-call Chat Integration | ✅ Done |

---

## 🛠️ Next Steps (Pending Features)

### 📼 Phase 6: Recording Flow (Status: Not Started)
- **Goal**: Implement the "Record Meeting" button functionality.
- **Backend API**: `POST /api/recording/start/{meetingId}`.
- **UI Interaction**: Consent dialog before recording → Signal start → Recording indicator → Final upload.

### 📅 Phase 7: Scheduling UI (Status: Partially Done)
- **Goal**: Hook up the "Schedule" screen to the `POST /api/scheduling/schedule` endpoint.
- **UI Change**: Replace mock date picker with real API payload.

### 🔔 Phase 8: Real Notifications (Status: Not Started)
- **Goal**: Integrate Push Notifications (FCM) or local polling for meeting reminders.

---

## 🚀 How to Test the Current Flow

1. **Configure IP**: Open `lib/core/config/api_config.dart` and update `pcIp` with your PC's actual IPv4 address.
2. **Start Backend**: Ensure all microservices (Ports 4000–4011) and the Gateway (Port 3000) are running.
3. **Run App**: `flutter run`.
4. **User Flow**:
   - **Login** with a real user (or signup).
   - **Click 'New Meeting'** on Home → This creates a code in the DB.
   - **Join** from Pre-Join → You'll see your local video and be connected to signaling.
   - **Open Chat** → Messages are sent/received through the real socket.

---

## 📌 Guiding Principle

The app currently runs entirely on **mock data** (hardcoded lists, fake tokens, `Future.delayed()`).  
The goal of this plan is to replace every mock with a **real API call**, wiring the Flutter app to the live backend microservices running locally.

> ⚠️ **Do NOT implement everything at once.** Follow the phases in order. Each phase builds on the previous one.

---

## 🗂️ Current State Snapshot

| File | Current State |
|---|---|
| `auth_provider.dart` | Mock login (`test@mizdah.com` / `password`), mock OAuth, fake JWT |
| `mizdah_repository.dart` | `MockMizdahRepository` — hardcoded contacts + call history |
| `meeting_room_screen.dart` | UI only — no Socket.IO, no WebRTC, no real chat |
| `schedule_screen.dart` | UI only — no real scheduling API calls |
| `home_screen.dart` | Reads from mock repository |
| `pre_join_screen.dart` | UI only — no meeting validation |
| `start_call_screen.dart` | UI only — no meeting creation API |
| `settings_screen.dart` | UI only — no real update calls |

---

## 📦 Phase 0 — Project Setup & Architecture

> **Goal:** Set up the folder structure and shared infrastructure before writing any feature code.

### 0.1 — Add Required Dependencies to `pubspec.yaml`

```yaml
dependencies:
  http: ^1.2.0                        # REST API calls
  socket_io_client: ^2.0.3+1          # Signaling + Chat Socket.IO
  flutter_webrtc: ^0.10.7             # WebRTC video/audio
  flutter_secure_storage: ^9.0.0      # JWT token storage (already added)
  flutter_riverpod: ^2.5.1            # State management (already added)
  go_router: ^13.0.0                  # Navigation (already added)
  image_picker: ^1.0.7                # Profile avatar upload
  file_picker: ^8.0.0                 # File attachment in chat
  share_plus: ^9.0.0                  # Share meeting invite (already added)
```

---

### 0.2 — Create `ApiConfig` (Central URL Configuration)

**New file:** `lib/core/config/api_config.dart`

```dart
// Define all base URLs and service ports here.
// Change YOUR_PC_IP to your actual IPv4 (run `ipconfig`).

class ApiConfig {
  static const String pcIp = '192.168.1.X';           // ← CHANGE THIS

  static const String gatewayBase    = 'http://$pcIp:3000';
  static const String signalingUrl   = 'http://$pcIp:4000';
  static const String chatSocketUrl  = 'http://$pcIp:4005';

  // Service prefixes (all routed through gateway port 3000)
  static const String auth           = '$gatewayBase/api/auth';
  static const String meetings       = '$gatewayBase/api/meetings';
  static const String meeting        = '$gatewayBase/api/meeting';
  static const String participant    = '$gatewayBase/api/participant';
  static const String chat           = '$gatewayBase/api/chat';
  static const String notifications  = '$gatewayBase/api/notifications';
  static const String scheduling     = '$gatewayBase/api/scheduling';
  static const String recording      = '$gatewayBase/api/recording';
  static const String files          = '$gatewayBase/api/files';
  static const String admin          = '$gatewayBase/api/admin';
}
```

---

### 0.3 — Create `ApiClient` (Shared HTTP helper)

**New file:** `lib/core/network/api_client.dart`

- Wraps `http` package.
- Auto-injects `Authorization: Bearer <token>` header from `flutter_secure_storage`.
- Handles `401`, `404`, `500` errors uniformly and throws typed exceptions.
- Methods: `get()`, `post()`, `patch()`, `delete()`, `postMultipart()`.

---

### 0.4 — Restructure `lib/` Folder

```
lib/
├── core/
│   ├── config/
│   │   └── api_config.dart           ← NEW
│   ├── network/
│   │   └── api_client.dart           ← NEW
│   ├── navigation/
│   │   └── app_router.dart
│   ├── theme/
│   │   └── theme_provider.dart
│   └── widgets/
│       └── (existing widgets)
├── data/
│   ├── models/
│   │   └── models.dart               ← EXPAND (add API response models)
│   └── repositories/
│       ├── mizdah_repository.dart    ← REPLACE mock with real impl
│       ├── auth_repository.dart      ← NEW
│       ├── meeting_repository.dart   ← NEW
│       ├── chat_repository.dart      ← NEW
│       ├── scheduling_repository.dart← NEW
│       └── recording_repository.dart ← NEW
├── features/
│   ├── auth/
│   ├── home/
│   ├── meeting/
│   ├── call/
│   └── settings/
└── main.dart
```

---

### 0.5 — Expand Data Models

**Expand `lib/data/models/models.dart`** to add proper serialization for all API responses:

| Model | Fields from API |
|---|---|
| `User` | id, email, name, role |
| `Meeting` | id, meeting_code, host_id, all feature flags, created_at |
| `Participant` | id, meeting_id, user_id, joined_at, left_at |
| `ChatMessage` | id, meetingId, senderId, senderName, recipientId, content, attachmentUrl, createdAt |
| `Notification` | id, userId, type, title, body, createdAt |
| `Schedule` | id, hostId, meetingId, title, startTime, endTime, recurrence, timezone |
| `Recording` | id, meetingId, fileUrl, recordedBy, duration, startedAt, endedAt |
| `CallHistory` | Derived from participant + meeting join |

Each model needs a `fromJson(Map<String, dynamic> json)` factory constructor.

---

## 🔐 Phase 1 — Authentication (Replace Mock)

> **Goal:** Real login/signup with JWT stored securely. All subsequent API calls use the real token.

### Steps:

**1.1 — Create `AuthRepository`** (`lib/data/repositories/auth_repository.dart`)

| Method | Calls |
|---|---|
| `signup(email, password, name)` | `POST /api/auth/signup` |
| `login(email, password)` | `POST /api/auth/login` |
| `getMe()` | `GET /api/auth/me` |
| `updateProfile(name, password)` | `POST /api/auth/update` |

**1.2 — Rewrite `AuthNotifier`** (`auth_provider.dart`)

- Replace `Future.delayed()` + hardcoded check with real `AuthRepository.login()`.
- On success: store real JWT from response via `flutter_secure_storage`.
- On app start (`_checkAuth()`): call `GET /api/auth/me` to validate the stored token server-side (don't just trust local storage blindly).
- Remove `loginWithOAuth()` or mark it as "coming soon" — **no backend OAuth endpoint exists yet**.

**1.3 — Update Login Screen**

- Wire up real error messages from API response (`"Email already exists"`, `"Invalid credentials"`).
- Show a `CircularProgressIndicator` while `AuthStatus.authenticating`.
- **Remove** the hardcoded `test@mizdah.com` / `password` check.

**1.4 — Handle Token Expiry Globally**

- In `ApiClient`, if any request returns `401`, clear the token from storage and navigate to Login screen using GoRouter.

---

## 🏠 Phase 2 — Home Screen (Real Data)

> **Goal:** Home screen shows real scheduled meetings and real call history instead of mock lists.

### Steps:

**2.1 — Create `MeetingRepository`** (`lib/data/repositories/meeting_repository.dart`)

| Method | Calls |
|---|---|
| `getScheduledMeetings(userId)` | `GET /api/scheduling/user/{userId}` |
| `getParticipationHistory(userId)` | `GET /api/participant/user/{userId}` |
| `getMeetingDetails(code)` | `GET /api/meeting/{meetingCode}` |
| `getUserMeetings(userId)` | `GET /api/meetings/user/{userId}` |

**2.2 — Replace `MockMizdahRepository`**

- Create `RealMizdahRepository implements MizdahRepository`.
- `getMeetings()` → calls `getScheduledMeetings(userId)`.
- `getCallHistory()` → calls `getParticipationHistory(userId)` and maps to `CallHistory` model.
- Update `mizdahRepositoryProvider` to return `RealMizdahRepository`.

**2.3 — Contacts List Gap**

> ⚠️ **No `/api/contacts` endpoint exists in the swagger.**

Options (pick one):
- **Option A (Recommended):** Use `GET /api/admin/users` to list platform users — rename it to "People" list.
- **Option B:** Ask backend developer to add `GET /api/users/search?q=` endpoint.
- **Option C:** Keep the contacts section UI but hide it until the endpoint is available.

**2.4 — Home Screen State**

- Use Riverpod `FutureProvider` to load scheduled meetings and call history.
- Show loading states (`CircularProgressIndicator`) and empty states ("No meetings yet").

---

## 📹 Phase 3 — Meeting Creation & Pre-Join

> **Goal:** Create real meeting codes from backend. Validate meeting codes before joining.

### Steps:

**3.1 — Start Call Screen** (`start_call_screen.dart`)

| Action | API Call |
|---|---|
| "New Meeting" button | `POST /api/meetings/create { hostId }` → get `meeting_code` |
| "Join" button (enter code) | `GET /api/meeting/{code}` → validate it exists |

**3.2 — Pre-Join Screen** (`pre_join_screen.dart`)

- After validating the meeting code, display meeting info from the API response (host, feature flags).
- Check feature flags: if `camera_enabled: false`, disable camera toggle.
- "Join now" button → call `POST /api/participant/join { meetingId, userId }`.
- Then navigate to `MeetingRoomScreen` passing the validated `meeting_code` + `meetingId`.

**3.3 — Send Invite Notification**

- "Copy invite / Share" → call `POST /api/notifications/invite { email, meetingId, hostName }`.

---

## 🔴 Phase 4 — Signaling & WebRTC (Core Call)

> **Goal:** Real peer-to-peer audio/video using Socket.IO signaling + flutter_webrtc.

> ⚠️ This is the most complex phase. Take your time.

### Steps:

**4.1 — Create `SignalingService`** (`lib/core/services/signaling_service.dart`)

Responsibilities:
- Establish Socket.IO connection to `http://<IP>:4000`.
- Emit `join-meeting(code, userId, name, isNewMeeting)`.
- Handle all listen events: `join-confirmation`, `user-joined`, `user-left`, `offer`, `answer`, `ice-candidate`, etc.
- Expose streams/callbacks the `MeetingRoomScreen` can listen to.

**4.2 — Create `WebRTCService`** (`lib/core/services/webrtc_service.dart`)

Responsibilities:
- Create and manage `RTCPeerConnection` instances (one per remote participant).
- On `user-joined` → create peer conn → create offer → emit to signaling.
- On `offer` received → set remote SDP → create answer → emit back.
- On `answer` received → set remote SDP.
- On `ice-candidate` → add to peer conn.
- Expose local `MediaStream` and map of remote `MediaStream`s.

**4.3 — Rewrite `MeetingRoomScreen`**

- On screen init: start `SignalingService` + `WebRTCService`.
- Replace `_participantCount = 0` with a real `List<Participant>` from signaling events.
- Replace fake `_VideoGrid` images with real `RTCVideoRenderer` widgets.
- Waiting room: on `join-confirmation` status = `WAITING_FOR_APPROVAL`, show waiting UI.
- Host: on `request-to-join`, show Admit/Deny dialog → emit `admit-user` or `deny-user`.
- On `user-left` → close peer conn, remove from list.
- On `removed-from-meeting` / `join-denied` → navigate away.
- On `meeting-ended` → show end screen.

**4.4 — Host Controls**

Wire `_HostControlsView` buttons to real socket emits:

| UI Button | Socket Emit |
|---|---|
| Mute participant | `mute-user { socketId }` |
| Turn off camera | `camera-off-user { socketId }` |
| Remove from meeting | `remove-user { socketId }` |
| Assign co-host | `assign-cohost { peerId }` |
| Toggle screen share | PATCH `/api/meeting/{code}/settings` + `update-settings` emit |

**4.5 — Leave Meeting**

- On hangup → close all peer connections → emit socket disconnect.
- Call `POST /api/participant/leave { meetingId, userId }`.
- Navigate back to home.

---

## 💬 Phase 5 — In-Call Chat

> **Goal:** Real real-time chat using Socket.IO + REST persistence.

### Steps:

**5.1 — Create `ChatRepository`** (`lib/data/repositories/chat_repository.dart`)

| Method | Calls |
|---|---|
| `sendMessage(meetingId, senderId, senderName, content, recipientId?)` | `POST /api/chat/send` |
| `getMessages(meetingId, userId)` | `GET /api/chat/{meetingId}?userId={userId}` |
| `deleteMessage(messageId)` | `DELETE /api/chat/{messageId}` |

**5.2 — Create `ChatSocketService`** (`lib/core/services/chat_socket_service.dart`)

- Connect to Socket.IO at port `4005`.
- Emit `join-chat { meetingId, userId }`.
- Emit `chat:send { meetingId, senderId, senderName, content, recipientId }`.
- Listen `chat:receive` → add to local message list.
- Listen `chat:deleted` → remove from list.

**5.3 — Rewrite `_ChatView`** in `meeting_room_screen.dart`

- On open: call `GET /api/chat/{meetingId}?userId={userId}` to load history.
- New messages arrive via `chat:receive` socket event (real-time).
- On send: call `POST /api/chat/send` (persist) AND emit `chat:send` (real-time broadcast).
- Support private messages (DM tab) using `recipientId` field.

---

## 📅 Phase 6 — Scheduling

> **Goal:** Real meeting scheduling from the Schedule screen.

### Steps:

**6.1 — Create `SchedulingRepository`**

| Method | Calls |
|---|---|
| `scheduleM(hostId, title, startTime, endTime, recurrence, timezone)` | `POST /api/scheduling/schedule` |
| `getUserSchedules(userId)` | `GET /api/scheduling/user/{userId}` |
| `cancelSchedule(scheduleId)` | `DELETE /api/scheduling/{scheduleId}` |

**6.2 — Rewrite `ScheduleScreen`**

- "Schedule" form submit → call `SchedulingRepository.scheduleM()`.
- After scheduling → call `POST /api/notifications/reminder { userId, title, body }`.
- List view → call `getUserSchedules(userId)`.
- Swipe-to-delete card → call `cancelSchedule(scheduleId)`.

---

## 📼 Phase 7 — Recording

> **Goal:** Wire the recording consent flow and upload the recorded file.

### Steps:

**7.1 — Connect Recording Socket Events**

In `SignalingService`:
- `request-recording` emit → triggers consent dialog on all clients.
- `respond-recording { agree: true/false }` emit → send consent.
- `recording-started` listen → identify if you are the recorder (`recorderId == socket.id`).
- If you are the recorder → start `MediaRecorder` on the local stream.
- `recording-stopped` listen → stop recorder → upload blob.

**7.2 — Create `RecordingRepository`**

| Method | Calls |
|---|---|
| `startRecording(meetingId)` | `POST /api/recording/start/{meetingId}` |
| `stopRecording(meetingId)` | `POST /api/recording/stop/{meetingId}` |
| `uploadRecording(file, meetingId, recordedBy, duration)` | `POST /api/recording/upload` (multipart) |
| `getRecordings(meetingId)` | `GET /api/recording/{meetingId}` |

**7.3 — Rewrite `_HostControlsView` Recording Toggle**

- "Start Recording" → emit `request-recording`.
- Wait for `recording-started` event.
- On stop → `stop-recording` emit → listen `recording-stopped` → call `uploadRecording()`.

---

## 🔔 Phase 8 — Notifications

> **Goal:** Fetch and display real notifications for the logged-in user.

### Steps:

**8.1 — Fetch Notifications on App Start**

- On home screen load → call `GET /api/notifications/user/{userId}`.
- Display in a notifications panel/badge.

**8.2 — Mark as Read (Gap)**

> ⚠️ No mark-as-read endpoint exists in the swagger.
- **Option A:** Add a `PATCH /api/notifications/{id}/read` to backend.
- **Option B:** Track read state locally in `shared_preferences`.

---

## ⚙️ Phase 9 — Settings Screen

> **Goal:** Real profile updates and platform settings.

### Steps:

**9.1 — Profile Update**

- "Save" button in settings → call `POST /api/auth/update { name, password }`.
- **Avatar upload gap:** No avatar endpoint in swagger.
  - Add `POST /api/files/upload` with `uploaderId` and attach to user profile, OR
  - Ask backend to add `POST /api/auth/update-avatar`.

**9.2 — Feedback & Contact**

- "Send Feedback" → `POST /api/meeting/feedback { category, description, user_email }`.
- "Contact Support" → `POST /api/meeting/contact { first_name, last_name, email, message }`.

**9.3 — Logout**

- Clear JWT from `flutter_secure_storage`.
- Disconnect all sockets.
- Navigate to Login screen.
- (Optional) ask backend to add `POST /api/auth/logout` for server-side session revocation.

---

## 🛡️ Phase 10 — Admin Panel (Optional)

> Only implement this if you are building an admin screen in the mobile app.

All endpoints are under `GET/POST/PUT/DELETE /api/admin/...` on port `4011`:
- Dashboard stats, user management, meetings management, abuse reports, feedback list, subscription plans, analytics.

---

## 🚨 Known Gaps (APIs You Need to Ask Backend to Add)

| Missing Feature | Suggested Endpoint | Priority |
|---|---|---|
| List users / contacts | `GET /api/users?search=` | 🔴 High |
| OAuth (Google/Apple sign-in) | `POST /api/auth/oauth` | 🟡 Medium |
| Server-side logout | `POST /api/auth/logout` | 🟡 Medium |
| Mark notification as read | `PATCH /api/notifications/{id}/read` | 🟡 Medium |
| Update avatar/profile photo | `POST /api/auth/update-avatar` | 🟡 Medium |
| Two-factor auth | `POST /api/auth/2fa/verify` | 🟢 Low |

---

## 🧪 Testing Checklist (Do After Each Phase)

- [ ] **Phase 1:** Login with a real account, see JWT in secure storage, `/me` works.
- [ ] **Phase 2:** Home screen shows real scheduled meetings and call history.
- [ ] **Phase 3:** Create meeting → get real code → join meeting → participant logged in DB.
- [ ] **Phase 4:** Two devices on same WiFi → both join meeting → can see and hear each other.
- [ ] **Phase 5:** Send chat message → visible on both devices in real time.
- [ ] **Phase 6:** Schedule meeting → appears in home screen list → cancel removes it.
- [ ] **Phase 7:** Start recording → all consent → recording uploaded to R2 → URL in DB.
- [ ] **Phase 8:** Invite notification email logged in backend console.
- [ ] **Phase 9:** Change name → reflected in next `GET /api/auth/me`.

---

## 🔢 Recommended Implementation Order

```
Phase 0  →  Phase 1  →  Phase 2  →  Phase 3  →  Phase 4
  ↓
Phase 5  →  Phase 6  →  Phase 7  →  Phase 8  →  Phase 9
  ↓
Phase 10 (optional)
```

> ✅ Complete and test each phase before moving to the next.
> ✅ Run `flutter run` after each phase and verify the feature end-to-end.
> ✅ Use Postman or curl to verify backend endpoints are working **before** wiring them to Flutter.

---

*— End of Mizdah Implementation Plan —*
*Generated 2026-02-24*
