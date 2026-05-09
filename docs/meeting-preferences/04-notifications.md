# 04 · Notifications & Sounds

4 features. All pure toggles — easiest section to wire up. Recommended as the first feature group to build after the architecture (00).

| Feature | Control | Default | Complexity |
|---|---|---|---|
| Sound on join / leave | toggle | `true` | S |
| Sound on chat message | toggle | `true` | S |
| Vibrate on incoming call | toggle | `true` | S |
| Mute notifications during meetings | toggle | `true` | M (needs DND permission) |

---

## Sound on join / leave

**What.** Plays a soft chime when a participant joins or leaves the meeting.

**Why.** In small meetings (1–5 people) it's polite to know when someone joined late. In large meetings (20+) the constant chiming is maddening. The toggle handles both extremes.

**UI.** `Switch.adaptive`.

**Default.** `true`.

**Storage.** `mizdah_sound_join_leave_v1`

**Behaviour notes.** When a participant-joined or participant-left event fires from the signaling socket, check this preference and conditionally play a short audio asset (e.g. `assets/sounds/join.wav`, `assets/sounds/leave.wav`) using `audioplayers` or similar. Asset doesn't exist yet — preference can ship before the audio asset.

**Competitive context.**
- **Zoom**: "Play sound when someone joins or leaves". Disabled in webinars.
- **Google Meet**: "Sound effects" toggle.
- **Microsoft Teams**: "Calls and meeting alerts" with sub-toggles.

---

## Sound on chat message

**What.** Plays a subtle pop when a new chat message arrives during a meeting.

**Why.** People focus on the video tiles and miss chat messages. The sound says "look at the chat tab". Users in large/formal meetings disable it to avoid distractions.

**UI.** `Switch.adaptive`.

**Default.** `true`.

**Storage.** `mizdah_sound_chat_v1`

**Behaviour notes.** When the chat socket delivers a new message and the chat panel isn't already open, play a short pop. Suppress when the chat panel is in the foreground (no point pinging the user about a message they just opened).

**Competitive context.** Universal toggle in every conferencing app.

---

## Vibrate on incoming call

**What.** When someone places a P2P call to the user (via the Call tab), the phone vibrates in addition to ringing.

**Why.** Phone may be in silent mode but vibration on. Or in a pocket — visual notifications would be missed. Vibration on call is the universal expected behaviour for any communication app.

**UI.** `Switch.adaptive`.

**Default.** `true`.

**Storage.** `mizdah_vibrate_on_call_v1`

**Behaviour notes.** When the `incoming-call` socket event fires (handled by `P2PCallService`), and this preference is `true`, trigger `HapticFeedback.heavyImpact()` in a 1.5s loop (matching ringtone cadence) until the user accepts/declines or the call cancels.

iOS-specific: the system Do Not Disturb override controls whether this fires regardless. Don't try to bypass it.

**Competitive context.** Universal mobile communication app behaviour. WhatsApp, Telegram, Signal, FaceTime — all have this. Most don't expose a toggle (it's hardcoded on); offering the toggle is a small delight.

---

## Mute notifications during meetings

**What.** When `true`, system-level OS notifications (other apps' banners, sounds) are silenced while the user is in a Mizdah meeting.

**Why.** A Slack ping, an email beep, a TikTok notification — all interrupt focus and **leak into the audio stream** if the user's mic catches the system sound. Silencing them during meetings = professional behaviour.

**UI.** `Switch.adaptive`.

**Default.** `true`.

**Storage.** `mizdah_mute_notifs_in_meeting_v1`

**Behaviour notes.** When the meeting room mounts AND this preference is `true`:
- **iOS**: request Focus mode (requires `INDeviceFocusStatusCenter` permission). User must grant once; subsequent calls are seamless.
- **Android**: request `ACCESS_NOTIFICATION_POLICY` permission and call `NotificationManager.setInterruptionFilter(INTERRUPTION_FILTER_PRIORITY)` to enable Do Not Disturb. Restore on meeting end.

The first time a user enables this, the system prompts for the permission. If denied, fall back gracefully (show a banner: "Mute notifications requires permission — open Settings?").

**Implementation note.** Permission flow is the most complex piece of this section, but the preference + UI ship today; permission request can be deferred to first-meeting-with-this-on.

**Competitive context.**
- **Zoom (macOS)**: "Do Not Disturb during meetings" — turns on macOS Focus.
- **Microsoft Teams (Windows)**: integrates with Windows Focus Assist.
- **Mobile equivalents**: rare. WhatsApp / Telegram don't ship this. Could be a real differentiator, especially for B2B users.

---

## Recommended for v1: all 4

This entire section is pure toggles. Cost is negligible per feature; visual completeness from shipping all four is high. The actual sound assets and DND permission flow can land incrementally.
