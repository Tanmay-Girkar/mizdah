# Add participant during a live session — Backend Spec

New backend work for the "Add participant" button the mobile app
will show during a meeting, voice call, or video call. Two
endpoints + two socket events; an existing meeting + invite
schema is reused for the heavy lifting.

End-state UX from the mobile side:

- User taps `+ Add` in the meeting/call toolbar.
- Bottom sheet appears with search + recent peers.
- User picks someone.
- Invitee's phone rings (FCM + in-app ring screen).
- Invitee taps Accept → joins the same meeting.
- For P2P calls, both original peers transparently move from P2P
  to SFU media on a fresh meeting room — the existing call does
  NOT drop, the media just briefly reconnects.

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

---

## 1. Summary of changes

| Change | Where | Status |
|---|---|---|
| `POST /api/meeting/:id/invite-in-call` | new REST route | NEW |
| `POST /api/p2p-call/:callId/promote-to-meeting` | new REST route | NEW |
| `PATCH /api/meeting/:id/permissions` | new REST route | NEW |
| `PATCH /api/meeting/:id/participants/:userId/permissions` | new REST route | NEW |
| `meetings.permissions` JSONB column (DDL migration) | schema | NEW |
| `meeting_participants.can_invite` BOOLEAN column (DDL migration) | schema | NEW |
| Socket event `meeting:in-call-invite` on `/signaling-fresh` | signaling-service | NEW |
| Socket event `p2p:promoted` on `/signaling-fresh` | signaling-service | NEW |
| Socket event `meeting:permissions-changed` on `/signaling-fresh` | signaling-service | NEW |
| Socket event `meeting:participant-permissions-changed` on `/signaling-fresh` | signaling-service | NEW |
| FCM data-message `kind: "in_call_invite"` | shared push util | NEW |
| Notifications row `type: "in_call_invite"` | uses existing inbox table | NEW |
| Authorization helper `isParticipantOf(userId, meetingId)` | shared util | NEW |
| Authorization helper `isHostOf(userId, meetingId)` | shared util | NEW |
| Authorization helper `hasInvitePermission(userId, meetingId)` | shared util | NEW |
| Reset `can_invite=false` whenever participant row goes inactive | trigger / app-level | NEW |
| Include `canInvite` in `participants-list` / `user-joined` payloads | signaling-service | NEW |
| Rate limit: max 5 invites/minute per inviter per meeting | middleware | NEW |

No changes to any existing endpoint. Additive only.

Estimated effort: **12–16 hours** for four endpoints, four socket
events, FCM pairing, two new schema columns + migrations, the
auth helper consolidation, and the rejoin-resets-grant rule.
Most of the cost is still the P2P promotion plumbing — the
permission endpoints are mostly column updates + emit fan-out.

---

## 2. `POST /api/meeting/:id/invite-in-call`

Send an invite to one user to join an **already-in-progress**
meeting. Different from the existing scheduler invite-fan-out
because:

- No new schedule row is created. The meeting is live now.
- The invitee gets a **ringing screen** (`in_progress: true`) — not
  a "scheduled meeting" tile.
- The endpoint must verify the caller is actually IN the meeting,
  not just any authenticated user.

### Authorization

Caller must clear BOTH checks:

1. **Participation gate.** Caller must be the authenticated user
   (JWT) AND be currently marked as `active` in
   `meeting_participants` for this meeting.
   - Returns `403 FORBIDDEN_NOT_PARTICIPANT` otherwise.

2. **Host-permission gate.** Either:
   - Caller is the host (`meetings.host_id == caller.id`), OR
   - `meetings.permissions.allowParticipantsToInvite == true`.
   - Returns `403 INVITE_NOT_ALLOWED_BY_HOST` when caller isn't
     the host AND the host has locked invites down. **Use a
     distinct error code from `FORBIDDEN_NOT_PARTICIPANT`** —
     mobile renders "Host has disabled invites" vs "You're not in
     this meeting" differently.

Admin role bypass: yes for both gates.

See §2a for the permission flag + how the host toggles it.

### Request body

```json
{
  "inviteeUserId": "uuid-of-existing-mizdah-user",
  "inviteeEmail": "alternative — server resolves to userId"
}
```

Exactly one of `inviteeUserId` or `inviteeEmail` must be present.
If both present, prefer `inviteeUserId`.

### Response (200)

```json
{
  "ok": true,
  "inviteId": "uuid",
  "inviteeUserId": "uuid",
  "meetingCode": "abc-defg-hij"
}
```

### Errors

