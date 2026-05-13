# Meeting presence & rejoin — backend specification

Status: **Draft v1** — implement against this contract; the Flutter client will
ship against this shape and currently degrades gracefully when the new fields
are absent (every recent meeting renders as "ended" until the backend supplies
`is_active`).

Audience: the dev who maintains `mizdah-backend.ogoul.cloud`.

---

## 1. Why this exists

The Recent tab on the Meetings screen currently shows every past meeting with a
chevron and a tappable card — there's no way for a user to tell whether the
meeting they hosted yesterday is *still going right now* or has ended hours ago.

WhatsApp / Google Meet solve this with a real-time "is this room live?" badge
plus a one-tap rejoin. We're matching that:

- A recent meeting card with `is_active = true` shows a LIVE pill, the current
  participant count, a chevron, and opens a "Rejoin meeting" bottom sheet on
  tap.
- A card with `is_active = false` shows no chevron, dims slightly, and is not
  tappable (or opens a read-only history detail).

The card has to react **without a refresh**: if the last participant leaves
the meeting while the user is on the Recent tab, the card silently downgrades
from active to ended.

---

## 2. The single invariant

```
meeting.is_active == TRUE  iff  COUNT(participants WHERE is_active = TRUE) > 0
```

The backend owns this. Clients **never** PATCH `is_active` directly — they emit
`join-meeting` / `leave-meeting` and the server recomputes inside the same DB
transaction. This is the only rule that matters; everything below is just how
that invariant is upheld and broadcast.

---

## 3. Database schema

### 3.1 `meetings` table

Add three columns:

| Column          | Type       | Notes                                          |
|-----------------|------------|------------------------------------------------|
| `is_active`     | BOOLEAN    | NOT NULL, default `TRUE` on insert             |
| `members_count` | INTEGER    | NOT NULL, default `0`, indexed                 |
| `ended_at`      | TIMESTAMP  | nullable; non-null **iff** `is_active = FALSE` |

Existing columns assumed present: `id` (UUID), `meeting_code` (string),
`host_id` (UUID), `title` (string), `started_at` (timestamp).

### 3.2 `participants` table

Add (or confirm existing):

| Column        | Type       | Notes                                                   |
|---------------|------------|---------------------------------------------------------|
| `joined_at`   | TIMESTAMP  | NOT NULL                                                |
| `left_at`     | TIMESTAMP  | nullable; non-null when the user has left               |
| `is_active`   | BOOLEAN    | NOT NULL, default `TRUE`; flips `FALSE` on leave/timeout|

Composite index: `(meeting_id, is_active)` — every state recomputation does
`SELECT COUNT(*) WHERE meeting_id = ? AND is_active = TRUE`. Without the index
this becomes the slowest hot-path query on the system.

### 3.3 Migration ordering

Run the migration in this order so the system never sees a half-state:

1. Add the three columns to `meetings` (nullable initially).
2. Backfill: for every row, set `members_count = 0`, `is_active = FALSE`,
   `ended_at = COALESCE(ended_at, started_at + INTERVAL '1 hour')`. Existing
   meetings are by definition not live anymore.
3. Apply NOT NULL constraints + default values.
4. Add the same columns + index to `participants`.

---

## 4. REST endpoint changes

### 4.1 `GET /api/participant/user/:userId`

Add three fields to **every meeting entry** in the response array.

Response 200 — new shape:

```json
{
  "meetings": [
    {
      "meeting_id": "uuid",
      "meeting_code": "abc-defg-hij",
      "title": "Sprint planning",
      "host_id": "uuid-of-host",
      "joined_at": "2026-05-12T10:08:00Z",
      "duration_seconds": 1842,
      "is_active": true,
      "members_count": 4,
      "ended_at": null
    },
    {
      "meeting_id": "uuid",
      "meeting_code": "xyz-pqrs-tuv",
      "title": "Design review",
      "host_id": "uuid-of-host",
      "joined_at": "2026-05-11T12:41:00Z",
      "duration_seconds": 2730,
      "is_active": false,
      "members_count": 0,
      "ended_at": "2026-05-11T13:27:30Z"
    }
  ]
}
```

Rules:

- `is_active` is a strict echo of `meetings.is_active`. No client-side guessing.
- `members_count` is the *current* count, not the peak — so when a meeting ends
  it reads `0`, not whatever the high-water mark was.
- `ended_at` is non-null **iff** `is_active = false`.
- Ordering stays as it is today (newest `joined_at` first). The client may
  re-sort to pin active meetings to the top — that's a UI decision, don't bake
  it into the API.

### 4.2 No new REST endpoints needed

Rejoin reuses the existing `GET /api/meetings/{code}` (or whatever the pre-join
fetch currently uses) and the existing socket `join-meeting` flow. The only
backend change for rejoin is that `join-meeting` on an already-ended meeting
**must** return a clean error so the client can show "This meeting has ended"
instead of letting the user into an empty room — see §7.3.

