# Recording — backend implementation spec

This document is the implementation spec for **meeting recording**.
The Flutter mobile client has the complete UI surface (record toggle,
consent dialog, REC indicator, consent banner, recordings list) and
the API + socket-event contracts wired against everything below.
Once this is shipped, recording works end-to-end with **no mobile
redeploy** — the client picks it up the moment the endpoints become
real.

Audience: the dev who maintains `mizdah-backend.ogoul.cloud`.

Verified against the live server on **2026-05-03**:
```
$ curl -s -o /dev/null -w "%{http_code}\n" -X POST \
    https://mizdah-backend.ogoul.cloud/api/recording/start/jhmyqrneac
404
```

So the endpoints below need to be built from scratch.

---

## Architecture overview

We use **server-side mediasoup recording with `PlainTransport` +
`ffmpeg`**. This is the standard mediasoup recording pattern — the
SFU forks each producer's RTP into a local UDP socket, ffmpeg
consumes it, the streams are muxed into one MP4, and the file is
uploaded to object storage.

```
Mobile / Web peers              mediasoup SFU                 Recorder worker
                                                              (same host as SFU)
   ─── audio prod ──>           PlainTransport ─── RTP ────> ffmpeg ─┐
   ─── video prod ──>           PlainTransport ─── RTP ────> ffmpeg ─┤
   ─── audio prod ──>           PlainTransport ─── RTP ────> ffmpeg ─┤
   ─── video prod ──>           PlainTransport ─── RTP ────> ffmpeg ─┤
                                                                     │
                                                                     ▼
                                                                 ffmpeg mux
                                                                     │
                                                                     ▼
                                                               /tmp/<id>.mp4
                                                                     │
                                                                     ▼
                                                                 R2 upload
                                                                     │
                                                                     ▼
                                                            recordings.url + signed URL
```

### Why this architecture

- Captures **everyone**, even if individual clients drop
- Quality doesn't depend on any one client's device or network
- Recording survives if the host's app dies mid-call
- Mediasoup has documented support — this is roughly 200 lines of
  Node + an ffmpeg invocation, not weeks of work

### When NOT this architecture

If you don't have ffmpeg available where the SFU runs, or you can't
afford the CPU/memory for compositing on the SFU host, the
fallback is a separate "recorder bot" Node process that connects
to the room as a regular mediasoup consumer. That's another half
day of work; spec on request.

---

## DB schema

```sql
CREATE TABLE recordings (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  meeting_id      UUID NOT NULL REFERENCES meetings(id) ON DELETE CASCADE,
  meeting_code    TEXT NOT NULL,        -- denormalised for /api/recording/<code>
  host_id         UUID NOT NULL REFERENCES users(id),
  status          TEXT NOT NULL CHECK (status IN
                    ('recording','processing','ready','failed')),
  started_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  ended_at        TIMESTAMPTZ,
  duration_seconds INTEGER,
  size_bytes      BIGINT,
  url             TEXT,                 -- full https URL once uploaded
  storage_key     TEXT,                 -- R2/S3 object key, for re-signing
  failure_reason  TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX recordings_meeting_code_idx
  ON recordings (meeting_code, started_at DESC);
CREATE INDEX recordings_host_id_idx
  ON recordings (host_id, started_at DESC);
```

### Status state machine

```
  recording  ─── stop() ──>  processing  ─── upload ok ──>  ready
       │                           │
       │                           └─── upload fail ───>  failed
       │
       └─── ffmpeg crash / timeout ─────────────────────>  failed
```

---

## REST endpoints

### `POST /api/recording/start/<meetingCode>`

**Authorization**: only the meeting's `host_id` may call. Reject
others with 403.

**Request body** (optional, all keys default if missing):

```json
{
  "kind":   "video",        // "video" | "audio"  (audio-only saves bandwidth + storage)
  "layout": "speaker"       // "speaker" | "grid" — speaker is cheaper (no compose)
}
```

**Behaviour**:
1. Verify host. If a `recordings` row already exists for this
   meeting with status=`recording`, return 409 with the existing
   `recordingId` instead of starting a duplicate.
2. Insert a `recordings` row (status=`recording`, started_at=now()).
3. For every CURRENT producer in the room (every peer's audio +
   video producer), call `mediasoup.router.createPlainTransport(...)`
   and pipe the RTP into a per-producer ffmpeg subprocess writing
   to `/tmp/<recordingId>-<producerId>.opus|vp8`.
4. Subscribe to the room's `newproducer` event so peers joining
   mid-recording also get hooked up. Likewise `producerclose`
   should close that producer's ffmpeg subprocess.
