# Notifications — Backend Spec

The Flutter app now ships a dedicated **Notifications** screen
(`/notifications` route) reached by tapping the bell in the home
header. The screen reads a per-user notification list, applies a
type-to-icon map, and filters chat-shaped types out. This doc
covers everything the backend needs to land so the screen works
end-to-end.

The screen is **already wired** on the client. The backend just
needs to ship the endpoints + schema + emit events from the right
places.

---

## 0. Conventions

Same as the rest of the API docs in this folder:

- Gateway: `https://<dev-host>:3001` (dev),
  `https://mizdah-backend.ogoul.cloud` (prod).
- Auth: `Authorization: Bearer <JWT>` required on every endpoint
  unless explicitly noted as public.
- Bodies: `application/json`.
- Errors: `{ "error": "human readable", "code": "MACHINE_READABLE" }`.
- Timestamps: ISO-8601 UTC, e.g. `2026-05-15T08:34:08.123Z`.
- IDs: UUID strings (string type in JSON).

---

## 1. Summary of changes

| Change | Where | Status |
|---|---|---|
| Add `notifications` table | DB | NEW |
| Endpoint `GET /api/notifications/user/:userId` | new route | NEW |
| Endpoint `PATCH /api/notifications/:id/read` | new route | NEW |
| Endpoint `PATCH /api/notifications/read-all` | new route | NEW (optional) |
| Endpoint `DELETE /api/notifications/:id` | new route | NEW (optional) |
| Emit notifications from meeting / call / recording / auth / contacts services | several | NEW |
| Pair every emit with FCM data-message via existing push service | shared util | NEW |
| **Never** persist chat-shaped types into this table | rule | NEW |

Additive — no existing endpoint changes shape.

Estimated effort: **6–10 hours** for endpoints + table + emit-site
wiring. Most of the cost is plumbing emit calls into the existing
services (meeting scheduler, P2P call signaling, recording
finalizer, file-service, auth password change, contacts matcher).

---

## 2. Data model — new table

```sql
CREATE TABLE notifications (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  -- Recipient. The list endpoint reads by user_id; the type is
  -- per-user notifications, not per-meeting / per-call (one
  -- meeting can spawn one row per invitee).
  user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  -- Closed vocabulary — see §3. Stored as VARCHAR(32) so SQL
  -- queries can filter by exact match cheaply. NOT an enum so
  -- adding a new type doesn't require a migration.
  type        VARCHAR(32) NOT NULL,
  -- One-line headline rendered in bold at the top of the tile,
  -- e.g. "Meeting invite", "Missed call from Farhan", etc.
  title       VARCHAR(120) NOT NULL,
  -- 1–3 line body. Plain text, no markdown. The client
  -- truncates at 3 lines + ellipsis.
  body        TEXT NOT NULL DEFAULT '',
  -- Optional structured payload the client can use to deep-link
  -- the tile (e.g. meetingId for meeting_invite so a tap can
  -- jump straight to the pre-join screen). JSONB so we don't
  -- have to bake every possible field into columns.
  data        JSONB NOT NULL DEFAULT '{}'::jsonb,
  -- Soft-delete flag for "Clear all" — keeps rows around for
  -- 30 days for audit, see §10.
  is_read     BOOLEAN NOT NULL DEFAULT FALSE,
  read_at     TIMESTAMPTZ,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Hot path: list-by-user, newest first. Single composite index
-- covers the most common query: "give me this user's last N
-- notifications, unread first."
CREATE INDEX idx_notifications_user_created
  ON notifications (user_id, created_at DESC);

-- Bell-badge query: count unread. Partial index keeps it tiny.
CREATE INDEX idx_notifications_user_unread
  ON notifications (user_id)
  WHERE is_read = FALSE;
```

### Prisma equivalent

