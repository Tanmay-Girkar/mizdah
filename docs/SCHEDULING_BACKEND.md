# Scheduling — backend changes needed

This document describes the changes the **backend developer** needs
to make so the mobile app's "Schedule a meeting" feature works
correctly. The mobile client has been updated to a forward-compatible
shape — once the changes below are deployed, the workaround in the
client (a `[code]` suffix in `title`) becomes a no-op and can be
removed in a later cleanup.

Audience: the dev who maintains `mizdah-backend.ogoul.cloud`.

Verified against the live server on **2026-05-03**.

---

## TL;DR — what's broken

1. `POST /api/scheduling/schedule` **silently drops** `meetingId` /
   `meetingCode` if the client sends them. Response always returns
   `"meetingId": null`. The schedule row therefore has no link to a
   real meeting.
2. `GET /api/scheduling/user/<userId>` does not return any meeting
   identifier — only `id`, `hostId`, `title`, `startTime`, `endTime`,
   `recurrence`, `timezone`, `createdAt`. Without a meeting code the
   mobile UI cannot navigate to the scheduled meeting.
3. The `DELETE` route the legacy mobile client called
   (`DELETE /api/scheduling/schedule/<id>`) returned **404**. The
   actual route is `DELETE /api/scheduling/<id>`. The mobile client
   has been corrected — but please confirm the route stays at
   `/api/scheduling/<id>` going forward.

After (1) and (2) ship, the client will read `meetingCode` directly
from the schedule object and the legacy "embed code in title" hack
becomes harmless dead code.

---

## Current vs. expected behaviour

### `POST /api/scheduling/schedule`

**Request the client now sends:**

```json
{
  "hostId":      "9844168e-2c11-4633-aa27-706efac987df",
  "meetingId":   "449086c4-3ddc-443a-85ec-bb5c681753ff",   // ← stored Meeting.id
  "meetingCode": "docscht3xy",                              // ← stored Meeting.meeting_code
  "title":       "Mizdah Meeting [docscht3xy]",
  "startTime":   "2026-05-04T10:00:00.000Z",
  "endTime":     "2026-05-04T11:00:00.000Z",
  "recurrence":  "none",
  "timezone":    "UTC"
}
```

**Current response** (verified against prod):

```json
{
  "id":         "638eb18d-f79b-4148-85a3-d4786ab2b003",
  "meetingId":  null,                                       // ← DROPPED
  "hostId":     "9844168e-2c11-4633-aa27-706efac987df",
  "title":      "Mizdah Meeting [docscht3xy]",
  "startTime":  "2026-05-04T10:00:00.000Z",
  "endTime":    "2026-05-04T11:00:00.000Z",
  "recurrence": "none",
  "timezone":   "UTC",
  "createdAt":  "2026-05-03T13:33:17.935Z"
}
```

**Required response:**

```json
{
  "id":          "638eb18d-f79b-4148-85a3-d4786ab2b003",
  "meetingId":   "449086c4-3ddc-443a-85ec-bb5c681753ff",    // ← echoed back
  "meetingCode": "docscht3xy",                               // ← echoed back
  "hostId":      "9844168e-2c11-4633-aa27-706efac987df",
  "title":       "Mizdah Meeting",                           // ← can be the raw client title; suffix removal optional
  "startTime":   "2026-05-04T10:00:00.000Z",
  "endTime":     "2026-05-04T11:00:00.000Z",
  "recurrence":  "none",
  "timezone":    "UTC",
  "createdAt":   "2026-05-03T13:33:17.935Z"
}
```

The minimal change is: **persist** `meetingId` and `meetingCode`
(or one of them — see below), and **return** them in the response.

### `GET /api/scheduling/user/<userId>`

**Current response** — same shape as create, missing the meeting
link.

**Required response:**

```json
[
  {
    "id":          "638eb18d-f79b-4148-85a3-d4786ab2b003",
    "meetingId":   "449086c4-3ddc-443a-85ec-bb5c681753ff",
    "meetingCode": "docscht3xy",
    "hostId":      "9844168e-2c11-4633-aa27-706efac987df",
    "title":       "Mizdah Meeting",
    "startTime":   "2026-05-04T10:00:00.000Z",
    "endTime":     "2026-05-04T11:00:00.000Z",
    "recurrence":  "none",
    "timezone":    "UTC",
    "createdAt":   "2026-05-03T13:33:17.935Z"
  }
]
```

If you only persist `meetingId` (the FK), please **JOIN** with the
meetings table on read to also return `meetingCode` — the client
needs the human-readable code to drive the join URL
(`/pre-join/<code>`). UUIDs are not valid meeting codes.

