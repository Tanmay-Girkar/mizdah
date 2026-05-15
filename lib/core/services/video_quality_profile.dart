// ════════════════════════════════════════════════════════════════════
//  VideoQualityProfile — one place to translate the user's
//  Auto/720p/1080p preference into actual camera + encoder knobs.
//  Read once at meeting/P2P start; re-applied on the active sender
//  when the user moves the dial mid-call.
// ════════════════════════════════════════════════════════════════════

import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../features/settings/video_preferences_provider.dart';

/// One quality preset → the four numbers we feed into WebRTC.
class VideoQualityProfile {
  /// `getUserMedia({video: {width: ideal: ..., height: ideal: ...}})`.
  final int width;
  final int height;

  /// RTCRtpEncodingParameters.maxBitrate — bytes per second the
  /// sender is allowed to push. WebRTC's congestion controller still
  /// adapts downward; this is the ceiling.
  final int maxBitrate;

  /// Floor so the encoder doesn't fall below "still readable" on
  /// a bad link. Same across all profiles by design — going below
  /// 300 kbps makes faces unrecognisable.
  final int minBitrate;

  /// 30 fps is the right answer for any face-on call. Higher
  /// burns CPU for no perceptual gain at typical lighting.
  final int maxFramerate;

  const VideoQualityProfile({
    required this.width,
    required this.height,
    required this.maxBitrate,
    required this.minBitrate,
    required this.maxFramerate,
  });

  /// Constraints blob for `getUserMedia`. The `ideal` values are
  /// hints — the camera may give us close-to but not exact, which
  /// is fine; the sender params below do the final capping.
  Map<String, dynamic> get cameraConstraints => {
        'facingMode': 'user',
        'width': {'ideal': width},
        'height': {'ideal': height},
        'frameRate': {'ideal': maxFramerate},
      };

  static VideoQualityProfile forQuality(OutgoingVideoQuality q) {
    switch (q) {
      case OutgoingVideoQuality.auto:
        // Auto = 720p capture with a slightly higher bitrate cap so
        // good links can push a sharper frame. Still bounded — never
        // let the encoder run away to 3-5 Mbps on a strong WiFi.
        return const VideoQualityProfile(
          width: 1280,
          height: 720,
          maxBitrate: 1800 * 1000,
          minBitrate: 300 * 1000,
          maxFramerate: 30,
        );
      case OutgoingVideoQuality.hd720:
        // Explicit 720p — bandwidth-conscious profile, tighter cap.
        return const VideoQualityProfile(
          width: 1280,
          height: 720,
          maxBitrate: 1500 * 1000,
          minBitrate: 300 * 1000,
          maxFramerate: 30,
        );
      case OutgoingVideoQuality.hd1080:
        // 1080p — eats noticeably more CPU + battery. Cap at 2.5
        // Mbps; pushing higher rarely helps because the SFU
        // re-encodes / re-transmits anyway.
        return const VideoQualityProfile(
          width: 1920,
          height: 1080,
          maxBitrate: 2500 * 1000,
          minBitrate: 300 * 1000,
          maxFramerate: 30,
        );
    }
  }

  /// Apply this profile's bitrate + framerate caps to an RTCRtpSender's
  /// FIRST encoding slot. Used both for the mediasoup producer's
  /// underlying sender AND for the legacy P2P peer-connection sender.
  ///
  /// Returns true if at least one encoding slot was patched. Returns
  /// false silently when the sender has no encoding slots yet (can
  /// happen during the brief window between addTrack and the first
  /// negotiation completes).
  Future<bool> applyToSender(RTCRtpSender sender) async {
    final params = sender.parameters;
    final encodings = params.encodings;
    if (encodings == null || encodings.isEmpty) return false;
    for (final enc in encodings) {
      enc.maxBitrate = maxBitrate;
      enc.minBitrate = minBitrate;
      enc.maxFramerate = maxFramerate;
    }
    // Sharpness over smoothness for face-on video — same call the
    // pre-feature _tuneVideoSender helper already made.
    params.degradationPreference = RTCDegradationPreference.MAINTAIN_RESOLUTION;
    await sender.setParameters(params);
    return true;
  }
}
