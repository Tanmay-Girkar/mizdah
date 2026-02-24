# 🚀 Newmeet — Flutter Developer API Reference (Swagger Style)

> Generated: 2026-02-24 | Version: 1.0.0
> **Hand this file to your Flutter developer.**

---

## 🌐 Base URLs

| Environment | Base URL |
|-------------|----------|
| **Local (same PC)** | `http://localhost:3000` |
| **Local Network (mobile on WiFi)** | `http://<YOUR_PC_IP>:3000` |
| **Signaling (Socket.IO — Direct)** | `http://<YOUR_PC_IP>:4000` |

> Find your PC IP: run `ipconfig` → look for **IPv4 Address** (e.g. `192.168.1.10`)

---

## 🔐 Authentication

All protected endpoints require a Bearer token in the header:

```
Authorization: Bearer <JWT_TOKEN>
```

Tokens are returned from `/api/auth/signup` and `/api/auth/login`.

---

## 📦 Flutter Packages Needed

```yaml
dependencies:
  http: ^1.2.0
  socket_io_client: ^2.0.3+1
  flutter_webrtc: ^0.10.7
  flutter_secure_storage: ^9.0.0
```

---
---

# 🔐 AUTH SERVICE
**Prefix:** `/api/auth` — Port `4004`

---

## POST `/api/auth/signup`
Register a new user account.

**Headers:** `Content-Type: application/json`

**Body Parameters:**
| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `email` | string | ✅ | User email address |
| `password` | string | ✅ | Min 5 characters |
| `name` | string | ❌ | Display name |

**cURL:**
```bash
curl -X POST http://localhost:3000/api/auth/signup \
  -H "Content-Type: application/json" \
  -d '{"email":"john@example.com","password":"pass123","name":"John Doe"}'
```

**✅ 200 Response:**
```json
{
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "user": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "email": "john@example.com",
    "name": "John Doe",
    "role": "USER"
  }
}
```

**❌ 400 Response:**
```json
{ "error": "Email already exists" }
```
```json
{ "error": "Password must be at least 5 characters long" }
```

---

## POST `/api/auth/login`
Login and receive a JWT token.

**Headers:** `Content-Type: application/json`

**Body Parameters:**
| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `email` | string | ✅ | Registered email |
| `password` | string | ✅ | Account password |

**cURL:**
```bash
curl -X POST http://localhost:3000/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"john@example.com","password":"pass123"}'
```

**✅ 200 Response:**
```json
{
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "user": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "email": "john@example.com",
    "name": "John Doe",
    "role": "USER"
  }
}
```

**❌ 401 Response:**
```json
{ "error": "Invalid credentials" }
```

---

## GET `/api/auth/me`
Get the currently authenticated user's profile.

**Headers:** `Authorization: Bearer <JWT_TOKEN>`

**cURL:**
```bash
curl -X GET http://localhost:3000/api/auth/me \
  -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
```

**✅ 200 Response:**
```json
{
  "user": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "email": "john@example.com",
    "name": "John Doe",
    "role": "USER"
  }
}
```

> Returns `{ "user": null }` if token is missing or invalid (not a 401).

---

## POST `/api/auth/update`
Update name or password of the logged-in user.

**Headers:** `Authorization: Bearer <TOKEN>`, `Content-Type: application/json`

**Body Parameters:**
| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | ❌ | New display name |
| `password` | string | ❌ | New password (min 5 chars) |

**cURL:**
```bash
curl -X POST http://localhost:3000/api/auth/update \
  -H "Authorization: Bearer <TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"name":"John Updated","password":"newpass123"}'
```

**✅ 200 Response:**
```json
{
  "user": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "email": "john@example.com",
    "name": "John Updated",
    "role": "USER"
  }
}
```

---
---

# 📹 MEETING SERVICE
**Prefix:** `/api/meetings` and `/api/meeting` — Port `4001`

---

## POST `/api/meetings/create`
Create a new meeting room.

**Headers:** `Content-Type: application/json`

**Body Parameters:**
| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `hostId` | string | ❌ | User ID of host |
| `id` | string | ❌ | Custom meeting code. Auto-generated if omitted |

**cURL:**
```bash
curl -X POST http://localhost:3000/api/meetings/create \
  -H "Content-Type: application/json" \
  -d '{"hostId":"550e8400-e29b-41d4-a716-446655440000"}'
```

**✅ 200 Response:**
```json
{
  "id": "a1b2c3d4-...",
  "meeting_code": "abc-defg-hij",
  "host_id": "550e8400-e29b-41d4-a716-446655440000",
  "private_chat_enabled": true,
  "general_chat_enabled": true,
  "whiteboard_enabled": true,
  "screenshare_enabled": true,
  "reactions_enabled": true,
  "camera_enabled": true,
  "created_at": "2026-02-24T05:30:00.000Z"
}
```

---

## GET `/api/meeting/{meetingCode}`
Get meeting details by code.

