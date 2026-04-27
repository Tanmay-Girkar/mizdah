import 'dart:io' show Platform;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Bridges the native Picture-in-Picture mode (Android) to a
/// Riverpod-watchable bool. The meeting room widget uses this to
/// switch to a compact layout when the OS puts us in a PiP window
/// and back to the full layout when expanded.
class PipController {
  PipController._();
  static final PipController instance = PipController._();

  static const _channel = MethodChannel('com.mizdah/pip');

  final ValueNotifier<bool> isInPip = ValueNotifier(false);
  bool _wired = false;

  void wire() {
    if (_wired || !Platform.isAndroid) return;
    _wired = true;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'modeChanged':
          isInPip.value = call.arguments as bool;
          break;
      }
    });
  }

  Future<bool> enter() async {
    if (!Platform.isAndroid) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('enter');
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> supported() async {
    if (!Platform.isAndroid) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('supported');
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }
}

/// Riverpod stream of the current PiP state. Widgets watch this and
/// rebuild when PiP toggles.
final pipModeProvider = StateNotifierProvider<_PipModeNotifier, bool>(
  (ref) => _PipModeNotifier(),
);

class _PipModeNotifier extends StateNotifier<bool> {
  _PipModeNotifier() : super(false) {
    PipController.instance.wire();
    PipController.instance.isInPip.addListener(_onChange);
  }

  void _onChange() {
    if (mounted) state = PipController.instance.isInPip.value;
  }

  @override
  void dispose() {
    PipController.instance.isInPip.removeListener(_onChange);
    super.dispose();
  }
}
