# Call ringtone assets

Two files belong in this directory, both bundled into the app via
[pubspec.yaml](../../pubspec.yaml)'s `assets/sounds/` registration:

| File | Length | Purpose | Plays for |
|---|---|---|---|
| `ringback.mp3` | ~6 s loop | US PSTN-style ringback (440 + 480 Hz, 2 s tone / 4 s silence) | The **caller**, while the callee's device is ringing |
| `incoming_ring.mp3` | ~3 s loop | Double "ring-ring" burst at higher pitch (CC0-licensed phone ringtone) | The **receiver**, while a call is ringing in on their device |

Both files are **referenced** by [lib/core/services/ringtone_service.dart](../../lib/core/services/ringtone_service.dart). The service wraps `AudioPlayer.play(AssetSource(...))` in a try/catch, so the build and runtime stay healthy even before the real audio files are dropped in — playback just silently no-ops with a warning in the log.

## Where to source them

- [`freesound.org`](https://freesound.org) — search "ringback" / "phone ringing", filter to CC0.
- [`pixabay.com/sound-effects`](https://pixabay.com/sound-effects) — labelled CC0.
- Self-synthesised: `ffmpeg -f lavfi -i "sine=frequency=440:duration=2" -af "afade=t=out:st=2:d=0.05" ringback.mp3` works fine for the caller-side tone.

## Constraints (per the Flutter spec doc)

- Keep both files **under 100 KB** each. Larger files get unwieldy in the APK / IPA and the loop overhead pays no dividends.
- **MP3 codec** so it plays everywhere `audioplayers` is supported.
- **Looping** is enabled in code via `ReleaseMode.loop` — the file itself doesn't need to be seamless, but a clean tail helps.
- Do **not** redistribute iOS or Android system ringtones — those are private API and shipping them is grounds for store rejection.

Once you drop both files in, the next call will play them.
