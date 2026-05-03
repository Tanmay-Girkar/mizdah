# More-options sheet — feature audit + backend spec

This document is a per-feature audit of the **More options** bottom
sheet that opens from the meeting room screen, covering:

- What each option currently does on mobile
- How that compares to Google Meet
- Whether the backend supports it today (verified against
  `mizdah-backend.ogoul.cloud` on **2026-05-03**)
- Backend changes needed where applicable

Audience: the dev who maintains `mizdah-backend.ogoul.cloud`.

---

## Status overview

| # | Option | UI state | Backend state | Action |
|---|--------|----------|---------------|--------|
| 1 | Raise hand | ✅ Works | ✅ Socket relayed | none |
| 2 | Screen share | ⚠️ Captures locally only | ✅ Mediasoup ready | **frontend**: produce via SFU |
| 3 | Captions (CC) | ✅ Works (on-device STT) | ✅ Socket relayed | none |
| 4 | On the go | ❌ Snackbar mock | n/a (UI-only) | **frontend**: build a compact mode |
| 5 | In-call messages (chat) | ⚠️ Socket path works, REST 502 | ⚠️ Partial | **backend**: fix `POST /api/chat/send` |
| 6 | Participants | ✅ Works | ✅ Works | none |
| 7 | Host Controls | ⚠️ Emits sockets, server side unverified | ⚠️ Needs verification | **backend**: confirm 4 socket events are honoured |
| 8 | Whiteboard | ⚠️ Emits sockets locally | ⚠️ Needs verification | **backend**: confirm whiteboard relay |
| 9 | Report abuse | ❌ Pure UI mock | ❌ No endpoint | **backend**: build endpoint |
| 10 | Record meeting | UI ready | ❌ Endpoint 404 | **backend**: build endpoint |

Everything that says **frontend** above is being shipped from the
mobile side in the same PR as this doc — see commits referenced at
the bottom. Everything that says **backend** needs a server change.

---

## 1. Raise hand — ✅ Working

Mobile flips `state.isHandRaised`, then emits Socket.IO event
`media-toggle` (server re-broadcasts as `media-toggle-remote`):

```json
{
  "meetingId": "<code>",
  "type": "MEDIA_TOGGLE",
  "isHandRaised": true,
  "from": "<socketId>"
}
```

Other clients show the hand badge on the participant tile.

**No backend change required.** This is identical to Google Meet's
behaviour modulo the rendering (Meet animates the hand emoji floating
upward).

---

## 2. Screen share — ⚠️ Frontend fix needed

**Current behaviour**: Mobile calls `getDisplayMedia` and tries to
hot-swap the video track on every peer connection via
`sender.replaceTrack(screenTrack)`. In SFU mode there are NO peer
connections, so the loop is a no-op — the user's local capture
starts but **other participants never see the screen**.

**Required fix (frontend)**: produce the screen track through the
SFU's send transport with `appData.isScreen: true`, mirroring what
the web client does. Code path lives in
`SFUService.produceScreen()` (already implemented, just not called
from `_startScreenShare`).

**Required fix (backend)**: none — mediasoup already accepts the
producer with `isScreen: true` in `appData`; consumers (other
peers) read that flag and render the producer in a dedicated
"presentation" tile on top of the camera tile. Verified against the
deployed web client which uses the same mechanism.

---

## 3. Captions (CC) — ✅ Working (on-device only)

Mobile uses `speech_to_text` (Android `SpeechRecognizer` / iOS
`Speech` framework) to transcribe the user's own speech locally.
Each partial transcript is broadcast over Socket.IO via
`media-toggle-remote` with `type: "CAPTION"`:

```json
{
  "meetingId": "<code>",
  "type": "CAPTION",
  "from": "<socketId>",
  "name": "<displayName>",
  "text": "hello world",
  "isFinal": false
}
```

Other clients pick this up and render rolling captions at the
bottom of the screen.

