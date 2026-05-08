# `/media-fresh` engine.io endpoint missing on dev server

The mobile client cannot establish video/audio with peers when
pointed at the local dev server (`https://192.168.1.48:3001`).
Diagnosis: the dev box does not expose the `/media-fresh`
engine.io endpoint that production has.

Audience: the backend dev maintaining the local dev server at
`192.168.1.48:3001`.

Verified on **2026-05-08**.

---

## What works on the dev server today

✅ All REST endpoints (login, meetings, participants, scheduling,
   waiting room) — return 2xx as expected.

✅ Engine.io `/signaling-fresh` — Socket.IO connects, the mobile
   gets a session id, `join-meeting` fires, `request-to-join` and
   `user-joined` events flow correctly. Host-detection bug
   (already documented) is the only quirk and the FE works
   around it.

## What's broken

❌ Engine.io `/media-fresh` — every WebSocket upgrade fails:

```
HttpException: Connection closed before full header was received,
uri = https://192.168.1.48:3001/media-fresh/?EIO=4&transport=websocket
```

The TCP connection is opened, but the server closes it before
sending complete HTTP headers. This happens identically on every
reconnection attempt (~every 4 seconds).

Without `/media-fresh`, mediasoup-client cannot:
- emit `createRoom` / `createTransport` / `joinMedia`
- receive `existingProducers` / `newProducer`

So no video/audio flows in either direction.

---

## Reproduce

### 1. Confirm signaling works (sanity check)

```bash
curl -k -sS -i --max-time 5 \
  'https://192.168.1.48:3001/signaling-fresh/?EIO=4&transport=polling' \
  | head -20
```

Expected: `HTTP/1.1 200 OK` + a body starting with `0{"sid":"...",...}`
(engine.io session payload).

### 2. Confirm media is broken

```bash
curl -k -sS -i --max-time 5 \
  'https://192.168.1.48:3001/media-fresh/?EIO=4&transport=polling' \
  | head -20
```

Likely outcomes:
- `HTTP/1.1 404 Not Found` → endpoint isn't mounted at all
- `HTTP/1.1 502 Bad Gateway` → mounted but the upstream mediasoup
  process isn't running / crashed
- Empty response / connection closed → engine.io is half-mounted
  (returns 101 then drops) — that's what the mobile client sees

The expected response on a healthy `/media-fresh` mount is the
same shape as `/signaling-fresh`: `HTTP/1.1 200 OK` + a body
starting with `0{"sid":"...","upgrades":["websocket"],...}`.
That's what the mobile client needs in order to upgrade to the
WebSocket transport and run the mediasoup handshake.

---

## What needs to happen

The dev server needs to mount the same engine.io endpoint that
production has at `/media-fresh`, attached to the mediasoup
namespace. The mobile FE expects the same protocol it
reverse-engineered from the deployed web bundle:

```
client → server: createRoom         {meetingId} → ack {routerRtpCapabilities}
client → server: createTransport    {meetingId, direction} → ack {params}
client → server: connectTransport   {meetingId, transportId, dtlsParameters} → ack
client → server: produce            {meetingId, transportId, kind, rtpParameters, appData} → ack {id}
client → server: consume            {meetingId, transportId, producerId, rtpCapabilities} → ack {params}
client → server: resumeConsumer     {meetingId, consumerId} → ack
client → server: joinMedia          {meetingId}
server → client: existingProducers  {producers: [{producerId, kind, appData}, ...]}
server → client: newProducer        {producerId, kind, appData}
server → client: consumerClosed     {consumerId}
```

Plus the previously-shipped recovery handlers:
- `requestConsumerKeyFrame {meetingId, consumerId}` → server calls
  `consumer.requestKeyFrame()` (see docs/RECEIVER_HEALTH_BACKEND.md)
- `setConsumerPreferredLayers {meetingId, consumerId, spatialLayer, temporalLayer}`
- `pauseConsumer` / `resumeConsumer` (already used today, plus the
  4-second keyframe-pump fallback the FE emits)

---

## How to confirm the fix works

After mounting `/media-fresh` and restarting the dev server, the
mobile log on the next meeting join should show:

```
[MEET] [SFU] 🚀 _bootstrapSfu() entered ...
[MEET] [SFU] media socket CONNECTED (sid=...)
[MEET] [SFU] got routerRtpCapabilities
[MEET] [SFU] device loaded
[MEET] [SFU] sendTransport state=connecting → connected
[MEET] [SFU] recvTransport state=connecting → connected
[MEET] [SFU] joinMedia emitted
[MEET] [SFU] producerCallback id=... kind=audio
[MEET] [SFU] producerCallback id=... kind=video
```

Instead of the current:

```
[MEET] [SFU] media socket ERROR: HttpException: Connection closed ...
[MEET] [SFU] media socket CONNECT_ERROR: HttpException: Connection closed ...
[MEET] [SFU] bootstrap aborted — media socket did not connect
```

Once the bootstrap succeeds, video should flow both ways within
the existing 1-3 second SFU establishment window.
