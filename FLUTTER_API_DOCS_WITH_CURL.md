# Mizdah Full API Documentation & cURL Instructions

**Base URL**: `http://192.168.1.24:3000`

## Auth APIs

### Sign Up
**Endpoint:** `/api/auth/signup`
**Method:** `POST`

**Sample cURL:**
```bash
curl -X POST http://192.168.1.24:3000/api/auth/signup \
  -H "Content-Type: application/json" \
  -d '{"email":"user@example.com","password":"mypassword","name":"John Doe"}'
```

### Login
**Endpoint:** `/api/auth/login`
**Method:** `POST`

**Sample cURL:**
```bash
curl -X POST http://192.168.1.24:3000/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"user@example.com","password":"mypassword"}'
```

### Get Current User
**Endpoint:** `/api/auth/me`
**Method:** `GET`

**Sample cURL:**
```bash
curl -X GET http://192.168.1.24:3000/api/auth/me \
  -H "Authorization: Bearer <TOKEN>"
```

### Update Profile
**Endpoint:** `/api/auth/update`
**Method:** `POST`

**Sample cURL:**
```bash
curl -X POST http://192.168.1.24:3000/api/auth/update \
  -H "Authorization: Bearer <TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"name":"New Name","password":"newpassword"}'
```

## Meeting APIs

### Create Meeting
**Endpoint:** `/api/meetings/create`
**Method:** `POST`

**Sample cURL:**
```bash
curl -X POST http://192.168.1.24:3000/api/meetings/create \
  -H "Content-Type: application/json" \
  -d '{"hostId":"uuid-1234"}'
```

### Get Meeting Info
**Endpoint:** `/api/meeting/abc-defg-hij`
**Method:** `GET`

**Sample cURL:**
```bash
curl -X GET http://192.168.1.24:3000/api/meeting/abc-defg-hij
```

### Get Meetings by Host
**Endpoint:** `/api/meetings/user/uuid-1234`
**Method:** `GET`

**Sample cURL:**
```bash
curl -X GET http://192.168.1.24:3000/api/meetings/user/uuid-1234
```

### Update Meeting Settings
**Endpoint:** `/api/meeting/abc-defg-hij/settings`
**Method:** `PATCH`

**Sample cURL:**
```bash
curl -X PATCH http://192.168.1.24:3000/api/meeting/abc-defg-hij/settings \
  -H "Content-Type: application/json" \
  -d '{"private_chat_enabled":false}'
```

### Get Global System Settings
**Endpoint:** `/api/meeting/settings`
**Method:** `GET`

**Sample cURL:**
```bash
curl -X GET http://192.168.1.24:3000/api/meeting/settings
```

### Update Global System Settings
**Endpoint:** `/api/meeting/settings`
**Method:** `POST`

**Sample cURL:**
```bash
curl -X POST http://192.168.1.24:3000/api/meeting/settings \
  -H "Content-Type: application/json" \
  -d '{"max_participants":50,"meeting_time_limit":45,"allow_recordings":false}'
```

### Submit Feedback
**Endpoint:** `/api/meeting/feedback`
**Method:** `POST`

**Sample cURL:**
```bash
curl -X POST http://192.168.1.24:3000/api/meeting/feedback \
  -H "Content-Type: application/json" \
  -d '{"category":"Audio Quality","description":"Echo during the call","user_email":"user@example.com"}'
```

### Contact / Support Form
**Endpoint:** `/api/meeting/contact`
**Method:** `POST`

**Sample cURL:**
```bash
curl -X POST http://192.168.1.24:3000/api/meeting/contact \
  -H "Content-Type: application/json" \
  -d '{"first_name":"John","last_name":"Doe","email":"john@example.com","message":"Help me"}'
```

### Report Abuse
**Endpoint:** `/api/meeting/report-abuse`
**Method:** `POST`

**Sample cURL:**
```bash
curl -X POST http://192.168.1.24:3000/api/meeting/report-abuse \
  -H "Content-Type: application/json" \
  -d '{"abuse_type":"Harassment","abuser_names":"John Doe","description":"Offensive language","meeting_id":"abc-xyz"}'
```

## Participant APIs

### Log Participant Join
**Endpoint:** `/api/participant/join`
**Method:** `POST`

**Sample cURL:**
```bash
curl -X POST http://192.168.1.24:3000/api/participant/join \
  -H "Content-Type: application/json" \
  -d '{"meetingId":"abc","userId":"uuid-123"}'
```

### Log Participant Leave
**Endpoint:** `/api/participant/leave`
**Method:** `POST`

**Sample cURL:**
```bash
curl -X POST http://192.168.1.24:3000/api/participant/leave \
  -H "Content-Type: application/json" \
  -d '{"meetingId":"abc","userId":"uuid-123"}'
```

