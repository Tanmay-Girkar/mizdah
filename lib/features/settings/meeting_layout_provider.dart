import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User-pickable layouts for the in-meeting video grid.
/// Names match Google Meet's "Adjust view" sheet so the picker
/// reads the same way: Auto / Tiled / Spotlight / Sidebar.
enum MeetingLayout {
  auto,             // Adaptive: picks tiled / spotlight by participant count
  equalGrid,        // 'Tiled (legacy)' — equal-size grid
  spotlight,        // Big active speaker, others as a strip
  speakerSidebar,   // Main speaker + vertical thumbnails on the right
  premiumCards,     // Kept for back-compat; not surfaced in the sheet
}

extension MeetingLayoutMeta on MeetingLayout {
  String get label {
    switch (this) {
      case MeetingLayout.auto:           return 'Auto (dynamic)';
      case MeetingLayout.equalGrid:      return 'Tiled (legacy)';
      case MeetingLayout.spotlight:      return 'Spotlight';
      case MeetingLayout.speakerSidebar: return 'Sidebar';
      case MeetingLayout.premiumCards:   return 'Premium Cards';
    }
  }

  String get description {
    switch (this) {
      case MeetingLayout.auto:
        return 'Picks the best layout based on the meeting';
      case MeetingLayout.equalGrid:
        return 'Everyone the same size in a grid';
      case MeetingLayout.spotlight:
        return 'Big active speaker, others as a strip';
      case MeetingLayout.speakerSidebar:
        return 'Main speaker, others stacked on the right';
      case MeetingLayout.premiumCards:
        return 'Glass cards with shadows and a speaker highlight';
    }
  }

  IconData get icon {
    switch (this) {
      case MeetingLayout.auto:           return Icons.auto_awesome_rounded;
      case MeetingLayout.equalGrid:      return Icons.grid_view_rounded;
      case MeetingLayout.spotlight:      return Icons.crop_landscape_rounded;
      case MeetingLayout.speakerSidebar: return Icons.view_sidebar_rounded;
      case MeetingLayout.premiumCards:   return Icons.dashboard_rounded;
    }
  }
}

/// Persists the user's preferred meeting layout across sessions.
/// Default is Equal Grid (matches what we shipped before this feature).
class MeetingLayoutNotifier extends StateNotifier<MeetingLayout> {
  static const _prefsKey = 'mizdah_meeting_layout_v1';
  MeetingLayoutNotifier() : super(MeetingLayout.equalGrid) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefsKey);
      if (saved == null) return;
      final match = MeetingLayout.values.firstWhere(
        (e) => e.name == saved,
        orElse: () => MeetingLayout.equalGrid,
      );
      if (mounted) state = match;
    } catch (_) {
      // ignore — keep default
    }
  }

  Future<void> set(MeetingLayout layout) async {
    if (state == layout) return;
    state = layout;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, layout.name);
    } catch (_) {
      // best-effort persistence
    }
  }
}

final meetingLayoutProvider =
    StateNotifierProvider<MeetingLayoutNotifier, MeetingLayout>(
  (ref) => MeetingLayoutNotifier(),
);

/// Maximum number of remote tiles to display in the grid. Beyond
/// this the grid scrolls / overflow into a "+N" chip. Persisted.
class MaxTilesNotifier extends StateNotifier<int> {
  static const _prefsKey = 'mizdah_meeting_max_tiles_v1';
  static const _defaultMax = 12;
  MaxTilesNotifier() : super(_defaultMax) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getInt(_prefsKey);
      if (v != null && v >= 4 && v <= 49 && mounted) state = v;
    } catch (_) {}
  }

  Future<void> set(int value) async {
    final clamped = value.clamp(4, 49);
    if (state == clamped) return;
    state = clamped;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefsKey, clamped);
    } catch (_) {}
  }
}

final maxTilesProvider =
    StateNotifierProvider<MaxTilesNotifier, int>((ref) => MaxTilesNotifier());

/// Whether to hide participant tiles whose camera is off (renders
/// them as a single collapsed "+N" chip instead of avatar tiles).
/// Persisted.
class HideTilesWithoutVideoNotifier extends StateNotifier<bool> {
  static const _prefsKey = 'mizdah_meeting_hide_no_video_v1';
  HideTilesWithoutVideoNotifier() : super(false) {
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

final hideTilesWithoutVideoProvider =
    StateNotifierProvider<HideTilesWithoutVideoNotifier, bool>(
  (ref) => HideTilesWithoutVideoNotifier(),
);
