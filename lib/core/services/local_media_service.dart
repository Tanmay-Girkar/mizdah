import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../features/settings/video_preferences_provider.dart';
import 'video_quality_profile.dart';

/// App-wide owner of the local camera + microphone and the
/// RTCVideoRenderer that displays them.
///
/// This exists because the app has *two* screens that need the
/// self-view (the pre-join "Start Meeting" screen and the in-meeting
/// room) and each one used to instantiate its own MeetingNotifier
/// → its own MediaStream + RTCVideoRenderer. The hand-off between
/// notifiers caused a 3-4 second black PIP after Start Now (camera
/// reopen + renderer re-initialize) and a screen-rebuild flicker
/// when the new texture finally lit up.
///
/// The fix: open the camera ONCE, allocate the renderer ONCE, and
/// keep them alive across navigation. Both screens render the same
/// renderer instance, so the texture survives unmount/mount.
///
/// Lifecycle:
///  - `initialize()` opens the camera if it isn't already open and
///    returns the in-flight future on subsequent calls (idempotent).
///  - `scheduleShutdown()` parks a 5 s timer to release the camera;
///    cancelled the moment another caller hits `initialize()`. This
///    bridges the brief gap between pre-join unmount and meeting-room
///    mount without the camera ever closing.
///  - `dispose()` is the explicit hard-close (logout, app exit).
class LocalMediaService {
  LocalMediaService._();
  static final LocalMediaService instance = LocalMediaService._();

  static const String _tag = '[LocalMedia]';
  static void _log(String msg) => debugPrint('$_tag $msg');

  // --- state ---------------------------------------------------------
  MediaStream? _stream;
  RTCVideoRenderer? _renderer;
  Future<void>? _initInFlight;
  Timer? _shutdownTimer;
  bool _audioRequested = true;
  bool _videoRequested = true;

  // --- public surface ------------------------------------------------
  MediaStream? get stream => _stream;
  bool get hasStream => _stream != null;

  /// Always returns the same renderer instance for the life of the
  /// app. Lazily allocated on first access.
  RTCVideoRenderer get renderer => _renderer ??= RTCVideoRenderer();

  /// Open the camera + mic if not already open. Idempotent — repeated
  /// calls share the same in-flight Future and return immediately
  /// once the stream is live.
  ///
  /// Pass [force]: true to FULLY tear down the cached stream and
  /// re-acquire from scratch. Called when the meeting screen
  /// detects that an underlying track has died (camera-app stole
  /// the device, OS reclaimed mic on resume, etc.) — without this
  /// the cache would happily return the dead stream forever.
  /// Remember the active profile across calls so `_doInit` knows
  /// which constraints to ask for. Defaults to Auto until a notifier
  /// passes in something more specific.
  OutgoingVideoQuality _quality = OutgoingVideoQuality.auto;

  /// Update the cached profile. Called from MeetingNotifier /
  /// P2PCallNotifier when the user moves the dial mid-call, OR at
  /// initialize-time via the [quality] arg. Note: changing this on
  /// an already-running camera does NOT auto-re-acquire the stream —
  /// re-acquire is heavy and would interrupt the call. The bitrate
  /// half of the profile is applied to the live sender separately
  /// via `VideoQualityProfile.applyToSender`, which DOES take effect
  /// immediately. The new resolution kicks in on the next acquire.
  void setQuality(OutgoingVideoQuality q) {
    _quality = q;
  }

  OutgoingVideoQuality get quality => _quality;

  Future<void> initialize({
    bool video = true,
    bool audio = true,
    bool force = false,
    OutgoingVideoQuality? quality,
  }) async {
    if (quality != null) _quality = quality;
    _shutdownTimer?.cancel();
    _shutdownTimer = null;

    if (force && _stream != null) {
      _log('initialize(force) — disposing stale stream and re-acquiring');
      try {
        for (final t in _stream!.getTracks()) {
          try {
            t.stop();
          } catch (_) {}
        }
        await _stream!.dispose();
      } catch (e) {
        _log('initialize(force) — dispose error (non-fatal): $e');
      }
      _stream = null;
      // Detach the renderer's srcObject so the next attach picks
      // up the fresh tracks. Don't dispose the renderer itself
      // — it's referenced by every meeting screen and recreating
      // it would force every consumer to rebind.
      _renderer?.srcObject = null;
    }

    // Already running? Just sync the requested track-enabled state.
    if (_stream != null) {
      _audioRequested = audio;
      _videoRequested = video;
      _applyEnabled();
      return;
    }

    // Init already underway? Wait for it to finish.
    if (_initInFlight != null) {
      await _initInFlight;
      _audioRequested = audio;
      _videoRequested = video;
      _applyEnabled();
      return;
    }

    _audioRequested = audio;
    _videoRequested = video;
    _initInFlight = _doInit();
    try {
      await _initInFlight;
    } finally {
      _initInFlight = null;
    }
  }