**URL Parameters:**
| Param | Type | Description |
|-------|------|-------------|
| `meetingCode` | string | The meeting code e.g. `abc-defg-hij` |

**cURL:**
```bash
curl -X GET http://localhost:3000/api/meeting/abc-defg-hij
```

**✅ 200 Response:** Same as create response above.
**❌ 404:** `{ "error": "Meeting not found" }`

---

## GET `/api/meetings/user/{userId}`
Get all meetings hosted by a specific user.

**URL Parameters:**
| Param | Type | Description |
|-------|------|-------------|
| `userId` | string | The host's user ID |

**cURL:**
```bash
curl -X GET http://localhost:3000/api/meetings/user/550e8400-e29b-41d4-a716-446655440000
```

**✅ 200 Response:**
```json
[
  {
    "id": "a1b2c3d4-...",
    "meeting_code": "abc-defg-hij",
    "host_id": "550e8400-...",
    "created_at": "2026-02-24T05:30:00.000Z"
  }
]
```

---

## PATCH `/api/meeting/{meetingCode}/settings`
Update in-meeting feature toggles (host only).

**URL Parameters:**
| Param | Type | Description |
|-------|------|-------------|
| `meetingCode` | string | The meeting code |

**Body Parameters (all optional):**
| Field | Type | Description |
|-------|------|-------------|
| `private_chat_enabled` | boolean | Allow private chat |
| `general_chat_enabled` | boolean | Allow public chat |
| `whiteboard_enabled` | boolean | Allow whiteboard |
| `screenshare_enabled` | boolean | Allow screen sharing |
| `reactions_enabled` | boolean | Allow emoji reactions |
| `camera_enabled` | boolean | Allow camera |

**cURL:**
```bash
curl -X PATCH http://localhost:3000/api/meeting/abc-defg-hij/settings \
  -H "Content-Type: application/json" \
  -d '{"screenshare_enabled":false,"reactions_enabled":true}'
```

**✅ 200 Response:** Updated meeting object.

---

## GET `/api/meeting/settings`
Get global platform settings (max participants, time limit, etc.).

**cURL:**
```bash
curl -X GET http://localhost:3000/api/meeting/settings
```

**✅ 200 Response:**
```json
{
  "id": 1,
  "max_participants": 100,
  "meeting_time_limit": 60,
  "allow_recordings": true,
  "updated_at": "2026-02-24T05:30:00.000Z"
}
```

---

## POST `/api/meeting/settings`
Update global platform settings (admin).

**Body Parameters:**
| Field | Type | Description |
|-------|------|-------------|
| `max_participants` | number | Max users per meeting |
| `meeting_time_limit` | number | Minutes before auto-end |
| `allow_recordings` | boolean | Allow recording feature |

**cURL:**
```bash
curl -X POST http://localhost:3000/api/meeting/settings \
  -H "Content-Type: application/json" \
  -d '{"max_participants":50,"meeting_time_limit":45,"allow_recordings":true}'
```

**✅ 200 Response:** Updated settings object.

---

## POST `/api/meeting/feedback`
Submit post-call feedback.

**Body Parameters:**
| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `category` | string | ✅ | Feedback category (e.g. "Audio Quality") |
| `description` | string | ✅ | Detailed feedback |
| `user_email` | string | ❌ | User's email |

**cURL:**
```bash
curl -X POST http://localhost:3000/api/meeting/feedback \
  -H "Content-Type: application/json" \
  -d '{"category":"Video Quality","description":"Lag during screen share","user_email":"john@example.com"}'
```

**✅ 201 Response:**
```json
{
  "category": "Video Quality",
  "description": "Lag during screen share",
  "user_email": "john@example.com"
}
```

---

## POST `/api/meeting/contact`
Submit a support/contact form.

**Body Parameters:**
| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `first_name` | string | ✅ | First name |
| `last_name` | string | ✅ | Last name |
| `email` | string | ✅ | Contact email |
| `message` | string | ✅ | Support message |

**cURL:**
```bash
curl -X POST http://localhost:3000/api/meeting/contact \
  -H "Content-Type: application/json" \
  -d '{"first_name":"John","last_name":"Doe","email":"john@example.com","message":"Need help"}'
```

**✅ 201 Response:**
```json
{
  "message": "Message sent successfully",
  "data": {
    "first_name": "John",
    "last_name": "Doe",
    "email": "john@example.com",
    "message": "Need help",
    "status": "pending"
  }
}
```

---

## POST `/api/meeting/report-abuse`
Report abusive behavior during a meeting.

**Body Parameters:**
| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `abuse_type` | string | ✅ | Type e.g. "Harassment", "Spam" |
| `abuser_names` | string | ✅ | Name(s) of abuser(s) |
| `description` | string | ✅ | What happened |
| `meeting_id` | string | ❌ | Meeting code where it occurred |

