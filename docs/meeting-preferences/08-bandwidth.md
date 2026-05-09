# 08 · Bandwidth & Performance

3 features for users on metered networks, weak devices, or just paranoid about data caps.

| Feature | Control | Default | Complexity |
|---|---|---|---|
| Data saver | toggle | `false` | M (UI now, pipeline gates later) |
| Don't upload video on cellular | toggle | `false` | M (needs `connectivity_plus` for network type) |
| Hardware acceleration | toggle | `true` | S (UI now, encoder factory honors later) |

---

## Data saver

**What.** When `true`, the app aggressively reduces bandwidth across the meeting:
- Outgoing video drops to 360p.
- Incoming video pauses for tiles not currently visible (off-screen during scroll, or non-spotlight in spotlight layout).
- Simulcast layers cap at the lowest tier the SFU offers.
- Audio is unchanged (it's already cheap; cutting audio isn't worth the quality hit).

**Why.** Travelers, users on metered hotspots, users in regions where data is expensive (India, Brazil, Indonesia, Egypt). A 1-hour HD meeting can burn 1+ GB; data saver brings that down to ~150 MB. For users on a 1 GB monthly mobile plan, this is the difference between "Mizdah is unusable" and "Mizdah is fine".

**UI.** `Switch.adaptive`.

**Default.** `false`. Most users have WiFi or generous data; toggle is opt-in.

**Storage.** `mizdah_data_saver_v1`

**Behaviour notes.** When `true`, the meeting room's send-side simulcast config caps at 360p:
```
encodings: [
  { rid: 'q', maxBitrate: 200_000, scaleResolutionDownBy: 1 },
  // No high or mid layer.
]
```

Receive side: the SFU consumer for off-screen tiles is paused via `pauseConsumer` (already implemented in `sfu_service.dart` for the keyframe pump). On scroll-into-view it resumes; on scroll-out it pauses again.

Network costs drop to ~25–30 % of normal HD meetings.

**Competitive context.**
- **Google Meet**: "Limit data usage" toggle.
- **WhatsApp video**: "Use less data for calls" toggle. Aggressive — caps at 144p.
- **Zoom**: doesn't expose a single-toggle data saver; instead exposes individual quality controls.

---

## Don't upload video on cellular

**What.** When `true` AND the user is on a mobile data connection (not WiFi), camera stays off automatically. Toggling camera-on while on cellular shows a confirm dialog ("You're on cellular data. Turn on camera anyway?").

**Why.** Stronger version of data saver — outgoing video is the biggest bandwidth eater. Users very protective of their data caps want a hard rule, not "reduced quality". Common in India, Brazil, parts of Africa, and any user on a small mobile plan.

**UI.** `Switch.adaptive`.

**Default.** `false`.

**Storage.** `mizdah_no_upload_on_cellular_v1`

**Behaviour notes.**
1. On meeting join, check the network type via `connectivity_plus`:
   - WiFi: no constraint.
   - Cellular AND `noUploadOnCellular == true`: force camera off, show subtle banner "Camera disabled on cellular".
2. Lifecycle listener detects network changes mid-call:
   - WiFi → Cellular transition: turn camera off, show banner.
   - Cellular → WiFi: don't auto-restore camera (let user opt back in).
3. User taps camera button while on cellular: show dialog. If confirmed, camera turns on for this meeting only (no preference change).

**Implementation note.** Requires `connectivity_plus` package (already a common Flutter dep) for the network-type check. UI ships before the network check is wired — the toggle is just stored until then.

**Competitive context.**
- **WhatsApp**: doesn't ship this exact feature, but its "Use less data" handles the spirit.
- **Skype**: has it for video calls.
- **Most others**: don't have. Differentiator for cost-conscious users in emerging markets.

---

## Hardware acceleration

**What.** Boolean toggle. When `true` (default), video encoding/decoding uses the GPU via platform APIs (`MediaCodec` on Android, `VideoToolbox` on iOS). When `false`, falls back to software (CPU) encoding.

**Why.** ~99 % of users want this `true` — it's faster, lower battery drain, lower CPU. But:
- ~1 % of devices have buggy hardware encoders that produce green frames, garbled video, or crashes.
- Some Android OEMs ship MediaCodec implementations with codec-specific bugs (e.g. certain VP8/H264 profiles fail on specific Mali GPUs).
- Users on those devices need an escape hatch — software encoding is slower but reliable.

The toggle is a support-team escape hatch: "Tell users with green frames to disable hardware acceleration".

**UI.** `Switch.adaptive`.

**Default.** `true`.

**Storage.** `mizdah_hardware_accel_v1`

**Behaviour notes.** When the WebRTC video encoder factory is constructed (in `sfu_service.dart` and `p2p_call_service.dart`), conditionally:
```
final factory = preference
  ? createHardwareVideoEncoderFactory()
  : createSoftwareVideoEncoderFactory();
```

Toggling the preference takes effect on next call (factory is constructed at call setup, not at app launch).

**Implementation note.** flutter_webrtc 0.12.x exposes `setVideoCodecsToReceiveSpec` and similar but doesn't have a clean public API to swap encoder factories per-call. May require a method-channel patch. UI ships independently — preference is recorded, pipeline honors it later.

**Competitive context.**
- **Zoom**: "Enable hardware acceleration for video processing" — split into receiving / sending toggles in advanced settings.
- **Microsoft Teams**: "Disable GPU hardware acceleration" toggle.
- **Google Meet**: doesn't expose. Has caused frustration when users hit GPU bugs.

Exposing it is a power-user / support-team affordance; most users will never touch it.

---

## Recommended for v1: 1 of 3

- **Data saver** — high user impact for emerging markets, well-understood feature, ships well.
- **Don't upload on cellular** — defer. Network-type detection adds a dependency; the use case overlaps heavily with Data Saver.
- **Hardware acceleration** — defer. Truly niche; only needed when support tickets demand it. Add when the first device-bug ticket arrives.

If you want only one feature from this section: ship **Data saver**. It's the one that meaningfully changes the user experience for a large audience (emerging-market users). The other two are belt-and-braces additions.

---

## Future extensions (post-v1)

- **Cap incoming streams** — slider 4 → 25. Limits how many HD streams the user receives concurrently. Useful for users with weak GPUs in 30+ person meetings.
- **Reduce quality on low battery** — toggle. Below 20 % battery, cap outgoing to 360p and pause off-screen incoming.
- **Pause video when app is backgrounded** — toggle. Already default on most platforms, but exposing it lets users override.
- **Frame rate cap** — slider 15 / 24 / 30 fps. Lower frame rate = lower CPU + bandwidth, more cinematic.
- **Bandwidth cap (kbps)** — slider 200 / 500 / 1000 / 2000 / Auto. Power-user override of the SFU's adaptive bitrate controller.