  Future<void> _doInit() async {
    _log('initializing — video=$_videoRequested audio=$_audioRequested');

    // Renderer (allocate + init exactly once for the app's lifetime).
    _renderer ??= RTCVideoRenderer();
    if (_renderer!.textureId == null) {
      await _renderer!.initialize();
      _log('renderer initialised (textureId=${_renderer!.textureId})');
    }

    // Camera — resolution + framerate hints come from the active
    // quality profile (Auto / 720p / 1080p) instead of being
    // hardcoded. See video_quality_profile.dart for the mapping.
    final profile = VideoQualityProfile.forQuality(_quality);
    final constraints = <String, dynamic>{
      'audio': _audioRequested,
      'video': _videoRequested ? profile.cameraConstraints : false,
    };
    _log('getUserMedia with quality=${_quality.name} '
        '(${profile.width}×${profile.height} @${profile.maxFramerate}fps)');
    final stream = await navigator.mediaDevices.getUserMedia(constraints);
    _stream = stream;
    _renderer!.srcObject = stream;
    _applyEnabled();
    _log('camera ready — tracks=${stream.getTracks().map((t) => t.kind).join(",")}');
  }

  void _applyEnabled() {
    final s = _stream;
    if (s == null) return;
    for (final t in s.getAudioTracks()) {
      t.enabled = _audioRequested;
    }
    for (final t in s.getVideoTracks()) {
      t.enabled = _videoRequested;
    }
  }

  /// Toggle the local mic. Returns the new enabled state.
  bool toggleAudio() {
    _audioRequested = !_audioRequested;
    _applyEnabled();
    return _audioRequested;
  }

  /// Toggle the local camera. Returns the new enabled state.
  bool toggleVideo() {
    _videoRequested = !_videoRequested;
    _applyEnabled();
    return _videoRequested;
  }

  bool get audioEnabled => _audioRequested;
  bool get videoEnabled => _videoRequested;

  Future<void> switchCamera() async {
    final track = _stream?.getVideoTracks().firstOrNull;
    if (track != null) await Helper.switchCamera(track);
  }

  /// Schedule a delayed camera shutdown. The grace window lets the
  /// next screen reuse the running camera without reopening it
  /// (pre-join → meeting room handoff). Pass `Duration.zero` to
  /// fire immediately — the post-leaveMeeting path uses that
  /// because there's no next screen waiting on the camera.
  void scheduleShutdown(
      {Duration delay = const Duration(seconds: 5)}) {
    _shutdownTimer?.cancel();
    if (delay <= Duration.zero) {
      _log('shutdown firing immediately');
      _hardShutdown();
      return;
    }
    _log('shutdown scheduled in ${delay.inSeconds}s');
    _shutdownTimer = Timer(delay, _hardShutdown);
  }

  /// Force-close the camera + detach the renderer NOW. Use after
  /// `leaveMeeting` where there's no handoff to the next screen
  /// and the 5s scheduleShutdown grace just keeps the
  /// CameraStatistics / EglRenderer / MediaCodec threads alive
  /// burning CPU. Idempotent — safe to call when nothing's open.
  void shutdownNow() {
    _shutdownTimer?.cancel();
    _shutdownTimer = null;
    _hardShutdown();
  }

  /// Cancel a pending shutdown. Called from initialize() but exposed
  /// for callers that want explicit control.
  void cancelShutdown() {
    _shutdownTimer?.cancel();
    _shutdownTimer = null;
  }

  /// Detach the renderer from the active stream without touching
  /// the camera itself. Used the moment leaveMeeting starts so the
  /// EglRenderer stops pumping frames while we tear down the rest
  /// of the meeting plumbing — the actual camera shutdown happens
  /// a few ms later in [shutdownNow], but the renderer needs to
  /// detach FIRST or it'll keep rendering whatever's in its buffer.
  void detachRendererFromStream() {
    if (_renderer == null) return;
    _renderer!.srcObject = null;
  }

  void _hardShutdown() {
    _log('camera shutdown');
    final s = _stream;
    if (s != null) {
      // Detach the renderer FIRST so it stops pulling frames before
      // we yank the tracks out from under it (avoids the JNI race
      // where a late frame callback hits a stopped track).
      _renderer?.srcObject = null;
      for (final t in s.getTracks()) {
        // enabled=false drops the kernel-side audio/video frame
        // delivery callbacks; stop() releases the camera capturer
        // and tells WebRTC to release the MediaCodec encoder.
        try {
          t.enabled = false;
        } catch (_) {}
        try {
          t.stop();
        } catch (_) {}
      }
      try {
        s.dispose();
      } catch (_) {}
    }
    _stream = null;
    // Renderer is intentionally NOT disposed — the texture is
    // reused across screens (pre-join → meeting room). Only the
    // explicit dispose() path tears it down.
  }

  /// Hard-stop and dispose everything, including the renderer.
  /// Call from app shutdown / logout, NOT from per-screen lifecycle.
  Future<void> dispose() async {
    _shutdownTimer?.cancel();
    _hardShutdown();
    final r = _renderer;
    _renderer = null;
    await r?.dispose();
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