### `DELETE /api/scheduling/<id>`

This is **already correct** on the server. The mobile client has
been fixed to call this path. No backend change required — just
please don't move it.

---

## Suggested schema change

Whichever DB you're using, add a column on the schedules table:

```sql
ALTER TABLE schedules
  ADD COLUMN meeting_id UUID REFERENCES meetings(id) ON DELETE SET NULL;

CREATE INDEX schedules_meeting_id_idx ON schedules (meeting_id);
```

You may want a `meeting_code` denormalisation too if cross-table
joins on read are expensive, but a JOIN is fine for the volume we
have.

The schedule controller's create handler should:

1. Accept `meetingId` (UUID) **or** `meetingCode` (string) in the
   POST body. If only `meetingCode` is supplied, look up the
   meeting by code and use its `id`.
2. Persist `meeting_id` on the new row.
3. Return both `meetingId` and `meetingCode` in the response, the
   latter joined from the meetings table.

The list handler should join in `meeting_code` so the client
doesn't need a second round-trip per row.

---

## Why both `meetingId` and `meetingCode`?

The mobile client sends both because we don't know which one your
ORM/handler prefers as the primary key into `meetings`. Pick the
one that fits your codebase — both refer to the same row:

```sql
SELECT * FROM meetings
 WHERE id = $meetingId
    OR meeting_code = $meetingCode
 LIMIT 1;
```

In the response, please return **both** so the client can choose
the friendlier one for display vs. routing.

---

## Why this matters

Right now in production:

- The user taps "Schedule in Google Calendar"
- The Mizdah backend creates a `schedules` row with `meetingId: null`
- The client (now fixed) creates a real meeting first and embeds
  its code in the title (workaround)
- Without that workaround, **the calendar invite would link to a
  non-existent meeting**, and the user's home screen tile would
  navigate to a 404 ("Meeting not found")

After the changes above, the workaround is no longer needed — the
client already sends and reads the proper fields, so flipping the
backend's behaviour will make the feature work cleanly with **zero
mobile redeploy**.

---

## Test plan once shipped

After deploying the backend change, run:

```bash
USERID="9844168e-2c11-4633-aa27-706efac987df"

# Create a meeting
M=$(curl -s -X POST "https://mizdah-backend.ogoul.cloud/api/meetings/create" \
  -H "Content-Type: application/json" \
  -d "{\"hostId\":\"$USERID\",\"title\":\"T\",\"scheduledFor\":\"2026-05-04T10:00:00\",\"id\":\"betatest1\",\"meeting_code\":\"betatest1\"}")
MID=$(echo "$M" | jq -r .id)

# Schedule it
S=$(curl -s -X POST "https://mizdah-backend.ogoul.cloud/api/scheduling/schedule" \
  -H "Content-Type: application/json" \
  -d "{\"hostId\":\"$USERID\",\"meetingId\":\"$MID\",\"meetingCode\":\"betatest1\",\"title\":\"T\",\"startTime\":\"2026-05-04T10:00:00Z\",\"endTime\":\"2026-05-04T11:00:00Z\",\"recurrence\":\"none\",\"timezone\":\"UTC\"}")
echo "$S" | jq '.meetingId, .meetingCode'
# expected:  "<MID>"  "betatest1"

# Read it back
curl -s "https://mizdah-backend.ogoul.cloud/api/scheduling/user/$USERID" \
  | jq '.[] | {id, meetingId, meetingCode, title}'
# expected:  the same row, with meetingCode == "betatest1"

# Cleanup
curl -s -X DELETE "https://mizdah-backend.ogoul.cloud/api/scheduling/$(echo "$S" | jq -r .id)"
```

If `meetingId` and `meetingCode` are both populated (not null) on
both POST and GET, the change is correct and the mobile UI will
start showing the real codes on the schedule tiles automatically
on the next cold start.

---

## Frontend status

The mobile client (commit pending) does the following BEFORE this
backend change ships:

- Creates the actual meeting room first via `/api/meetings/create`
  so a real, working code exists on the server.
- Sends `meetingId` and `meetingCode` to `/api/scheduling/schedule`
  (currently dropped, but ready for when persisted).
- Embeds the code into the schedule's `title` in the form
  `Original Title [code]` so it can be recovered on later GETs.
- The home-screen tile reads `meetingCode` if present, else
  `meetingId`, else parses the `[code]` suffix back out of `title`.
- Tapping the tile navigates to `/pre-join/<code>`.

After this backend change ships, the title-suffix path becomes a
fallback that almost never fires; we'll clean it up in a follow-up.