```prisma
model Notification {
  id        String   @id @default(uuid())
  userId    String   @map("user_id")
  user      User     @relation(fields: [userId], references: [id], onDelete: Cascade)
  type      String   @db.VarChar(32)
  title     String   @db.VarChar(120)
  body      String   @default("")
  data      Json     @default("{}")
  isRead    Boolean  @default(false) @map("is_read")
  readAt    DateTime? @map("read_at")
  createdAt DateTime @default(now()) @map("created_at")

  @@index([userId, createdAt(sort: Desc)])
  @@index([userId], where: { isRead: false }, name: "idx_notifications_user_unread")
  @@map("notifications")
}
```

---

## 3. Notification type catalog

The Flutter screen has a frozen map of `type → icon + colour`. If
you ship a type the client doesn't know it falls back to a neutral
bell icon — usable but uglier. **Coordinate before adding a new
type.** Source of truth on the client:
`lib/features/notifications/presentation/notifications_screen.dart`,
`_NotificationTile._meta()`.

| `type` | When backend emits | `title` example | `body` example | `data` shape |
|---|---|---|---|---|
| `meeting_invite` | Host creates a meeting and adds you to invitees, OR scheduler runs and a new schedule references you. Emitted once per invitee. | `Meeting invite — Standup` | `Farhan invited you. Starts Fri 10:00 AM.` | `{ meetingId, meetingCode, scheduledStart, hostUserId }` |
| `meeting_reminder` | Cron emits T-10 min and T-1 min before a scheduled meeting starts for each invitee who hasn't joined yet. | `Standup starts in 10 minutes` | `Tap to join when it opens.` | `{ meetingId, meetingCode, scheduledStart, minutesUntilStart }` |
| `meeting_started` | Host actually opens the meeting room (first participant join). Emitted once per invitee. | `Standup just started` | `Farhan opened the room. Tap to join.` | `{ meetingId, meetingCode, hostUserId }` |
| `meeting_cancelled` | Host cancels an upcoming scheduled meeting. Emitted once per invitee. | `Meeting cancelled` | `Standup on Fri 10:00 AM was cancelled.` | `{ meetingId, meetingCode, scheduledStart }` |
| `meeting_rescheduled` | Host updates start/end time of an upcoming meeting. Emitted once per invitee. | `Meeting moved to Fri 11:00 AM` | `Standup — new start time below.` | `{ meetingId, meetingCode, oldStart, newStart }` |
| `recording_ready` | Recording finalizer finishes processing the file and uploads it. Emitted to the user who started the recording. | `Recording is ready` | `Standup — 23 min · 142 MB. Tap to view.` | `{ meetingId, meetingCode, recordingId, durationSeconds, sizeBytes, fileUrl }` |
| `missed_call` | P2P callee was offline OR didn't answer within the 30s auto-decline window. Emitted to callee, not caller. | `Missed call from Farhan` | `Video call · just now` | `{ callerId, callerName, callerAvatarUrl, callType: "audio"|"video", durationSeconds, callId }` |
| `contact_joined` | Contact-matcher job finds a phone number from a user's `/contacts/match` upload that just signed up. Emitted to the existing user (i.e. the one whose contact joined). | `Farhan joined Mizdah` | `You can call or message them now.` | `{ joinedUserId, joinedUserName, joinedUserAvatarUrl, phoneE164 }` |
| `security` | Password changed, new-device sign-in, 2FA enabled/disabled, password reset link consumed. Emitted to the affected user. | `Password changed` | `If this wasn't you, reset your password now.` | `{ event: "password_changed"|"new_device_login"|..., ip?, userAgent?, location? }` |
| _(fallback)_ | Backend emits a type the client doesn't recognise. Renders with a neutral icon — the client doesn't crash. | (free-form) | (free-form) | (free-form) |

### Types you must NOT emit into this table

The screen filters these out, but inserting them is still wasted
DB rows + bandwidth and risks them slipping through if the client
filter ever regresses. **Chat lives in its own channel.**

