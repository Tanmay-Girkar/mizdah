import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Bridge to the Android `OngoingCallFgService` foreground service.
///
/// While the service is running, the OS treats the app as "doing a
/// phone call" — mic + camera stay alive even after the screen locks
/// and the app drops to the background. This is what stops the
/// "audio dies 2-3 seconds after power button" bug on Android 14+.
///
/// No-op on iOS (background audio is handled by `UIBackgroundModes`
/// in Info.plist; CallKit would be the equivalent native primitive
/// but is out of scope here — see Info.plist for the TODO).
class OngoingCallForegroundService {
  OngoingCallForegroundService._();
  static final OngoingCallForegroundService instance =
      OngoingCallForegroundService._();

  static const _channel = MethodChannel('com.mizdah/call_fg');

  /// Whether the service is believed to be running right now. Driven
  /// by `start` / `stop` round-trips, used so double-start / double-
  /// stop calls are idempotent.
  bool _running = false;
  bool get isRunning => _running;

  /// Start the foreground service. `peerName` and `withVideo` go into
  /// the persistent notification the OS forces a foreground service
  /// to display ("Video call in progress · Test User 1"). Safe to
  /// call multiple times — re-starts are coalesced by the OS.
  Future<bool> start({
    required String peerName,
    required bool withVideo,
  }) async {
    if (!Platform.isAndroid) return false;
    if (_running) {
      debugPrint('[call-fg] start skipped — already running');
      return true;
    }
    try {
      final ok = await _channel.invokeMethod<bool>('start', <String, dynamic>{
        'peerName': peerName,
        'withVideo': withVideo,
      });
      _running = ok ?? false;
      debugPrint('[call-fg] start → ${_running ? "OK" : "FAILED"}');
      return _running;
    } catch (e) {
      debugPrint('[call-fg] start exception: $e');
      _running = false;
      return false;
    }
  }

  /// Stop the foreground service. Drops the persistent notification.
  /// Always safe to call — no-op when not running.
  Future<void> stop() async {
    if (!Platform.isAndroid) return;
    if (!_running) {
      debugPrint('[call-fg] stop skipped — not running');
      return;
    }
    try {
      await _channel.invokeMethod<bool>('stop');
      _running = false;
      debugPrint('[call-fg] stop → OK');
    } catch (e) {
      debugPrint('[call-fg] stop exception: $e');
      _running = false;
    }
  }
}
