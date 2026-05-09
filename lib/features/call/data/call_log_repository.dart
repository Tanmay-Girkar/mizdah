// ════════════════════════════════════════════════════════════════════
//  CallLogRepository — single source of truth for the P2P call log
// ════════════════════════════════════════════════════════════════════
//  Today: a `LocalCallLogRepository` that persists entries in
//  SharedPreferences as a JSON array. Survives app restarts, lost on
//  uninstall, single-device only.
//
//  Future: swap to `RealCallLogRepository(ApiClient(), socketClient)`
//  per docs/CALL_HISTORY_API.md — REST hydrate + socket "call:logged"
//  push for live multi-device sync. UI doesn't care which is wired.

import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'call_log_models.dart';

abstract class CallLogRepository {
  /// Stream of the full log, newest first. Emits a fresh snapshot on
  /// every append.
  Stream<List<CallLogEntry>> watch();

  /// Append a single entry. Idempotent on `entry.id`.
  Future<void> append(CallLogEntry entry);

  /// Wipe the log — used by "Clear call history" in settings.
  Future<void> clear();
}

class LocalCallLogRepository implements CallLogRepository {
  static const _prefsKey = 'mizdah_p2p_call_log_v1';
  /// Cap to keep the JSON blob bounded. Older entries fall off.
  static const _maxEntries = 500;

  final _ctrl = StreamController<List<CallLogEntry>>.broadcast();
  List<CallLogEntry>? _cache;
  bool _booted = false;

  Future<void> _boot() async {
    if (_booted) return;
    _booted = true;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) {
      _cache = [];
      return;
    }
    try {
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      _cache = list
          .map(CallLogEntry.fromJson)
          .toList()
        ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    } catch (_) {
      // Corrupted blob — drop it rather than crash the app.
      _cache = [];
      await prefs.remove(_prefsKey);
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final list = _cache ?? const <CallLogEntry>[];
    final out = list.map((e) => e.toJson()).toList();
    await prefs.setString(_prefsKey, jsonEncode(out));
  }

  void _emit() {
    _ctrl.add(List.unmodifiable(_cache ?? const []));
  }

  @override
  Stream<List<CallLogEntry>> watch() async* {
    await _boot();
    yield List.unmodifiable(_cache ?? const []);
    yield* _ctrl.stream;
  }

  @override
  Future<void> append(CallLogEntry entry) async {
    await _boot();
    final list = _cache ??= <CallLogEntry>[];
    // Idempotency — skip if we already recorded this id.
    if (list.any((e) => e.id == entry.id)) return;
    list.insert(0, entry);
    if (list.length > _maxEntries) {
      list.removeRange(_maxEntries, list.length);
    }
    await _persist();
    _emit();
  }

  @override
  Future<void> clear() async {
    _cache = [];
    await _persist();
    _emit();
  }
}
