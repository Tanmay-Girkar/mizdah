# Meeting Preferences — feature catalogue

Reference docs for the preferences screen at **Settings → Account → Meeting preferences**. Each file describes one group; each group lists 2–6 features with everything needed to wire it up.

## Why this exists

The backend doesn't expose endpoints for these settings yet, so all of them are local-only via `SharedPreferences`. Each feature ships in two parts:

1. A `StateNotifier` provider in `lib/features/settings/meeting_preferences_provider.dart` (or `meeting_layout_provider.dart` for the existing layout settings).
2. A row widget on `lib/features/settings/presentation/meeting_preferences_screen.dart`.

When the backend grows endpoints later, `set(...)` on the notifier just gains an HTTP call — every callsite stays the same.

## Status

Already shipped:
- Default video layout (Auto / Tiled / Spotlight / Sidebar)
- Maximum tiles
- Hide cameras-off tiles

Suggested for v1 — pick what you want, in any order:

| File | Group | Features | Recommended for v1 |
|---|---|---|---|
| [00-architecture.md](00-architecture.md) | Shared infrastructure | Generic prefs helpers + row widgets | Build first |
| [01-audio.md](01-audio.md) | Audio | 3 features | All 3 |
| [02-video.md](02-video.md) | Video & Camera | 5 features | 4 of 5 |
| [03-layout.md](03-layout.md) | Layout & Display | 3 new features | 2 of 3 |
| [04-notifications.md](04-notifications.md) | Notifications & Sounds | 4 features | All 4 |
| [05-captions.md](05-captions.md) | Captions & Accessibility | 3 features | All 3 |
| [06-privacy.md](06-privacy.md) | Privacy & Security | 2 features | 1 of 2 |
| [07-behaviour.md](07-behaviour.md) | Behaviour & Controls | 3 features | All 3 |
| [08-bandwidth.md](08-bandwidth.md) | Bandwidth & Performance | 3 features | 1 of 3 |

**Recommended must-have v1 (10 features)** — fast to ship, covers table-stakes:

- Audio: Mute on join · Noise suppression
- Video: Camera off on join · Mirror preview · HD outgoing video · Background blur
- Layout: Active speaker indicator · Reduce motion
- Notifications: Sound on join/leave · Mute notifications during meetings
- Captions: Live captions on join · Caption language

## How to read each file

Every feature has the same template:

- **What** — one-line summary of the behaviour.
- **Why** — the user value.
- **UI control** — toggle / segmented / slider / picker.
- **Default** — recommended starting value.
- **Storage** — `SharedPreferences` key name.
- **Behaviour notes** — what changes when the user toggles it.
- **Competitive context** — how Zoom / Meet / Teams ship it.
- **Complexity** — S (one toggle), M (multi-state), L (needs ML model / external service).

## Build order suggestion

1. **00-architecture** — generic helpers so every later feature is one provider + one row widget.
2. **04-notifications** — pure toggles, easiest to wire and test.
3. **01-audio** — mostly toggles, one segmented.
4. **07-behaviour** — pure toggles + one segmented.
5. **03-layout** — extends the existing layout section.
6. **05-captions** — toggle + segmented + picker (introduces the bottom-sheet picker pattern).
7. **02-video** — adds the slider pattern for touch-up appearance.
8. **06-privacy** — pure toggles.
9. **08-bandwidth** — pure toggles.

That order keeps each step's complexity climbing gradually so you can verify the screen still builds + persists correctly between additions.
