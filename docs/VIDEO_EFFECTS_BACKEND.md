# Video Effects — Backend Spec (a.k.a. "you don't need to do anything")

Quick answer: **the backend has zero work for video effects in v1.**
Effects are 100% local processing — each peer applies them to their
own outgoing camera frames *before* the WebRTC encoder, and the SFU
just forwards the encoded bytes. Whatever a peer encodes is what
others see.

This doc exists so the backend team has the same source of truth
the mobile team has, knows what changed on the wire (nothing for
v1), and can plan for the small follow-up surface that v2 (real
blur + touch-up) might introduce.

---

## 0. The three effects

| Effect | What it is | Backend impact |
|---|---|---|
| Outgoing video quality (Auto / 720p / 1080p) | Camera resolution + encoder bitrate cap | **None** — pure WebRTC sender-side knobs |
| Background blur (None / Light / Strong) | Real-time segmentation model + composite | **None for v1** (UI says "Coming soon") |
| Touch up appearance (0..100 slider) | Per-frame skin-smoothing shader | **None for v1** (UI says "Coming soon") |

The mobile client now (as of this commit) actually applies the
outgoing-quality preset to the live RTP sender. Before this commit
the user could move the dial but nothing happened — peers always
got the raw 720p default.

---

## 1. What changed on the mobile side this week

For the backend's awareness — none of this requires server
changes, but the wire shape is slightly different now:

### Outgoing bitrate cap

`RTCRtpSender.setParameters` now sets:

| Preset | maxBitrate | minBitrate | maxFramerate | camera ideal |
|---|---|---|---|---|
| **Auto** (default) | 1.8 Mbps | 300 kbps | 30 fps | 1280×720 |
| **720p** | 1.5 Mbps | 300 kbps | 30 fps | 1280×720 |
| **1080p** | 2.5 Mbps | 300 kbps | 30 fps | 1920×1080 |

Pre-change behaviour: no cap was set on the SFU producer at all
(mediasoup-client default). Peers' typical max was 3–5 Mbps on a
good link — too aggressive for the SFU's per-meeting budget.

If you've been observing the SFU as "always near 2 Mbps per
producer," that's why. Going forward you should see Auto sit
closer to 1.5–1.8 Mbps under normal conditions, and the per-meeting
forwarding budget gets the matching headroom back.

### Where the cap is applied

| Path | File | Function |
|---|---|---|
| Meeting (SFU) | `lib/core/services/sfu_service.dart` | `_applyQualityToVideoProducer()` runs on `_handleProducerCreated` + on `applyVideoQuality()` mid-call |
| P2P call | `lib/core/services/p2p_call_service.dart` | `_applyQualityToVideoSender()` runs right after `addTrack` + on `applyVideoQuality()` mid-call |
| Legacy mesh (pre-SFU fallback in meeting) | `lib/features/meeting/meeting_provider.dart` | `_tuneVideoSender()` reads the same provider |

All three call into the shared
`lib/core/services/video_quality_profile.dart` so the numbers above
live in exactly one place.

---

## 2. Possible v2 endpoints (not for now)

When background blur + touch-up actually ship as native plugins,
there's still no *required* backend work — frames are processed
on-device before encoding. But there are two **optional** surfaces
that would be nice to have someday:

### 2a. Telemetry — "what % of users have blur on"

If you want to know how often users enable blur (product
analytics), the cleanest path is a thin `POST /api/telemetry/effect`
event endpoint:

```json
POST /api/telemetry/effect
{
  "event": "effect_changed",
  "effect": "background_blur",
  "value": "light",
  "context": "meeting" | "p2p_call"
}
```

Non-blocking, low priority. The mobile client already has all
the state — we just don't have a sink for it.

### 2b. Server-enforced quality cap

Backend could publish a per-meeting `maxVideoBitrate` field on the
meeting row (for low-bandwidth tenants or paid-tier upgrades).
Mobile would read it and clamp the user's chosen quality to that
ceiling. v1 trusts the client. Defer until we have a paying tenant
that cares.

---

## 3. Why backend doesn't help with blur / touch-up

This is the question we got asked most when scoping this — "can
the server do the blur?" Answer: no, not in any way that ends up
at the peer's screen.

The reason: in any SFU architecture, the server forwards encoded
RTP packets. To run blur server-side, the server would have to
**decode every incoming track, run the segmentation model on every
frame, composite the blur, re-encode, and forward** — that's GPU
work multiplied by participant count × meeting count. mediasoup
isn't designed for that; it's purpose-built to forward, not
process. Google Meet does its blur client-side for the same
reason.

So the only viable architecture is:

```
camera → segmentation model → blur composite → encoder → SFU → peer
         (local, per-frame)
```

The piece that's missing is "segmentation model → blur composite."
That needs native code on each platform:

- **Android**: MediaPipe Selfie Segmentation (TFLite model, GPU
  delegate) inside a custom `VideoCapturer` that feeds the
  composited frames into WebRTC's `VideoTrackSourceInterface`.
- **iOS**: Vision framework's `VNGeneratePersonSegmentationRequest`
  feeding a Metal compositor on the same custom track source.

Estimated work: **1–2 weeks per platform** assuming you're
comfortable with the WebRTC native APIs. The mobile team is on
this as an R&D branch — not blocking the call/meeting release.

---

## 4. What the user sees today

After today's commit:

- The **Outgoing video quality** picker actually does what it
  says. Pick 720p on a meeting → peers receive your stream capped
  at 1.5 Mbps. Pick 1080p → peers receive up to 2.5 Mbps from a
  higher-resolution camera capture.
- The **Background blur** + **Touch up appearance** rows are
  visually marked "Coming soon" with a pill in the top-right
  corner. The controls still work (the values save, so when the
  native plugin lands the user's pre-existing preference takes
  effect immediately) but nothing reaches the wire today.

---

## 5. TL;DR for the backend stand-up

1. No new endpoints required.
2. No socket events required.
3. No schema changes required.
4. SFU will see a noticeable drop in per-producer outgoing
   bitrate variance — that's the maxBitrate cap doing its job.
5. If anyone asks "is blur done?" — no, mobile native R&D, ~2
   weeks per platform, doesn't gate the release.