| HTTP | code | When |
|---|---|---|
| 400 | `MISSING_INVITEE` | Neither `inviteeUserId` nor `inviteeEmail` provided |
| 400 | `CANNOT_INVITE_SELF` | inviteeUserId == caller's user id |
| 400 | `ALREADY_IN_MEETING` | invitee already has an active participant row |
| 401 | `AUTH_REQUIRED` | No JWT |
| 403 | `FORBIDDEN_NOT_PARTICIPANT` | Caller isn't in the meeting |
| 403 | `INVITE_NOT_ALLOWED_BY_HOST` | Host has set `allowParticipantsToInvite = false` and caller isn't the host |
| 404 | `MEETING_NOT_FOUND` | `:id` doesn't exist OR meeting has already ended |
| 404 | `INVITEE_NOT_FOUND` | inviteeEmail/userId doesn't match a Mizdah user |
| 409 | `MEETING_FULL` | Hit the per-meeting participant cap (proposed: 8 for v1, configurable) |
| 429 | `RATE_LIMITED` | More than 5 invites/minute by this inviter in this meeting |

### What the backend does on success

1. Insert a row into the existing `notifications` table (per
   `docs/NOTIFICATIONS_BACKEND.md` §3) with:
   - `type: "in_call_invite"` (NEW type — add to client + server
     dictionaries simultaneously)
   - `title: "{caller.name} is calling"` (or "added you to a call")
   - `body: "Tap to join the meeting."`
   - `data: { meetingCode, meetingId, hostUserId, callerName, callerAvatarUrl, in_progress: true, expiresAt }`
2. Push an FCM data-message with `kind: "in_call_invite"` and the
   same payload — the mobile client renders the ringing screen
   from this push.
3. Emit a `meeting:in-call-invite` socket event on the
   `/signaling-fresh` namespace to the invitee's currently-
   connected sockets (if any). Same payload. Powers the in-app
   ringing screen when the app is already open.
4. Start a 30-second auto-expire timer. If the invitee hasn't
   joined or declined by then, mark the notification as expired so
   the ringing screen times out. (Match the P2P auto-decline
   behaviour in `p2p_call_provider.dart::_autoDeclineTimer`.)

---

## 2a. Per-meeting permissions — `meetings.permissions`

The host controls whether **non-host participants** can invite
others to the live meeting. The flag lives on the meeting row so
late-joiners + reconnects all read the same source of truth.

### Schema migration

```sql
ALTER TABLE meetings
  ADD COLUMN permissions JSONB NOT NULL
  DEFAULT '{"allowParticipantsToInvite": true}'::jsonb;
```

Prisma equivalent:

```prisma
model Meeting {
  // ... existing fields ...
  permissions Json @default("{\"allowParticipantsToInvite\": true}")
}
```

**Backfill rule:** existing meeting rows get the same default
(`allowParticipantsToInvite: true`) on migration. This matches
pre-feature behaviour where anyone in a meeting could effectively
share the meeting code — the new feature only adds the ability to
restrict.

**Shape rationale:** stored as a JSON blob (not a flat boolean
column) so the next host-control toggle — `allowScreenShare`,
`muteOnJoin`, `lockMeeting`, etc. — is a JSON key add instead of a
schema migration. Client tolerates unknown keys.

### Read path

Every `GET /api/meeting/:code` response should now include the
`permissions` blob:

```json
{
  "id": "uuid",
  "code": "abc-defg-hij",
  "host_id": "uuid",
  "permissions": { "allowParticipantsToInvite": true }
  // ... rest ...
}
```

Same for `GET /api/meetings/user/:userId` rows — the mobile client
reads `permissions` off each row when it lands on the meeting
screen.

---

## 2b. `PATCH /api/meeting/:id/permissions`

Update the host-controlled permission flags for a live meeting.

### Authorization

- Caller MUST be the host (`meetings.host_id == caller.id`).
- Admin role bypass: yes.
- Returns `403 FORBIDDEN_NOT_HOST` for everyone else.

### Request body

```json
{
  "allowParticipantsToInvite": false
}
```

Partial updates — only the keys present in the body are touched.
Missing keys retain their existing values. (Easier for the mobile
client to send `{ allowParticipantsToInvite: <new> }` without
echoing the full blob.)

### Response (200)

```json
{
  "ok": true,
  "permissions": {
    "allowParticipantsToInvite": false
  }
}
```

### Errors

| HTTP | code | When |
|---|---|---|
| 400 | `INVALID_PERMISSIONS_BODY` | Body isn't a JSON object, or contains keys outside the known set |
| 401 | `AUTH_REQUIRED` | No JWT |
| 403 | `FORBIDDEN_NOT_HOST` | Caller isn't the host |
| 404 | `MEETING_NOT_FOUND` | `:id` doesn't exist OR meeting ended |