5. Emit Socket.IO event `recording-started` to every socket in the
   room (see "Socket events" below).
6. Return `200 OK`:

```json
{
  "recordingId": "<uuid>",
  "status":      "recording",
  "startedAt":   "2026-05-03T16:00:00.000Z"
}
```

**Failure modes** the FE handles:
- `403` — not host. FE shows "Only the host can record" SnackBar.
- `409` — already recording. FE just refreshes UI from the
  existing row (silently absorbed).
- `500` — backend exception. FE shows the message in a red
  SnackBar and resets the toggle.

### `POST /api/recording/stop/<meetingCode>`

**Authorization**: host only.

**Behaviour**:
1. Find the active `recordings` row (status=`recording`).
   If none, return 404.
2. Send `q` to ffmpeg stdin on every active subprocess; await exit
   with a 30-second timeout. SIGKILL if it hangs.
3. Update row → status=`processing`, ended_at=now(),
   duration_seconds.
4. Emit `recording-stopped` to all sockets in the room.
5. Run the mux step in the background:
   - Speaker layout: `ffmpeg -i a1.opus -i a2.opus … -i v_speaker.vp8 \`
     `-filter_complex "[0:a][1:a]amix=inputs=N" \`
     `-c:v copy -c:a libopus output.mp4`
   - Grid layout: same but with `-filter_complex` doing a 2x2/3x3
     `xstack` of the video inputs. (Defer to phase 2 if speaker
     is what you ship first.)
6. Upload `/tmp/<recordingId>.mp4` to object storage.
7. Update row → status=`ready`, url=signed URL (24h expiry),
   storage_key=…, size_bytes=….
8. Emit `recording-ready` to all sockets in the room **AND** to
   the host's user-channel (so they get notified even if they've
   left the room).
9. Delete the `/tmp/<recordingId>-*` working files.

**Returns** *immediately after step 4* (don't make the host wait
for the upload):

```json
{
  "recordingId":     "<uuid>",
  "status":          "processing",
  "endedAt":         "2026-05-03T16:42:11.000Z",
  "durationSeconds": 2531
}
```

The FE displays "Processing recording…" until the
`recording-ready` socket event arrives with the final URL.

### `GET /api/recording/<meetingCode>`

**Authorization**: any participant of the meeting (host or
prior attendee). Reject others with 403.

**Returns** an array of recordings for that meeting, newest first:

```json
[
  {
    "recordingId":     "9c3f2c4e-…",
    "status":          "ready",
    "startedAt":       "2026-05-03T15:00:00.000Z",
    "endedAt":         "2026-05-03T16:42:11.000Z",
    "durationSeconds": 6131,
    "sizeBytes":       412376432,
    "url":             "https://r2.signed-url..."
  },
  {
    "recordingId":     "...",
    "status":          "processing",
    "startedAt":       "...",
    "endedAt":         null,
    "durationSeconds": null,
    "url":             null
  }
]
```

If the signed URL has expired (> 24h since generation), return a
freshly signed one in the same response. The FE doesn't need to
know — it just opens whatever URL it gets.

### `GET /api/recordings/user/<userId>`  *(phase 2, optional)*

For a "My recordings" screen on the home dashboard. Same shape as
above but filtered by `host_id`. Defer to phase 2; the per-meeting
endpoint covers MVP.

---

## Socket events

All on the existing **signaling** socket (`/signaling-fresh`).

### Server → clients (broadcast to room)

| Event | When | Payload |
|---|---|---|
| `recording-started` | `POST /start/<code>` succeeds | `{ recordingId, hostName, startedAt }` |
| `recording-stopped` | `POST /stop/<code>` succeeds (before upload) | `{ recordingId, durationSeconds }` |
| `recording-ready` | Upload finishes | `{ recordingId, url, durationSeconds, sizeBytes }` |
| `recording-failed` | ffmpeg crash, upload fails, etc. | `{ recordingId, reason }` |

### Server → host only

| Event | When | Payload |
|---|---|---|
| `recording-ready` | Same as above, but ALSO sent to the host's per-user channel so they see it even after leaving the meeting | same |

### Client → server (already used by the existing FE)

| Event | When | Payload |
|---|---|---|
| `request-recording` | Host taps "Record" — current FE emits this *in addition to* the REST `start` call. You can ignore it on the server, the REST call is authoritative. | `{}` |
| `respond-recording` | Reserved for future consent-vote flow (non-hosts can opt-out). MVP: server can ignore. | `{ agree: bool }` |
| `stop-recording` | Host taps "Stop". Like `request-recording`, also covered by the REST call — server can ignore. | `{}` |

---

## Mediasoup PlainTransport snippet

Reference Node ~30 lines:

```js
async function attachRecorder(router, producer, recordingId) {
  // Create a PlainTransport on the SFU side that forwards RTP to
  // a local UDP port. ffmpeg listens on that port.
  const transport = await router.createPlainTransport({
    listenIp: { ip: '127.0.0.1', announcedIp: null },
    rtcpMux: false,                  // ffmpeg wants RTP/RTCP separately
    comedia: true,                   // we don't have remote IP yet
  });
  const rtpPort = transport.tuple.localPort;
  const rtcpPort = transport.rtcpTuple.localPort;

  // Tell mediasoup to forward this producer's RTP to the transport.
  const consumer = await transport.consume({
    producerId: producer.id,
    rtpCapabilities: router.rtpCapabilities,
    paused: true,                    // resume after ffmpeg is up
  });

  // Spawn ffmpeg with a per-producer SDP file describing the codec.
  const sdp = buildSdp(consumer, rtpPort, rtcpPort);
  const sdpPath = `/tmp/${recordingId}-${producer.id}.sdp`;
  await fs.writeFile(sdpPath, sdp);

  const outFile = `/tmp/${recordingId}-${producer.id}.${
    producer.kind === 'audio' ? 'opus' : 'webm'
  }`;
  const ff = spawn('ffmpeg', [
    '-loglevel', 'warning',
    '-protocol_whitelist', 'pipe,udp,rtp,file',
    '-i', sdpPath,
    '-c', 'copy',
    outFile,
  ]);
  ff.stdin = process.openStdin();    // for the 'q' to stop cleanly

  await consumer.resume();
  return { transport, consumer, ff, outFile };
}
```

### Building the SDP

```js
function buildSdp(consumer, rtpPort, rtcpPort) {
  const params = consumer.rtpParameters;
  const codec = params.codecs[0];
  const kind = consumer.kind;
  const payload = codec.payloadType;
  const ssrc = params.encodings[0].ssrc;

  return [
    'v=0',
    'o=- 0 0 IN IP4 127.0.0.1',
    's=Mizdah Recording',
    'c=IN IP4 127.0.0.1',
    't=0 0',
    `m=${kind} ${rtpPort} RTP/AVP ${payload}`,
    `a=rtpmap:${payload} ${codec.mimeType.split('/')[1]}/${codec.clockRate}` +
      (codec.channels ? `/${codec.channels}` : ''),
    `a=rtcp:${rtcpPort}`,
    `a=ssrc:${ssrc} cname:mizdah-recorder`,
    'a=recvonly',
    '',
  ].join('\n');
}
```

### Mux command (after stopping)

```bash
ffmpeg \
  -i in1-audio.opus -i in2-audio.opus -i in3-audio.opus \
  -i in_speaker-video.webm \
  -filter_complex \
    "[0:a][1:a][2:a]amix=inputs=3:duration=longest[aud]" \
  -map "[aud]" -map 3:v \
  -c:v copy -c:a aac -b:a 128k \
  -movflags +faststart \
  /tmp/<recordingId>.mp4
