# 06 · Privacy & Security

2 features. Small section but high value for B2B / enterprise positioning.

| Feature | Control | Default | Complexity |
|---|---|---|---|
| Require waiting room | toggle | `false` | S (UI) — backend honors per-meeting flag |
| Block screenshots (Android only) | toggle | `false` | M (needs FLAG_SECURE wiring) |

---

## Require waiting room

**What.** When `true`, every meeting the user **hosts** starts with a waiting room enabled — guests are held in a queue until the host explicitly admits them.

**Why.** Three concrete benefits:
1. **Anti-zoom-bombing**: prevents trolls from joining via leaked links.
2. **Vetting**: lets the host confirm who's joining a sensitive meeting (HR, legal, board reviews, personal calls) before exposing the conversation.
3. **Late-arrival management**: hosts can choose to keep someone in the waiting room until a sensitive section ends.

This is a **per-user default**, not a per-meeting toggle. Power users who always want it set it once. The actual per-meeting waiting room behaviour is driven server-side and may already exist.

**UI.** `Switch.adaptive`.

**Default.** `false`. Increases friction for guests, so the default should be off; security-conscious users opt in.

**Storage.** `mizdah_require_waiting_room_v1`

**Behaviour notes.** When the user creates a meeting (instant or scheduled), the meeting payload includes `isWaitingRoomEnabled: <preference>`. Backend already supports this per-meeting; the UI just chooses the default. Existing `start a meeting` flows pass it through.

**No backend integration needed for the preference itself** — it just modifies what's sent to the existing `createMeeting` API.

**Competitive context.**
- **Zoom**: defaults waiting room ON post-2020 (zoom-bombing era). Has the same per-user default toggle.
- **Microsoft Teams**: "Lobby" with options for who bypasses (Everyone / Invited people only / People in my org / Only me).
- **Google Meet**: "Quick access" toggle (inverse — when off, waiting room is on).

---

## Block screenshots (Android only)

**What.** When `true`, sets `FLAG_SECURE` on the meeting Activity. This:
- Hides the meeting screen from screenshots (system shows a system warning toast and writes a black image).
- Blocks screen recording (recording captures black frames during the meeting).
- Hides the meeting from the recents/task switcher (shows a black thumbnail with the app name).

iOS does not expose the equivalent API publicly — the toggle should be greyed out or hidden on iPhone. Don't try to fake it; users who toggle it on iOS would expect protection that doesn't exist.

**Why.** Confidential meetings — legal counsel, healthcare consultations, executive briefings, HR processes, or sensitive personal calls — need protection against an attendee secretly recording. With FLAG_SECURE, the recording is impossible at the OS level; no app-side hack can bypass it.

**UI.** `Switch.adaptive`. On iOS: render the row dimmed / disabled with helper text "Available on Android only" so iOS users understand the option exists app-wide but doesn't apply to them.

**Default.** `false`.

**Storage.** `mizdah_block_screenshots_v1`

**Behaviour notes.**
- Meeting room reads this preference on mount. If `true` AND `Platform.isAndroid`:
  - Call a method-channel function that wraps `getWindow().setFlags(FLAG_SECURE, FLAG_SECURE)` on the Activity.
  - Restore on meeting end with `clearFlags(FLAG_SECURE)`.
- If `false`, no-op.
- iOS path: no-op regardless. The preference is preserved (so the user's choice carries over to Android devices on the same account).

**Implementation note.** This requires a tiny method channel — Flutter's standard library doesn't expose `FLAG_SECURE` directly. Two ways:
1. Use the `flutter_windowmanager` package (~3 KB; just exposes setFlag/clearFlag).
2. Hand-roll the channel: ~30 lines in `MainActivity.kt` + ~5 lines in Dart.

Either way, the preference + UI can ship before the channel; until then, the toggle is a no-op stored value.

**Competitive context.**
- **WhatsApp / Signal**: use FLAG_SECURE on chat lists for privacy. Strong precedent.
- **Banking apps**: virtually all use FLAG_SECURE.
- **Zoom / Meet / Teams**: do **not** ship this for meetings. Real differentiator for B2B / enterprise / legal / healthcare positioning.

---

## Recommended for v1: 1 of 2

- **Require waiting room** — easy win, widely understood feature, just routes through existing backend support.
- **Block screenshots** — defer to v1.1. The MethodChannel + iOS handling adds complexity without enough user demand for a consumer launch.

If you want to lead with privacy as a positioning angle (B2B / healthcare / legal), include both. The marketing copy ("Mizdah meetings can't be screen-recorded") is stronger than "we have a waiting room".

---

## Future extensions (post-v1)

- **Allow others to record my meetings** — toggle. Per-user permission flag; a meeting host who toggles this off can prevent any participant from recording.
- **End-to-end encryption preference** — Standard / E2EE only segmented. Forces meetings to use the E2EE pipeline (lower group sizes, no recording, no captions, but sealed contents).
- **Auto-record my meetings** — toggle. Server-side recording starts on join.
- **Hide my email from invites** — toggle. Calendar invites show the user's name only.
