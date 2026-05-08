# Receiver health — keyframe pump

The mobile mediasoup client experiences "remote video froze after a
few seconds" symptoms on cellular and on networks with light
packet loss. The root cause is the natural keyframe interval on the
producer side (5-15s on most browsers / mobile encoders) combined
with simulcast layer switches: when the SFU drops a consumer to a
smaller layer, the receiver's H264 decoder must reinitialise and
needs a keyframe to start producing frames. If the next periodic
keyframe is several seconds away, the renderer shows the last good
frame and looks frozen.

The mobile FE shipped a workaround in commit `<pending>` that
emits `requestConsumerKeyFrame` every 4 seconds for each video
consumer. Pair it with a server-side handler that calls
`consumer.requestKeyFrame()` and the freezing stops.

Audience: the dev who maintains `mizdah-backend.ogoul.cloud`.

Verified on **2026-05-07**.

---

## Reproduce (current behaviour)

1. Open the meeting from web at `mizdah-front.ogoul.cloud`,
   camera on.
2. Join the same meeting from the mobile app, camera on.
3. Watch the web user's tile on the mobile app.
4. After 5-30 seconds (varies by network), the tile freezes on the
   last frame. Audio continues. The mobile log shows the H264
   hardware decoder being released and reinitialised at a smaller
   resolution (e.g. 120x90 → 80x60 → 80x60) — that's the simulcast
   layer drop. There's no keyframe to start the new decoder, so the
   renderer reports `Frames received: 0` over 4-second windows.

---

## What the FE workaround does

On every `consume` + `resumeConsumer` for a video consumer, the
mobile client now also:

1. **At consumer create + 600ms**: emits `requestConsumerKeyFrame`
   (custom event, the preferred path) AND a `pauseConsumer` →
   80ms → `resumeConsumer` cycle (fallback, works on the existing
   server because resumeConsumer triggers a PLI in mediasoup).
2. **Every 4s thereafter**: same combo for every active video
   consumer. Audio consumers are skipped — Opus self-recovers.

The pause/resume cycle works against the current server — it just
relies on the existing `resumeConsumer` handler. The downside: each
pump cycle introduces a ~80ms gap in RTP delivery to the consumer.
With a server-side `requestConsumerKeyFrame` handler we can drop
the pause/resume fallback and avoid the gap entirely.

---

## What needs to happen (server)

Add a Socket.IO handler on the `/media` namespace
(path `/media-fresh`):

```js
socket.on('requestConsumerKeyFrame', async ({ meetingId, consumerId }) => {
  const consumer = consumersById.get(consumerId);
  if (!consumer) return;          // unknown consumer, ignore
  if (consumer.kind !== 'video') return;
  try {
    await consumer.requestKeyFrame();
  } catch (e) {
    // RTP / RTCP errors are non-fatal — the next pump cycle retries
    console.warn('requestKeyFrame failed', consumer.id, e.message);
  }
});
```

`Consumer.prototype.requestKeyFrame()` is a built-in mediasoup
method ([docs](https://mediasoup.org/documentation/v3/mediasoup/api/#consumer-requestKeyFrame)).
It sends a PLI (Picture Loss Indication) RTCP packet to the
producer; the producer responds by emitting an IDR (keyframe) on
its next encode tick. End-to-end latency: ~50-200ms.

No ack is needed. The mobile client emits without `emitWithAck`.

Once this handler ships, the FE pause/resume fallback becomes
silently redundant — both paths fire, both work, but the
`requestConsumerKeyFrame` path completes first and the next pump
cycle short-circuits because the renderer is already alive again.
We can remove the pause/resume fallback from the FE in a later
cleanup commit; until then it's belt-and-suspenders.

---

## Test plan

### Before the server handler ships

```
[device log on mobile join]
[SFU] starting keyframe-pump (4s interval, 1 video consumer(s))
[SFU] requestConsumerKeyFrame consumer=<id>
... every 4 seconds, with the pause/resume fallback also firing.
```

Expected: video unsticks within ~80-200ms after each pump cycle.

### After the server handler ships

```
[server log]
requestConsumerKeyFrame meetingId=<id> consumerId=<id>
consumer.requestKeyFrame → ok
```

The server should see the event arrive every 4 seconds per video
consumer. Should complete in <50ms. No errors expected for healthy
consumers; producer-side errors (e.g. closed) are logged-and-ignored
per the snippet above.

---

## Bonus — simulcast preferred-layers

If the freezing is mostly caused by the SFU dropping consumers to
the smallest simulcast layer (which keyframes infrequently), we
could also expose:

```js
socket.on('setConsumerPreferredLayers', async (
  { meetingId, consumerId, spatialLayer, temporalLayer },
) => {
  const consumer = consumersById.get(consumerId);
  if (!consumer) return;
  await consumer.setPreferredLayers({ spatialLayer, temporalLayer });
});
```

## Bonus — producer-side keyframe nudge

When the mobile camera is toggled off then back on, flutter_webrtc
fully releases and re-initialises the H264 hardware encoder. The
new encoder emits a fresh IDR on its first frame, but the
remote consumers on web sometimes don't pick it up — they keep
showing the last frame they had before the toggle, OR a black
tile if there was none. The receiver-side keyframe pump
eventually pulls them back into sync, but a producer-side nudge
is much faster:

```js
socket.on('requestProducerKeyFrame', async (
  { meetingId, producerId },
) => {
  const producer = producersById.get(producerId);
  if (!producer || producer.kind !== 'video') return;
  try {
    // mediasoup's Producer doesn't expose requestKeyFrame
    // directly — instead enumerate every consumer of this
    // producer and ask each one for a key frame. The end
    // effect is the same: a PLI is sent up to the producer's
    // RTP source and the next encoded frame becomes an IDR.
    for (const c of consumersByProducerId.get(producerId) ?? []) {
      if (c.kind === 'video') c.requestKeyFrame().catch(() => {});
    }
  } catch (e) {
    console.warn('requestProducerKeyFrame failed', producerId, e.message);
  }
});
```

The mobile emits this exactly once per camera-on toggle, ~200ms
after `track.enabled = true`. No ack needed — fire-and-forget like
`requestConsumerKeyFrame`.

The mobile FE can then "pin" each consumer to the highest layer
that fits its decoded resolution, avoiding the layer-switch
storms entirely. Not required for the fix above to work — file
this under "future polish".