```

`-movflags +faststart` is critical for streaming playback —
without it the user has to download the full file before it'll
play in a browser.

---

## Storage (Cloudflare R2)

### Why R2

You're already on Cloudflare (visible in `cf-ray` headers across
the existing API). R2 has **zero egress fees**, which matters a
lot for video — a 100MB recording streamed by 10 viewers on AWS
S3 costs ~$0.09 per playback, on R2 it's $0.

### Bucket setup

```
mizdah-recordings (R2 bucket)
├── meeting/<meetingCode>/<recordingId>.mp4
└── ...
```

Use the `meetingCode` prefix so a per-meeting list query is a
fast prefix scan, not a full bucket walk.

### Signed URLs

- Generate at upload time + on every `GET /api/recording/<code>`
- 24-hour expiry
- HTTP method: `GET`
- Don't cache the URL in the DB — store the `storage_key` and
  re-sign on demand. Survives R2 credential rotation.

### Permissions

- R2 bucket **private**
- Backend has read+write via API token
- No public URL — clients only ever get signed URLs

---

## Failure modes the frontend handles

The FE expects these failure surfaces. Match them so the user gets
a sensible error instead of a silent stuck-on-"recording" state:

| Backend failure | What the FE expects |
|---|---|
| ffmpeg dies during recording | Server emits `recording-failed { recordingId, reason: 'recorder-died' }`. FE flips the toggle off and shows red snackbar with the reason. |
| Upload to R2 fails | Server emits `recording-failed { recordingId, reason: 'upload-failed' }` AFTER updating the row to status=`failed`. |
| Disk full during recording | Same as ffmpeg-died. Cleanup the partial files. |
| Recording exceeds duration cap (4h default) | Server auto-stops AND emits `recording-stopped` followed by `recording-ready` once mux+upload finish. Treat as a normal stop. |
| Backend restart mid-recording | Persist active recording state somewhere durable (Redis is fine) so on boot you can either resume the ffmpeg subprocesses (if /tmp survived) or mark the row failed. The FE shows "Recording failed: server restarted" if the row is set to failed with `failure_reason: 'server-restart'`. |

---

## Test plan once shipped

```bash
USERID="9844168e-2c11-4633-aa27-706efac987df"
CODE=$(echo "rectest$(date +%s | tail -c 4)")