**cURL:**
```bash
curl -X POST http://localhost:3000/api/meeting/report-abuse \
  -H "Content-Type: application/json" \
  -d '{"abuse_type":"Harassment","abuser_names":"Bad Actor","description":"Used offensive language","meeting_id":"abc-defg-hij"}'
```

**✅ 201 Response:**
```json
{
  "id": "report-uuid",
  "abuse_type": "Harassment",
  "abuser_names": "Bad Actor",
  "description": "Used offensive language",
  "meeting_id": "abc-defg-hij"
}
```

---
---

# 👥 PARTICIPANT SERVICE
**Prefix:** `/api/participant` — Port `4002`

---

## POST `/api/participant/join`
Log that a user has joined a meeting (call this alongside the Socket.IO join).

**Body Parameters:**
| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `meetingId` | string | ✅ | Meeting UUID (from meeting object `id`) |
| `userId` | string | ✅ | User UUID |

**cURL:**
```bash
curl -X POST http://localhost:3000/api/participant/join \
  -H "Content-Type: application/json" \
  -d '{"meetingId":"a1b2c3d4-...","userId":"550e8400-..."}'
```

**✅ 200 Response:**
```json
{
  "id": "participant-uuid",
  "meeting_id": "a1b2c3d4-...",
  "user_id": "550e8400-...",
  "joined_at": "2026-02-24T05:30:00.000Z",
  "left_at": null
}
```

---

## POST `/api/participant/leave`
Log that a user has left a meeting.

**Body Parameters:**
| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `meetingId` | string | ✅ | Meeting UUID |
| `userId` | string | ✅ | User UUID |

**cURL:**
```bash
curl -X POST http://localhost:3000/api/participant/leave \
  -H "Content-Type: application/json" \
  -d '{"meetingId":"a1b2c3d4-...","userId":"550e8400-..."}'
```

**✅ 200 Response:**
```json
{ "status": "Left" }
```

---

## GET `/api/participant/user/{userId}`
Get all meetings a user has ever participated in.

**URL Parameters:**
| Param | Type | Description |
|-------|------|-------------|
| `userId` | string | User UUID |

**cURL:**
```bash
curl -X GET http://localhost:3000/api/participant/user/550e8400-e29b-41d4-a716-446655440000
```

**✅ 200 Response:**
```json
[
  {
    "id": "participant-uuid",
    "meeting_id": "a1b2c3d4-...",
    "user_id": "550e8400-...",
    "joined_at": "2026-02-24T05:30:00.000Z",
    "left_at": "2026-02-24T06:00:00.000Z"
  }
]
```

---

## GET `/api/participant/{meetingId}`
Get all participants in a specific meeting.

**URL Parameters:**
| Param | Type | Description |
|-------|------|-------------|
| `meetingId` | string | Meeting UUID |

**cURL:**
```bash
curl -X GET http://localhost:3000/api/participant/a1b2c3d4-e29b-41d4-a716-446655440000
```

**✅ 200 Response:** Array of participant objects.

---
---

# 💬 CHAT SERVICE
**Prefix:** `/api/chat` — Port `4005`

---

## POST `/api/chat/send`
Send a public or private chat message.

**Body Parameters:**
| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `meetingId` | string | ✅ | Meeting UUID |
| `senderId` | string | ✅ | Sender's user UUID |
| `senderName` | string | ✅ | Sender's display name |
| `content` | string | ✅ | Message text |
| `recipientId` | string | ❌ | For private DM: recipient user UUID |
| `recipientName` | string | ❌ | For private DM: recipient name |
| `attachmentUrl` | string | ❌ | URL of attached file |

**cURL (public):**
```bash
curl -X POST http://localhost:3000/api/chat/send \
  -H "Content-Type: application/json" \
  -d '{"meetingId":"a1b2c3d4-...","senderId":"550e8400-...","senderName":"John","content":"Hello everyone!"}'
```

**cURL (private DM):**
```bash
curl -X POST http://localhost:3000/api/chat/send \
  -H "Content-Type: application/json" \
  -d '{"meetingId":"a1b2c3d4-...","senderId":"550e8400-...","senderName":"John","content":"Hey!","recipientId":"other-uuid","recipientName":"Jane"}'
```

**✅ 200 Response:**
```json
{
  "id": "msg-uuid",
  "meetingId": "a1b2c3d4-...",
  "senderId": "550e8400-...",
  "senderName": "John",
  "recipientId": null,
  "recipientName": null,
  "content": "Hello everyone!",
  "attachmentUrl": null,
  "createdAt": "2026-02-24T05:31:00.000Z"
}
```

---

## GET `/api/chat/{meetingId}?userId={userId}`
Get all messages in a meeting (public + messages sent to/from the user).

**URL Parameters:**
| Param | Type | Description |
|-------|------|-------------|
| `meetingId` | string | Meeting UUID |