---

## 5. Socket protocol

### 5.1 Connection model

The Flutter client opens a **long-lived presence socket** on the existing
mediasoup namespace `/signaling-fresh` immediately on login (parallel to the
existing chat and P2P signaling sockets). It stays open until logout. This is
*not* the same socket that `joinMeeting()` opens for in-call signaling —
treat them as two separate connections from the same user.

Authentication: same `auth: { token: <JWT> }` handshake as every other socket.
Server resolves `userId` from the JWT and stamps it on the connection.

### 5.2 Subscription model

The simplest viable approach: **auto-subscribe on connect.**

On every successful socket handshake (presence socket OR in-call socket — easier
to do it uniformly), the server runs:

```sql
SELECT DISTINCT meeting_id
FROM participants
WHERE user_id = $userId
  AND joined_at > NOW() - INTERVAL '30 days'
```

…and joins that socket to one socket.io room per meetingId, plus a personal
room `user:{userId}`. The 30-day window keeps the per-socket subscription size
bounded; tune if needed. The personal room is the fallback for users whose
recent list changes mid-session (e.g., they join a brand-new meeting that
wasn't in the snapshot when the socket connected).

When a participant joins a meeting they weren't in before, the server should
**also** join their socket to that new meeting's room right then (inside the
`join-meeting` handler), so the user starts receiving updates for that meeting
without having to reconnect.

### 5.3 Event: `meeting-updated`

Direction: **server → client**. Emitted whenever the meeting's state changes
(member joins, member leaves, meeting deactivates).

Room target: `meeting:{meetingId}` — every socket subscribed to this meeting
receives the event regardless of which user owns it.

Payload:

```json
{
  "meetingId": "uuid",
  "meetingCode": "abc-defg-hij",
  "isActive": true,
  "membersCount": 3,
  "endedAt": null
}
```

Rules:

- Fire **once** per state change. If three participants leave simultaneously,
  emit once after the transaction commits — not three times.
- `endedAt` MUST be `null` while `isActive = true`. MUST be a non-null ISO
  timestamp when `isActive = false`.
- Field names are camelCase here even though the REST response uses snake_case.
  This matches the existing `user-joined` / `user-left` event convention in
  `meeting_provider.dart` and minimises client-side adapter code. Don't mix.

### 5.4 What the client does with it

The Flutter client maintains a `Map<meetingId, MeetingPresence>` in memory.
On every `meeting-updated`, the map is patched and any visible recent-meeting
card whose `meetingId` matches re-renders. Cards whose meeting is no longer in
the map (e.g., never had a presence event) fall back to the REST snapshot's
`is_active` field.

---

## 6. State machine

Three events drive the state machine. All three run inside a single DB
transaction so the recompute + emit pair is atomic.

### 6.1 Participant joins

```
BEGIN;

  UPSERT participants
    (meeting_id, user_id, joined_at, is_active, left_at)
    VALUES ($mid, $uid, NOW(), TRUE, NULL)
    ON CONFLICT (meeting_id, user_id)
    DO UPDATE SET is_active = TRUE, left_at = NULL, joined_at = NOW();
    -- ON CONFLICT branch handles re-join: same row, fresh timestamps.

  -- Recompute. Lock the meetings row to serialise concurrent join/leave.
  SELECT id, is_active FROM meetings WHERE id = $mid FOR UPDATE;

  newCount := SELECT COUNT(*) FROM participants
              WHERE meeting_id = $mid AND is_active = TRUE;

  UPDATE meetings
  SET members_count = newCount,
      is_active = TRUE,
      ended_at = NULL
  WHERE id = $mid;

COMMIT;

-- After commit:
io.to("meeting:" + $mid).emit("meeting-updated", {
  meetingId, meetingCode, isActive: true, membersCount: newCount, endedAt: null
});

-- Also join this socket to the meeting room if it wasn't already, so the
-- joiner gets future updates for this meeting.
socket.join("meeting:" + $mid);
```

### 6.2 Participant leaves (clean)

```
BEGIN;

  UPDATE participants
  SET is_active = FALSE, left_at = NOW()
  WHERE meeting_id = $mid AND user_id = $uid;

  SELECT id FROM meetings WHERE id = $mid FOR UPDATE;

  newCount := SELECT COUNT(*) FROM participants
              WHERE meeting_id = $mid AND is_active = TRUE;

  IF newCount = 0 THEN
    UPDATE meetings
    SET members_count = 0, is_active = FALSE, ended_at = NOW()
    WHERE id = $mid;
  ELSE
    UPDATE meetings SET members_count = newCount WHERE id = $mid;
  END IF;

COMMIT;

io.to("meeting:" + $mid).emit("meeting-updated", {
  meetingId, meetingCode,
  isActive: newCount > 0,
  membersCount: newCount,
  endedAt: newCount > 0 ? null : <timestamp>
});
```