# 1. Create the meeting
curl -s -X POST https://mizdah-backend.ogoul.cloud/api/meetings/create \
  -H "Content-Type: application/json" \
  -d "{\"hostId\":\"$USERID\",\"title\":\"rec-test\",\"id\":\"$CODE\",\"meeting_code\":\"$CODE\"}"

# 2. Start recording
curl -i -X POST https://mizdah-backend.ogoul.cloud/api/recording/start/$CODE \
  -H "Content-Type: application/json" -d '{"kind":"video","layout":"speaker"}'
# expected:  200 OK, body has {recordingId, status:"recording", startedAt}

# 3. Verify status is `recording`
curl -s https://mizdah-backend.ogoul.cloud/api/recording/$CODE | jq
# expected:  one row with status:"recording"

# 4. Stop
curl -i -X POST https://mizdah-backend.ogoul.cloud/api/recording/stop/$CODE
# expected:  200 OK, body has status:"processing"

# 5. Wait ~30s, then verify it became ready
sleep 30
curl -s https://mizdah-backend.ogoul.cloud/api/recording/$CODE | jq
# expected:  status:"ready", url:"https://...r2.cloudflarestorage.com/...",
#            durationSeconds, sizeBytes

# 6. Open the URL — it should stream playable MP4 in any browser
open "$(curl -s ... | jq -r '.[0].url')"

# 7. Authorization: a non-host calling start/stop must get 403
curl -i -X POST https://mizdah-backend.ogoul.cloud/api/recording/start/$CODE \
  -H "X-User-Id: <some-other-user-uuid>"
# expected:  403 Forbidden
```

If all 7 pass, the implementation is correct end-to-end and the
mobile client + web client will pick up the feature immediately.

---

## Frontend status

The mobile client (commit pending in this PR) ships:

- **REC indicator** in the meeting top bar — small red dot + "REC"
  label, visible to all participants when `recording-started` has
  fired.
- **Consent banner** — full-width strip across the top of the
  meeting room when recording is active. Shown for users who
  joined AFTER recording started (the host's own start triggers
  a confirm dialog instead, which already exists).
- **Recordings list screen** at `/recordings/<meetingCode>` —
  reachable from the meeting's overflow menu and from the home
  screen Recent activity (long-press a meeting tile). Lists every
  recording with status badge (`recording` / `processing` /
  `ready` / `failed`), duration, size, and a play button that
  opens the signed URL.
- **`recording-ready` socket listener** — surfaces a SnackBar to
  the host: *"Your recording is ready — view"* with a tap-action
  that opens the URL.
- **`recording-failed` socket listener** — surfaces a red SnackBar
  with the failure reason.
- **Auto-recovery from "track is null" state** — the existing
  toggle-recovery shipped in commit `eb203bc` already handles
  the camera/mic re-acquire path, so a recording that catches a
  stale producer mid-call will continue to receive frames after
  the user re-enables the camera.

After this backend ships, no further mobile redeploy is needed
for MVP recording. Phase 2 features (recordings list on home,
auto-delete, audio-only) will come in a follow-up PR.

---

## Phasing summary

| Phase | Backend | Frontend | Cost |
|---|---|---|---|
| **1 — MVP**   | Endpoints + ffmpeg + R2 + 4 socket events | Already shipping in this PR | ~1 week BE |
| **2 — Polish** | Grid layout, /api/recordings/user/`<id>`, retention policy | Recordings tab on home | ~3-5 days BE |
| **3 — Compliance** | Encryption at rest, DSAR export, per-org quotas, max-duration cap, audit log | Settings → Recordings preferences | ~1 week BE |

Phase 1 alone is a working "Zoom-style record + share" feature.
Don't block on phase 2/3 to ship.
