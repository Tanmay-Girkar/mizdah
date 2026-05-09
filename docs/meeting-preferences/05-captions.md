# 05 · Captions & Accessibility

3 features around live transcription and caption rendering. This section introduces a new UI pattern (the bottom-sheet picker) — worth building before the audio/video sections that don't need it.

| Feature | Control | Default | Complexity |
|---|---|---|---|
| Live captions on join | toggle | `false` | S |
| Caption language | bottom-sheet picker | `en` | M |
| Caption size | segmented (3) | `Medium` | S |

---

## Live captions on join

**What.** When `true`, real-time speech-to-text captions auto-enable when the user enters a meeting.

**Why.**
- **Hearing-impaired users**: critical accessibility feature.
- **Non-native speakers**: text reinforces audio comprehension.
- **Noisy environments without headphones**: read instead of listen.
- **Quiet environments**: see what was said without turning audio up.

Manually toggling captions every meeting is friction. A persistent preference removes it.

**UI.** `Switch.adaptive` row.

**Default.** `false`. Auto-enable for everyone is wasteful; users who want it will discover and enable.

**Storage.** `mizdah_captions_on_join_v1`

**Behaviour notes.** When the meeting room mounts, this preference toggles the `captionsVisible` flag. The transcription stream starts subscribing to incoming audio when visible. Live transcription itself requires a backend service (see implementation note).

**Implementation note.** Real-time speech-to-text has three viable paths:
1. **Server-side**: SFU forwards audio to Google Cloud Speech / AssemblyAI / Deepgram and broadcasts captions over the signaling socket. Best quality, costs ~$0.01/minute/participant.
2. **On-device**: Use platform speech recognition (Apple's `SFSpeechRecognizer`, Google's `SpeechRecognizer`). Free but lower accuracy and only transcribes the LOCAL user's speech.
3. **Hybrid**: Each client transcribes their own outgoing audio on-device and broadcasts the text to others. Decentralised, private, no server cost.

Pick path later. The preference + UI ship today and become a no-op until path is chosen.

**Competitive context.**
- **Zoom**: "Always show captions" toggle. Server-side path (paid).
- **Google Meet**: "Always show captions" toggle. Server-side path, free.
- **Microsoft Teams**: "Turn on live captions automatically" toggle. Server-side path.

---

## Caption language

**What.** A bottom-sheet picker showing a list of supported languages (English, Spanish, French, German, Hindi, Arabic, Chinese, Japanese, Portuguese, Russian — adjustable). User picks one; captions assume that language going forward.

**Why.** Speech-to-text needs to know the source language. A Spanish meeting with English caption settings produces gibberish. Most STT services support auto-detect, but it's slower and less accurate than declaring upfront.

**UI.** `_PickerRow` — opens a modal bottom sheet with a scrollable list. The active language has a check-mark indicator (gradient pill with white check, matching the app's design language).

**Default.** `en` (English).

**Storage.** `mizdah_caption_lang_v1` (stores the BCP-47 short code: `en`, `es`, `hi`, etc.).

**Behaviour notes.** When captions activate, the chosen language is passed to the STT service. If the actual spoken audio doesn't match, captions will be wrong (which is the user's fault, but the UI could show a "Captions: Spanish — change language?" footer).

**Bottom-sheet UI details:**
- Slide up from bottom, ~70 % screen height.
- Drag handle (38×4 rounded pill) at top.
- "Caption language" title with close button on the right.
- Scrollable list of languages — name only (e.g. "Spanish"), no flag emoji (flags are politically fraught for some languages).
- Active item: gradient circle with white check icon.
- Tap an item: write to provider, dismiss sheet.

**Competitive context.**
- **Google Meet**: language picker; supports ~12 languages.
- **Microsoft Teams**: language picker; supports 40+ via Azure Cognitive Services.
- **Zoom**: auto-translate to user's language (any → any) — distinct UX.

---

## Caption size

**What.** 3-state segmented: **Small / Medium / Large**. Controls the font size of caption text in the meeting overlay.

**Why.**
- **Small phones, fewer captions on screen at once** vs. **Large screens / accessibility needs**.
- iOS native captions have 4 sizes and users actively use the picker.
- Not exposing this is a missed accessibility opportunity that's cheap to fix.

**UI.** `_SegmentedRow`.

**Default.** `Medium`.

**Storage.** `mizdah_caption_size_v1`

**Behaviour notes.** When captions render in the meeting overlay, the chosen size scales the text:
- **Small**: 13 sp.
- **Medium**: 16 sp (default).
- **Large**: 20 sp.

Optionally also scale the line height proportionally so multi-line captions don't feel cramped at Large.

**Competitive context.**
- **iOS native captions pane**: 4 sizes — small, medium, large, extra large.
- **Meet, Zoom, Teams**: don't expose caption size. Differentiation opportunity.

---

## Recommended for v1: all 3

Captions is a complete-or-not feature — shipping just one of these three feels half-baked. The toggle + picker + size triplet is the minimum viable accessibility set. Until the STT pipeline lands the values are no-ops, but users who need them will see the section exists and trust the app's accessibility commitment.

---

## Future extensions (post-v1)

- **Caption contrast** — Standard / High picker (white-on-black-shadow vs. yellow-on-black-box).
- **Save transcript to** — Device / Drive / None picker.
- **Auto-translate** — segmented On / Off; uses translation API.
- **Speaker labels in captions** — toggle to prefix captions with "Alice:", "Bob:".