**Query Parameters:**
| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `userId` | string | ✅ | Current user UUID (filters private messages) |

**cURL:**
```bash
curl -X GET "http://localhost:3000/api/chat/a1b2c3d4-e29b-41d4-a716-446655440000?userId=550e8400-e29b-41d4-a716-446655440000"
```

**✅ 200 Response:** Array of message objects, ordered by `createdAt` ascending.

---

## DELETE `/api/chat/{messageId}`
Delete a chat message.

**URL Parameters:**
| Param | Type | Description |
|-------|------|-------------|
| `messageId` | string | Message UUID |

**cURL:**
```bash
curl -X DELETE http://localhost:3000/api/chat/msg-uuid-here
```

**✅ 200 Response:**
```json
{ "status": "Message deleted" }
```

---
---

# 🔔 NOTIFICATION SERVICE
**Prefix:** `/api/notifications` — Port `4008`

---

## POST `/api/notifications/invite`
Send a meeting invite (logs to console, no real email in dev mode).

**Body Parameters:**
| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `email` | string | ✅ | Recipient's email address |
| `meetingId` | string | ✅ | Meeting code (e.g. `abc-defg-hij`) |
| `hostName` | string | ✅ | Host's display name |

**cURL:**
```bash
curl -X POST http://localhost:3000/api/notifications/invite \
  -H "Content-Type: application/json" \
  -d '{"email":"jane@example.com","meetingId":"abc-defg-hij","hostName":"John Doe"}'
```

**✅ 200 Response:**
```json
{ "status": "Invite sent (logged to console)" }
```

---

## POST `/api/notifications/reminder`
Create a reminder notification for a user.

**Body Parameters:**
| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `userId` | string | ✅ | Recipient's user UUID |
| `title` | string | ✅ | Notification title |
| `body` | string | ✅ | Notification body text |

**cURL:**
```bash
curl -X POST http://localhost:3000/api/notifications/reminder \
  -H "Content-Type: application/json" \
  -d '{"userId":"550e8400-...","title":"Meeting in 15 minutes","body":"Your Weekly Standup starts soon"}'
```

**✅ 200 Response:**
```json
{
  "id": "notif-uuid",
  "userId": "550e8400-...",
  "type": "REMINDER",
  "title": "Meeting in 15 minutes",
  "body": "Your Weekly Standup starts soon",
  "createdAt": "2026-02-24T05:30:00.000Z"
}
```

---

## GET `/api/notifications/user/{userId}`
Get all notifications for a user.

**URL Parameters:**
| Param | Type | Description |
|-------|------|-------------|
| `userId` | string | User UUID |

**cURL:**
```bash
curl -X GET http://localhost:3000/api/notifications/user/550e8400-e29b-41d4-a716-446655440000
```

**✅ 200 Response:** Array of notification objects, newest first.

---
---

# 📅 SCHEDULING SERVICE
**Prefix:** `/api/scheduling` — Port `4009`

---

## POST `/api/scheduling/schedule`
Schedule a future meeting.

**Body Parameters:**
| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `hostId` | string | ✅ | Host's user UUID |
| `title` | string | ✅ | Meeting title |
| `startTime` | string (ISO 8601) | ✅ | e.g. `"2026-03-01T09:00:00Z"` |
| `endTime` | string (ISO 8601) | ✅ | e.g. `"2026-03-01T09:30:00Z"` |
| `recurrence` | string | ❌ | `"once"`, `"daily"`, `"weekly"` |
| `timezone` | string | ❌ | e.g. `"Asia/Kolkata"` |

**cURL:**
```bash
curl -X POST http://localhost:3000/api/scheduling/schedule \
  -H "Content-Type: application/json" \
  -d '{"hostId":"550e8400-...","title":"Team Standup","startTime":"2026-03-01T09:00:00Z","endTime":"2026-03-01T09:30:00Z","recurrence":"weekly","timezone":"Asia/Kolkata"}'
```

**✅ 200 Response:**
```json
{
  "id": "schedule-uuid",
  "hostId": "550e8400-...",
  "meetingId": "xyz-abcd-efg",
  "title": "Team Standup",
  "startTime": "2026-03-01T09:00:00.000Z",
  "endTime": "2026-03-01T09:30:00.000Z",
  "recurrence": "weekly",
  "timezone": "Asia/Kolkata",
  "createdAt": "2026-02-24T05:30:00.000Z"
}
```

---

## GET `/api/scheduling/user/{userId}`
Get all scheduled meetings for a user.

**URL Parameters:**
| Param | Type | Description |
|-------|------|-------------|
| `userId` | string | Host's user UUID |

**cURL:**
```bash
curl -X GET http://localhost:3000/api/scheduling/user/550e8400-e29b-41d4-a716-446655440000
```

**✅ 200 Response:** Array of schedule objects ordered by `startTime` ascending.

---

## DELETE `/api/scheduling/{scheduleId}`
Cancel and delete a scheduled meeting.

