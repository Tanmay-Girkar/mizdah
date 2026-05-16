# Host Management & Host Transfer — Backend Spec

Three-tier role system (Host / Co-host / Participant), automatic
host transfer on disconnect with a 45-second reconnect grace
window, and a meeting lifecycle state machine. Replaces the
implicit "host_id is whoever created the meeting and that's it"
model with a real role system that survives host drops, allows
co-host promotion, and never strands a meeting because one
participant lost their connection.

Solves the user-reported issue:
> "If the host leaves the meeting, the meeting should continue
> for remaining participants instead of ending."

Architecture is documented + decided. v1 is built for current
scale (single signaling pod is OK; Redis is required); the
sharding-friendly choices in §11 let us scale out later without
schema churn.

---

## 0. Conventions

Same as the other backend docs in this folder:

- Gateway: `https://<dev-host>:3001` (dev),
  `https://mizdah-backend.ogoul.cloud` (prod).
- Auth: `Authorization: Bearer <JWT>` required on every endpoint.
- Bodies: `application/json`.
- Errors: `{ "error": "human readable", "code": "MACHINE_READABLE" }`.
- Timestamps: ISO-8601 UTC.
- IDs: UUID strings.
- Socket namespace: `/signaling-fresh` (same one chat + media
  signaling already run on).

---

## 1. Summary of changes

| Change | Where | Status |
|---|---|---|
| `meeting_participants.role` VARCHAR(16) column | DB migration | NEW |
| `meetings.lifecycle_state` VARCHAR(16) column | DB migration | NEW |
| `meetings.ended_at` TIMESTAMPTZ column | DB migration | NEW |
| `meeting_audit` table | DB migration | NEW |
| `PATCH /api/meeting/:id/participants/:userId/role` | new REST route | NEW |
| `POST /api/meeting/:id/transfer-host` | new REST route | NEW |
| `POST /api/meeting/:id/resume-host` | new REST route | NEW |
| `GET /api/meeting/:id/audit` | new REST route | NEW |
| Socket event `meeting:host_changed` | signaling-service | NEW |
| Socket event `meeting:host_reconnecting` | signaling-service | NEW |
| Socket event `meeting:host_reconnected` | signaling-service | NEW |
| Socket event `meeting:role_updated` | signaling-service | NEW |
| Socket event `meeting:state_changed` | signaling-service | NEW |
| Socket event `meeting:ended` (new reason codes) | signaling-service | EXTEND |
| Redis presence + reconnect-token + distributed-lock keys | infra | NEW |
| RoleManager service module | signaling-service | NEW |
| ReconnectManager service module | signaling-service | NEW |
| MeetingLifecycle state-machine module | signaling-service | NEW |
| Disconnect handler — drives host-leaves logic | signaling-service | EXTEND |

