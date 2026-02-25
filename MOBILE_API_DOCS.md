# 📱 Mobile App API Documentation — Newmeet (Google Meet Clone)

> **Last Updated:** 2026-02-24  
> **Base URL (Gateway):** `http://192.168.1.24:3000`  
> **All HTTP APIs go through the Next.js gateway** — do NOT call microservice ports directly from the mobile app.

---

## 🔧 Setup for Mobile App

| Item | Value |
|------|-------|
| **API Base URL** | `http://192.168.1.24:3000` |
| **Auth Method** | `Authorization: Bearer <JWT_TOKEN>` header |
| **Content-Type** | `application/json` |
| **Signaling URL** | `http://192.168.1.24:4000` (Socket.IO, direct) |
| **WebRTC Package (Flutter)** | `flutter_webrtc` |
| **Socket.IO Package (Flutter)** | `socket_io_client` |

> **To find your PC IP:** Run `ipconfig` → look for IPv4 Address (e.g. `192.168.1.5`)

---

## 📊 Quick Summary

| Service | HTTP APIs | Required? |
|---------|-----------|-----------|
| Auth Service | 4 | ✅ Core |
| Meeting Service | 9 | ✅ Core |
| Participant Service | 4 | ✅ Core |
| Chat Service | 3 | ✅ In-Meeting |
| Notification Service | 3 | ✅ Invites & Reminders |
| Scheduling Service | 3 | ✅ Calendar/Scheduled Calls |
| Recording Service | 5 | ✅ If Recordings Enabled |
| File Service | 2 | ✅ Attachments in Chat |
| History Service | 1 | ✅ Auto (called by server) |
| **Signaling (Socket.IO)** | **14 events** | ✅ Video Call Core |
| **Total HTTP APIs** | **34** | |
| **Total Socket Events** | **14** | |
| **GRAND TOTAL** | **48** | |

---

## 🔐 1. Auth Service
**Port:** `4004` | **Gateway Prefix:** `/api/auth`

> Handles user registration, login, profile fetch and updates.  
> After login/signup, store the JWT token and send it in every subsequent request header.

---

### 1.1 Sign Up
```
POST /api/auth/signup
```
**Body:**
```json
{
  "email": "user@example.com",
  "password": "mypassword",
  "name": "John Doe"
}
```
**Response:**
```json
{
  "token": "<JWT_TOKEN>",
  "user": {
    "id": "uuid",
    "email": "user@example.com",
    "name": "John Doe",
    "role": "USER"
  }
}
```
**Errors:** `400` if email exists or password < 5 chars

---

### 1.2 Login
```
POST /api/auth/login
```
**Body:**
```json
{
  "email": "user@example.com",
  "password": "mypassword"
}
```
**Response:**
```json
{
  "token": "<JWT_TOKEN>",
  "user": { "id": "uuid", "email": "...", "name": "...", "role": "USER" }
}
```
**Errors:** `401` if credentials are invalid

---

### 1.3 Get Current User
```
GET /api/auth/me
Headers: Authorization: Bearer <JWT_TOKEN>
```
**Response:**
```json
{
  "user": { "id": "uuid", "email": "...", "name": "...", "role": "USER" }
}
```
> Returns `{ "user": null }` if token is invalid (does NOT return 401)

---

### 1.4 Update Profile
```
POST /api/auth/update
Headers: Authorization: Bearer <JWT_TOKEN>
```
**Body (send only fields you want to update):**
```json
{
  "name": "New Name",
  "password": "newpassword"
}
```
**Response:**
```json
{
  "user": { "id": "uuid", "email": "...", "name": "New Name", "role": "USER" }
}
```

---

## 📹 2. Meeting Service
**Port:** `4001` | **Gateway Prefix:** `/api/meeting` and `/api/meetings`

> Core meeting management — create, join, configure meetings.

---