**URL Parameters:**
| Param | Type | Description |
|-------|------|-------------|
| `scheduleId` | string | Schedule UUID |

**cURL:**
```bash
curl -X DELETE http://localhost:3000/api/scheduling/schedule-uuid-here
```

**✅ 200 Response:**
```json
{ "status": "Schedule deleted" }
```

---
---

# 📼 RECORDING SERVICE
**Prefix:** `/api/recording` — Port `4007`

> ⚠️ File uploads require Cloudflare R2 credentials configured in `.env`.

---

## POST `/api/recording/start/{meetingId}`
Signal that recording has started (status tracking).

**URL Parameters:**
| Param | Type | Description |
|-------|------|-------------|
| `meetingId` | string | Meeting code |

**cURL:**
```bash
curl -X POST http://localhost:3000/api/recording/start/abc-defg-hij
```

**✅ 200 Response:**
```json
{ "message": "Recording status: REQUESTED" }
```

---

## POST `/api/recording/stop/{meetingId}`
Signal that recording has stopped.

**URL Parameters:**
| Param | Type | Description |
|-------|------|-------------|
| `meetingId` | string | Meeting code |

**cURL:**
```bash
curl -X POST http://localhost:3000/api/recording/stop/abc-defg-hij
```

**✅ 200 Response:**
```json
{ "message": "Recording status: STOPPED" }
```

---

## POST `/api/recording/upload`
Upload the actual recording blob to Cloudflare R2.

**Headers:** `Content-Type: multipart/form-data`

**Form Fields:**
| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `recording` | file | ✅ | Video file (`.webm`, `.mp4`) |
| `meetingId` | string | ✅ | Meeting code |
| `recordedBy` | string | ✅ | User UUID who recorded |
| `participants` | string (JSON) | ❌ | JSON array of participant names |
| `duration` | string/number | ❌ | Duration in seconds |

**cURL:**
```bash
curl -X POST http://localhost:3000/api/recording/upload \
  -F "recording=@/path/to/video.webm" \
  -F "meetingId=abc-defg-hij" \
  -F "recordedBy=550e8400-..." \
  -F "duration=1800"
```

**✅ 200 Response:**
```json
{
  "id": "rec-uuid",
  "meetingId": "abc-defg-hij",
  "fileUrl": "https://your-r2-domain/recordings/abc-defg-hij/1234567890-video.webm",
  "recordedBy": "550e8400-...",
  "duration": 1800,
  "startedAt": "2026-02-24T05:30:00.000Z",
  "endedAt": "2026-02-24T06:00:00.000Z"
}
```

---

## GET `/api/recording/{meetingId}`
Get all recordings for a specific meeting.

**URL Parameters:**
| Param | Type | Description |
|-------|------|-------------|
| `meetingId` | string | Meeting code |

**cURL:**
```bash
curl -X GET http://localhost:3000/api/recording/abc-defg-hij
```

**✅ 200 Response:** Array of recording objects, newest first.

---

## GET `/api/recording/`
Get all recordings (admin view).

**cURL:**
```bash
curl -X GET http://localhost:3000/api/recording/
```

**✅ 200 Response:** Array of all recording objects across all meetings.

---
---

# 📁 FILE SERVICE
**Prefix:** `/api/files` — Port `4010`

> ⚠️ Requires Cloudflare R2 credentials in `.env`.

---

## POST `/api/files/upload`
Upload a file (image, PDF, doc) to share in chat.

**Headers:** `Content-Type: multipart/form-data`

**Form Fields:**
| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `file` | file | ✅ | Any file type |
| `uploaderId` | string | ✅ | User UUID of uploader |
| `meetingId` | string | ✅ | Meeting where file is shared |

**cURL:**
```bash
curl -X POST http://localhost:3000/api/files/upload \
  -F "file=@/path/to/document.pdf" \
  -F "uploaderId=550e8400-..." \
  -F "meetingId=abc-defg-hij"
```

**✅ 200 Response:**
```json
{
  "id": "file-uuid",
  "uploaderId": "550e8400-...",
  "meetingId": "abc-defg-hij",
  "fileUrl": "https://your-r2-domain/uploads/1234567890-document.pdf",
  "fileType": "application/pdf",
  "size": 204800
}
```

---

## GET `/api/files/{fileId}`
Retrieve file metadata by ID.

**URL Parameters:**
| Param | Type | Description |
|-------|------|-------------|
| `fileId` | string | File UUID |

**cURL:**
```bash
curl -X GET http://localhost:3000/api/files/file-uuid-here
```

**✅ 200 Response:** File metadata object with `fileUrl` for download.
**❌ 404:** `{ "error": "File not found" }`

---
---

# 📖 HISTORY SERVICE
**Prefix:** `/api/history` — Port `4003`

> ℹ️ This is called automatically by the Signaling Server when a meeting ends. You do **not** need to call it manually from Flutter. Listed here for completeness only.