### 6.3 Participant disconnect (network drop, app killed)

Clients won't always emit a clean `leave-meeting`. The socket layer is the only
truth source for "is this participant still here".

On socket `disconnect` for any socket that has the meeting room joined:

1. Look up `(socket.userId, meetingId)` — meaning *that user was in that
   meeting*.
2. If the user has **no other active sockets** in the same meeting room (they
   could be joined from another device), run the §6.2 leave logic.
3. If they have other sockets, do nothing — they're still in.

Server-side grace period: **5 seconds**. A reconnect within 5 seconds of
disconnect is treated as a non-event. This kills the flapping bug where mobile
users dipping into a tunnel briefly fire spurious leave→join cycles. Implement
with a per-socket `setTimeout` that's cleared on `reconnect`.

### 6.4 Ghost-participant cleanup (last-resort)

Even with disconnect handling, the participants table can leak rows that say
`is_active = TRUE` after a crash. Run a cron every 5 minutes:

```sql
UPDATE participants
SET is_active = FALSE,
    left_at = NOW()
WHERE is_active = TRUE
  AND meeting_id IN (
    SELECT id FROM meetings WHERE is_active = FALSE
  );
```

This is a safety net; the §6.3 disconnect path should make it find nothing 99%
of the time.

---

## 7. Edge cases

### 7.1 Race: A joins while B leaves

The `FOR UPDATE` row-lock on `meetings.id` in §6.1 and §6.2 serialises them.
Whichever transaction commits last gets the final `members_count`. Both
transactions emit their `meeting-updated`; the client takes the most recent.

### 7.2 Same user, multiple devices

If user X is in the meeting on their phone AND opens the same meeting on the
web tab, that's **one** active participant — not two. Use the `(meeting_id,
user_id)` unique constraint and treat it as idempotent: the second device's
join is a no-op for the count. When either device leaves, only set
`is_active = FALSE` after *all* of that user's sockets have left the room.

### 7.3 Rejoin attempted on an ended meeting

When a client emits `join-meeting` for a meeting where `is_active = FALSE` AND
the request is more than 60 seconds after `ended_at`, return:

```json
{ "error": "meeting_ended", "message": "This meeting has already ended." }
```

…via the existing `join-meeting` error channel (whichever ack/event you already
use). The 60-second grace lets a participant who briefly disconnected during
the moment the meeting ended re-establish the meeting if they want — they're
the host, they can pick up where they left off, and the meeting flips back to
active via §6.1. Past 60 seconds, the meeting is gone and the client shows
"This meeting has ended."

### 7.4 Backend restart

After a restart, every participant row is stale. On boot:

```sql
UPDATE meetings
SET is_active = FALSE,
    ended_at = NOW(),
    members_count = 0
WHERE is_active = TRUE;

UPDATE participants
SET is_active = FALSE,
    left_at = NOW()
WHERE is_active = TRUE;
```

Then on the first client reconnect for each meeting, the §6.1 path runs and the
meeting flips back to active if anyone actually rejoins. This is safe because
nobody was *truly* in those rooms during the restart anyway.

### 7.5 Backwards compatibility with older clients

Older Flutter builds don't know about `is_active` / `members_count` / `ended_at`
in the REST response. JSON additions are ignored by the existing parser, so
this is safe.

Older builds also don't subscribe to `meeting-updated` events. They'll see
stale state until they next refresh their recent list, which is the existing
behaviour — no regression.

---

## 8. Wire sequence examples

### 8.1 Meeting fills and empties

```
Time     | Actor    | Event                                          | State
---------|----------|------------------------------------------------|----------------------------
T+0:00   | Host A   | emit join-meeting (creates meeting)            | active=true,  count=1
         | server   | emit meeting-updated (count=1)                 |
T+0:42   | User B   | emit join-meeting                              | active=true,  count=2
         | server   | emit meeting-updated (count=2)                 |
T+1:08   | User C   | emit join-meeting                              | active=true,  count=3
         | server   | emit meeting-updated (count=3)                 |
T+8:30   | User B   | emit leave-meeting                             | active=true,  count=2
         | server   | emit meeting-updated (count=2)                 |
T+8:31   | User C   | socket disconnect (no clean leave)             | (5s grace started)
T+8:36   | server   | grace expires — treat as leave                 | active=true,  count=1
         | server   | emit meeting-updated (count=1)                 |
T+9:14   | Host A   | emit leave-meeting                             | active=false, count=0, ended_at=NOW
         | server   | emit meeting-updated (isActive=false)          |
```

### 8.2 User looking at Recent tab while a meeting they hosted ends

```
T+0:00 | User D opens app → presence socket connects → server auto-subscribes
        D's socket to meetings rooms for the last 30 days (5 meetings).