### 2.1 Create Meeting
```
POST /api/meetings/create
```
**Body (optional):**
```json
{
  "hostId": "user-uuid",
  "id": "custom-code"
}
```
> If `id` is omitted, a random code like `abc-defg-hij` is generated.

**Response:**
```json
{
  "id": "uuid",
  "meeting_code": "abc-defg-hij",
  "host_id": "user-uuid",
  "private_chat_enabled": true,
  "general_chat_enabled": true,
  "whiteboard_enabled": true,
  "screenshare_enabled": true,
  "reactions_enabled": true,
  "camera_enabled": true,
  "created_at": "2026-02-24T..."
}
```

---

### 2.2 Join Meeting (Get Meeting Info)
```
GET /api/meetings/join?code=abc-defg-hij
```
> OR

```
GET /api/meeting/abc-defg-hij
```
**Response:** Same meeting object as above. Returns `404` if not found.

---

### 2.3 Get Meetings by Host
```
GET /api/meetings/user/{userId}
```
**Response:** Array of meeting objects, ordered newest first.

---

### 2.4 Update Meeting Settings
```
PATCH /api/meeting/{meetingCode}/settings
```
**Body (send only fields to change):**
```json
{
  "private_chat_enabled": false,
  "screenshare_enabled": true,
  "camera_enabled": true,
  "general_chat_enabled": true,
  "whiteboard_enabled": false,
  "reactions_enabled": true
}
```
**Response:** Updated meeting object.

---

### 2.5 Get Global System Settings
```
GET /api/meeting/settings
```
**Response:**
```json
{
  "id": 1,
  "max_participants": 100,
  "meeting_time_limit": 60,
  "allow_recordings": true,
  "updated_at": "2026-02-24T..."
}
```

---

### 2.6 Update Global System Settings *(Admin only)*
```
POST /api/meeting/settings
```
**Body:**
```json
{
  "max_participants": 50,
  "meeting_time_limit": 45,
  "allow_recordings": false
}
```

---

### 2.7 Submit Feedback
```
POST /api/meeting/feedback
```
**Body:**
```json
{
  "category": "Audio Quality",
  "description": "Echo during the call",
  "user_email": "user@example.com"
}
```
**Response:** `201` with submitted data.

---

### 2.8 Contact / Support Form
```
POST /api/meeting/contact
```
**Body:**
```json
{
  "first_name": "John",
  "last_name": "Doe",
  "email": "john@example.com",
  "message": "I need help with my account"
}
```
**Response:** `201` with `{ "message": "Message sent successfully", "data": {...} }`

---

### 2.9 Report Abuse
```
POST /api/meeting/report-abuse
```
**Body:**
```json
{
  "abuse_type": "Harassment",
  "abuser_names": "John Doe",
  "description": "Was using offensive language",
  "meeting_id": "abc-defg-hij"
}
```
**Response:** `201` with the report data.

---

## 👥 3. Participant Service
**Port:** `4002` | **Gateway Prefix:** `/api/participant`

> Tracks who joined/left meetings. Call these alongside the Socket.IO events.

---

### 3.1 Log Participant Join
```
POST /api/participant/join
```
**Body:**
```json
{
  "meetingId": "meeting-uuid",
  "userId": "user-uuid"
}
```
**Response:** Participant record with `joined_at` timestamp.

---

### 3.2 Log Participant Leave
```
POST /api/participant/leave
```
**Body:**
```json
{
  "meetingId": "meeting-uuid",
  "userId": "user-uuid"
}
```
**Response:** `{ "status": "Left" }`

---

### 3.3 Get User's Meeting History (Participant Records)
```
GET /api/participant/user/{userId}
```
**Response:** Array of participant records (all meetings this user joined), newest first.

---

### 3.4 Get Participants in a Meeting
```
GET /api/participant/{meetingId}
```
**Response:** Array of all participants currently/previously in the meeting.

---

## 💬 4. Chat Service
**Port:** `4005` | **Gateway Prefix:** `/api/chat`