### Get Users Meeting History
**Endpoint:** `/api/participant/user/uuid-123`
**Method:** `GET`

**Sample cURL:**
```bash
curl -X GET http://192.168.1.24:3000/api/participant/user/uuid-123
```

### Get Participants in a Meeting
**Endpoint:** `/api/participant/abc-defg-hij`
**Method:** `GET`

**Sample cURL:**
```bash
curl -X GET http://192.168.1.24:3000/api/participant/abc-defg-hij
```

## Chat APIs

### Send Message (Public)
**Endpoint:** `/api/chat/send`
**Method:** `POST`

**Sample cURL:**
```bash
curl -X POST http://192.168.1.24:3000/api/chat/send \
  -H "Content-Type: application/json" \
  -d '{"meetingId":"abc","senderId":"uuid-123","senderName":"John","content":"Hello!"}'
```

### Get Messages
**Endpoint:** `/api/chat/abc-defg-hij?userId=uuid-123`
**Method:** `GET`

**Sample cURL:**
```bash
curl -X GET http://192.168.1.24:3000/api/chat/abc-defg-hij?userId=uuid-123
```

### Delete Message
**Endpoint:** `/api/chat/msg-uuid`
**Method:** `DELETE`

**Sample cURL:**
```bash
curl -X DELETE http://192.168.1.24:3000/api/chat/msg-uuid
```

## Notifications APIs

### Send Meeting Invite
**Endpoint:** `/api/notifications/invite`
**Method:** `POST`

**Sample cURL:**
```bash
curl -X POST http://192.168.1.24:3000/api/notifications/invite \
  -H "Content-Type: application/json" \
  -d '{"userId":"uuid-123","meetingCode":"abc","message":"Join!"}'
```

### Send Meeting Reminder
**Endpoint:** `/api/notifications/reminder`
**Method:** `POST`

**Sample cURL:**
```bash
curl -X POST http://192.168.1.24:3000/api/notifications/reminder \
  -H "Content-Type: application/json" \
  -d '{"userId":"uuid-123","scheduleId":"sch-123","message":"Starts soon"}'
```

### Get User Notifications
**Endpoint:** `/api/notifications/user/uuid-123`
**Method:** `GET`

**Sample cURL:**
```bash
curl -X GET http://192.168.1.24:3000/api/notifications/user/uuid-123
```

## Scheduling APIs

### Create Schedule
**Endpoint:** `/api/scheduling/schedule`
**Method:** `POST`

**Sample cURL:**
```bash
curl -X POST http://192.168.1.24:3000/api/scheduling/schedule \
  -H "Content-Type: application/json" \
  -d '{"hostId":"uuid-123","title":"Standup","startTime":"2026-02-25T09:00:00Z","endTime":"2026-02-25T09:30:00Z","recurrence":"weekly","timezone":"UTC"}'
```

### Get Users Scheduled Meetings
**Endpoint:** `/api/scheduling/user/uuid-123`
**Method:** `GET`

**Sample cURL:**
```bash
curl -X GET http://192.168.1.24:3000/api/scheduling/user/uuid-123
```

### Delete Schedule
**Endpoint:** `/api/scheduling/sch-uuid`
**Method:** `DELETE`

**Sample cURL:**
```bash
curl -X DELETE http://192.168.1.24:3000/api/scheduling/sch-uuid
```

## Recording APIs

### Start Recording
**Endpoint:** `/api/recording/start/abc-defg-hij`
**Method:** `POST`

**Sample cURL:**
```bash
curl -X POST http://192.168.1.24:3000/api/recording/start/abc-defg-hij
```

### Stop Recording
**Endpoint:** `/api/recording/stop/abc-defg-hij`
**Method:** `POST`

**Sample cURL:**
```bash
curl -X POST http://192.168.1.24:3000/api/recording/stop/abc-defg-hij
```

### Get Recordings for a Meeting
**Endpoint:** `/api/recording/abc-defg-hij`
**Method:** `GET`

**Sample cURL:**
```bash
curl -X GET http://192.168.1.24:3000/api/recording/abc-defg-hij
```

### Get All Recordings
**Endpoint:** `/api/recording/`
**Method:** `GET`

**Sample cURL:**
```bash
curl -X GET http://192.168.1.24:3000/api/recording/
```

## File APIs

### Get File
**Endpoint:** `/api/files/file-uuid`
**Method:** `GET`

**Sample cURL:**
```bash
curl -X GET http://192.168.1.24:3000/api/files/file-uuid
```

## History APIs

### Store Call History
**Endpoint:** `/api/history/store`
**Method:** `POST`

**Sample cURL:**
```bash
curl -X POST http://192.168.1.24:3000/api/history/store \
  -H "Content-Type: application/json" \
  -d '{"meetingId":"abc","duration":1800,"endedAt":"2026-02-24T11:30:00Z"}'
```

