# 02 · Video & Camera

5 features covering self-view, image processing, and quality.

| Feature | Control | Default | Complexity |
|---|---|---|---|
| Camera off on join | toggle | `false` | S |
| Mirror my preview | toggle | `true` | S |
| Touch up appearance | slider 0–100 | `0` | M (UI) — needs camera-feed shader |
| Outgoing video quality | segmented (3) | `Auto` | S (UI) — pipeline applies the cap |
| Background | segmented (3+) | `None` | L — needs MediaPipe segmentation model |

---

## Camera off on join

**What.** When the user enters a meeting, their camera is disabled by default. They tap "camera on" when ready.

**Why.** Privacy default — same logic as mute-on-join. Users frequently join from bed, while changing, with kids or roommates in frame. Off-by-default lets users decide when they're presentable.

**UI.** `Switch.adaptive`.

**Default.** `false` (camera on at join is the current behaviour).

**Storage.** `mizdah_camera_off_on_join_v1`

**Behaviour notes.** Mirrors the audio version: the meeting room screen reads the provider on mount and disables the local video track before negotiation. User sees a black tile with their initial / avatar; tapping the camera button enables.

**Competitive context.** Universal — Zoom, Meet, Teams, all ship it.

---

## Mirror my preview

**What.** When the user looks at their own video tile, the image is horizontally flipped (mirror). **Other participants always see the un-flipped video.**

**Why.** Looking at yourself feels natural ONLY when mirrored — otherwise raising your right hand makes it look like your left hand. But mirroring what others see would render text and logos backwards (e.g. a t-shirt logo, a whiteboard behind you), which is jarring for them. So the convention universally is: mirror locally, send normally.

**UI.** `Switch.adaptive`. Default ON (the natural choice).

**Default.** `true`.

**Storage.** `mizdah_mirror_preview_v1`

**Behaviour notes.** The local `RTCVideoView` (or however the self-tile is rendered) gets `mirror: true` when the preference is on. The remote stream encoder is unaffected.

**Competitive context.** Universal. Zoom labels the toggle "Mirror my video"; Meet has the same; Teams has it as "Mirror my video".

---

## Touch up appearance

**What.** Slider 0 → 100. `0` = off; higher values apply progressively heavier skin smoothing on the user's outgoing camera feed.

**Why.** Subtle Gaussian/bilateral filter applied to the camera feed before encoding. Smooths skin texture, hides minor blemishes, evens out lighting. Popularised by Zoom in 2020 — became one of the surprise bestseller features of pandemic-era UX.

**UI.** `_SliderRow` with min=0, max=100, step=1. Inline value pill ("47") shows the current value.

**Default.** `0` (off).

**Storage.** `mizdah_touch_up_v1`

**Behaviour notes.** Applies a pre-encode shader pass on the local video pipeline:
- 0: no processing.
- 1–30: light bilateral filter, sigma_color ~10.
- 31–70: stronger filter, sigma_color ~25, plus mild brightness lift.
- 71–100: aggressive smoothing, can look "painterly" but some users want it.

Doesn't increase bandwidth (the smoothed frame just replaces the raw one before encoding). Adds GPU/CPU cost; on weak devices, frame rate may drop slightly at high values.

**Implementation note.** The shader pass is a native concern. The slider just records the user's preference. When the camera pipeline is wired, the chosen value drives the shader's intensity uniform.

**Competitive context.**
- **Zoom**: 0–10 slider. The flagship feature.
- **Microsoft Teams**: simple on/off toggle.
- **Google Meet**: doesn't ship this.
- **Snapchat / Instagram**: heavily over-baked (filters galore).

---

## Outgoing video quality

**What.** 3-state segmented control: **Auto / 720p / 1080p**.

**Why.** 1080p outgoing eats ~3–4× the bandwidth of 720p and uses ~2× the CPU. Some users on slow networks need to force 720p; some users with strong networks want 1080p for screen-sharing detail or interview quality. Most users want "Auto" and never think about it.

**UI.** `_SegmentedRow` with three options.

**Default.** `Auto`.

**Storage.** `mizdah_video_quality_v1`

**Behaviour notes.**
- **Auto**: SFU/peer negotiates quality based on network feedback. Layers up to 1080p when conditions allow; degrades cleanly under congestion.
- **720p**: Outgoing simulcast caps at 1280×720. Saves bandwidth.
- **1080p**: Allow up to 1920×1080. Uses more CPU + bandwidth; pegs older phones.

The pipeline reads this preference at meeting bootstrap and configures the simulcast layers accordingly.

**Competitive context.**
- **Zoom**: "HD video" toggle (off / on, with "Group HD" requiring paid plan).
- **Microsoft Teams**: "Standard / HD / Full HD" picker on Teams Premium.
- **Google Meet**: "Send resolution" picker with auto / SD / HD options.

---

## Background

**What.** Picker with 3 options to start: **None / Light blur / Strong blur**. Custom image upload is a future extension.

**Why.** Hides messy room, kids, roommates, hotel walls from the camera background. Became table-stakes in 2020 after the BBC interview where a child walked into the frame. Now expected by every business user.

**UI.** `_SegmentedRow` for the 3-state version. If you add custom backgrounds later, switch to a horizontal scrollable card list with the segments first and image thumbs after.

**Default.** `None`.

**Storage.** `mizdah_background_v1`

**Behaviour notes.**
- **None**: Raw camera feed.
- **Light blur**: ML segmentation (e.g. Google's MediaPipe Selfie Segmentation) splits foreground/background; background gets Gaussian sigma ~10. Subject stays sharp.
- **Strong blur**: Same segmentation, sigma ~25 — almost solid color blur. Useful when you don't want viewers to be able to read anything behind you.

**Implementation note.** Background processing is the heaviest of the v1 features:
- Requires bundling the MediaPipe Selfie Segmentation model (~2.5 MB compressed, ~5 MB in memory).
- Runs every frame (or every 2nd/3rd frame on weak devices) — significant CPU/GPU cost.
- Easy to ship the **preference + UI** today and wire it to the camera pipeline later. Until then, the toggle is functionally a no-op (which is fine — users don't see any harm).

**Competitive context.**
- **Microsoft Teams**: pioneered this. Has 30+ stock backgrounds + custom upload.
- **Google Meet**: Light blur / Strong blur / Stock backgrounds / Custom upload.
- **Zoom**: pioneered virtual backgrounds (green-screen era), now has segmentation-based blur + replace.
- **WhatsApp**: just blur (light / off).

---

## Recommended for v1: 4 of 5

Skip **Touch up appearance** if you're tight on time — it requires a native shader pass that doesn't exist yet, and the UI without the actual effect feels deceptive. The other 4 either work as-is (mirror, camera off on join) or just record a preference for the pipeline to honour later (HD quality, background).

If you can afford the ML model: ship Background. If you can't: ship just the preference and document that the actual blur lands in v1.1.