T+0:01 | User D taps Recent tab → callHistoryProvider fetches /api/participant/
        user/D. Three of D's recent meetings have is_active=true on the
        snapshot. Cards render with LIVE pills + member counts.
T+2:18 | The last participant in "Sprint planning" (one of D's recent meetings)
        leaves. Server runs §6.2 leave-logic, emits meeting-updated with
        isActive=false, endedAt=2026-05-12T16:50:18Z.
T+2:18 | D's presence socket receives the event. Flutter client patches the
        in-memory presence map. The matching card's trailing chevron
        AnimatedSwitcher swaps to the "Ended" label; the LIVE pill fades out.
        No tap target on the card any more.
```

### 8.3 Rejoin from the Recent tab

```
T+0:00 | User E sees a card showing "Sprint planning · LIVE · 3 in meeting".
T+0:01 | E taps the card → client opens the Rejoin bottom sheet.
T+0:02 | While the sheet is open, the meeting's last other participant leaves.
        Server emits meeting-updated isActive=false to E's presence socket.
        The bottom sheet listens to the same presence provider — its Rejoin
        button disables and shows "Meeting ended"; auto-dismiss after 2s.
T+0:04 | Sheet closes. The Recent card itself flips to inactive state.
```

If E had tapped Rejoin in the brief window before the deactivation event
arrived, the §7.3 server-side guard returns `meeting_ended` on the
`join-meeting` emit and the client shows the same toast.

---

## 9. Acceptance criteria

The backend dev can mark this done when **all** of the following are true. Run
each as an integration test against the real socket + REST stack.

- [ ] Creating a meeting with one host sets `meetings.is_active = TRUE`,
      `members_count = 1`, and `participants` has one row with `is_active = TRUE`.
- [ ] `GET /api/participant/user/:userId` returns the three new fields on every
      entry. `is_active = true` entries have `ended_at = null`; `is_active =
      false` entries have non-null `ended_at`.
- [ ] Two clients join the same meeting — both receive a `meeting-updated`
      event with `membersCount = 2` within 200ms of the second join.
- [ ] The first client leaves cleanly — both clients receive a
      `meeting-updated` with `membersCount = 1`.
- [ ] The second client kills its socket (no clean leave). Within 6 seconds
      (5s grace + 1s emit latency), `meetings.is_active` flips to `FALSE`,
      `ended_at` is set, and a `meeting-updated` with `isActive: false` is
      emitted to anyone still subscribed to that meeting's room.
- [ ] A client that was offline during all the above, then connects, gets the
      correct `is_active` / `members_count` from the REST snapshot. No
      stale-active meetings.
- [ ] Backend restart: every active meeting is force-deactivated on boot.
- [ ] `join-meeting` against a deactivated meeting (more than 60s after
      `ended_at`) returns `meeting_ended`. Within 60s, it succeeds and the
      meeting flips back to active.
- [ ] Same user joining from phone + web counts as `members_count = 1`, not 2.
- [ ] Three participants leaving simultaneously emit ONE `meeting-updated`,
      not three. (Verify by `console.log` inside the emit path.)

---

## 10. Open questions for the backend dev

These are decisions the backend dev should make — flag if the answers differ
from the client's assumptions:

1. **Should `members_count` include the host?** Client assumes yes — the host
   is a participant. If the backend treats hosts separately, the client UI
   counter will be off by one.
2. **Window for "recent meetings" subscription** — defaulted to 30 days in §5.2.
   Anything from 7 days to 90 days is fine; longer means more rooms per socket,
   shorter means missed updates on older meetings. 30d is a reasonable
   default.
3. **Rate limit on `meeting-updated`** — at peak, a meeting with 50 participants
   shuffling in and out fires ~5 events/sec. Cheap on the wire but worth a
   small debounce (e.g., coalesce events for the same meeting within a 250ms
   window). Not required for v1; flag if you see backpressure.

---

## 11. Client-side wiring (FYI for the backend dev)

The Flutter client side of this protocol lives in:

- `lib/data/models/models.dart` — `CallHistory` gets three new nullable fields.
- `lib/features/meeting/services/meeting_presence_service.dart` (new) —
  presence socket + in-memory state.
- `lib/features/meeting/meeting_presence_provider.dart` (new) — Riverpod glue.
- `lib/features/meetings/presentation/meetings_screen.dart` — `_RecentCard`
  gains active/inactive render branches.
- `lib/features/meeting/presentation/rejoin_sheet.dart` (new) — modal sheet.

The client degrades gracefully when the backend hasn't shipped: all three new
fields default to null, every meeting renders as ended, and the recent list
behaves exactly as it does today (chevron, navigates to pre-join). No client
update needed to ship the backend changes.