### What the backend does on success

1. Patch the JSONB column with the supplied keys.
2. Emit `meeting:permissions-changed` over `/signaling-fresh` to
   the meeting room (`meeting:<meetingId>`):

   ```json
   {
     "kind": "meeting:permissions-changed",
     "meetingId": "uuid",
     "permissions": { "allowParticipantsToInvite": false },
     "changedByUserId": "uuid"
   }
   ```

3. Mobile clients listen and update `meetingProvider.state.permissions`
   immediately — non-host clients hide the `+ Add` button as soon
   as the host flips the toggle.

### Race-condition note

A participant might tap `+ Add` and have the request reach
`/api/meeting/:id/invite-in-call` AFTER the host has already
flipped `allowParticipantsToInvite` to `false`. The server reads
the flag at request-processing time, so this races cleanly:
**last write wins**, server returns `403 INVITE_NOT_ALLOWED_BY_HOST`,
mobile shows a "Host has disabled invites" snackbar. The
participant doesn't get to slip an invite through.

### Authorization helper

```js
// services/auth-checks.js
async function isHostOf(userId, meetingId) {
  const m = await prisma.meeting.findUnique({
    where: { id: meetingId },
    select: { host_id: true },
  });
  return m && m.host_id === userId;
}
```

Used by `PATCH /permissions` and also by the host-only branch of
the `invite-in-call` authorization check (§2.Authorization).

---

## 2c. Per-participant invite grants (additive on top of §2a)

The global `allowParticipantsToInvite` toggle is binary — everyone
or no one. Real meetings sometimes need a third state: **everyone
denied EXCEPT this one person**. The host might be the only one
sending invites in a 10-person all-hands, but they want their
co-facilitator to be able to add a late-joiner too.

This section adds a per-participant grant that **stacks on top** of
the global toggle. The auth gate for `invite-in-call` becomes:

```
caller is allowed to invite if ANY of:
  • caller is the host
  • meetings.permissions.allowParticipantsToInvite == true
  • meeting_participants[caller].can_invite == true
```

The mobile UI only surfaces the per-participant grant when the
global toggle is **OFF** (no reason to clutter rows with switches
when everyone can already invite anyway).

### Schema migration

```sql
ALTER TABLE meeting_participants
  ADD COLUMN can_invite BOOLEAN NOT NULL DEFAULT FALSE;

-- Index helps the invite-in-call hot path: "is THIS user allowed
-- to invite RIGHT NOW?" looks up one row.
CREATE INDEX idx_meeting_participants_can_invite
  ON meeting_participants (meeting_id, user_id, can_invite)
  WHERE is_active = TRUE;
```

Prisma:

```prisma
model MeetingParticipant {
  // ... existing fields ...
  canInvite Boolean @default(false) @map("can_invite")

  @@index([meetingId, userId, canInvite])
}
```

### Reset-on-rejoin rule (REQUIRED)

When a participant row goes inactive (the user leaves, host kicked,
network drop after timeout, …) the server **MUST** clear
`can_invite` back to FALSE. Two equivalent implementations:

- **App-level** (recommended): wherever you set `is_active = false`,
  also `can_invite = false` in the same UPDATE.
- **Trigger-level**: Postgres trigger on `meeting_participants`
  update that mirrors the flip.

This matches the Zoom/Meet "co-host" lifecycle and avoids stale
grants on someone who joined for 10 seconds two weeks ago.

Mobile side does NOT remember the grant locally — every time a
participant rejoins, the participants-list payload from the server
is the source of truth.

---

## 2d. `PATCH /api/meeting/:id/participants/:userId/permissions`

Host-only — flip a single non-host participant's invite grant.

### Authorization

- Caller must be the host (`isHostOf`).
- Admin role bypass: yes.
- Returns `403 FORBIDDEN_NOT_HOST` otherwise.
- Returns `404 PARTICIPANT_NOT_FOUND` if `:userId` isn't a current
  active participant of `:id`.
- Returns `400 CANNOT_GRANT_HOST_SELF` if `:userId == meetings.host_id`
  (host already has infinite invite power; setting can_invite on the
  host row would be a no-op that confuses the audit log).

### Request body

```json
{
  "canInvite": true
}
```

### Response (200)

```json
{
  "ok": true,
  "userId": "uuid",
  "canInvite": true
}
```

### What the backend does on success

1. Update `meeting_participants.can_invite` for the (meeting,
   userId) row.
2. Emit `meeting:participant-permissions-changed` on the meeting
   room socket so every other client updates the granted-user's
   row in their participants panel and recomputes their own
   `+ Add` button visibility:

   ```json
   {
     "kind": "meeting:participant-permissions-changed",
     "meetingId": "uuid",
     "userId": "uuid",
     "canInvite": true,
     "changedByUserId": "uuid"
   }
   ```

