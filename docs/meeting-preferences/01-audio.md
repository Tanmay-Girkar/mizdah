# 01 · Audio

3 features that shape how the user's microphone behaves in meetings.

| Feature | Control | Default | Complexity |
|---|---|---|---|
| Mute on join | toggle | `false` | S |
| Noise suppression | segmented (3) | `Standard` | S (UI) — backend wires in real audio pipeline later |
| Music mode | toggle | `false` | S |

---

## Mute on join

**What.** When the user enters a meeting, their microphone is disabled by default. They have to tap "unmute" to be heard.

**Why.** Privacy / politeness default. Users frequently join meetings while finishing a sentence, eating, or in noisy environments. Auto-mute prevents awkward "you're on mute"-but-also-not-on-mute moments.

**UI.** Simple `Switch.adaptive`. Whole row tappable.

**Default.** `false` (current behaviour where mic is on at join). Some users will flip it to `true` immediately; that's fine — once set, it persists.

**Storage.** `mizdah_mute_on_join_v1`

**Behaviour notes.** When the meeting room screen mounts, it reads this provider and conditionally calls `localStream.getAudioTracks().forEach((t) => t.enabled = false)` before the meeting socket connects. The user sees the mic icon with a slash badge in the bottom dock; tapping un-mutes.

**Competitive context.**
- **Zoom**: "Always mute my microphone when joining a meeting" (Settings → Audio).
- **Google Meet**: Auto-mute kicks in for meetings with 5+ participants by default; user can override per-meeting.
- **Microsoft Teams**: "Default mic" toggle in calls settings.

---

## Noise suppression

**What.** ML-based filter that strips background noise (typing, fans, traffic, dog barking) from the user's outgoing mic feed. Three intensity levels.

**Why.** The single highest-impact audio feature in modern conferencing. Without it, every meeting from a coffee shop or open-plan office is unbearable. Krisp built an entire company around this; Google, Zoom, Microsoft all licensed or built their own.

**UI.** `_SegmentedRow` with three options: **Off / Standard / High**. Sliding gradient pill animates between them.

**Default.** `Standard` — the value most users want without thinking about it.

**Storage.** `mizdah_noise_suppression_v1` (stored as the enum's `.name` — `off`, `standard`, `high`).

**Behaviour notes.**
- **Off**: Raw mic audio — only echo cancellation applied (handled by WebRTC by default).
- **Standard**: Mild filter. Background fans / gentle typing / room reverb fade. Voice slightly compressed but natural.
- **High**: Aggressive filter. Even loud chewing, construction noise, or a vacuum cleaner gets silenced. Voice can sound slightly robotic on poor hardware — "speech-coded" feel.

**Implementation note.** The actual DSP is a backend / native concern (RNNoise, Krisp SDK, or platform-native API). This setting just records the user's preference. When the audio pipeline is wired, the chosen value selects the model intensity. UI for it is decoupled; you can ship this preference today even if the pipeline lands later.

**Competitive context.**
- **Zoom**: "Suppress background noise" with off / auto / low / medium / high.
- **Google Meet**: "Noise cancellation" — toggle only; intensity hidden.
- **Microsoft Teams**: "Noise suppression" with low / auto / high.
- **Discord**: "Krisp noise cancellation" toggle only.

---

## Music mode

**What.** Boolean toggle. When enabled, **disables** noise suppression and **raises audio bitrate** for high-fidelity sound.

**Why.** Noise suppression murders music. A guitar instructor running a remote class wants the algorithm to NOT identify their guitar as noise and silence it. Same for podcasters interviewing each other, or a band rehearsing remotely. Music mode is the escape hatch.

**UI.** `Switch.adaptive`.

**Default.** `false`. Niche feature, but loved by the people who need it.

**Storage.** `mizdah_music_mode_v1`

**Behaviour notes.** When `true`:
- Noise suppression preference is overridden to `Off` for the duration of the meeting (preference is preserved; just bypassed).
- Echo cancellation is also disabled (musicians often want to hear themselves through monitors without the AEC removing their own audio).
- Audio bitrate raised: typical meeting audio uses Opus at ~32 kbps mono; music mode bumps to 96–128 kbps stereo.
- Bandwidth cost is ~3–4× higher; battery usage increases proportionally.

**Implementation note.** Like noise suppression, the actual DSP / encoder config is downstream of this preference. UI ships independently.

**Competitive context.**
- **Zoom**: "Original sound for musicians" with stereo / high-fidelity sub-toggles. Most well-known music mode in the industry.
- **Google Meet**: "Music mode" — experimental, off by default.
- **Microsoft Teams**: "High fidelity music mode" added in 2022.
- **Most others**: don't ship this. Differentiator for music / podcast use cases.

---

## Recommended for v1: all 3

Even though Music mode is niche, it's a one-line toggle and the entire Audio section feels incomplete without it. Cost of including it is essentially zero.
