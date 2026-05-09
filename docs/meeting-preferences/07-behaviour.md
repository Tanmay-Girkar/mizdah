# 07 · Behaviour & Controls

3 features that shape how the app responds to user actions inside and around meetings.

| Feature | Control | Default | Complexity |
|---|---|---|---|
| Confirm before leaving | toggle | `true` | S |
| Show pre-join screen | toggle | `true` | S |
| Default meeting type | segmented (2) | `Mizdah room` | S |

---

## Confirm before leaving

**What.** When `true`, tapping the red end-call button shows a confirm dialog ("Leave meeting?" + Cancel / Leave) before actually disconnecting.

**Why.** Accidental hang-ups during important meetings are mortifying. Adding one confirm dialog catches:
- **Phantom taps** from pockets when the screen wakes mid-meeting.
- **Kid grabs** when phone is propped up.
- **Fat-finger errors** when reaching for an adjacent control.
- **Browser/PWA back button** triggers (on web).

The cost is one extra tap when leaving deliberately — minor friction in exchange for safety against career-bad mistakes.

**UI.** `Switch.adaptive`.

**Default.** `true`. Conservative; users running back-to-back 1:1s can disable.

**Storage.** `mizdah_confirm_leave_v1`

**Behaviour notes.** End-call handler logic:
```
if (preference == true) {
  final confirmed = await showDialog(...);
  if (!confirmed) return;
}
await leaveMeeting();
```

Dialog uses Mizdah's existing themed `AlertDialog` style (light surface in light mode, dark surface in dark mode, gradient confirm button).

**Competitive context.**
- **Zoom**: doesn't ship this; users asked for years.
- **Teams**: same.
- **Meet**: same.
- **WhatsApp video**: tapping end gives no confirm (consumer app — assumes intent).

So this is actually a feature most apps **lack** — a small but real polish win.

---

## Show pre-join screen

**What.** When `true`, after tapping a meeting link/code or a "Start a meeting" button, the user lands on a pre-join screen showing their camera + mic preview before the actual meeting starts. When `false`, the user jumps straight into the meeting.

**Why.** Pre-join lets you:
- Fix your hair / framing.
- Set your background blur.
- Mute beforehand.
- Choose a different microphone or camera.
- Confirm you're joining the right meeting.

But many users hate it because they're already running late and want to skip the friction. The toggle covers both audiences.

**UI.** `Switch.adaptive`.

**Default.** `true` (current behaviour — pre-join always shown).

**Storage.** `mizdah_show_pre_join_v1`

**Behaviour notes.** When a meeting code is invoked (from the home screen, a notification, a deep link, or the call hub):
- If `true`: navigate to `/pre-join/:id`. Existing flow.
- If `false`: skip pre-join. Navigate directly to `/meeting/:id?video=...&audio=...` using the user's last-known mic/camera state (or Mute-on-join / Camera-off-on-join preferences if those are set).

When `false` and the user denied camera/mic permissions earlier, the meeting room handles the permission prompt inside the call (instead of on the pre-join screen).

**Competitive context.**
- **Google Meet**: pre-join always shown, no toggle. Considered a feature, not friction.
- **Zoom**: "Skip preview window" toggle in advanced settings.
- **Microsoft Teams**: same toggle, calls it "Skip the meeting preview".
- **WhatsApp video**: no pre-join, one-tap to join.

Mizdah following the toggle approach gives users both behaviours.

---

## Default meeting type

**What.** 2-state segmented: **Mizdah room** (SFU group meeting) / **Direct call** (P2P 1-on-1). When the user taps a generic "Start a meeting" or "Call" CTA, this preference decides which pipeline kicks in.

**Why.** Mizdah uniquely supports both modes:
- **SFU / Mizdah room**: server-mediated group meeting. Best for 3+ people, schedules, recordings, screen sharing to many viewers.
- **P2P / Direct call**: peer-to-peer 1-on-1. Lower latency (no server hop), zero server cost, ideal for personal calls to a specific person.

A power user who runs daily standups wants SFU as default. A user who calls one specific person every day wants P2P. Forcing them through a picker every time creates friction; the preference flips the default. The picker can still be invoked by long-press on the CTA for one-off overrides.

**UI.** `_SegmentedRow` with two options. Sublabel under each shows what the mode is best for (e.g. "Best for 3+ people" / "Best for 1-on-1").

**Default.** `Mizdah room` (SFU). Covers the broader majority of use cases.

**Storage.** `mizdah_default_meeting_type_v1`

**Behaviour notes.** The "Start a meeting" CTA in the home hero card AND the central Call tab become preference-aware:
- `Mizdah room` → call the existing `MeetingRepository.createMeeting()` flow → push `/pre-join/:code?host=true`.
- `Direct call` → navigate to the Call tab's search interface (since P2P calls require choosing a specific person to call). Or if the user is already on a recent contact, place a direct call.

The home hero card might show subtle iconography hinting at which mode is active (small video-camera-with-people for SFU, phone for P2P).

**Competitive context.**
- **Most apps don't expose this** — they only have one mode.
- **WhatsApp**: has separate buttons for "Call" (P2P) and "Group call" (multi-party).
- **FaceTime**: separate "FaceTime audio" / "FaceTime video" / "FaceTime link" entries.

Exposing this as a single user preference is a Mizdah-specific affordance — your dual-mode architecture makes it useful.

---

## Recommended for v1: all 3

All three are simple toggles/segmented controls, each with clear user value and minimal implementation cost. Behaviour & Controls is one of the cleanest sections to ship in full.

---

## Future extensions (post-v1)

- **Auto-lower hand after** — None / 30 s / 1 min / 2 min picker. Auto-resets the raised-hand state if you forget to lower it.
- **Default reaction emoji** — emoji picker. The quick-react button on the meeting controls fires this one with a single tap.
- **Show participant count in tab badge** — toggle.
- **Auto-end meeting when last person leaves** — toggle. Useful for hosts who want the meeting to clean up when they're the last one.
- **Default chat retention** — Persistent / During meeting only segmented.
