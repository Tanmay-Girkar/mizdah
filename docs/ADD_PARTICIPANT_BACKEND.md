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
| Socket event `meeting:in-call-invite` on `/signaling-fresh` | signaling-service | NEW |
| Socket event `p2p:promoted` on `/signaling-fresh` | signaling-service | NEW |
| FCM data-message `kind: "in_call_invite"` | shared push util | NEW |
| Notifications row `type: "in_call_invite"` | uses existing inbox table | NEW |
| Authorization helper `isParticipantOf(userId, meetingId)` | shared util | NEW |
| Rate limit: max 5 invites/minute per inviter per meeting | middleware | NEW |

No changes to any existing endpoint. Additive only.

Estimated effort: **8–12 hours** for the two endpoints, two socket
events, FCM pairing, and authorization checks. Most of the cost is
the P2P promotion plumbing — meeting invite-in-call is a thin
wrapper over what the scheduler invite-fan-out already does.

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

- Caller must be the authenticated user (JWT) AND be currently
  marked as `active` in `meeting_participants` for this meeting.
- Admin role bypass: yes.
- Returns `403 FORBIDDEN_NOT_PARTICIPANT` if caller isn't in the
  meeting.

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
```

---

## 11. Migration order (one PR, in this order)

1. Add `in_call_invite` to the notification type dictionary
   (both server + client docs).
2. Land `isParticipantOf` / `isPeerOnP2PCall` helpers + unit tests.
3. Land `POST /api/meeting/:id/invite-in-call` + auth + rate
   limit + tests.
4. Wire FCM `kind: "in_call_invite"` push pairing on this endpoint
   (reuse the helper from
   `docs/NOTIFICATIONS_BACKEND.md` §6).
5. Wire `meeting:in-call-invite` socket event emission.
6. Land `POST /api/p2p-call/:callId/promote-to-meeting`.
7. Wire `p2p:promoted` socket event emission to both peers.
8. Add the 30-second auto-expire timer.
9. Update `docs/NOTIFICATIONS_BACKEND.md` §3 with the new type
   row (one-line edit).

Stage 3 alone unblocks the meeting "Add" button on mobile. Stages
6–7 unblock the P2P "Add" path. Each can ship independently.

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

Send answers when you've had a look and we'll iterate.
