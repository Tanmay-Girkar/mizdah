# Host detection in `join-meeting` — backend bug

The Socket.IO `join-meeting` handler currently treats EVERYONE as a
guest, including the user who created the meeting. Hosts are put
into their own meeting's waiting room and shown the
"Wait for the host to let you in" screen — which is impossible to
escape because there's nobody on the other side to admit them
(they ARE the host).

Audience: the dev who maintains `mizdah-backend.ogoul.cloud`.

Verified on **2026-05-06**.

---

## Reproduce

1. Log in as `Alex` (userId `a7bae225-5f5a-40b6-b177-36cf1c0d3e48`).
2. Tap "New Meeting → Start an instant meeting".
3. Mobile log shows:

   ```
   POST /api/meetings/create
     →  { "id":"f8215d3e-...", "meeting_code":"mspoyeunkm",
          "host_id":"a7bae225-..." }                        ✅ host_id stored

   joinMeeting → meetingId=mspoyeunkm userId=a7bae225-... name=Alex
   Local host match: true (hostId=a7bae225-..., userId=a7bae225-...)
                                                            ✅ FE knows it's the host
   📤 emit join-meeting [mspoyeunkm, a7bae225-..., Alex, isCameraOff=false]

   📡 EVENT: join-confirmation | DATA:
     { "isHost": false, "status": "WAITING_FOR_APPROVAL" }   ❌ server says guest!

   /api/waiting-room/waiting/mspoyeunkm
     →  [{ socketId: "...", name: "Alex", userId: null }]    ❌ host is in own waiting list
   ```

4. The user is shown the waiting-room screen on their own meeting.

The mobile client now ships a workaround that detects this
condition and overrides locally (see "Frontend status" below), but
the bug should be fixed properly server-side so guests still get
queued correctly.

---

## What needs to happen

The Socket.IO `join-meeting` handler receives:
```
[code, userId, name, isCameraOff]
```

Right now it appears to look up the meeting by code and then
queue every joiner into the waiting room (or into the room if
locking is off — but always with `isHost: false`). It needs to
**compare `userId` against `meetings.host_id`** and skip the
waiting-room logic when they match.

### Pseudo-code (matches the docs section §5 of TECHNICAL_DOCUMENTATION.md)

```js
socket.on('join-meeting', async ([code, userId, name, isCameraOff]) => {
  const meeting = await db.meetings.findOne({ where: { meeting_code: code } });
  if (!meeting) {
    socket.emit('join-confirmation', { status: 'INVALID_CODE' });
    return;
  }

  const isHost = userId && userId === meeting.host_id;       // ← ADD THIS

  if (!isHost && meeting.locked) {                            // ← guard locked rooms
    socket.emit('join-confirmation', {
      status: 'WAITING_FOR_APPROVAL',
      isHost: false,
    });
    notifyHost(meeting.id, { socketId: socket.id, userId, name });
    return;
  }

  // Host bypasses waiting-room ALWAYS:
  if (isHost) {
    await joinRoom(socket, meeting, { isHost: true });
    socket.emit('join-confirmation', {
      status: 'JOINED',
      isHost: true,
      participants: await participantsInRoom(meeting.id),
      hostId: meeting.host_id,
      // ... rest of your existing JOINED payload
    });
    return;
  }

  // Non-host with no waiting-room → straight in
  await joinRoom(socket, meeting, { isHost: false });
  socket.emit('join-confirmation', {
    status: 'JOINED',
    isHost: false,
    participants: await participantsInRoom(meeting.id),
    hostId: meeting.host_id,
    // ...
  });
});
```

The two fixes are:
1. **Compute `isHost` from `userId === meeting.host_id`** before any
   waiting-room logic.
2. **Branch on `isHost` first** — hosts ALWAYS go straight to JOINED,
   never WAITING_FOR_APPROVAL.

### Bonus: `userId: null` in the waiting list

The `GET /api/waiting-room/waiting/<code>` response includes
the host's row with `userId: null`. That suggests the
waiting-room insert isn't capturing the userId at all. While
fixing the host check, please also store the joining `userId`
on the waiting-room row so we can do better filtering and the
host can see "Alex (alex@example.com) is waiting" instead of
just "Alex".

---

## Test plan

### Before fix (this is what production does today)

```bash
# Create meeting as Alex
M=$(curl -s -X POST https://mizdah-backend.ogoul.cloud/api/meetings/create \
  -H 'Content-Type: application/json' \
  -d '{"hostId":"a7bae225-5f5a-40b6-b177-36cf1c0d3e48",
       "title":"host-test","id":"hosttest1","meeting_code":"hosttest1"}')

# Have Alex join via Socket.IO emitting join-meeting
# Result: server sends back { "isHost": false, "status": "WAITING_FOR_APPROVAL" }
# /api/waiting-room/waiting/hosttest1 returns Alex's own row.
```

### After fix

```bash
# Same setup. Alex emits join-meeting.
# Expected:
#   { "isHost": true, "status": "JOINED", "participants": [...],
#     "hostId": "a7bae225-..." }
# /api/waiting-room/waiting/hosttest1 returns [].

# Sanity check — non-host (Bob) joining should still work:
# Without locking → JOINED
# With locking → WAITING_FOR_APPROVAL, host gets request-to-join
```

---

## Frontend status

The mobile client (commit pending) ships a workaround:

- After emitting `join-meeting`, when `join-confirmation` says
  `WAITING_FOR_APPROVAL` BUT the local check (`userId === hostId`,
  computed before the socket connect) says we're the host, the FE
  ignores the server status and proceeds as JOINED.
- The waiting-room poll (`GET /api/waiting-room/waiting/<code>`)
  filters out the host's own row before showing it in the
  "<n> people waiting" banner. Without this the host saw
  themselves listed as a waiter on their own meeting.

Both workarounds become silent no-ops once the backend fix ships
— no FE redeploy needed. The server simply stops sending the
buggy responses, and the override conditions stop matching.

Please ship the backend fix soon — the FE workaround relies on
the local hostMatch check, which is brittle if the
`/api/meeting/<code>` REST endpoint ever returns a stale
`host_id` (e.g. host transfer feature, currently not built).
Server-side enforcement is the right long-term answer.