---

## POST `/api/history/store`
Store call duration and end time.

**Body Parameters:**
| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `meetingId` | string | ✅ | Meeting code |
| `duration` | number | ✅ | Duration in seconds |
| `endedAt` | string (ISO 8601) | ✅ | When meeting ended |

**cURL:**
```bash
curl -X POST http://localhost:3000/api/history/store \
  -H "Content-Type: application/json" \
  -d '{"meetingId":"abc-defg-hij","duration":1800,"endedAt":"2026-02-24T06:00:00Z"}'
```

**✅ 200 Response:**
```json
{
  "id": "history-uuid",
  "meeting_id": "abc-defg-hij",
  "duration": 1800,
  "ended_at": "2026-02-24T06:00:00.000Z"
}
```

---
---

# 🔴 SIGNALING SERVICE — Socket.IO
**Direct URL:** `http://<YOUR_PC_IP>:4000`
**Flutter Package:** `socket_io_client: ^2.0.3+1`

---

## Connection Setup (Flutter)
```dart
import 'package:socket_io_client/socket_io_client.dart' as IO;

final socket = IO.io('http://192.168.1.10:4000', IO.OptionBuilder()
  .setTransports(['websocket'])
  .disableAutoConnect()
  .build());

socket.connect();

socket.onConnect((_) => print('Signaling connected'));
socket.onDisconnect((_) => print('Signaling disconnected'));
```

---

## 📤 Events You EMIT (Flutter → Server)

---

### `join-meeting`
Join a meeting room. **First event to emit** after connecting.

**Parameters:** (positional arguments, not a map)
```dart
socket.emit('join-meeting', [
  meetingCode,   // String  — e.g. "abc-defg-hij"
  userId,        // String  — user UUID or "guest"
  displayName,   // String  — display name
  isNewMeeting   // bool    — true if YOU created it
]);
```

**Server responds with:** `join-confirmation` event

---

### `offer`
Send a WebRTC offer to another participant.

```dart
socket.emit('offer', {
  'to': targetSocketId,  // String — socket ID of target
  'offer': {             // RTCSessionDescription
    'type': 'offer',
    'sdp': sdpString
  }
});
```

---

### `answer`
Reply to a WebRTC offer.

```dart
socket.emit('answer', {
  'to': targetSocketId,  // String — socket ID of target
  'answer': {            // RTCSessionDescription
    'type': 'answer',
    'sdp': sdpString
  }
});
```

---

### `ice-candidate`
Send ICE candidate (call multiple times during negotiation).

```dart
socket.emit('ice-candidate', {
  'to': targetSocketId,    // String — socket ID of target
  'candidate': {           // RTCIceCandidate
    'candidate': candidateString,
    'sdpMid': sdpMid,
    'sdpMLineIndex': sdpMLineIndex
  }
});
```

---

### `admit-user`
*(Host only)* Admit a waiting participant into the meeting.

```dart
socket.emit('admit-user', {
  'socketId': waitingSocketId  // String — from request-to-join event
});
```

---

### `deny-user`
*(Host only)* Deny a participant from joining.

```dart
socket.emit('deny-user', {
  'socketId': waitingSocketId
});
```

---

### `remove-user`
*(Host only)* Remove a participant from the call.

```dart
socket.emit('remove-user', {
  'socketId': targetSocketId
});
```

---

### `mute-user`
*(Host/Co-host only)* Force mute a participant.

```dart
socket.emit('mute-user', {
  'socketId': targetSocketId
});
```

---

### `camera-off-user`
*(Host/Co-host only)* Turn off a participant's camera.

```dart
socket.emit('camera-off-user', {
  'socketId': targetSocketId
});
```

---

### `assign-cohost`
*(Host only)* Assign co-host role to a participant.

```dart
socket.emit('assign-cohost', {
  'peerId': targetSocketId
});
```

---

### `remove-cohost`
*(Host only)* Remove the co-host role.

```dart
socket.emit('remove-cohost', {});
```

---

### `update-settings`
*(Host/Co-host only)* Broadcast a settings toggle to all participants.

```dart
socket.emit('update-settings', {
  'key': 'screenshare_enabled',   // String — setting key
  'value': false                   // bool/String — new value
});
```

---

### `request-recording`
Request consent from all participants to start recording.

```dart
socket.emit('request-recording', {});
```

---

### `respond-recording`
Respond to a recording consent request.

```dart
socket.emit('respond-recording', {
  'agree': true  // bool — true=consent, false=deny
});
```

---

### `stop-recording`
Signal that recording has stopped.

```dart
socket.emit('stop-recording', {});
```

---

### `send-caption`
Broadcast a live caption/transcription.

```dart
socket.emit('send-caption', {
  'text': 'Hello, how are you?',  // String — transcribed text
  'isFinal': true                  // bool — is this a final result?
});
```

---

