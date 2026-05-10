// ════════════════════════════════════════════════════════════════════
//  Video meeting preferences — local-only, no backend
// ════════════════════════════════════════════════════════════════════
//  Per docs/meeting-preferences/02-video.md, three of the five video
//  prefs are wired here:
//
//    • Outgoing video quality   — Auto / 720p / 1080p
//    • Touch up appearance      — int 0..100
//    • Background blur          — None / Light / Strong
//
//  (Camera-off-on-join and Mirror-my-preview intentionally omitted
//  per product call.)
//
//  Storage is SharedPreferences so each preference persists across
//  launches with zero backend involvement. The actual GPU/CPU work
//  (touch-up shader, segmentation model, simulcast layer cap) lives
//  downstream in the camera pipeline. These providers just record
//  the user's choice; the pipeline reads them at meeting bootstrap
//  and on change.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 3-state outgoing-video resolution cap. Stored as the enum's
/// `.name`. Drives the simulcast layer config when joining a
/// meeting.
enum OutgoingVideoQuality {
  /// Negotiate dynamically; SFU may upgrade to 1080p when the
  /// network allows. Recommended default.
  auto,

  /// Cap at 1280×720. Sensible on slow connections.
  hd720,

  /// Allow up to 1920×1080. Higher CPU + bandwidth.
  hd1080,
}

extension OutgoingVideoQualityMeta on OutgoingVideoQuality {
  String get label {
    switch (this) {
      case OutgoingVideoQuality.auto:
        return 'Auto';
      case OutgoingVideoQuality.hd720:
        return '720p';
      case OutgoingVideoQuality.hd1080:
        return '1080p';
    }
  }

  String get description {
    switch (this) {
      case OutgoingVideoQuality.auto:
        return 'Adapts to network conditions.';
      case OutgoingVideoQuality.hd720:
        return 'Cap at 1280×720 — gentler on bandwidth.';
      case OutgoingVideoQuality.hd1080:
        return 'Up to 1920×1080 — uses more data + CPU.';
    }
  }
}

/// 3-step background blur level. Stored as the enum's `.name`.
enum BackgroundBlurLevel {
  /// Raw camera feed — no segmentation.
  none,

  /// Mild gaussian on the segmented background; subject stays
  /// crisp.
  light,

  /// Heavy gaussian — background reads as a soft colour wash.
  strong,
}

extension BackgroundBlurLevelMeta on BackgroundBlurLevel {
  String get label {
    switch (this) {
      case BackgroundBlurLevel.none:
        return 'None';
      case BackgroundBlurLevel.light:
        return 'Light';
      case BackgroundBlurLevel.strong:
        return 'Strong';
    }
  }
}

// ── Outgoing video quality ──────────────────────────────────────

class OutgoingVideoQualityNotifier
    extends StateNotifier<OutgoingVideoQuality> {
  static const _prefsKey = 'mizdah_video_quality_v1';
  OutgoingVideoQualityNotifier() : super(OutgoingVideoQuality.auto) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefsKey);
      if (saved == null) return;
      final match = OutgoingVideoQuality.values.firstWhere(
        (e) => e.name == saved,
        orElse: () => OutgoingVideoQuality.auto,
      );
      if (mounted) state = match;
    } catch (_) {}
  }

  Future<void> set(OutgoingVideoQuality q) async {
    if (state == q) return;
    state = q;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, q.name);
    } catch (_) {}
  }
}

final outgoingVideoQualityProvider = StateNotifierProvider<
    OutgoingVideoQualityNotifier, OutgoingVideoQuality>(
  (ref) => OutgoingVideoQualityNotifier(),
);

// ── Touch up appearance ────────────────────────────────────────

/// 0..100 inclusive. 0 = off; higher values mean stronger skin
/// smoothing in the camera-feed shader.
class TouchUpIntensityNotifier extends StateNotifier<int> {
  static const _prefsKey = 'mizdah_touch_up_v1';
  TouchUpIntensityNotifier() : super(0) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getInt(_prefsKey);
      if (v != null && v >= 0 && v <= 100 && mounted) state = v;
    } catch (_) {}
  }

  Future<void> set(int value) async {
    final clamped = value.clamp(0, 100);
    if (state == clamped) return;
    state = clamped;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefsKey, clamped);
    } catch (_) {}
  }
}

final touchUpIntensityProvider =
    StateNotifierProvider<TouchUpIntensityNotifier, int>(
  (ref) => TouchUpIntensityNotifier(),
);

// ── Background blur ────────────────────────────────────────────

class BackgroundBlurNotifier extends StateNotifier<BackgroundBlurLevel> {
  static const _prefsKey = 'mizdah_background_v1';
  BackgroundBlurNotifier() : super(BackgroundBlurLevel.none) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefsKey);
      if (saved == null) return;
      final match = BackgroundBlurLevel.values.firstWhere(
        (e) => e.name == saved,
        orElse: () => BackgroundBlurLevel.none,
      );
      if (mounted) state = match;
    } catch (_) {}
  }

  Future<void> set(BackgroundBlurLevel level) async {
    if (state == level) return;
    state = level;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, level.name);
    } catch (_) {}
  }
}

final backgroundBlurProvider =
    StateNotifierProvider<BackgroundBlurNotifier, BackgroundBlurLevel>(
  (ref) => BackgroundBlurNotifier(),
);