| `type` to avoid | Where it should go instead |
|---|---|
| `chat`, `message`, `dm` | Persisted in the chat thread; surfaced in the Chats tab unread count. |
| `chat:message`, `chat:mention`, `chat:reply` | Same as above. |
| `typing` / presence events | WebSocket only, never persisted. |

If you need to ping a user about a chat from a server-side flow
(e.g. "you have 5 new messages from Farhan"), do that via FCM
data-message + chat unread-count, not through this table.

---

## 4. Endpoints

### 4.1 `GET /api/notifications/user/:userId` — list

Returns this user's notifications, newest first.

**Authorization:** caller must be the same user as `:userId`
(extract from JWT, compare to path). Admin role bypasses for
support tooling. Reject with `403 FORBIDDEN_OTHER_USER` if a user
asks for someone else's list.

**Query params:**

| Param | Type | Default | Notes |
|---|---|---|---|
| `limit` | int | 50 | Hard cap at 200. |
| `before` | ISO-8601 | _(none)_ | Cursor for pagination — return rows where `created_at < before`. |
| `unread` | bool | false | If `true`, only `is_read = false`. Powers the bell badge count. |

**Response (200):**

```json
{
  "data": [
    {
      "id": "9c6d4f7e-7f0b-4b3e-9e8a-3a1b2c3d4e5f",
      "userId": "uuid",
      "type": "meeting_invite",
      "title": "Meeting invite — Standup",
      "body": "Farhan invited you. Starts Fri 10:00 AM.",
      "data": {
        "meetingId": "uuid",
        "meetingCode": "abc-defg-hij",
        "scheduledStart": "2026-05-16T04:30:00.000Z",
        "hostUserId": "uuid"
      },
      "isRead": false,
      "readAt": null,
      "createdAt": "2026-05-15T08:30:00.000Z"
    }
  ],
  "nextCursor": "2026-05-15T08:25:00.000Z",
  "unreadCount": 7
}
```

`nextCursor` is omitted when there are no more rows. The client
doesn't paginate today — but it should be possible without a v2
endpoint, hence the cursor in the response.

**Compatibility note:** the existing client code already accepts
either `{ data: [...] }` OR a bare `[...]` (see
`notification_repository.dart:18`). Use the wrapped shape going
forward; the bare-array branch is just legacy tolerance.

### 4.2 `PATCH /api/notifications/:id/read` — mark one as read

Already exists on the client side
(`NotificationRepository.markAsRead`). Idempotent — re-calling
on an already-read row is a 200 no-op.

**Authorization:** caller must own the notification. `403
FORBIDDEN_OTHER_USER` otherwise.

**Response (200):**

```json
{ "id": "uuid", "isRead": true, "readAt": "2026-05-15T08:31:00.000Z" }
```

### 4.3 `PATCH /api/notifications/read-all` — mark all as read

Bulk-version of the above. The client doesn't call this yet but
it's cheap and the next iteration of the screen probably needs it
(common "Clear unread" gesture).

**Authorization:** scoped to `req.user.id` server-side — there is
NO path param. Trying to bulk-read someone else's notifications
must be physically impossible from the API surface.

**Response (200):**

```json
{ "markedReadCount": 7 }
```

### 4.4 `DELETE /api/notifications/:id` — dismiss one

