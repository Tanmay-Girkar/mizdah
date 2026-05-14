// ════════════════════════════════════════════════════════════════════
//  RingtoneService — caller ringback + receiver incoming ring
//  ────────────────────────────────────────────────────────────────────
//  Spec: docs/CALL_RINGTONE_FLUTTER.md §6.
//
//  Singleton owning at most ONE looping AudioPlayer at a time. Calling
//  `startRingback()` while the incoming ring is playing (or vice
//  versa) cleanly stops the previous one — overlapping tones would
//  be jarring and on Android can compete for the audio focus.
//
//  Graceful "missing asset" behaviour: if the mp3 files in
//  assets/sounds/ haven't been dropped in yet, `play()` throws and
//  we swallow + log. The rest of the app keeps working; the user
//  just hears no tone. The README in that directory tells the next
//  dev where to drop them.
//
//  After `stop()` we wait 50 ms before allowing the WebRTC stack
//  to take over the audio session — both iOS and Android can
//  otherwise drop the first ~half-second of call audio while the
//  session swap settles. Spec §7.3.
// ════════════════════════════════════════════════════════════════════

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

enum _RingtoneKind { ringback, incoming }

class RingtoneService {
  RingtoneService._();
  static final RingtoneService instance = RingtoneService._();

  AudioPlayer? _player;
  _RingtoneKind? _activeKind;

  /// True if SOME tone is currently looping. Used by the P2P
  /// notifier's defensive checks (e.g. don't restart ringback on
  /// every onCallAccepted hand-off if we never started one).
  bool get isPlaying => _player != null;

  /// Caller-side: start the ringback tone the moment the user taps
  /// a call button. Stops automatically on accept / decline /
  /// offline / cancel — the caller hooks below in
  /// P2PCallNotifier handle each terminal event.
  Future<void> startRingback() async {
    if (_activeKind == _RingtoneKind.ringback && _player != null) {
      debugPrint('[ringtone] startRingback no-op (already playing)');
      return;
    }
    await _play('sounds/ringback.mp3', _RingtoneKind.ringback);
  }

  /// Receiver-side: start the incoming-ring tone when the
  /// `incoming-call` socket event arrives. Stops on accept /
  /// decline / 30 s auto-decline / caller-cancelled.
  Future<void> startIncoming() async {
    if (_activeKind == _RingtoneKind.incoming && _player != null) {
      debugPrint('[ringtone] startIncoming no-op (already playing)');
      return;
    }
    await _play('sounds/incoming_ring.mp3', _RingtoneKind.incoming);
  }

  /// Stop whichever tone is currently playing. Always safe — no-op
  /// if nothing is playing. Sleeps 50 ms after disposing the
  /// player so the platform audio session has time to release
  /// before WebRTC grabs it (avoids a clipped first half-second
  /// of call audio on iOS and Android).
  Future<void> stop() async {
    final p = _player;
    if (p == null) return;
    _player = null;
    _activeKind = null;
    try {
      await p.stop();
    } catch (_) {}
    try {
      await p.dispose();
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 50));
    debugPrint('[ringtone] stopped');
  }

  Future<void> _play(String asset, _RingtoneKind kind) async {
    // Always stop the previous tone first — overlapping ringtones
    // are jarring and on Android compete for the audio focus.
    await stop();
    final p = AudioPlayer();
    try {
      await p.setReleaseMode(ReleaseMode.loop);
      await p.play(AssetSource(asset));
      _player = p;
      _activeKind = kind;
      debugPrint('[ringtone] playing $asset (loop)');
    } catch (e) {
      // Most common cause: the mp3 file is missing under
      // assets/sounds/. Service stays in "idle" — the call still
      // functions, just silently. README in the asset directory
      // explains the fix.
      debugPrint('[ringtone] play failed for $asset → $e '
          '(check assets/sounds/README.md)');
      try {
        await p.dispose();
      } catch (_) {}
    }
  }
}
