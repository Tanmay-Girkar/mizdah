# Scheduling backend — what works, what doesn't (2026-05-09)

Snapshot taken with curl against the dev gateway
`https://192.168.1.100:3001`. The Flutter "Schedule in Google Calendar"
flow now works end-to-end *despite* one of the two backend services being
broken — but the broken one is still worth fixing.

---

## ✅ Scheduling service — fully working

`/api/scheduling/schedule` (POST) and `/api/scheduling/user/:userId` (GET)
are both healthy. Verified live:

```bash
curl -sk -X POST https://192.168.1.100:3001/api/scheduling/schedule \
  -H "Content-Type: application/json" \
  -d '{
    "hostId":"<uuid>",
    "title":"Mizdah Meeting [abc123]",
    "startTime":"2026-05-09T18:00:00.000Z",
    "endTime":"2026-05-09T19:00:00.000Z",
    "recurrence":"none",
    "timezone":"Asia/Kolkata",
    "meetingCode":"abc123"
  }'
# → 200 {"id":"...","meetingId":null,"meetingCode":"abc123",...}
```

**Fields the controller reads**
(verified by deliberately sending `{}` and reading the Prisma error
echo):

| Field | Type | Required? | Notes |
| --- | --- | --- | --- |
| `hostId` | UUID string | yes | |
| `title` | string | yes | The scheduling service uses `title`, **not** `topic` (different from meeting-service — see below) |
| `startTime` | ISO 8601 | yes | Must parse to a valid `Date` |
| `endTime` | ISO 8601 | yes | |
| `recurrence` | string | yes | `none` / `daily` / `weekly` / etc. |
| `timezone` | string | yes | IANA name |
| `meetingId` | UUID/null | no | Nullable in the DB ✓ |
| `meetingCode` | string/null | no | Nullable in the DB ✓ |

The Flutter app is now wired to call this endpoint with
`meetingId: null` and a client-generated `meetingCode`, so scheduling
works **without depending on the meeting-service.**

---

## ❌ Meeting service — Prisma migration not applied

`/api/meetings/create` (POST) and `/api/meetings/user/:userId` (GET) both
500 with the same root cause:

```
Invalid prisma.meeting.create() invocation
  → const meeting = await prisma.meeting.create(
  The column `topic` does not exist in the current database.
```

The code at `backend/meeting-service/index.js:121` writes a `topic`
column that the database hasn't been migrated to add. The validator a
few lines earlier (`Meeting topic is required`) was updated but the
schema migration was never run.

**To fix:**

```bash
cd backend/meeting-service
npx prisma migrate dev --name add_topic_column
# or `npx prisma migrate deploy` for prod
```

After that:
- `POST /api/meetings/create` will start creating rooms again.
- `GET /api/meetings/user/<id>` (used by Recent Activity hosted-meeting
  detection) will stop 500-ing.

The Flutter app already sends both `topic` and `title` in the body
(see `lib/data/repositories/mizdah_repository.dart`), so once the
column exists, no client change is needed.

---

## Other gaps the same log surfaced

These aren't blocking the calendar flow, but worth a look:

### 1. `/api/notifications/user/<userId>` returns 404 (HTML)

```
GET /api/notifications/user/<uuid>
→ 404 <!DOCTYPE html>... (Next.js error page)
```

The notifications service either isn't routed under `/api/notifications`
on the gateway, or the path moved. The HTML response means the gateway
fell through to a Next.js catch-all rather than reverse-proxying.

### 2. `/api/auth/me` returned `session_superseded`

```
{"user":null,"reason":"session_superseded"}
```

Auth flow appears to invalidate prior sessions when a new login lands.
That's normally desirable, but worth confirming the lifecycle is
intentional (mobile users juggle multiple devices).

### 3. `/chats` socket namespace times out

```
[chats] socket connect_error: timeout
```

The Flutter client connects to `<baseUrl>/chats` with the default
engine.io path `/socket.io/`. The existing P2P signaling uses
`/signaling-fresh` — if the chats namespace was mounted on a custom
engine.io path, please share what it is so we can update the client.
REST polling is the live fallback right now (read receipts still
flip every 4s).

---

## End-to-end "Schedule in Google Calendar" flow (current)

```
User taps "Schedule in Google Calendar"
       │
       ├── Flutter generates code locally
       │      (e.g. "abcdefghij")
       │
       ├── Builds CalendarPayload
       │
       ├──> launchUrl(externalApplication,
       │     "https://calendar.google.com/calendar/render?...")
       │     ├── Google Calendar app installed → opens app prefilled
       │     └── Not installed → opens browser prefilled
       │
       └──> POST /api/scheduling/schedule    (in parallel — non-blocking)
              ├── 200 → row appears in /api/scheduling/user/<id>
              │         → "Upcoming Meetings" refreshes
              └── failure → debugPrint, no user-facing error
                            (calendar entry on Google's side is
                             already saved, so the user isn't blocked)
```

The persist call is fire-and-forget so calendar opening never
waits on the backend.