Decisions locked in (from the mobile team's product call):
- **3-tier roles**: Host + Co-host + Participant (no "Presenter").
- **Grace window**: 45 seconds.
- **Ephemeral store**: Redis (required for multi-pod signaling).

Estimated effort: **16–22 hours** for the full Phase 1+2+3
implementation. Phase 1 alone (roles + transfer, no reconnect
grace) is ~10–14 h and already fixes the host-leaves-meeting-dies
issue.

---

## 2. Data model — schema migrations

### Phase 1 — roles

```sql
ALTER TABLE meeting_participants
  ADD COLUMN role VARCHAR(16) NOT NULL DEFAULT 'participant';
-- Allowed values: 'host' | 'co_host' | 'participant'.
-- Stored as VARCHAR not enum so adding 'presenter' later is a
-- code change, not a migration.

-- Backfill: every existing row gets its role from meetings.host_id
-- so a meeting in flight at deploy time doesn't lose its host.
UPDATE meeting_participants mp
SET role = 'host'
FROM meetings m
WHERE mp.meeting_id = m.id
  AND mp.user_id = m.host_id;

CREATE INDEX idx_meeting_participants_role
  ON meeting_participants (meeting_id, role)
  WHERE is_active = TRUE;
```

### Phase 3 — lifecycle + ended_at

```sql
ALTER TABLE meetings
  ADD COLUMN lifecycle_state VARCHAR(16) NOT NULL DEFAULT 'WAITING';
-- 'WAITING' | 'ACTIVE' | 'HOST_RECONNECTING' | 'ENDED'

ALTER TABLE meetings
  ADD COLUMN ended_at TIMESTAMPTZ;
-- NULL while the meeting is still alive. Set on transition to ENDED.

-- Backfill: any meeting where ALL participants left long ago is
-- already effectively ENDED. Conservative: leave them WAITING
-- (default) and let the next health-check job clean them.
```

### Phase 3 — audit log

```sql
CREATE TABLE meeting_audit (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  meeting_id  UUID NOT NULL REFERENCES meetings(id) ON DELETE CASCADE,
  actor_id    UUID,                  -- null for system-initiated events
  event_type  VARCHAR(32) NOT NULL,
  -- 'host_changed' | 'role_granted' | 'role_revoked' |
  -- 'host_reconnecting' | 'host_reconnected' | 'state_changed' |
  -- 'meeting_ended'
  payload     JSONB NOT NULL DEFAULT '{}'::jsonb,
  at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_meeting_audit_meeting_at
  ON meeting_audit (meeting_id, at DESC);
```

### Prisma equivalents

```prisma
model MeetingParticipant {
  // existing fields ...
  role String @default("participant") @db.VarChar(16)
  @@index([meetingId, role])
}

model Meeting {
  // existing fields ...
  lifecycleState String    @default("WAITING") @map("lifecycle_state") @db.VarChar(16)
  endedAt        DateTime? @map("ended_at")
}

model MeetingAudit {
  id         String   @id @default(uuid())
  meetingId  String   @map("meeting_id")
  meeting    Meeting  @relation(fields: [meetingId], references: [id], onDelete: Cascade)
  actorId    String?  @map("actor_id")
  eventType  String   @map("event_type") @db.VarChar(32)
  payload    Json     @default("{}")
  at         DateTime @default(now())
  @@index([meetingId, at(sort: Desc)])
  @@map("meeting_audit")
}
```

---

## 3. Redis key structure

Required (no in-memory fallback). All keys use the `{meetingId}`
hash-tag pattern so they land on the same Redis Cluster node when
sharding lands later.

| Key | Type | TTL | Purpose |
|---|---|---|---|
| `presence:meeting:{meetingId}` | Set\<userId\> | none while ACTIVE; deleted on ENDED | Roster — who's in the room right now |
| `presence:socket:<socketId>` | Hash `{userId, meetingId}` | 30 s rolling | Reverse-lookup on socket drop |
| `reconnect:{meetingId}` | Hash `{hostUserId, sessionToken}` | 45 s | Host's grace-window claim slot |
| `lock:transfer:{meetingId}` | string `<podId>` | 10 s | Distributed lock for transfer logic |
| `lifecycle:{meetingId}` | string `<state>` | none while not ENDED | Mirror of `meetings.lifecycle_state` for fast reads |
| `host:{meetingId}` | string `<userId>` | none while not ENDED | Mirror of `meetings.host_id` for fast reads |

The 30-second rolling TTL on `presence:socket:*` is refreshed by
the heartbeat the client sends every 10 s (existing pattern). If
three heartbeats are missed, the socket is presumed dead, the
disconnect handler fires, and the participant row flips
`is_active = false`. This is the stale-participant cleanup
mechanism — no separate cron job needed.

---

## 4. State machine

```
                ┌──────────┐  first participant joins
                │ WAITING  │ ──────────────────────────┐
                │  (host   │                           │
                │  hasn't  │                           ▼
                │  joined) │                       ┌─────────┐
                └────┬─────┘                       │ ACTIVE  │
                     │  host joined                │ (≥1     │
                     └────────────────────────────▶│ partic) │
                                                   └────┬────┘
                                                        │
                                  host disconnected     │
                                  (socket drop)         │
                  ┌────────────┐         │              │
                  │  HOST_     │◀────────┘              │
                  │ RECONNECT- │                        │
                  │   ING      │                        │
                  └────┬───┬───┘                        │
            host       │   │  45s grace expires        │
            reconnects │   │  → transfer host          │
                       │   └───────────────────────────┤
                       └───────────────────────────────┘
                                                        │
                            last participant leaves     │
                            OR host clicks End-for-all  ▼
                                                   ┌─────────┐
                                                   │  ENDED  │
                                                   └─────────┘
```

Transitions also fan a `meeting:state_changed` socket event so
every client tracks the same lifecycle.

---

## 5. Role-transfer algorithm

Triggered by:
- Host's socket disconnects AND grace expires (§6)
- Host explicitly calls `POST /transfer-host` (§7.3)
- Host explicitly calls "End for all" — no transfer, meeting goes
  to ENDED directly

Pseudocode (server-side, behind the distributed lock):

```js
async function transferHostOnDisconnect(meetingId) {
  // SETNX with 10s TTL — only one signaling-pod proceeds.
  const lockKey = `lock:transfer:{${meetingId}}`;
  const lockToken = randomBytes(16).toString('hex');
  const acquired = await redis.set(
    lockKey,
    lockToken,
    'NX',
    'EX',
    10
  );
  if (!acquired) return; // Another pod is handling it.

  try {
    // Idempotency: if state isn't HOST_RECONNECTING any more,
    // bail — someone else already handled the transfer OR the
    // host came back.
    const state = await redis.get(`lifecycle:{${meetingId}}`);
    if (state !== 'HOST_RECONNECTING') return;

    // Pick the new host:
    //   1. Earliest-joined co-host
    //   2. Otherwise earliest-joined active participant
    const candidate = await prisma.meetingParticipant.findFirst({
      where: {
        meetingId,
        isActive: true,
        userId: { not: currentHostId },
      },
      orderBy: [
        // 'co_host' sorts before 'participant' alphabetically,
        // which is the priority we want. If you ever rename the
        // role strings keep this ordering in mind, or replace
        // with a CASE-based SQL ORDER BY.
        { role: 'desc' },
        { joinedAt: 'asc' },
      ],
    });

    if (!candidate) {
      // No one left to be host — end the meeting.
      await endMeeting(meetingId, 'host_lost');
      return;
    }

    // Atomic role swap in a transaction.
    await prisma.$transaction([
      prisma.meeting.update({
        where: { id: meetingId },
        data: { hostId: candidate.userId, lifecycleState: 'ACTIVE' },
      }),
      prisma.meetingParticipant.updateMany({
        where: { meetingId, userId: currentHostId },
        data: { role: 'participant' },
      }),
      prisma.meetingParticipant.update({
        where: { meetingId_userId: { meetingId, userId: candidate.userId } },
        data: { role: 'host' },
      }),
      prisma.meetingAudit.create({
        data: {
          meetingId,
          actorId: null,
          eventType: 'host_changed',
          payload: {
            from: currentHostId,
            to: candidate.userId,
            reason: 'disconnect',
          },
        },
      }),
    ]);

    // Mirror to Redis fast-read path.
    await redis.set(`host:{${meetingId}}`, candidate.userId);
    await redis.set(`lifecycle:{${meetingId}}`, 'ACTIVE');

    // Fan to the room.
    io.to(`meeting:${meetingId}`).emit('meeting:host_changed', {
      newHostUserId: candidate.userId,
      newHostName: candidate.name,
      previousHostUserId: currentHostId,
      reason: 'disconnect',
    });
    io.to(`meeting:${meetingId}`).emit('meeting:state_changed', {
      lifecycleState: 'ACTIVE',
    });
  } finally {
    // Release the lock — only if WE hold it. Avoids releasing
    // someone else's lock if our work overran the 10s TTL.
    const stored = await redis.get(lockKey);
    if (stored === lockToken) await redis.del(lockKey);
  }
}
```

**Why the lock**: two signaling pods can detect the host's socket
drop within milliseconds. Without the lock, both run the transfer
in parallel → two simultaneous host assignments + two
`host_changed` fan-outs. The SETNX + 10s TTL is enough — even if
the holding pod crashes, the lock auto-releases.

---

## 6. Reconnect grace state machine

When the host's socket disconnects:

```js
async function onHostSocketDisconnect(meetingId, hostUserId) {
  // 1. Flip meeting state.
  await prisma.meeting.update({
    where: { id: meetingId },
    data: { lifecycleState: 'HOST_RECONNECTING' },
  });
  await redis.set(`lifecycle:{${meetingId}}`, 'HOST_RECONNECTING');

  // 2. Mint a one-time resume token. Only this token can claim
  //    the host slot back during the grace window — prevents
  //    someone else from stealing the host role by passing the
  //    meetingId mid-grace.
  const sessionToken = randomBytes(32).toString('hex');
  await redis.set(
    `reconnect:{${meetingId}}`,
    JSON.stringify({ hostUserId, sessionToken }),
    'EX',
    45
  );

  // 3. Hand the token to the client OUT OF BAND.
  //    On Phase 1 we deliver via FCM data-message — the host's
  //    device receives it whether the app is foregrounded or
  //    backgrounded. Tag with kind=host_resume_token and the
  //    payload {meetingId, sessionToken, expiresAt}.
  await pushService.sendDataMessage(hostUserId, {
    kind: 'host_resume_token',
    meetingId,
    sessionToken,
    expiresAt: new Date(Date.now() + 45_000).toISOString(),
  });

  // 4. Fan to the room so participants see the banner.
  io.to(`meeting:${meetingId}`).emit('meeting:host_reconnecting', {
    hostUserId,
    graceSeconds: 45,
    expiresAt: new Date(Date.now() + 45_000).toISOString(),
  });

  // 5. Audit.
  await prisma.meetingAudit.create({
    data: {
      meetingId,
      actorId: hostUserId,
      eventType: 'host_reconnecting',
      payload: { graceSeconds: 45 },
    },
  });

  // 6. Schedule the expire-and-transfer.
  setTimeout(async () => {
    const stillHere = await redis.get(`reconnect:{${meetingId}}`);
    if (stillHere) {
      await redis.del(`reconnect:{${meetingId}}`);
      await transferHostOnDisconnect(meetingId);
    }
  }, 45_000);
}
```

When the host calls `POST /resume-host` with the token (§7.4):

```js
async function resumeHost(meetingId, presentedToken, callerUserId) {
  const raw = await redis.get(`reconnect:{${meetingId}}`);
  if (!raw) {
    return { ok: false, code: 'RESUME_WINDOW_EXPIRED' };
  }
  const { hostUserId, sessionToken } = JSON.parse(raw);
  if (callerUserId !== hostUserId || sessionToken !== presentedToken) {
    return { ok: false, code: 'RESUME_TOKEN_INVALID' };
  }

  await redis.del(`reconnect:{${meetingId}}`);
  await prisma.meeting.update({
    where: { id: meetingId },
    data: { lifecycleState: 'ACTIVE' },
  });
  await redis.set(`lifecycle:{${meetingId}}`, 'ACTIVE');

  io.to(`meeting:${meetingId}`).emit('meeting:host_reconnected', {
    hostUserId,
  });
  io.to(`meeting:${meetingId}`).emit('meeting:state_changed', {
    lifecycleState: 'ACTIVE',
  });

  await prisma.meetingAudit.create({
    data: {
      meetingId,
      actorId: hostUserId,
      eventType: 'host_reconnected',
      payload: {},
    },
  });
  return { ok: true };
}
```

**Why a session token (not just userId)**: in a brief network blip
the host's auth token might be cached on another device or in
local browser storage. Without the resume token, a colleague on
the same JWT could claim the host slot. The token is generated
server-side on each disconnect, delivered via FCM (out-of-band),
and lives 45 s. Anyone without it gets a 403.

---

## 7. REST endpoints

### 7.1 `PATCH /api/meeting/:id/participants/:userId/role`

Host promotes / demotes a participant.

**Authorization:**
- Caller is the host of `:id`.
- Admin role bypass: yes.
- Returns `403 FORBIDDEN_NOT_HOST` otherwise.

**Request:**

```json
{ "role": "co_host" }
```

Allowed values: `host`, `co_host`, `participant`.

**Setting `role: "host"` is a transfer**, equivalent to calling
`POST /transfer-host`. Idiomatic if you want a single PATCH for
all role changes; the dedicated transfer endpoint exists for
clients that prefer the explicit verb.

**Response (200):**

```json
{ "ok": true, "userId": "uuid", "role": "co_host" }
```

**Errors:**

| HTTP | code | When |
|---|---|---|
| 400 | `INVALID_ROLE` | Role isn't one of the three allowed values |
| 400 | `CANNOT_DEMOTE_HOST_VIA_ROLE` | Trying to set the current host to `participant`/`co_host` — use `POST /transfer-host` instead |
| 401 | `AUTH_REQUIRED` | No JWT |
| 403 | `FORBIDDEN_NOT_HOST` | Caller isn't the host |
| 404 | `PARTICIPANT_NOT_FOUND` | `:userId` isn't an active participant |
| 409 | `MEETING_NOT_ACTIVE` | Meeting is in `WAITING` / `HOST_RECONNECTING` / `ENDED` |

**On success:** emits `meeting:role_updated` `{ userId, role,
changedByUserId }` to the meeting room. Audit row written.

### 7.2 `POST /api/meeting/:id/transfer-host`

Explicit host transfer. Same effect as
`PATCH /participants/:userId/role { role: "host" }` but the verb
+ payload make audit logs grep-able.

**Authorization:** host-only.

**Request:**

```json
{ "toUserId": "uuid" }
```

**Response (200):**

```json
{ "ok": true, "newHostUserId": "uuid", "previousHostUserId": "uuid" }
```

**Errors:**

| HTTP | code | When |
|---|---|---|
| 400 | `CANNOT_TRANSFER_TO_SELF` | `toUserId == caller.id` |
| 400 | `TARGET_NOT_ACTIVE` | Target isn't currently in the meeting |
| 401 | `AUTH_REQUIRED` | No JWT |
| 403 | `FORBIDDEN_NOT_HOST` | Caller isn't the host |
| 404 | `MEETING_NOT_FOUND` | `:id` doesn't exist or already ENDED |

**On success:** atomic role swap (transaction), emits
`meeting:host_changed` with `reason: 'manual'`. Both rows audited.

### 7.3 `POST /api/meeting/:id/resume-host`

Host claims their slot back during the grace window. Body carries
the one-time token delivered via the FCM data-message that the
disconnect handler sent.

**Authorization:** caller must equal the `hostUserId` stored in
the `reconnect:{meetingId}` Redis key AND the token must match.

**Request:**

```json
{ "sessionToken": "<32-hex from the FCM data message>" }
```

**Response (200):**

```json
{ "ok": true }
```

**Errors:**

| HTTP | code | When |
|---|---|---|
| 401 | `AUTH_REQUIRED` | No JWT |
| 403 | `RESUME_TOKEN_INVALID` | Wrong token or wrong user |
| 410 | `RESUME_WINDOW_EXPIRED` | Past the 45 s grace; transfer already fired |

**On success:** state goes back to `ACTIVE`, fans
`meeting:host_reconnected`, audit row written, the original host
keeps the slot.

### 7.4 `GET /api/meeting/:id/audit`

Paginated audit log. Host or admin only.

**Query params:**

| Param | Default | Notes |
|---|---|---|
| `limit` | 50 | Hard cap at 200 |
| `before` | — | ISO-8601 cursor (returns rows with `at < before`) |

**Response (200):**

```json
{
  "data": [
    {
      "id": "uuid",
      "actorId": "uuid",
      "eventType": "host_changed",
      "payload": { "from": "uuid", "to": "uuid", "reason": "disconnect" },
      "at": "2026-05-15T08:30:00.000Z"
    }
  ],
  "nextCursor": "2026-05-15T08:25:00.000Z"
}
```

---

## 8. Socket events (additions to `/signaling-fresh`)

### `meeting:host_changed`

Server → meeting room. Sent on any host transition (manual,
disconnect-triggered, or "End for all").

```json
{
  "kind": "meeting:host_changed",
  "meetingId": "uuid",
  "newHostUserId": "uuid",
  "newHostName": "Test User 1",
  "previousHostUserId": "uuid",
  "reason": "manual" | "disconnect" | "left"
}
```

### `meeting:host_reconnecting`

Server → meeting room. Sent the instant the host's socket
disconnects, before the 45 s grace timer starts ticking.

```json
{
  "kind": "meeting:host_reconnecting",
  "meetingId": "uuid",
  "hostUserId": "uuid",
  "graceSeconds": 45,
  "expiresAt": "2026-05-15T08:30:45.000Z"
}
```

### `meeting:host_reconnected`

Server → meeting room. Sent when `resume-host` succeeds before
grace expires.

```json
{
  "kind": "meeting:host_reconnected",
  "meetingId": "uuid",
  "hostUserId": "uuid"
}
```

### `meeting:role_updated`

Server → meeting room. Sent on any role change that isn't a host
transfer (i.e. promote/demote to/from co-host).

```json
{
  "kind": "meeting:role_updated",
  "meetingId": "uuid",
  "userId": "uuid",
  "role": "co_host" | "participant",
  "changedByUserId": "uuid"
}
```

### `meeting:state_changed`

Server → meeting room. Sent on every lifecycle transition. Mobile
clients listen to flip banners / disable-during-reconnect UI.

```json
{
  "kind": "meeting:state_changed",
  "meetingId": "uuid",
  "lifecycleState": "WAITING" | "ACTIVE" | "HOST_RECONNECTING" | "ENDED"
}
```

### `meeting:ended` (extended `reason` codes)

Already exists. New `reason` values:

| `reason` | When |
|---|---|
| `host_ended` | Host clicked End-for-all |
| `all_left` | Every participant including the host has gone |
| `host_lost` | Host disconnected, grace expired, no candidate available for transfer |

```json
{
  "kind": "meeting:ended",
  "meetingId": "uuid",
  "reason": "host_ended" | "all_left" | "host_lost"
}
```

---

## 9. Backend folder structure (matches existing pattern)

```
backend/
  signaling-service/
    src/
      services/
        meetingLifecycle.js      ← state machine transitions
        roleManager.js           ← grant / revoke / transfer
        reconnectManager.js      ← grace period + tokens
        presence.js              ← Redis presence sync
      handlers/
        socketDisconnect.js      ← drives host-leaves logic
        socketHeartbeat.js       ← 30 s rolling TTL refresh
      locks/
        distributedLock.js       ← SETNX + TTL wrapper
      routes/
        role.js                  ← §7.1
        transfer.js              ← §7.2
        resumeHost.js            ← §7.3
        audit.js                 ← §7.4
      events/
        emitters.js              ← single place that owns each fan-out
```

The five `services/*.js` modules are pure functions over Postgres
+ Redis. The `handlers/*.js` glue them to socket events. Keeping
this split means the role-manager logic is unit-testable without
spinning up a socket server.

---

## 10. Edge cases

| Case | Behavior |
|---|---|
| Host clicks **End for all** | `endMeeting(meetingId, 'host_ended')` — no transfer, no grace. State → ENDED, `meeting:ended` fanned. |
| Host drops + reconnects within 45 s | Grace timer cancelled (token DEL'd); state → ACTIVE; `host_reconnected` fanned. No transfer fired. |
| Host drops + 2 co-hosts exist | Earliest-joined co-host wins (`ORDER BY role DESC, joined_at ASC LIMIT 1`). |
| Host drops + no co-host + only 1 participant | That participant becomes host. They get a `host_changed` event for themselves. UI shows "You're now the host" toast. |
| Host drops + last participant leaves during grace | `lock:transfer:{meetingId}` is held only briefly. The "no candidate" branch of the transfer fires → state → ENDED, reason `host_lost`. Reconnect token DEL'd. |
| Two signaling pods both see host drop | First to win `SETNX lock:transfer:{meetingId}` runs the transfer. Second sees state != `HOST_RECONNECTING` (the first changed it) and returns. |
| Host's phone permanently dies (no rejoin) | 45 s later, auto-transfer fires normally. |
| Promoted-to-host user disconnects 5 s later | Cascade — same grace logic applies to them. New `HOST_RECONNECTING` → 45 s → next-candidate transfer. |
| Participant disconnects mid-grace | Their participant row's `is_active = false` flips on next heartbeat miss. If they were the only remaining candidate, the eventual transfer hits "no candidate" → ENDED. |
| Someone tries `POST /resume-host` without the token | 403 `RESUME_TOKEN_INVALID`. Doesn't extend or affect the grace timer. |
| Someone tries `POST /resume-host` AFTER grace expired | 410 `RESUME_WINDOW_EXPIRED`. State is already past `HOST_RECONNECTING` — transfer or end has fired. |
| Host promotes a non-active participant | 400 `TARGET_NOT_ACTIVE`. Can't promote someone who isn't in the meeting. |
| Host demotes the only co-host while themselves dropping | Race: caller's PATCH lands first (sync REST), then disconnect handler runs. Transfer goes through earliest-joined participant since no co-host remains. Correct outcome. |

---

## 11. Scale path (deferred — DO NOT BUILD NOW)

These are listed so the v1 architecture stays sharding-friendly,
NOT as work for this phase.

| Item | When to actually do it | What stays compatible |
|---|---|---|
| Redis Cluster | When single-Redis hits ~50k ops/sec | Hash-tag pattern `{meetingId}` already in every key — drop-in upgrade |
| Multiple signaling pods | When single pod hits ~5k concurrent meetings | Distributed lock in §5 already pod-safe; presence + reconnect Redis keys are pod-agnostic |
| Meeting-id sharded routing | When even Redis Cluster is hot | Hash-tag pattern lets the ingress sticky-route by meetingId without re-sharding |
| Audit log archival | When `meeting_audit` exceeds ~50M rows | Roll old rows to cold storage; `meeting_audit` has the right indexes for time-bounded delete |
| Separate role-manager microservice | Never, probably. | In-process modules in `services/*` keep the network hop count low; only split if a single host transfer takes >100 ms locally |

`§13 1M+ users` from the spec template falls under "deferred" —
hash-tag keys + stateless REST + sticky-per-meeting sockets are
the architectural prerequisites; no further work needed now.

---

## 12. Testing — curl scripts

Set up:

```bash
TOKEN_HOST=$(curl -k -s -X POST https://192.168.1.20:3001/api/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"email":"test1@mizdah.dev","password":"<pw>"}' | jq -r .token)
TOKEN_CO=$(   ... test2 ... )
TOKEN_GUEST=$(... test3 ... )

MEETING_ID="<an active meeting test1 hosts; test2 + test3 joined>"
TEST2_USER_ID="<uuid>"
TEST3_USER_ID="<uuid>"
```

```bash
# ── 1. Host promotes test2 to co-host ─────────────────────────
curl -k -s -X PATCH \
  "https://192.168.1.20:3001/api/meeting/$MEETING_ID/participants/$TEST2_USER_ID/role" \
  -H "Authorization: Bearer $TOKEN_HOST" \
  -H 'Content-Type: application/json' \
  -d '{"role":"co_host"}' | jq

# Expected: 200 { "ok": true, "userId":"...", "role":"co_host" }
# Also expected: every socket in the room receives
#                meeting:role_updated { userId, role:"co_host", ... }

# ── 2. Non-host tries to promote — denied ─────────────────────
curl -k -s -X PATCH \
  "https://192.168.1.20:3001/api/meeting/$MEETING_ID/participants/$TEST3_USER_ID/role" \
  -H "Authorization: Bearer $TOKEN_GUEST" \
  -H 'Content-Type: application/json' \
  -d '{"role":"co_host"}' | jq
# Expected: 403 FORBIDDEN_NOT_HOST

# ── 3. Manual host transfer ───────────────────────────────────
curl -k -s -X POST \
  "https://192.168.1.20:3001/api/meeting/$MEETING_ID/transfer-host" \
  -H "Authorization: Bearer $TOKEN_HOST" \
  -H 'Content-Type: application/json' \
  -d "{\"toUserId\":\"$TEST2_USER_ID\"}" | jq

# Expected: 200 { "ok":true, "newHostUserId":"...", "previousHostUserId":"..." }
# Also expected: meeting:host_changed fanned with reason:"manual"
#                test1 + test2 participant rows have roles swapped
#                meeting.host_id flipped to test2

# ── 4. Cannot transfer to self ────────────────────────────────
TEST1_USER_ID="<uuid>"
curl -k -s -X POST \
  "https://192.168.1.20:3001/api/meeting/$MEETING_ID/transfer-host" \
  -H "Authorization: Bearer $TOKEN_HOST" \
  -H 'Content-Type: application/json' \
  -d "{\"toUserId\":\"$TEST1_USER_ID\"}" | jq
# Expected: 400 CANNOT_TRANSFER_TO_SELF

# ── 5. Auto-transfer on host disconnect (manual reproduction) ─
# Disconnect test1's signaling socket abruptly:
#   • close their tab / kill the app, OR
#   • kill -9 the socket on the dev server
# Verify:
#   • All clients in meeting receive meeting:host_reconnecting
#     within ~1 s.
#   • test1's user receives an FCM data-message with the
#     sessionToken.
#   • At t+45 s, all clients receive meeting:host_changed with
#     reason:"disconnect", host flips to earliest co-host
#     (test2 if §1 ran).
#   • SELECT lifecycle_state FROM meetings WHERE id = $MEETING_ID
#     transitions WAITING/ACTIVE → HOST_RECONNECTING → ACTIVE.

# ── 6. Host reconnects within grace window ───────────────────
# Simulate by capturing the sessionToken from the FCM payload
# delivered to test1, then before t+45:
curl -k -s -X POST \
  "https://192.168.1.20:3001/api/meeting/$MEETING_ID/resume-host" \
  -H "Authorization: Bearer $TOKEN_HOST" \
  -H 'Content-Type: application/json' \
  -d "{\"sessionToken\":\"<the token from the FCM>\"}" | jq
# Expected: 200 { "ok": true }
# Also expected: meeting:host_reconnected fanned;
#                no transfer fires when the 45 s timer expires;
#                state → ACTIVE.

# ── 7. Reject stale resume after grace ───────────────────────
# Wait > 45 s, then try the same resume call:
curl -k -s -X POST \
  "https://192.168.1.20:3001/api/meeting/$MEETING_ID/resume-host" \
  -H "Authorization: Bearer $TOKEN_HOST" \
  -H 'Content-Type: application/json' \
  -d "{\"sessionToken\":\"<old token>\"}" | jq
# Expected: 410 RESUME_WINDOW_EXPIRED

# ── 8. Audit log ─────────────────────────────────────────────
curl -k -s "https://192.168.1.20:3001/api/meeting/$MEETING_ID/audit?limit=20" \
  -H "Authorization: Bearer $TOKEN_HOST" | jq
# Expected: chronological list with each role change + transfer
#           + reconnect event from above tests.

# ── 9. Non-host can't read audit ─────────────────────────────
curl -k -s "https://192.168.1.20:3001/api/meeting/$MEETING_ID/audit?limit=20" \
  -H "Authorization: Bearer $TOKEN_GUEST" | jq
# Expected: 403 FORBIDDEN_NOT_HOST

# ── 10. Last participant leaves — meeting ends ───────────────
# Reproduce manually: with state ACTIVE, leaveMeeting in turn
# from each device until only the host is left, then host leaves.
# Expected: meeting:ended { reason: "all_left" }, state → ENDED,
#          meetings.ended_at set.
```

---

## 13. Migration order (one PR per stage, in this order)

1. **Schema migration A** — `meeting_participants.role` column +
   backfill rule (§2).
2. **Schema migration B** — `meetings.lifecycle_state` + `ended_at`
   + `meeting_audit` table (§2).
3. **Land helpers** — `distributedLock`, `presence.js` Redis sync,
   `meetingLifecycle.js` state-machine module + unit tests.
4. **Land role manager + endpoints** — `roleManager.js`, §7.1
   `PATCH /role`, §7.2 `POST /transfer-host`. Wire
   `meeting:role_updated` + `meeting:host_changed` emitters.
5. **Wire socketDisconnect handler** — detect host vs non-host
   drop; non-host path flips `is_active=false`, host path goes to
   `reconnectManager.startGrace()`.
6. **Land reconnect manager** — `reconnectManager.js`, §7.3
   `POST /resume-host`. Wire `meeting:host_reconnecting` +
   `meeting:host_reconnected` emitters.
7. **Wire grace-expire transfer** — the 45 s scheduled callback
   that runs `transferHostOnDisconnect`.
8. **Land audit endpoint** — §7.4 `GET /audit`. Host-only +
   admin bypass.
9. **Extend `meeting:ended` reason codes** — add `host_lost`,
   `all_left`, keep `host_ended`. Mobile gracefully handles
   unknown reasons via the generic fallback.

**Independent slices:**
- Stages 1–4 alone fix the user-stated bug (meeting continues
  after host leaves) — no reconnect grace, just instant transfer
  on socket drop. Acceptable for first ship.
- Stages 5–7 add the grace window UX polish.
- Stage 8 is non-blocking audit/observability.

---

## 14. Open questions for backend

1. **Existing Redis presence?** — if the signaling service already
   stores presence in Redis under a different key shape, we should
   either reuse that or document the migration. §3 assumes greenfield.
2. **FCM data-message size cap** — the resume token is 32 hex
   chars (~64 bytes). FCM data messages are 4 KB max. Should be
   fine but worth confirming nothing else is being shoved into
   that same payload.
3. **Grace timer in-pod vs cron** — §6 uses `setTimeout` inside
   the signaling-pod that detected the disconnect. If that pod
   crashes, the timer is lost and the transfer never fires
   (state stays in `HOST_RECONNECTING` forever). For production
   resilience, the timer should live in a small scheduled-task
   service (the existing `scheduling-service` if it can run cron
   jobs, or a new lightweight worker). For v1 with a single
   signaling pod this is academic.
4. **"Co-host" capability matrix** — what specifically CAN a
   co-host do that a participant can't? Proposal:
     - Co-host CAN: invite (`/invite-in-call`), change global
       toggle (`/permissions`), grant per-user invite
       (`/participants/.../permissions`), kick participants
       (future endpoint), end-for-all is HOST ONLY.
     - Co-host CANNOT: transfer host, end-for-all, demote
       host.
   Confirm or push back.
5. **What if every participant is a co-host?** — fine, no
   contention. The earliest-joined still wins on auto-transfer.
6. **Resume on app cold start** — if the host's app was force-
   killed and reopens 30 s later, the FCM message is in the
   notification tray. Tapping it deep-links to the meeting AND
   carries the sessionToken. Confirm the FCM data payload doesn't
   strip the token through that path.

Send answers and we'll iterate.