**No backend change required.** Google Meet does cloud STT (more
accurate, multi-language), but the on-device path is fine for v1
and avoids server cost. **DO NOT remove this** — the FE depends on
the backend simply re-broadcasting `media-toggle-remote` as it does
today.

---

## 4. On the go — ❌ Will be implemented frontend-only

Currently a snackbar saying "On the go mode activated" with no
behaviour. No backend involvement — Google Meet's "on-the-go" is a
local audio-first compact UI for use while moving (driving). FE
will ship this as:

- Hide the video grid
- Surface large mic / hangup / speaker buttons
- Persist preference in `SharedPreferences`

**No backend change required.**

---

## 5. In-call messages (chat) — ⚠️ Backend bug

Two delivery paths today:

### Path A — Socket.IO broadcast (✅ works)

`POST` over Socket.IO `media-toggle-remote` with `type: "CHAT"`:

```json
{
  "meetingId": "<code>",
  "type": "CHAT",
  "name": "<displayName>",
  "content": "hello",
  "from": "<socketId>",
  "timestamp": "2026-05-03T14:00:00.000Z"
}
```

This is the primary delivery channel and works correctly between
mobile and web today.

### Path B — REST persistence (❌ broken)

`POST /api/chat/send` returns **502 Bad Gateway** on the live server.
The response body is the Cloudflare error page.

Test:

```bash
curl -i -X POST https://mizdah-backend.ogoul.cloud/api/chat/send \
  -H "Content-Type: application/json" \
  -d '{"meetingId":"jhmyqrneac","senderId":"<userId>","senderName":"X","content":"probe"}'
# → HTTP/2 502
```

`GET /api/chat/<meetingId>?userId=<userId>` is also CORS-blocked
when called from `https://mizdah-front.ogoul.cloud` — the `Access-
Control-Allow-Origin` header is missing. Confirmed in browser
console during the SFU debugging session.

### Required backend changes

- Fix or restart the chat service so `POST /api/chat/send` returns
  201 Created (or 200) with the saved message body.
