// ════════════════════════════════════════════════════════════════════
//  RendererManager — single owner of every RTCVideoRenderer
//  ────────────────────────────────────────────────────────────────────
//  Why a singleton:
//
//   • Before this, every provider that needed a renderer just did
//     `RTCVideoRenderer()` inline. That worked for a single happy
//     path, but every code branch (call declined, callee offline,
//     network drop, user logout, hot reload, route pop) needed its
//     own bespoke dispose call — and a few branches forgot, which
//     is the proximate cause of the `BLASTBufferQueue: Can't acquire
//     next buffer` log spam and the "EglRenderer: Frames received:
//     0, Rendered: 0" lines after a call ends.
//
//   • Centralising creation + disposal behind a keyed acquire/release
//     API turns "did every branch dispose?" into "did anyone forget
//     to call release()?" — which `dump()` makes trivial to audit
//     in dev.
//
//  Keys we use in this codebase (kept in one place so a future
//  refactor can grep them):
//
//    p2p-local           — P2P caller's / callee's local self-view.
//    p2p-remote          — P2P remote peer's video.
//    meeting-local       — Meeting room local self-view. Owned by
//                          LocalMediaService.instance.renderer at the
//                          moment; this manager isn't on that path
//                          yet but the same keys keep things tidy.
//    meeting-remote-<id> — Per-participant remote renderer in the
//                          meeting grid.
//
//  Safety guarantees:
//
//   • `acquire(key)` is idempotent — calling it twice for the same
//     key returns the same renderer instance. RTCVideoView's
//     `ValueKey(renderer)` therefore stays stable across rebuilds,
//     which stops Flutter from churning the underlying Android
//     SurfaceView / iOS UIView on every parent rebuild.
//
//   • `release(key)` always sets `srcObject = null` before
//     `dispose()`. flutter_webrtc's dispose can JNI-crash on
//     Android if a frame callback fires after dispose with the
//     stream still attached — clearing srcObject first is the
//     defensive ordering.
//
//   • Every async operation is wrapped in try/catch. Renderer
//     disposal failures must never block call teardown.
// ════════════════════════════════════════════════════════════════════

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class RendererManager {
  RendererManager._();
  static final RendererManager instance = RendererManager._();

  final Map<String, RTCVideoRenderer> _renderers = {};
  /// In-flight `acquire()` calls keyed by the same key — prevents a
  /// double-acquire (two simultaneous callers, e.g. preview warmup
  /// fires just as the call screen mounts) from creating two
  /// renderers for the same key.
  final Map<String, Future<RTCVideoRenderer>> _pending = {};

  /// Number of renderers currently alive. Exposed for the leak
  /// dashboard / debug overlay.
  int get count => _renderers.length;

  /// Snapshot of keys currently held — used by leak detectors.
  List<String> get keys => _renderers.keys.toList();

  /// Idempotent acquire. Returns the existing renderer if one exists
  /// for `key`, otherwise creates one, initialises it, and caches it.
  ///
  /// Race-safe: concurrent calls for the same key await the same
  /// in-flight Future instead of each constructing a new renderer.
  Future<RTCVideoRenderer> acquire(String key) async {
    final existing = _renderers[key];
    if (existing != null) {
      if (kDebugMode) {
        debugPrint('[renderer-mgr] acquire $key — reusing existing '
            '(total=${_renderers.length})');
      }
      return existing;
    }
    final inflight = _pending[key];
    if (inflight != null) return inflight;

    final future = _createAndInit(key);
    _pending[key] = future;
    try {
      final r = await future;
      _renderers[key] = r;
      if (kDebugMode) {
        debugPrint('[renderer-mgr] acquire $key — created '
            '(total=${_renderers.length})');
      }
      return r;
    } finally {
      _pending.remove(key);
    }
  }

  Future<RTCVideoRenderer> _createAndInit(String key) async {
    final r = RTCVideoRenderer();
    try {
      await r.initialize();
    } catch (e, st) {
      debugPrint('[renderer-mgr] initialize() failed for $key: $e\n$st');
      // Best-effort dispose so the half-initialised native handle
      // doesn't leak. Caller still gets the renderer instance —
      // attempting to use it will fail loudly which surfaces the
      // bug fast.
      try {
        await r.dispose();
      } catch (_) {}
      rethrow;
    }
    return r;
  }

  /// Release the renderer for `key`. Safe to call multiple times —
  /// the second call is a no-op. Always detaches `srcObject` BEFORE
  /// `dispose()` so a late frame callback can't race the disposal
  /// and JNI-crash on Android.
  Future<void> release(String key) async {
    final r = _renderers.remove(key);
    if (r == null) return;
    try {
      r.srcObject = null;
    } catch (_) {}
    try {
      await r.dispose();
    } catch (e) {
      debugPrint('[renderer-mgr] dispose($key) error (swallowed): $e');
    }
    if (kDebugMode) {
      debugPrint('[renderer-mgr] release $key '
          '(remaining=${_renderers.length})');
    }
  }

  /// Release everything. Called on logout so a re-login doesn't
  /// inherit leaked renderers from the previous user's session.
  Future<void> releaseAll() async {
    final all = _renderers.keys.toList();
    for (final k in all) {
      await release(k);
    }
    if (kDebugMode) {
      debugPrint('[renderer-mgr] releaseAll — all released');
    }
  }

  /// Returns the live renderer for `key` without creating one. Used
  /// by lifecycle helpers that need to poke `srcObject` to force a
  /// re-paint after screen lock without accidentally allocating a
  /// new renderer on a path where one is expected to already exist.
  RTCVideoRenderer? peek(String key) => _renderers[key];

  /// Apply a callback to every live renderer. Used by the post-
  /// background recovery hook to nudge every active SurfaceView
  /// back into rendering after the OS killed and recreated it.
  void forEach(void Function(String key, RTCVideoRenderer r) cb) {
    _renderers.forEach(cb);
  }

  /// Re-bind every live renderer's `srcObject` to itself. Cheap
  /// (same MediaStream reference) but on Android it triggers the
  /// SurfaceView to schedule a redraw — fixes the black-frozen-frame
  /// state after screen-off → screen-on. Called from each video-
  /// rendering screen's `AppLifecycleState.resumed` handler.
  void rebindAll() {
    if (kDebugMode) {
      debugPrint('[renderer-mgr] rebindAll over ${_renderers.length} renderer(s)');
    }
    _renderers.forEach((key, r) {
      try {
        final s = r.srcObject;
        if (s != null) r.srcObject = s;
      } catch (e) {
        debugPrint('[renderer-mgr] rebind($key) error: $e');
      }
    });
  }

  /// Dev-only diagnostic. Prints the full set of currently-held keys
  /// + their video-flowing state. Wire this to a long-press or a
  /// debug menu when chasing a leak — anything still present after
  /// a call ends is the leak.
  void dump() {
    if (!kDebugMode) return;
    debugPrint('────────── RendererManager.dump() ──────────');
    if (_renderers.isEmpty) {
      debugPrint('   (no live renderers)');
    } else {
      _renderers.forEach((key, r) {
        final v = r.value;
        debugPrint('   $key  renderVideo=${v.renderVideo} '
            'aspectRatio=${v.aspectRatio.toStringAsFixed(2)} '
            'rotation=${v.rotation}');
      });
    }
    debugPrint('───────────────────────────────────────────');
  }
}
