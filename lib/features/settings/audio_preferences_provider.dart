// ════════════════════════════════════════════════════════════════════
//  Audio meeting preferences — local-only (no backend)
// ════════════════════════════════════════════════════════════════════
//  Per docs/meeting-preferences/01-audio.md, two of the three audio
//  prefs are wired here:
//
//    • Mute on join         — bool, default false
//    • Noise suppression    — Off / Standard / High, default Standard
//
//  (Music mode intentionally omitted per product call.)
//
//  Storage is SharedPreferences so the choice persists across launches
//  with zero backend involvement. The actual DSP for noise suppression
//  is downstream of this preference — once an audio pipeline (RNNoise /
//  Krisp / native API) is wired into the meeting room, it reads this
//  value to pick the model intensity. The preference can ship today
//  even though the pipeline lands later.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 3-step noise-suppression intensity. Stored as the enum's `.name`.
enum NoiseSuppressionLevel {
  /// Raw mic — only WebRTC's default echo cancellation applies.
  off,

  /// Mild filter; fans / gentle typing fade. Voice stays natural.
  standard,

  /// Aggressive — even chewing / construction / vacuums silenced;
  /// voice can sound "speech-coded" on poor hardware.
  high,
}

extension NoiseSuppressionLevelMeta on NoiseSuppressionLevel {
  /// User-visible label used inside the segmented row.
  String get label {
    switch (this) {
      case NoiseSuppressionLevel.off:
        return 'Off';
      case NoiseSuppressionLevel.standard:
        return 'Standard';
      case NoiseSuppressionLevel.high:
        return 'High';
    }
  }
}

/// Persists "mute mic on meeting join". Read by the meeting-room
/// provider; if true, the mic is disabled before the signaling
/// socket connects so the user joins silent and unmutes manually.
class MuteOnJoinNotifier extends StateNotifier<bool> {
  static const _prefsKey = 'mizdah_mute_on_join_v1';
  MuteOnJoinNotifier() : super(false) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getBool(_prefsKey);
      if (v != null && mounted) state = v;
    } catch (_) {}
  }

  Future<void> set(bool value) async {
    if (state == value) return;
    state = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsKey, value);
    } catch (_) {}
  }
}

final muteOnJoinProvider =
    StateNotifierProvider<MuteOnJoinNotifier, bool>(
  (ref) => MuteOnJoinNotifier(),
);

/// Persists the noise-suppression intensity. The audio pipeline
/// reads this when initialising the outgoing mic track.
class NoiseSuppressionNotifier
    extends StateNotifier<NoiseSuppressionLevel> {
  static const _prefsKey = 'mizdah_noise_suppression_v1';
  NoiseSuppressionNotifier() : super(NoiseSuppressionLevel.standard) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefsKey);
      if (saved == null) return;
      final match = NoiseSuppressionLevel.values.firstWhere(
        (e) => e.name == saved,
        orElse: () => NoiseSuppressionLevel.standard,
      );
      if (mounted) state = match;
    } catch (_) {}
  }

  Future<void> set(NoiseSuppressionLevel level) async {
    if (state == level) return;
    state = level;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, level.name);
    } catch (_) {}
  }
}

final noiseSuppressionProvider = StateNotifierProvider<
    NoiseSuppressionNotifier, NoiseSuppressionLevel>(
  (ref) => NoiseSuppressionNotifier(),
);
