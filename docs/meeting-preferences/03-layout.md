# 03 · Layout & Display

3 NEW features that extend the existing Layout section (which already has Default video layout, Maximum tiles, Hide cameras-off tiles).

| Feature | Control | Default | Complexity |
|---|---|---|---|
| Show my own preview | segmented (3) | `Always` | M |
| Active speaker indicator | toggle | `true` | S |
| Reduce motion | toggle | `false` | S (UI) — read by every animated widget |

---

## Show my own preview

**What.** 3-state segmented control: **Always / On hover / Hidden**. Controls the picture-in-picture self-view tile during a meeting.

**Why.** Self-view is a love-it-or-hate-it feature.
- Some users find it distracting (they look at themselves the whole call instead of others).
- Some users want it always visible to confirm they're framed correctly and lit well.
- The middle ground — "show on tap, fade away" — works for users who only check periodically.

**UI.** `_SegmentedRow`.

**Default.** `Always`.

**Storage.** `mizdah_self_preview_v1`

**Behaviour notes.**
- **Always**: Self-view PiP always pinned to a corner of the screen.
- **On hover**: Self-view auto-hides after ~3 seconds of no interaction; reappears on tap. On mobile, "hover" maps to "tap to peek".
- **Hidden**: Self-view never shown. Saves a renderer + frees up screen real estate. Some users with weak devices choose this for the FPS gain.

**Implementation note.** The meeting room reads this preference and conditionally renders the self-tile. The 3-second auto-hide on the "hover" mode is a tiny `Timer` that resets on every screen touch.

**Competitive context.**
- **Zoom**: "Hide self view" toggle (just on/off).
- **Google Meet**: same — toggle.
- **Microsoft Teams**: same — toggle.

A 3-state version is a small but real improvement over the binary toggle.

---

## Active speaker indicator

**What.** When `true`, the tile of whoever is currently talking gets a colored border (the brand gradient in our case) with a subtle glow.

**Why.** In meetings of 5+ participants, you can't always tell who's talking — especially when voices sound similar or audio is compressed. The indicator answers "who is this?" instantly. Users with hearing differences rely on it heavily.

**UI.** `Switch.adaptive`.

**Default.** `true`.

**Storage.** `mizdah_active_speaker_v1`

**Behaviour notes.** The meeting pipeline already runs voice activity detection (VAD) — it's the same signal that decides who's spotlit in spotlight layout. When this preference is `true`, the matching tile gets a 2 px gradient border + soft purple glow. Updates ~5×/second. When `false`, no border is drawn.

Cheap to compute (one paint per frame), so disabling is mostly a stylistic choice.

**Competitive context.** Universal — every major platform shows an active speaker indicator. Adding a toggle is a power-user nicety; most apps don't expose it.

---

## Reduce motion

**What.** When `true`, all entrance animations, fade-ups, pulsing indicators, and segment slider transitions are disabled or replaced with hard cuts.

**Why.** Three audiences:
1. **Accessibility**: users with vestibular disorders get nauseous from page-level animations.
2. **Performance**: low-end devices drop frames during the entrance fade-up. Disabling = smoother experience.
3. **Preference**: some users just hate animation.

Both iOS and Android expose a system-level "Reduce motion" setting. Honouring it within the app shows respect for OS-level accessibility — and offering an explicit in-app override is even better.

**UI.** `Switch.adaptive`.

**Default.** `false`. Optionally: read `MediaQuery.disableAnimations` from the OS at first launch and seed the preference with that value.

**Storage.** `mizdah_reduce_motion_v1`

**Behaviour notes.** Every animated widget reads this preference and conditionally short-circuits:
- `MizdahFadeUp` becomes instant (skips the controller animation).
- The pulsing nav indicator (the active-tab "breathe" loop) stops.
- `AnimatedSwitcher` transitions become hard cuts (`Duration.zero`).
- The segmented control's sliding pill jumps to the new position instead of animating.
- Profile-card pulse halo (in p2p outgoing screen) stops.

To wire it, expose a top-level helper:
```
bool mizdahShouldReduceMotion(WidgetRef ref) =>
    ref.watch(reduceMotionProvider);
```
Then animation widgets gate their durations on it.

**Competitive context.**
- **iOS apps that respect this**: Telegram, Apple's first-party apps.
- **Apps that ignore it**: most. So shipping it is a real differentiator.

---

## Recommended for v1: 2 of 3

- **Active speaker indicator** — table-stakes, ship it.
- **Reduce motion** — accessibility win, easy to implement.
- **Show my own preview** — nice but not urgent. The 3-state UX is more complex than it sounds (auto-hide timer + tap-to-reveal logic). Consider deferring to v1.1.

If you only want one: ship Reduce Motion. It's a clear accessibility differentiator with low complexity.