> Persistent in-meeting chat (messages saved to DB). Also supports private (DM) messages.

---

### 4.1 Send Message
```
POST /api/chat/send
```
**Body (public message):**
```json
{
  "meetingId": "meeting-uuid",
  "senderId": "user-uuid",
  "senderName": "John Doe",
  "content": "Hello everyone!"
}
```
**Body (private message):**
```json
{
  "meetingId": "meeting-uuid",
  "senderId": "user-uuid",
  "senderName": "John Doe",
  "content": "Hey, just you and me",
  "recipientId": "other-user-uuid",
  "recipientName": "Jane Doe",
  "attachmentUrl": null
}
```
**Response:** Message object with `id`, `createdAt`, etc.

---

### 4.2 Get Messages for a Meeting
```
GET /api/chat/{meetingId}?userId={currentUserId}
```
> `userId` query param is used to filter private messages — only returns messages the user can see.

**Response:** Array of message objects ordered by `createdAt` ascending.

---

### 4.3 Delete Message
```
DELETE /api/chat/{messageId}
```
**Response:** `{ "status": "Message deleted" }`

---

## 🔔 5. Notification Service
**Port:** `4008` | **Gateway Prefix:** `/api/notifications`

> Handles meeting invites and reminders.

---

### 5.1 Send Meeting Invite
```
POST /api/notifications/invite
```
**Body:**
```json
{
  "userId": "recipient-user-uuid",
  "meetingCode": "abc-defg-hij",
  "message": "You're invited to join my meeting!"
}
```
**Response:** Notification record.

---

### 5.2 Send Meeting Reminder
```
POST /api/notifications/reminder
```
**Body:**
```json
{
  "userId": "user-uuid",
  "scheduleId": "schedule-uuid",
  "message": "Your meeting starts in 15 minutes"
}
```
**Response:** Notification record.

---

### 5.3 Get User Notifications
```
GET /api/notifications/user/{userId}
```
**Response:** Array of notification objects for this user.

---

## 📅 6. Scheduling Service
**Port:** `4009` | **Gateway Prefix:** `/api/scheduling`

> Schedule future meetings with title, time, recurrence, and timezone.

---

### 6.1 Create Schedule
```
POST /api/scheduling/schedule
```
**Body:**
```json
{
  "hostId": "user-uuid",
  "title": "Weekly Team Standup",
  "startTime": "2026-02-25T09:00:00Z",
  "endTime": "2026-02-25T09:30:00Z",
  "recurrence": "weekly",
  "timezone": "Asia/Kolkata"
}
```
**Response:** Schedule object with `id`, `meetingId` (auto-generated code), timestamps.

---

### 6.2 Get User's Scheduled Meetings
```
GET /api/scheduling/user/{userId}
```
**Response:** Array of schedule objects ordered by `startTime` ascending.

---

### 6.3 Delete / Cancel Schedule
```
DELETE /api/scheduling/{scheduleId}
```
**Response:** `{ "status": "Schedule deleted" }`

---

## 📼 7. Recording Service
**Port:** `4007` | **Gateway Prefix:** `/api/recording`

> Start, stop, and retrieve recordings. Files are stored in Cloudflare R2.

---

### 7.1 Start Recording
```
POST /api/recording/start/{meetingId}
```
**Response:** Recording record with `id`, `meetingId`, `startedAt`.

---

### 7.2 Stop Recording
```
POST /api/recording/stop/{meetingId}
```
**Response:** Updated recording record.

---

### 7.3 Upload Recording File
```
POST /api/recording/upload
Content-Type: multipart/form-data

Form field: "recording" → video file (mp4, webm, etc.)
```
**Response:** Recording record with `fileUrl` pointing to R2 storage.

---

### 7.4 Get Recordings for a Meeting
```
GET /api/recording/{meetingId}
```
**Response:** Array of recording objects for that meeting.

---

### 7.5 Get All Recordings *(Admin)*
```
GET /api/recording/
```
**Response:** Array of all recordings across all meetings.