## 📥 Events You LISTEN (Server → Flutter)

---

### `join-confirmation`
Received after emitting `join-meeting`. Acts as the handshake result.

```dart
socket.on('join-confirmation', (data) {
  // data['status'] = "JOINED" | "WAITING_FOR_APPROVAL" | "DENIED"
  // data['isHost'] = bool
  // data['participants'] = List (when JOINED)
  // data['waitingParticipants'] = List (host only)
  // data['coHostId'] = String? (socket ID of co-host)
  // data['error'] = String (when DENIED — e.g. "Meeting is full")
});
```

---

### `user-joined`
A new participant has been admitted. **Trigger WebRTC offer to this user.**

```dart
socket.on('user-joined', (data) {
  // data['socketId'] = String — new user's socket ID
  // data['userId']   = String — new user's app UUID
  // data['name']     = String — display name
  // → Create peer connection and emit 'offer' to data['socketId']
});
```

---

### `user-left`
A participant disconnected or was removed.

```dart
socket.on('user-left', (data) {
  // data['socketId'] = String — socket ID of departed user
  // → Remove their video tile, close peer connection
});
```

---

### `request-to-join`
*(Host only)* A guest is waiting for admission.

```dart
socket.on('request-to-join', (data) {
  // data['socketId'] = String — waiting user's socket ID
  // data['userId']   = String — user UUID
  // data['name']     = String — display name
  // → Show "Admit / Deny" dialog
});
```

---

### `offer`
Received a WebRTC offer from another participant.

```dart
socket.on('offer', (data) {
  // data['from']  = String — sender's socket ID
  // data['offer'] = { 'type': 'offer', 'sdp': String }
  // → Set remote description, then emit 'answer'
});
```

---

### `answer`
Received a WebRTC answer.

```dart
socket.on('answer', (data) {
  // data['from']   = String — sender's socket ID
  // data['answer'] = { 'type': 'answer', 'sdp': String }
  // → Set remote description
});
```

---

### `ice-candidate`
Received an ICE candidate.

```dart
socket.on('ice-candidate', (data) {
  // data['from']      = String — sender's socket ID
  // data['candidate'] = { 'candidate': String, 'sdpMid': String, 'sdpMLineIndex': int }
  // → Add ICE candidate to peer connection
});
```

---

### `removed-from-meeting`
You have been removed by the host.

```dart
socket.on('removed-from-meeting', (_) {
  // → Navigate back to home screen
});
```

---

### `join-denied`
Your join request was denied by the host.

```dart
socket.on('join-denied', (_) {
  // → Show "Your request was denied" and navigate away
});
```

---

### `mute-remote`
Host/co-host has requested you to mute yourself.

```dart
socket.on('mute-remote', (_) {
  // → Mute local microphone
});
```

---

### `camera-off-remote`
Host/co-host has requested you to turn off your camera.

```dart
socket.on('camera-off-remote', (_) {
  // → Disable local video track
});
```

---

### `setting-updated`
A meeting setting was changed by host/co-host.

```dart
socket.on('setting-updated', (data) {
  // data['key']   = String — e.g. "screenshare_enabled"
  // data['value'] = dynamic — new value
});
```

---

### `recording-requested`
Someone has requested to start recording (consent phase).

```dart
socket.on('recording-requested', (data) {
  // data['requestedBy']     = String — socket ID
  // data['requestedByName'] = String — display name
  // data['totalExpected']   = int   — how many need to agree
  // data['alreadyAgreed']   = int   — count so far
  // → Show consent dialog
});
```

---

### `recording-consent-update`
Progress update on recording consent.

```dart
socket.on('recording-consent-update', (data) {
  // data['agreedCount']        = int
  // data['totalExpected']      = int
  // data['agreedParticipants'] = List<String> (names)
});
```

---

### `recording-started`
All participants consented — start recording now.

```dart
socket.on('recording-started', (data) {
  // data['recorderId'] = String — socket ID of who records
  // data['startTime']  = String — ISO timestamp
  // → If recorderId == socket.id, begin MediaRecorder
});
```

---

### `recording-stopped`
Recording has been stopped.

```dart
socket.on('recording-stopped', (data) {
  // data['stoppedBy'] = String — socket ID
  // → Stop MediaRecorder, upload blob to /api/recording/upload
});
```

---

### `recording-denied`
A participant denied the recording request.

```dart
socket.on('recording-denied', (data) {
  // data['deniedBy']     = String — socket ID
  // data['deniedByName'] = String — display name
  // → Show "Recording was denied by {name}"
});
```

---

### `recording-error`
Recording action failed (e.g. already in progress).

```dart
socket.on('recording-error', (data) {
  // data['message'] = String — error description
});
```

---

### `caption-received`
A live caption was broadcast from another participant.

```dart
socket.on('caption-received', (data) {
  // data['userId']    = String
  // data['userName']  = String
  // data['text']      = String — transcribed speech
  // data['isFinal']   = bool
  // data['socketId']  = String
  // data['timestamp'] = int (ms since epoch)
});
```

