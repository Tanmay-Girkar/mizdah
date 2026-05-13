// ════════════════════════════════════════════════════════════════════
//  ScheduledMeetingsNotifier — local store + Riverpod stream for
//  meetings scheduled via the in-app "Schedule Meeting" sheet
// ════════════════════════════════════════════════════════════════════
//  Why local-first: Google Calendar's URL-launch is a one-way hand-
//  off — there's no callback when the user saves the event inside
//  Calendar. So if we want the meeting to appear in "Upcoming
//  Meetings" immediately and survive an app relaunch, we have to
//  persist it on the device ourselves at the moment the user taps
//  "Add to Google Calendar" inside our sheet.
//
//  Backend persistence is a separate path (`createMeeting` so the
//  join code is valid + the in-app schedule API for participants
//  who haven't installed the app). Backend write failures don't
//  affect this local store — the meeting still shows on home and
//  the reminder still fires.
//
//  Storage: SharedPreferences JSON-encoded list. Already pulled in
//  by the project (no new dep). For dozens of meetings this is
//  fine; if the user accumulates hundreds, swap for Hive without
//  touching call-sites.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/scheduled_meeting.dart';

class ScheduledMeetingsNotifier extends StateNotifier<List<ScheduledMeeting>> {
  ScheduledMeetingsNotifier() : super(const []) {
    // Fire-and-forget — initial state is empty until disk read
    // completes (a few ms). UI binding to this provider will
    // rebuild when state flips.
    // ignore: discarded_futures
    _load();
  }

  /// Bumped if the JSON shape changes; old keys are ignored so a
  /// rename never throws at startup.
  static const _storageKey = 'mizdah_scheduled_meetings_v1';

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw == null || raw.isEmpty) return;
      final list = (jsonDecode(raw) as List).cast<dynamic>();
      state = [
        for (final j in list)
          if (j is Map) ScheduledMeeting.fromJson(Map<String, dynamic>.from(j)),
      ];
    } catch (e) {
      debugPrint('[schedule] failed to load local meetings: $e');
      // Corrupt JSON — start clean. Don't crash the home screen.
      state = const [];
    }
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode([for (final m in state) m.toJson()]);
      await prefs.setString(_storageKey, encoded);
    } catch (e) {
      debugPrint('[schedule] failed to save local meetings: $e');
    }
  }

  /// Adds a meeting and immediately broadcasts the new list to
  /// listeners. The UI animates the insertion via the existing
  /// `MizdahFadeUp` wrapper around each row (no extra animation
  /// code needed — the StreamProvider rebuild does the work).
  Future<void> add(ScheduledMeeting m) async {
    state = [...state, m]..sort((a, b) => a.startTime.compareTo(b.startTime));
    await _save();
  }

  Future<void> remove(String id) async {
    state = state.where((m) => m.id != id).toList(growable: false);
    await _save();
  }

  Future<void> replace(ScheduledMeeting m) async {
    state = [
      for (final existing in state)
        if (existing.id == m.id) m else existing,
    ]..sort((a, b) => a.startTime.compareTo(b.startTime));
    await _save();
  }

  /// Strip meetings whose `endTime` is past — called at app start
  /// and periodically by the home screen. Hidden meetings are
  /// permanently deleted so the SharedPreferences blob doesn't
  /// grow forever.
  Future<void> sweepPast() async {
    final cutoff = DateTime.now().toUtc().subtract(const Duration(hours: 1));
    final next = state.where((m) => m.endTime.isAfter(cutoff)).toList();
    if (next.length != state.length) {
      state = next;
      await _save();
    }
  }
}

/// Public provider — every UI screen reads from this, never from
/// `ScheduledMeetingsNotifier` directly.
final scheduledMeetingsProvider =
    StateNotifierProvider<ScheduledMeetingsNotifier, List<ScheduledMeeting>>(
        (ref) => ScheduledMeetingsNotifier());