---

## 📁 8. File Service
**Port:** `4010` | **Gateway Prefix:** `/api/files`

> Upload and retrieve files/attachments shared in chat.

---

### 8.1 Upload File
```
POST /api/files/upload
Content-Type: multipart/form-data

Form field: "file" → any file (image, pdf, doc, etc.)
```
**Response:**
```json
{
  "id": "file-uuid",
  "fileUrl": "https://...",
  "fileName": "document.pdf",
  "fileSize": 102400,
  "mimeType": "application/pdf"
}
```
> Save the `fileUrl` or `id` and attach it to a chat message using `attachmentUrl`.

---

### 8.2 Get File
```
GET /api/files/{fileId}
```
**Response:** File metadata object with download URL.

---

## 📖 9. History Service
**Port:** `4003` | **Gateway Prefix:** `/api/history`

> Stores call duration and end time. Called **automatically** by the signaling server when a meeting ends — you don't need to call this from the mobile app manually.

---

### 9.1 Store Call History *(Auto-called by server)*
```
POST /api/history/store
```
**Body:**
```json
{
  "meetingId": "abc-defg-hij",
  "duration": 1800,
  "endedAt": "2026-02-24T11:30:00Z"
}
```
**Response:** History record.

---

## 🔴 10. Real-Time Signaling — Socket.IO
**URL:** `http://192.168.1.24:4000`  
**Package (Flutter):** [`socket_io_client`](https://pub.dev/packages/socket_io_client)

> This is the **heart of the video call**. WebRTC signaling, participant tracking, reactions, captions, and timers all go through here.

---

### Connection
```dart
// Flutter example
import 'package:socket_io_client/socket_io_client.dart' as IO;

IO.Socket socket = IO.io('http://192.168.1.x:4000', <String, dynamic>{
  'transports': ['websocket'],
  'autoConnect': false,
});
socket.connect();
```

---

### 10.1 Events You EMIT (App → Server)

| Event Name | Payload | Purpose |
|-----------|---------|---------|
| `joinMeeting` | `{ meetingId, userId, name, isHost }` | Join a meeting room |
| `offer` | `{ to: socketId, offer: RTCSessionDescription }` | Send WebRTC offer |
| `answer` | `{ to: socketId, answer: RTCSessionDescription }` | Send WebRTC answer |
| `ice-candidate` | `{ to: socketId, candidate: RTCIceCandidate }` | Send ICE candidate |
| `liveCaption` | `{ meetingId, caption: "text..." }` | Broadcast live caption |
| `sendReaction` | `{ meetingId, reaction: "👍", userId }` | Send emoji reaction |
| `requestRecording` | `{ meetingId }` | Request recording to start |
| `leaveMeeting` | `{ meetingId, userId }` | Leave the meeting room |

---

### 10.2 Events You LISTEN (Server → App)

| Event Name | Payload | Purpose |
|-----------|---------|---------|
| `userJoined` | `{ socketId, userId, name, isHost }` | A new user joined — initiate WebRTC offer |
| `userLeft` | `{ socketId, userId, name }` | A user left — remove their video tile |
| `receiveOffer` | `{ from: socketId, offer: RTCSessionDescription }` | Received WebRTC offer — send answer |
| `receiveAnswer` | `{ from: socketId, answer: RTCSessionDescription }` | Received WebRTC answer |
| `receiveIceCandidate` | `{ from: socketId, candidate: RTCIceCandidate }` | Received ICE candidate |
| `meetingEnded` | `{ meetingId }` | Host ended the meeting — close screen |
| `liveCaption` | `{ userId, caption: "text..." }` | Someone's live speech caption |
| `reactionReceived` | `{ userId, reaction: "👍" }` | Show emoji reaction on screen |
| `timerWarning` | `{ minutesLeft: 5 }` | Meeting time limit approaching |
| `existingParticipants` | `[{ socketId, userId, name }]` | List of already-joined users when you join |

---

## 🗺️ Full Meeting Flow (How to use the APIs together)

```
1. User signs up/logs in           → POST /api/auth/signup or /api/auth/login
                                     Save JWT token

2. Create or join a meeting        → POST /api/meetings/create  (host)
                                     GET  /api/meeting/{code}   (guest)

3. Log participation in DB         → POST /api/participant/join

4. Connect to Socket.IO            → socket.connect() to port 4000
                                     Emit: joinMeeting

5. WebRTC negotiation              → Listen: userJoined → emit offer
                                     Listen: receiveOffer → emit answer
                                     Listen/emit: ice-candidate

6. During meeting                  → POST /api/chat/send (chat messages)
                                     Emit: liveCaption / sendReaction

7. Recording (optional)            → POST /api/recording/start/{meetingId}
                                     POST /api/recording/stop/{meetingId}

8. Leave meeting                   → Emit: leaveMeeting
                                     POST /api/participant/leave

9. After meeting (auto by server)  → POST /api/history/store
```

---

## ⚠️ Important Notes

1. **No `PORT` in base URL** — always use `http://<IP>:3000` (the gateway). Do NOT call ports like 4001, 4002 directly.
2. **JWT Token** — store securely (use `flutter_secure_storage`). Attach to every authenticated request.
3. **Meeting code format** — uses `xxx-xxxx-xxx` pattern (e.g. `abc-defg-hij`). This is what you share with other users to join.
4. **Socket.IO only** — the Signaling Service (`port 4000`) is **Socket.IO only**, not REST HTTP.
5. **R2 Storage** — recording and file uploads require Cloudflare R2 credentials in `.env`. Without them, uploads will fail.
6. **multiSchema** — the DB uses PostgreSQL schemas (`auth`, `meeting`, `participant`, etc.). Prisma handles this transparently.
7. **Admin APIs** — endpoints under `/api/admin/` (users, reports, plans, analytics) are only needed if you build an admin module in the app.

---

## 🌐 Admin API Endpoints (Optional — For Admin Panel)
**Port:** `4011` | **Gateway Prefix:** `/api/admin`

| Method | Endpoint | Purpose |
|--------|----------|---------|
| `GET` | `/api/admin/stats` | Dashboard stats (users, meetings, active, etc.) |
| `GET` | `/api/admin/users` | List all users |
| `POST` | `/api/admin/users` | Create a user |
| `PUT` | `/api/admin/users/{id}` | Update a user |
| `DELETE` | `/api/admin/users/{id}` | Delete a user |
| `GET` | `/api/admin/meetings` | List all meetings with enriched data |
| `GET` | `/api/admin/meetings/{id}` | Get single meeting with participants |
| `POST` | `/api/admin/meetings/{id}/end` | Force-end a meeting |
| `GET` | `/api/admin/reports` | List abuse reports |
| `GET` | `/api/admin/feedbacks` | List all feedback submissions |
| `GET` | `/api/admin/queries` | List support queries |
| `PUT` | `/api/admin/queries/{id}/status` | Update support query status |
| `GET` | `/api/admin/plans` | List subscription plans |
| `POST` | `/api/admin/plans` | Create a plan |
| `PUT` | `/api/admin/plans/{id}` | Update a plan |
| `DELETE` | `/api/admin/plans/{id}` | Delete a plan |
| `GET` | `/api/admin/languages` | List supported languages |
| `POST` | `/api/admin/languages` | Add/update a language |
| `DELETE` | `/api/admin/languages/{id}` | Delete a language |
| `GET` | `/api/admin/analytics/summary` | Hourly/daily meeting volume & abuse stats |
| `GET` | `/api/admin/analytics/latency` | API latency metrics |
| `GET` | `/api/admin/logs/audit` | Audit logs (signups, logins, deletes, etc.) |

---

*Generated from codebase analysis of the newmeet project — 2026-02-24*