3. Also include `canInvite` in the live participants-list payload
   that `user-joined` / `participants-update` events carry. Mobile
   clients keep their local list in sync, so a late-joiner with
   a grant already in place sees their `+ Add` button on first
   render.

### Race-condition note

Same model as the global toggle (§2b): the server reads
`can_invite` at request-processing time, so if the host revokes
a grant 50 ms after a participant tapped `+ Add`, the invite
endpoint sees the revoked state and returns
`403 INVITE_NOT_ALLOWED_BY_HOST`. Last-write-wins.

---

## 2e. Updated `invite-in-call` auth gate

Replace §2.Authorization with the three-way OR:

```
1. Participation gate (unchanged):
   - caller MUST be active in meeting_participants for :id.
   - 403 FORBIDDEN_NOT_PARTICIPANT otherwise.

2. Invite-permission gate (updated):
   - allowed if ANY of:
     a) caller is the host (host_id == caller.id), OR
     b) meetings.permissions.allowParticipantsToInvite == true, OR
     c) meeting_participants[caller].can_invite == true
   - 403 INVITE_NOT_ALLOWED_BY_HOST otherwise.
```

The error code stays `INVITE_NOT_ALLOWED_BY_HOST` whether the
caller lacks the global flag OR the per-user grant — from the
caller's perspective both are "host hasn't given me permission".

### Authorization helper additions

```js
// services/auth-checks.js
async function hasInvitePermission(userId, meetingId) {
  // Single round-trip — pull the meeting + participant rows together.
  const result = await prisma.meeting.findUnique({
    where: { id: meetingId },
    select: {
      host_id: true,
      permissions: true,
      participants: {
        where: { user_id: userId, is_active: true },
        select: { can_invite: true },
        take: 1,
      },
    },
  });
  if (!result) return false;
  if (result.host_id === userId) return true;
  if (result.permissions?.allowParticipantsToInvite === true) return true;
  return result.participants[0]?.can_invite === true;
}
```

Use this from the `invite-in-call` handler instead of the two
existing checks — cleaner and one DB hit instead of two.

---

## 3. `POST /api/p2p-call/:callId/promote-to-meeting`

Turn an active P2P 1:1 call into a server-mediated meeting so a
3rd (or 4th, …) participant can join.

### Authorization

- Caller must be either of the two peers in the P2P call.
- Admin bypass: yes.
- Returns `403 FORBIDDEN_NOT_IN_CALL` otherwise.

### Request body

```json
{
  "inviteeUserId": "uuid"
}
```

`inviteeEmail` accepted as alternative, same rule as §2.

### Response (200)

```json
{
  "ok": true,
  "meetingId": "uuid",
  "meetingCode": "abc-defg-hij",
  "inviteId": "uuid"
}
```

### Errors

| HTTP | code | When |
|---|---|---|
| 400 | `MISSING_INVITEE` | Body missing both id and email |
| 400 | `CANNOT_INVITE_SELF` | inviteeUserId is one of the two existing peers |
| 401 | `AUTH_REQUIRED` | No JWT |
| 403 | `FORBIDDEN_NOT_IN_CALL` | Caller isn't a peer on this callId |
| 404 | `CALL_NOT_FOUND` | callId doesn't exist OR call already ended |
| 404 | `INVITEE_NOT_FOUND` | Invitee isn't a Mizdah user |
| 409 | `ALREADY_PROMOTED` | This call was already promoted (`promote-to-meeting` is non-idempotent — second call errors) |
| 429 | `RATE_LIMITED` | More than 3 promotes/minute per caller |

### What the backend does on success

1. Create a new meeting row using the existing
   `/api/meetings/create` logic — server-side, not by re-hitting
   the public endpoint. The meeting's `created_by` is the caller.
2. Insert two participant rows for the existing peers (caller +
   the other peer), marked active.