Soft-delete: sets a `dismissed_at` column (add it now if you want
the swipe-to-dismiss gesture later, otherwise hard-DELETE is fine
since we're cleaning up after 30 days anyway). Authorization same
as 4.2.

### 4.5 `GET /api/notifications/unread-count` — badge fast path

Just the count. Cheaper than fetching the list every time the
bell needs to show its dot. Hits the partial index from §2.

**Response (200):**

```json
{ "unreadCount": 7 }
```

Not strictly required for v1 — the client computes the badge from
the list it already has — but extremely cheap to add and the
home screen polls every focus, so worth it.

---

## 5. Where each type fires from (emit-site checklist)

This is the "what services need to import the new
`createNotification()` helper" map. Build a single shared util
(`createNotification({ userId, type, title, body, data })`) that:

1. Inserts a row into the `notifications` table.
2. Calls `pushService.sendDataMessage(userId, { ...payload })` —
   reuses your existing FCM service so the OS notification tray
   updates too.
3. Returns the inserted row.

Then sprinkle calls at these sites:

| Type | Service / file | Hook point |
|---|---|---|
| `meeting_invite` | meeting-service createMeeting / scheduling-service create | After the meeting + invitees rows commit. One call per invitee. |
| `meeting_reminder` | cron worker (T-10, T-1) | Per-invitee sweep. Skip invitees who already have an active participant row for the meeting. |
| `meeting_started` | media-server `room.peerJoined` (host first) | On the first participant join with role=host. Fan out to all invitees. |
| `meeting_cancelled` | scheduling-service cancelSchedule | After the schedule row flips to cancelled. |
| `meeting_rescheduled` | scheduling-service updateSchedule | Only when start/end actually changed. Don't emit on title-only edits. |
| `recording_ready` | recording-service finalizer | After upload + metadata row commits. To `userId = recording.startedByUserId`. |
| `missed_call` | signaling-service P2P controller | When the callee's auto-decline fires OR `online=false` at offer time. Caller does NOT get one. |
| `contact_joined` | contacts-service match worker | When a brand-new user signs up whose `phone` matches a previously-uploaded number from someone's `/contacts/match` batch. To the **existing** user, NOT the new signup. |
| `security` | auth-service password-change / new-device-detector | On `/api/auth/update` with `password`, on `/api/auth/reset-password` consumed, on first sign-in from a new device fingerprint. |

### Idempotency

Emit-sites that can fire twice (cron reminders, signaling retries,
duplicate webhooks) must dedupe **before** insert. Use a content
hash in `data` or a partial unique index on `(user_id, type,
data->>'meetingId')` for meeting-shaped types. Don't make the
client dedupe.

### Throughput sanity check

For 2M users with median 3 meetings/week × 2 reminders × 5
invitees = `~12 emits per user per week`. ≈ **40 rows/sec** at
peak. Well within a single Postgres write per emit; the partial
unread index is the only thing that needs watching.

---

## 6. FCM pairing — push vs persist

Every emit must do **both**:

1. **Persist** to `notifications` so the bell screen has a list.
2. **Push** an FCM data-message to the user's active device tokens
   so the OS tray + the in-app FCM listener can react in
   real-time.

Use FCM **data-only** messages (no `notification` block) so the
Flutter `PushNotificationService` can route them through its own
display logic — see
`lib/core/services/push_notification_service.dart`. The data
payload should mirror the persisted row:

```json
{
  "to": "<device_token>",
  "data": {
    "kind": "inbox",
    "notificationId": "uuid",
    "type": "meeting_invite",
    "title": "Meeting invite — Standup",
    "body": "Farhan invited you. Starts Fri 10:00 AM.",
    "meetingId": "uuid",
    "meetingCode": "abc-defg-hij",
    "scheduledStart": "2026-05-16T04:30:00.000Z"
  },
  "android": { "priority": "high" },
  "apns": { "headers": { "apns-priority": "10" } }
}
```

The top-level `kind: "inbox"` tag lets the client distinguish
inbox-bound pushes from operational pushes (incoming call ring,
chat:message — those use different `kind`s).

### Special cases

- **`missed_call`** must NOT race the in-app ring. Only emit
  AFTER the call lifecycle ends (declined / unanswered / offline
  re-route) — never during. If you emit during, the callee gets a
  "missed call" notification while their phone is still ringing.
- **`meeting_reminder`** T-1 min: skip if you already see a
  participant row for this user on this meeting (they joined
  early). Otherwise users who joined at T-2 get a redundant ping.
- **`security`** should set a higher visibility flag in FCM
  (`android.priority=high`, `apns.headers.apns-priority=10`) so
  it bypasses do-not-disturb on most devices.

---

## 7. Authorization model

| Endpoint | Who can call | What they can see |
|---|---|---|
| `GET /api/notifications/user/:userId` | the user themselves, admin | only that user's rows |
| `PATCH /api/notifications/:id/read` | the user who owns the row, admin | own rows |
| `PATCH /api/notifications/read-all` | the authenticated user | own rows |
| `DELETE /api/notifications/:id` | the user who owns the row, admin | own rows |
| `GET /api/notifications/unread-count` | the authenticated user | own count |

Never trust `:userId` in the path — always cross-check against
`req.user.id` from the JWT. The same kind of bug as the one we
have in file-service today (see
`docs/FILE_UPLOAD_UPLOADER_ID_BACKEND.md`).

---

## 8. Error catalog

| HTTP | `code` | When |
|---|---|---|
| 400 | `INVALID_LIMIT` | `limit > 200` or non-integer |
| 400 | `INVALID_CURSOR` | `before` not a parseable ISO-8601 |
| 401 | `AUTH_REQUIRED` | No JWT or expired |
| 403 | `FORBIDDEN_OTHER_USER` | Path `:userId` doesn't match `req.user.id` and not admin |
| 404 | `NOTIFICATION_NOT_FOUND` | `:id` doesn't exist OR caller doesn't own it (don't leak existence) |

Body shape: `{ "error": "human readable", "code": "MACHINE_READABLE" }`.

---

## 9. Pagination

Cursor-based, ordered by `created_at DESC`. The client passes
`before=<the oldest createdAt it has>` to get the next page.
Don't use offset/limit — soft-deletes and live inserts make
offsets unstable.

When the client first loads the screen (no cursor), return the
newest 50 rows. The screen ListView currently fits roughly
8–12 rows on screen so 50 covers ~5 screens of scroll without
needing a second round-trip.

---

## 10. Retention

- Rows older than **30 days** AND `is_read = true` can be deleted
  by a nightly cleanup job. Unread rows older than 30 days stay
  — if you've ignored a notification for a month, dropping it is
  probably fine, but it's the user's call to dismiss.
- A more aggressive retention (7 days) is fine for `meeting_*`
  types since the meeting itself is in the past at that point.
- Never auto-purge `security` rows — keep them at least 90 days
  for the user's own audit trail.

---

## 11. Real-time delivery (optional, v2)

The persistent endpoint + FCM combo is enough for v1. If you want
the bell badge to refresh without a poll while the app is in the
foreground, fan a single `notification:new` event onto the
existing `/signaling-fresh` socket (the chat namespace already
lives there — see `docs/CHATS_API.md` §3). The client can listen
on `socket.on('notification:new', invalidateNotificationsProvider)`
and the screen re-fetches automatically.

Not blocking for v1 — the FCM data-message already wakes the app
up.

---

## 12. Testing — curl scripts

Set `TOKEN=<your_jwt>` and `USER_ID=<your_user_id>` then:

```bash
# 1. list — fresh user, expect []
curl -k -s -H "Authorization: Bearer $TOKEN" \
  "https://192.168.1.20:3001/api/notifications/user/$USER_ID" | jq

# expected:
# { "data": [], "unreadCount": 0 }

# 2. seed a meeting_invite from psql (or your seed script):
#   INSERT INTO notifications (user_id, type, title, body, data)
#   VALUES ('$USER_ID', 'meeting_invite', 'Meeting invite — Standup',
#           'Farhan invited you. Starts Fri 10:00 AM.',
#           '{"meetingId":"uuid","meetingCode":"abc-defg-hij"}');

# 3. list again — expect 1 row
curl -k -s -H "Authorization: Bearer $TOKEN" \
  "https://192.168.1.20:3001/api/notifications/user/$USER_ID" | jq

# 4. mark as read
NOTIF_ID=<row_id>
curl -k -s -X PATCH -H "Authorization: Bearer $TOKEN" \
  "https://192.168.1.20:3001/api/notifications/$NOTIF_ID/read" | jq
# expected: { "id":"...","isRead":true,"readAt":"..." }

# 5. unread filter — expect [] now
curl -k -s -H "Authorization: Bearer $TOKEN" \
  "https://192.168.1.20:3001/api/notifications/user/$USER_ID?unread=true" | jq

# 6. forbidden — try to read someone else's list
OTHER_USER_ID=<another_user>
curl -k -s -H "Authorization: Bearer $TOKEN" \
  "https://192.168.1.20:3001/api/notifications/user/$OTHER_USER_ID" | jq
# expected: 403 {"error":"...","code":"FORBIDDEN_OTHER_USER"}

# 7. invalid limit
curl -k -s -H "Authorization: Bearer $TOKEN" \
  "https://192.168.1.20:3001/api/notifications/user/$USER_ID?limit=999" | jq
# expected: 400 {"error":"...","code":"INVALID_LIMIT"}
```

---

## 13. Migration order (one PR, in this order)

1. Migration: create `notifications` table + indexes.
2. Land `createNotification()` helper + tests.
3. Land `GET /api/notifications/user/:userId` + auth + tests.
4. Land `PATCH /api/notifications/:id/read` + auth + tests.
5. Wire emit calls in **meeting-service** first
   (`meeting_invite` + `meeting_started` cover ~80% of expected
   volume).
6. Wire emit calls in **scheduling-service** (`meeting_reminder`,
   `meeting_cancelled`, `meeting_rescheduled`) + cron.
7. Wire emit calls in **signaling-service** (`missed_call`).
8. Wire emit calls in **recording-service** (`recording_ready`).
9. Wire emit calls in **contacts-service** (`contact_joined`).
10. Wire emit calls in **auth-service** (`security`).
11. Land `PATCH /read-all`, `DELETE /:id`, `/unread-count` at
    leisure (client doesn't depend on them yet).

Stages 1–4 are the unblocker — the moment those ship, the
mobile screen renders real data. Stages 5–10 are independent of
each other and can ship in any order.

---

## 14. What the mobile client expects, verbatim

The Flutter `NotificationModel.fromJson` (see
`lib/data/models/models.dart:294`):

```dart
factory NotificationModel.fromJson(Map<String, dynamic> json) {
  return NotificationModel(
    id: json['id']?.toString() ?? '',
    title: json['title'] ?? 'Notification',
    body: json['content'] ?? json['body'] ?? '',
    type: json['type'] ?? 'info',
    createdAt: (DateTime.tryParse(json['createdAt'] ?? json['created_at'] ?? '') ?? DateTime.now()).toLocal(),
    isRead: json['isRead'] ?? json['is_read'] ?? false,
  );
}
```

That tolerates both camelCase and snake_case keys. Prefer the
camelCase shape going forward; snake_case is just legacy
tolerance.

`data` is not parsed today — it's there for the next iteration
(deep-link on tap). Send it anyway so the screen can wire taps
without a second migration.

---

## 15. Open questions for the backend team

1. **Existing rows?** Is there any half-built `notifications`
   table in dev already? If so, the schema in §2 might need a
   migration rather than a fresh create.
2. **Push token storage** — where are FCM device tokens stored?
   `users.fcm_token`? A separate `user_devices` table? The
   shared `createNotification()` helper needs to know.
3. **Real-time bus** — does the gateway run socket.io on the
   same process as the REST API, or is signaling on a separate
   container? Affects whether §11's `notification:new` socket
   event is one-line or needs a Redis pub/sub.
4. **Admin tooling** — should `GET /api/notifications/user/:userId`
   return more rows / different fields when called with an admin
   role? Default to "same shape, different scope" but flag if you
   want it richer.

Send answers (or just open a PR — your call) and we'll iterate.