---

### `meeting-warning`
Meeting is about to end due to time limit.

```dart
socket.on('meeting-warning', (data) {
  // data['message']     = String — warning message
  // data['remainingMs'] = int    — milliseconds left (60000 = 1 min)
});
```

---

### `meeting-ended`
Meeting has ended (time limit reached or host ended it).

```dart
socket.on('meeting-ended', (data) {
  // data['reason']  = String — "TIME_LIMIT_REACHED" or "HOST_ENDED"
  // data['message'] = String — human-readable reason
  // → Navigate to call-ended screen
});
```

---

## 💬 Chat Socket Events (Port `4005`)
The Chat Service also supports Socket.IO for real-time chat alongside the REST API.

**Connect to:** `http://<YOUR_PC_IP>:4005`

```dart
// Join chat room
socket.emit('join-chat', {'meetingId': meetingCode, 'userId': userId});

// Send message in real-time (does NOT persist — use REST API to save)
socket.emit('chat:send', {
  'meetingId': meetingCode,
  'senderId': userId,
  'senderName': displayName,
  'content': messageText,
  'recipientId': null,   // null for public, UUID for private
});

// Listen for incoming messages
socket.on('chat:receive', (data) {
  // data has same fields as the REST POST /api/chat/send response
});

// Delete message in real-time
socket.emit('chat:delete', {'meetingId': meetingCode, 'messageId': messageId});

// Listen for deleted messages
socket.on('chat:deleted', (messageId) {
  // Remove message with this ID from UI
});
```

---
---

# 🗺️ COMPLETE INTEGRATION FLOW

```
STEP 1 — Register/Login
  POST /api/auth/signup  OR  POST /api/auth/login
  → Save JWT token securely

STEP 2 — Create or Join Meeting
  Create:  POST /api/meetings/create   → get meeting_code
  Join:    GET  /api/meeting/{code}    → verify meeting exists

STEP 3 — Log participation
  POST /api/participant/join  { meetingId: meeting.id, userId }

STEP 4 — Connect Signaling
  Connect Socket.IO to port 4000
  Emit: join-meeting(code, userId, name, isNew)
  Listen: join-confirmation

STEP 5 — Handle Waiting Room (guest)
  Listen: join-confirmation → status = "WAITING_FOR_APPROVAL"
  Host: listen request-to-join → emit admit-user or deny-user

STEP 6 — WebRTC Call Setup
  Listen: user-joined → create RTCPeerConnection, emit offer
  Listen: offer → set remote SDP, emit answer
  Listen: answer → set remote SDP
  Listen/Emit: ice-candidate (multiple times)

STEP 7 — During Call
  Chat:      POST /api/chat/send  (persist) + emit chat:send (real-time)
  Captions:  emit send-caption
  Reactions: emit update-settings { key: 'reaction', value: '👍' }
  Recording: emit request-recording → listen recording-started → start recorder

STEP 8 — Leave Meeting
  Emit: (disconnect socket)
  POST /api/participant/leave  { meetingId, userId }

STEP 9 — After Call
  Upload recording: POST /api/recording/upload (multipart)
  Submit feedback:  POST /api/meeting/feedback
```

---
---

# 🛡️ ADMIN APIs (Optional)
**Prefix:** `/api/admin` — Port `4011`
> Only needed if building an admin panel screen in the mobile app.

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/admin/stats` | Dashboard stats |
| GET | `/api/admin/users` | List all users |
| POST | `/api/admin/users` | Create user |
| PUT | `/api/admin/users/{id}` | Update user |
| DELETE | `/api/admin/users/{id}` | Delete user |
| GET | `/api/admin/meetings` | All meetings |
| GET | `/api/admin/meetings/{id}` | Meeting detail + participants |
| POST | `/api/admin/meetings/{id}/end` | Force end meeting |
| GET | `/api/admin/reports` | Abuse reports |
| GET | `/api/admin/feedbacks` | All feedback |
| GET | `/api/admin/queries` | Support queries |
| PUT | `/api/admin/queries/{id}/status` | Update query status |
| GET | `/api/admin/plans` | Subscription plans |
| POST | `/api/admin/plans` | Create plan |
| PUT | `/api/admin/plans/{id}` | Update plan |
| DELETE | `/api/admin/plans/{id}` | Delete plan |
| GET | `/api/admin/languages` | Language list |
| POST | `/api/admin/languages` | Add/update language |
| DELETE | `/api/admin/languages/{id}` | Delete language |
| GET | `/api/admin/analytics/summary` | Analytics charts |
| GET | `/api/admin/analytics/latency` | API latency metrics |
| GET | `/api/admin/logs/audit` | Audit logs |

---

*— End of Newmeet Flutter API Reference —*
*Generated 2026-02-24 from live codebase.*