- Add `Access-Control-Allow-Origin: https://mizdah-front.ogoul.cloud`
  (or `*` if you don't restrict origins) on the `GET /api/chat/<id>`
  response so the web client can fetch chat history.

---

## 6. Participants — ✅ Working

UI shows `state.participants` plus self. Updated through the
`join-confirmation`, `user-joined`, `user-left` socket events that
the backend already emits correctly.

**No backend change required.**

---

## 7. Host Controls — ⚠️ Needs server-side verification

The mobile client emits these Socket.IO events when the host
toggles controls in the panel:

| Action | Event | Payload |
|--------|-------|---------|
| Lock meeting | `lock-meeting` | `{ "lock": true \| false }` |
| Allow mic / cam / chat | `update-settings` | `{ "key": "allowMic" \| "allowCam" \| "allowChat", "value": true \| false }` |
| Mute everyone | `mute-all` | (no payload) |
| End for all | `end-meeting-for-all` | (no payload) |

Mobile **emits** these correctly today. We have not verified that
the server side:

1. Honours `lock-meeting` by rejecting subsequent `join-meeting`
   requests with `WAITING_FOR_APPROVAL` or `JOIN_DENIED`.
2. Stores `update-settings` per meeting and applies the rule
   server-side (e.g. drops chat from a peer if `allowChat=false`).
3. On `mute-all`, broadcasts a `force-mute` event to every peer's
   socket so their mediasoup audio producer is paused.
4. On `end-meeting-for-all`, broadcasts `meeting-ended` to all
   sockets in the room. (This one we can confirm works — the
   mobile client already listens for it and tears down.)

### Required backend changes

Add server-side state for each meeting:

```sql
ALTER TABLE meetings
  ADD COLUMN locked BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN allow_mic BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN allow_cam BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN allow_chat BOOLEAN NOT NULL DEFAULT true;
```

Behaviour:

- `join-meeting` on a `locked` room → emit `join-denied` (or move
  to waiting room and send a `request-to-join` to the host).
- New peer joining an `allow_mic=false` room → emit `force-mute`
  to that peer immediately on join.
- `mute-all` → server fan-outs `force-mute` to every peer in the
  room AND sets `meetings.allow_mic = false` so newcomers are
  muted too.
- `update-settings` from a non-host socket → drop with an `error`
  event back to the sender.

The mobile already listens for `force-mute` and `meeting-ended`
events; new ones are noted below.

### Server → mobile events to ADD

| Event | Payload | Purpose |
|-------|---------|---------|
| `force-mute` | `{ "kind": "audio" \| "video" }` | Pause the local producer client-side |
| `host-changed-permission` | `{ "key": "allowMic" \| "allowCam" \| "allowChat", "value": true \| false }` | Sync UI badge so non-host sees the lock |
| `join-denied` | `{ "reason": "room_locked" \| "host_denied" }` | Show "host has locked the meeting" snackbar instead of waiting forever |

The mobile client will be updated to handle these in a follow-up
once the backend ships them.

---

## 8. Whiteboard — ⚠️ Needs server-side verification

The mobile client emits these Socket.IO events:

| Action | Event | Payload |
|--------|-------|---------|
| Open whiteboard | `whiteboard-toggle` | `{ "isOpen": true }` |
| Stroke / shape | `draw-move` | `{ "type": "...", "points": [...], ... }` |
| Request initial state | `request-whiteboard-state` | `{}` |
| Clear board | `clear-board` | `{}` |

The mobile listens for the same events back from peers. We have
not verified that the server **re-broadcasts** these to the rest
of the room (in our SFU debugging the `onAny` log only showed
`media-toggle-remote`, `existingProducers`, `newProducer`, etc. —
none of the whiteboard events ever appeared, suggesting the server
might not be relaying them).

### Required backend changes

If not already implemented:

- Subscribe each room to a `whiteboard:<meetingCode>` channel.
- On `draw-move` from any participant, broadcast to every other
  socket in the room.
- On `request-whiteboard-state`, respond with the latest known
  state (server stores last N strokes per room — keep last 1000
  is fine).
- On `clear-board`, drop stored state and broadcast.

If you confirm this is already implemented, the FE side is ready —
nothing more to do.

---

## 9. Report abuse — ❌ Backend endpoint missing

**Current behaviour**: The submit button on the Report screen
shows a green snackbar that says "Report submitted successfully"
and pops the page. There is **no network call**. Pure UI mock.

The closest existing endpoint is `POST /api/meeting/feedback`
(used by Settings → Send Feedback) — but it returns
**405 Method Not Allowed** on the live server:

```bash
curl -i -X POST https://mizdah-backend.ogoul.cloud/api/meeting/feedback \
  -H "Content-Type: application/json" \
  -d '{"category":"abuse","description":"probe","user_email":"x@y.z"}'
# → HTTP/2 405 Method Not Allowed
```

So even the Settings feedback path is broken on the server.

### Required backend changes

Either fix the existing `POST /api/meeting/feedback` (preferred,
since the FE already calls it) or add a dedicated
`POST /api/abuse/report`:

```http
POST /api/abuse/report
Content-Type: application/json

{
  "meetingId":  "<code>",          // optional — only if reported during a call
  "reporterId": "<userId>",         // who is reporting
  "subjectId":  "<userId>" | null,  // who is being reported (null for general abuse)
  "type":       "Hate speech" | "Harassment" | "Spam" | "Other",
  "names":      "alice, bob",        // free-form names typed by reporter
  "description": "Detailed text of the report",
  "includeVideoClip": true | false   // whether mobile should upload last 30s
}
```

Response:

```json
{ "status": "received", "reportId": "<uuid>" }
```

Once this exists the mobile client (already updated this PR) will
call it from the Report submit button instead of the mock
snackbar.

If a video-clip upload is in scope, also expose
`POST /api/abuse/report/<reportId>/clip` accepting a multipart
file. v1 can ignore that and just store the text report.

---

## 10. Record meeting — ❌ Backend endpoints missing

The Host Controls panel exposes a "Record Meeting" toggle. The FE
already calls these endpoints (via `RecordingRepository`):

```
POST /api/recording/start/<meetingCode>
POST /api/recording/stop/<meetingCode>
GET  /api/recording/<meetingCode>
```

Live server returns **404** for both `start` and `stop`:

```bash
curl -i -X POST https://mizdah-backend.ogoul.cloud/api/recording/start/jhmyqrneac
# → HTTP/2 404 Not Found
```

### Required backend changes

This is the largest piece of work — recording typically needs:

- A worker process that joins the room as a "recorder bot"
  (mediasoup consumer for every producer) and writes a composed
  video to disk / S3.
- A control plane endpoint:
  - `POST /api/recording/start/<meetingCode>` → spin up the
    recorder, return `{ "status": "recording", "recordingId": "<uuid>" }`
  - `POST /api/recording/stop/<meetingCode>` → tear down the
    recorder, return `{ "status": "stopped", "url": "https://..." }`
  - `GET /api/recording/<meetingCode>` → list recordings for
    this room (returned objects need at least `id`, `url`,
    `startedAt`, `endedAt`, `durationSeconds`).
- A signed-URL upload endpoint if you want the mobile recorder to
  upload directly. Lower priority — server-side compositing is
  simpler.

If recording is not on the v1 roadmap, please **hide the toggle in
Host Controls** (or grey it out with a "Coming soon" subtitle) so
hosts don't think it's broken when it actually doesn't exist.

---

## Test plan (after backend changes ship)

```bash
# 1. Chat REST works
curl -i -X POST https://mizdah-backend.ogoul.cloud/api/chat/send \
  -H "Content-Type: application/json" \
  -d '{"meetingId":"jhmyqrneac","senderId":"<id>","senderName":"X","content":"probe"}'
# → expected:  201 Created

# 2. Chat history CORS
curl -i -H "Origin: https://mizdah-front.ogoul.cloud" \
  https://mizdah-backend.ogoul.cloud/api/chat/jhmyqrneac?userId=<id>
# → expected:  Access-Control-Allow-Origin response header present

# 3. Report abuse endpoint
curl -i -X POST https://mizdah-backend.ogoul.cloud/api/abuse/report \
  -H "Content-Type: application/json" \
  -d '{"reporterId":"<id>","type":"Spam","names":"alice","description":"t"}'
# → expected:  200 OK, body includes "reportId"

# 4. Recording start
curl -i -X POST https://mizdah-backend.ogoul.cloud/api/recording/start/jhmyqrneac
# → expected:  200 OK, body includes "status":"recording"

# 5. Host controls — connect via socket.io and verify
#    lock-meeting, mute-all, update-settings, end-meeting-for-all
#    are all honoured + force-mute / host-changed-permission /
#    join-denied are emitted to peers when appropriate.
```

---

## Frontend changes shipping in this PR

The mobile client (commit pending) makes the following changes
that work TODAY against the existing backend:

- **Report abuse**: submit button now calls
  `SettingsRepository.sendFeedback()` (`/api/meeting/feedback`).
  Will switch over to `/api/abuse/report` once that endpoint
  exists. Errors are surfaced to the user instead of pretending
  success.
- **On the go**: implements a real compact-mode UI rather than
  the snackbar — toggling the option flips the meeting screen
  into a large-button audio-first layout suitable for use while
  moving. No backend involvement.
- **Screen share**: routes through `SFUService.produceScreen` so
  the screen video reaches other peers via mediasoup. No backend
  change.

After the backend changes documented above ship, no further
mobile redeploy is needed for: chat REST, abuse reporting, host
control enforcement, recording start/stop. Mobile will pick up the
new behaviour automatically.