3. Insert an `in_call_invite` notification for the invitee (same
   shape as §2, with `data.from_promotion: true` so the mobile
   client can render slightly different wording — "Farhan added
   you to a video call" vs "Farhan is calling").
4. Push FCM `kind: "in_call_invite"` to the invitee.
5. Emit **two** socket events on `/signaling-fresh`:
   - To BOTH existing peers: `p2p:promoted { meetingId, meetingCode }`.
     - Mobile clients listen for this and transparently navigate
       from `/p2p-call` to `/meeting/:meetingCode`, carrying mic +
       camera state.
   - To the invitee (if their socket is connected):
     `meeting:in-call-invite` — same as §2.4.
6. Mark the P2P call as `status: 'promoted'` in your call log so
   it doesn't show up as "still active" in admin tooling.
7. Start the 30s auto-expire timer for the invitee.

### State machine for the original peers

```
P2P active ──[promote-to-meeting POST]──▶  Server creates meeting
                                            └─▶ Emit p2p:promoted to both peers
Both peers receive p2p:promoted ────────▶  Tear down P2P transport
                                            └─▶ Join /meeting/:code via existing flow
```

Mobile client behaviour on `p2p:promoted`:
- Capture current mic + camera enabled state from
  `p2pCallProvider.state` BEFORE teardown.
- Call `endCall()` on the P2P session (NO rating prompt — see §6).
- Push `/meeting/:meetingCode` with `joinAsExistingPeer: true` so
  the meeting screen skips pre-join camera preview and joins
  immediately.
- Restore mic + camera enabled state in the meeting.

The user sees: the call screen briefly shows "Adding participant…",
then transitions into the multi-tile meeting layout. ~1 second
gap in audio is acceptable for v1; can be reduced later by
keeping the camera/mic open across the swap.

---

## 4. Socket events

Both run on the existing `/signaling-fresh` namespace, same
engine.io mount path as meeting signaling.

### `meeting:in-call-invite`

Server → invitee (room = `user:<inviteeUserId>`)

```json
{
  "kind": "meeting:in-call-invite",
  "meetingId": "uuid",
  "meetingCode": "abc-defg-hij",
  "callerUserId": "uuid",
  "callerName": "Farhan",
  "callerAvatarUrl": "https://.../1.jpg",
  "fromPromotion": false,
  "expiresAt": "2026-05-15T11:00:30.000Z"
}
```

Mobile listens and renders the ringing screen.

### `p2p:promoted`

Server → both original peers (rooms = `user:<peerUserId>`)

```json
{
  "kind": "p2p:promoted",
  "originalCallId": "uuid",
  "meetingId": "uuid",
  "meetingCode": "abc-defg-hij",
  "promotedByUserId": "uuid",
  "promotedByName": "Farhan"
}
```

Mobile listens and triggers the state-machine transition above.

---

## 5. New notification type

Add `in_call_invite` to the
`docs/NOTIFICATIONS_BACKEND.md` §3 type catalog:

```
in_call_invite — Someone added you to an active meeting or
                 promoted a P2P call you're not part of yet.
                 The mobile client renders this as a full-screen
                 RING (not just a list tile) when the FCM lands
                 while the app is open. After the 30s expiry it
                 becomes a regular list tile with the title
                 "Missed call from {callerName}".
                 data: { meetingCode, meetingId, callerName,
                         callerAvatarUrl, fromPromotion, expiresAt }
```

The Flutter client has a fallback icon for unknown types (per
`notifications_screen.dart:_meta`), so a rolling deploy where the
server emits this before the client knows about it is non-fatal.

---

## 6. Rating-prompt interaction

When a P2P call is promoted to a meeting:

- The original peers' `p2p_call_provider.dart` will receive
  `p2p:promoted` and run `endCall()` to tear down the P2P session.
- **Do NOT trigger the post-call rating sheet** for this teardown.
  The user didn't end the call; the meeting they're joining is the
  continuation. Triggering the sheet here would be jarring.
- Mobile-side fix: pass a `reason: 'promoted'` flag through
  `endCall()` and gate `maybePromptFor` on `reason != 'promoted'`.
  The provider's existing gates already handle the second-leg
  meeting end-of-session rating naturally.

This is purely a mobile-side change but worth flagging so the
backend dev knows the rating endpoint won't see a flood of
P2P-promoted ratings.

---

## 7. Data model

No new tables. Reuses:

- `meetings` — the new meeting row created on promotion.
- `meeting_participants` — the two original peers + the invitee
  once they join.
- `notifications` — the `in_call_invite` row (and the
  auto-expired "missed" follow-up).
- `p2p_calls` (if you have one) — flip `status` to `promoted` for
  the original call.

If a `p2p_calls` table doesn't exist yet, this spec doesn't
require you to add one. The signaling-service can keep the
in-flight call state in memory; the promotion endpoint just
needs to read it.

---

## 8. Authorization helper

The two endpoints share a "is this user authorized to invite
to this session" check. Recommended to land as a single shared
helper so the rules are in one place:

```js
// services/auth-checks.js
async function isParticipantOf(userId, meetingId) {
  const row = await prisma.meetingParticipants.findFirst({
    where: { meeting_id: meetingId, user_id: userId, is_active: true },
  });
  return !!row;
}

async function isPeerOnP2PCall(userId, callId) {
  // Implementation depends on where you store P2P state.
  // If memory-only on signaling-service, read from that store.
  // If you have a `p2p_calls` table, query it.
}
```

Use these in the route handlers BEFORE doing any other work.
Don't trust the request body's claim of "I'm in this meeting" —
re-verify from the DB / in-memory store.

---

## 9. Rate limiting

| Scope | Limit | Key |
|---|---|---|
| Invites per meeting per minute | 5 | `(inviterUserId, meetingId)` |
| Promotes per caller per minute | 3 | `inviterUserId` |
| Invites per invitee per minute | 3 | `inviteeUserId` (anti-spam — multiple inviters can't pile-ring one user) |

Return `429 RATE_LIMITED` with a `retry_after` field in the body
when exceeded. The mobile client maps this to the "Please wait
before sending another invite" inline message.

---

## 10. Testing — curl scripts

```bash
# Setup: log in two test users
TOKEN_A=$(curl -k -s -X POST https://192.168.1.20:3001/api/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"email":"test1@mizdah.dev","password":"<pw>"}' | jq -r .token)

TOKEN_B=$(curl -k -s -X POST https://192.168.1.20:3001/api/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"email":"test2@mizdah.dev","password":"<pw>"}' | jq -r .token)

INVITEE_ID="<userId-of-test3>"

# ── Meeting in-call invite ───────────────────────────────────
MEETING_ID="<id-of-a-meeting-test1-is-currently-in>"

curl -k -s -X POST \
  "https://192.168.1.20:3001/api/meeting/$MEETING_ID/invite-in-call" \
  -H "Authorization: Bearer $TOKEN_A" \
  -H 'Content-Type: application/json' \
  -d "{\"inviteeUserId\":\"$INVITEE_ID\"}" | jq

# Expected: 200 { "ok": true, "inviteId": "...", ... }

# ── Forbidden — test2 tries to invite to a meeting they aren't in
curl -k -s -X POST \
  "https://192.168.1.20:3001/api/meeting/$MEETING_ID/invite-in-call" \
  -H "Authorization: Bearer $TOKEN_B" \
  -H 'Content-Type: application/json' \
  -d "{\"inviteeUserId\":\"$INVITEE_ID\"}" | jq

# Expected: 403 { "error":"...","code":"FORBIDDEN_NOT_PARTICIPANT" }

# ── P2P promotion ─────────────────────────────────────────────
CALL_ID="<id-of-active-p2p-call-between-test1-and-test2>"

curl -k -s -X POST \
  "https://192.168.1.20:3001/api/p2p-call/$CALL_ID/promote-to-meeting" \
  -H "Authorization: Bearer $TOKEN_A" \
  -H 'Content-Type: application/json' \
  -d "{\"inviteeUserId\":\"$INVITEE_ID\"}" | jq

# Expected: 200 { "ok": true, "meetingId": "...", "meetingCode": "..." }
# Also expected: both test1 + test2 receive p2p:promoted socket event
# Also expected: test3 receives meeting:in-call-invite socket event

# ── Idempotency check — try to promote the same call again
curl -k -s -X POST \
  "https://192.168.1.20:3001/api/p2p-call/$CALL_ID/promote-to-meeting" \
  -H "Authorization: Bearer $TOKEN_A" \
  -H 'Content-Type: application/json' \
  -d "{\"inviteeUserId\":\"$INVITEE_ID\"}" | jq

# Expected: 409 { "error":"...","code":"ALREADY_PROMOTED" }

# ── Rate limit — fire 6 invites in <60s
for i in {1..6}; do
  curl -k -s -X POST \
    "https://192.168.1.20:3001/api/meeting/$MEETING_ID/invite-in-call" \
    -H "Authorization: Bearer $TOKEN_A" \
    -H 'Content-Type: application/json' \
    -d "{\"inviteeUserId\":\"$INVITEE_ID\"}"
done

# Expected: 5×200 then 1×429 RATE_LIMITED

# ── Host-permission toggle ────────────────────────────────────
# Assume TOKEN_HOST is the meeting's host and TOKEN_GUEST is
# another participant.

# 1. Host disables invites for non-hosts.
curl -k -s -X PATCH \
  "https://192.168.1.20:3001/api/meeting/$MEETING_ID/permissions" \
  -H "Authorization: Bearer $TOKEN_HOST" \
  -H 'Content-Type: application/json' \
  -d '{"allowParticipantsToInvite": false}' | jq

# Expected: 200 { "ok": true, "permissions": { "allowParticipantsToInvite": false } }
# Also expected: every participant socket receives
#                meeting:permissions-changed

# 2. Guest tries to invite — should now be blocked.
curl -k -s -X POST \
  "https://192.168.1.20:3001/api/meeting/$MEETING_ID/invite-in-call" \
  -H "Authorization: Bearer $TOKEN_GUEST" \
  -H 'Content-Type: application/json' \
  -d "{\"inviteeUserId\":\"$INVITEE_ID\"}" | jq

# Expected: 403 { "error":"...","code":"INVITE_NOT_ALLOWED_BY_HOST" }

# 3. Host can still invite even when the toggle is off (host bypass).
curl -k -s -X POST \
  "https://192.168.1.20:3001/api/meeting/$MEETING_ID/invite-in-call" \
  -H "Authorization: Bearer $TOKEN_HOST" \
  -H 'Content-Type: application/json' \
  -d "{\"inviteeUserId\":\"$INVITEE_ID\"}" | jq

# Expected: 200 (host bypasses the permission gate)

# 4. Guest tries to flip the permission — must be denied.
curl -k -s -X PATCH \
  "https://192.168.1.20:3001/api/meeting/$MEETING_ID/permissions" \
  -H "Authorization: Bearer $TOKEN_GUEST" \
  -H 'Content-Type: application/json' \
  -d '{"allowParticipantsToInvite": true}' | jq

# Expected: 403 { "error":"...","code":"FORBIDDEN_NOT_HOST" }

# 5. Host re-enables and guest can invite again.
curl -k -s -X PATCH \
  "https://192.168.1.20:3001/api/meeting/$MEETING_ID/permissions" \
  -H "Authorization: Bearer $TOKEN_HOST" \
  -H 'Content-Type: application/json' \
  -d '{"allowParticipantsToInvite": true}' | jq
# then re-run step 2 — expected: 200

# ── Per-participant invite grant (§2c / §2d) ──────────────────
# Test the additive grant — global toggle stays OFF, host grants
# just one participant.

# 6. Host turns global OFF.
curl -k -s -X PATCH \
  "https://192.168.1.20:3001/api/meeting/$MEETING_ID/permissions" \
  -H "Authorization: Bearer $TOKEN_HOST" \
  -H 'Content-Type: application/json' \
  -d '{"allowParticipantsToInvite": false}' | jq

# 7. Guest tries to invite — blocked (control case).
curl -k -s -X POST \
  "https://192.168.1.20:3001/api/meeting/$MEETING_ID/invite-in-call" \
  -H "Authorization: Bearer $TOKEN_GUEST" \
  -H 'Content-Type: application/json' \
  -d "{\"inviteeUserId\":\"$INVITEE_ID\"}" | jq
# Expected: 403 INVITE_NOT_ALLOWED_BY_HOST

# 8. Host grants invite permission to the guest.
GUEST_USER_ID="<test2-user-id>"
curl -k -s -X PATCH \
  "https://192.168.1.20:3001/api/meeting/$MEETING_ID/participants/$GUEST_USER_ID/permissions" \
  -H "Authorization: Bearer $TOKEN_HOST" \
  -H 'Content-Type: application/json' \
  -d '{"canInvite": true}' | jq
# Expected: 200 { "ok": true, "userId": "...", "canInvite": true }
# Also expected: meeting:participant-permissions-changed fans to
#                every other participant in the room.

# 9. Guest retries — now succeeds.
curl -k -s -X POST \
  "https://192.168.1.20:3001/api/meeting/$MEETING_ID/invite-in-call" \
  -H "Authorization: Bearer $TOKEN_GUEST" \
  -H 'Content-Type: application/json' \
  -d "{\"inviteeUserId\":\"$INVITEE_ID\"}" | jq
# Expected: 200

# 10. Non-host tries to grant someone — must be denied.
curl -k -s -X PATCH \
  "https://192.168.1.20:3001/api/meeting/$MEETING_ID/participants/$INVITEE_ID/permissions" \
  -H "Authorization: Bearer $TOKEN_GUEST" \
  -H 'Content-Type: application/json' \
  -d '{"canInvite": true}' | jq
# Expected: 403 FORBIDDEN_NOT_HOST

# 11. Host can't grant themselves.
HOST_USER_ID="<test1-user-id>"
curl -k -s -X PATCH \
  "https://192.168.1.20:3001/api/meeting/$MEETING_ID/participants/$HOST_USER_ID/permissions" \
  -H "Authorization: Bearer $TOKEN_HOST" \
  -H 'Content-Type: application/json' \
  -d '{"canInvite": true}' | jq
# Expected: 400 CANNOT_GRANT_HOST_SELF

# 12. Reset-on-rejoin — guest leaves the meeting, then rejoins.
#     After rejoin, the guest's row MUST come back with
#     can_invite=false. Easiest check: scope from the
#     participants-list payload after rejoin, OR call invite-in-call
#     from the rejoined guest and expect 403 again.
```

---

## 11. Migration order (one PR, in this order)

1. **Schema migration A:** add `meetings.permissions` JSONB
   column with the documented default + backfill (see §2a).
2. **Schema migration B:** add `meeting_participants.can_invite`
   BOOLEAN column with default false + index (see §2c).
3. Wire the reset-on-rejoin rule — whenever
   `meeting_participants.is_active` flips to false, the same
   UPDATE clears `can_invite` to false (see §2c).
4. Update every meeting read path (`GET /api/meeting/:code`,
   `GET /api/meetings/user/:userId`, etc.) to include the
   `permissions` blob.
5. Update every participants-list path (`participants-update`
   socket fan-out, `user-joined` event, `GET /participants`
   if exposed) to include `canInvite` per row.
6. Add `in_call_invite` to the notification type dictionary
   (both server + client docs).
7. Land `isParticipantOf` / `isHostOf` / `isPeerOnP2PCall` /
   `hasInvitePermission` helpers + unit tests.
8. Land `PATCH /api/meeting/:id/permissions` (global toggle) +
   host-only auth + tests.
9. Wire `meeting:permissions-changed` socket event emission.
10. Land `PATCH /api/meeting/:id/participants/:userId/permissions`
    (per-user grant) + host-only auth + `CANNOT_GRANT_HOST_SELF`
    + tests.
11. Wire `meeting:participant-permissions-changed` socket emission.
12. Land `POST /api/meeting/:id/invite-in-call` with the three-way
    auth gate (host OR global OR per-user) + rate limit + tests.
13. Wire FCM `kind: "in_call_invite"` push pairing on
    invite-in-call (reuse the helper from
    `docs/NOTIFICATIONS_BACKEND.md` §6).
14. Wire `meeting:in-call-invite` socket event emission.
15. Land `POST /api/p2p-call/:callId/promote-to-meeting`.
16. Wire `p2p:promoted` socket event emission to both peers.
17. Add the 30-second auto-expire timer for unanswered invites.
18. Update `docs/NOTIFICATIONS_BACKEND.md` §3 with the new
    `in_call_invite` type row (one-line edit).

**Independent slices:**
- Stages 1–9 alone ship the host-controls global toggle (no
  `+ Add` button yet, but global permission flips are sync'd
  to every client). Useful for early QA.
- Stages 10–11 add the per-user grant on top of the global.
- Stage 12 alone unblocks the meeting `+ Add` button on mobile
  with the FULL three-way auth (global + per-user + host).
- Stages 15–16 unblock the P2P `+ Add` path.

Each slice can ship in its own deploy if you want to space them
out — mobile gracefully degrades when an endpoint hasn't landed
yet (button stays hidden / call returns 404 / picker shows a
friendly error).

---

## 12. Open questions for backend

1. **Per-meeting participant cap** — what's the practical SFU
   ceiling? The mobile UI defaults to "no cap" but we should
   know the server's number for the `MEETING_FULL` (409)
   threshold.
2. **P2P call state location** — does the signaling-service
   store active P2P calls in a table, or memory only? Affects
   how `isPeerOnP2PCall` is implemented.
3. **Existing in-flight invites** — if test1 has already invited
   test3 to this meeting and test3 hasn't responded, should a
   second invite from test1 (or from test2) for the same
   meeting/invitee be a 409 or a refresh-the-ring no-op?
   Proposal: **refresh** — invalidate the prior unanswered
   invite, fire a new ring, restart the 30s expiry.
4. **Admin dashboards** — should `in_call_invite` events show up
   in any existing admin view, or stay invisible (they're noisy
   and short-lived)?
5. **Permissions blob versioning** — when we add `allowScreenShare`
   / `muteOnJoin` / `lockMeeting` / etc. in future iterations,
   how do you want to handle JSON validation? Whitelist of known
   keys per server release, or lenient pass-through? Proposal:
   **strict whitelist** on PATCH (`INVALID_PERMISSIONS_BODY` for
   unknown keys) so a stale-client typo never lands; **lenient**
   on read (unknown keys retained but ignored), so a rolling
   downgrade doesn't drop data.
6. **Initial permissions at meeting create** — should
   `POST /api/meetings/create` accept a `permissions` body
   argument so a host can pre-set the toggle before the meeting
   starts? Or always default-true and require a PATCH after
   creation? Proposal: **accept at create time** — saves the
   host an extra round-trip.

Send answers when you've had a look and we'll iterate.
