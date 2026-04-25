import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User-pickable layouts for the in-meeting video grid.
enum MeetingLayout {
  spotlight,        // Big speaker on top + horizontal strip below
  equalGrid,        // Adaptive equal-size grid
  speakerSidebar,   // Main speaker fills, vertical thumbnails on the right
  premiumCards,     // Gradient cards with shadows + speaker glow
}

extension MeetingLayoutMeta on MeetingLayout {
  String get label {
    switch (this) {
      case MeetingLayout.spotlight:      return 'Spotlight + Strip';
      case MeetingLayout.equalGrid:      return 'Equal Grid';
      case MeetingLayout.speakerSidebar: return 'Speaker + Sidebar';
      case MeetingLayout.premiumCards:   return 'Premium Cards';
    }
  }

  String get description {
    switch (this) {
      case MeetingLayout.spotlight:
        return 'Big active speaker, others as a thumbnail strip below';
      case MeetingLayout.equalGrid:
        return 'Everyone the same size in an adaptive grid';
      case MeetingLayout.speakerSidebar:
        return 'Main speaker fills, others stacked on the right';
      case MeetingLayout.premiumCards:
        return 'Glass cards with shadows and a speaker highlight';
    }
  }

  IconData get icon {
    switch (this) {
      case MeetingLayout.spotlight:      return Icons.view_agenda_rounded;
      case MeetingLayout.equalGrid:      return Icons.grid_view_rounded;
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
