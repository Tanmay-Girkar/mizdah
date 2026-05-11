// ════════════════════════════════════════════════════════════════════
//  Privacy & security meeting preferences — local-only, no backend
// ════════════════════════════════════════════════════════════════════
//  Mirrors the existing audio / video preference providers. Stores
//  per-user safety / privacy choices in SharedPreferences. The
//  meeting room reads them on mount.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// "Confirm before leaving a meeting" — when ON, tapping the end-
/// call button (or hardware back) pops a confirmation dialog
/// before the call actually ends. Prevents accidental disconnects,
/// which are the single most common UX complaint in conferencing
/// apps (the user fat-fingers the red button mid-fidget).
class ConfirmBeforeLeavingNotifier extends StateNotifier<bool> {
  static const _prefsKey = 'mizdah_confirm_before_leaving_v1';

  /// Default ON — safety prefs default to on, the user can opt out
  /// if they find the prompt annoying. Aligns with how Zoom,
  /// Microsoft Teams, and Google Meet ship this feature.
  ConfirmBeforeLeavingNotifier() : super(true) {
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

final confirmBeforeLeavingProvider =
    StateNotifierProvider<ConfirmBeforeLeavingNotifier, bool>(
  (ref) => ConfirmBeforeLeavingNotifier(),
);
