import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'dart:io' show Platform;

class ScreenShareService {
  MediaStream? _localScreenStream;
  
  /// Requests capture permissions and starts the screen recording foreground 
  /// service on Android, or Broadcast Extension on iOS.
  Future<MediaStream?> startScreenShare() async {
    final Map<String, dynamic> mediaConstraints = {
      'audio': false,
      'video': true, 
      // For mobile native APIs you often use standard flutter_webrtc methods
      // or a specific platform-channel based broadcast extension plugin on iOS.
    };

    try {
      if (Platform.isAndroid) {
        // Typically requires starting a Foreground Service beforehand 
        // using flutter_background or a custom method, 
        // to bypass Android 10+ MediaProjection background restrictions.
      } else if (Platform.isIOS) {
        // iOS requires ReplayKit Broadcast Extension, which is typically 
        // handled using a supplementary native target & plugin.
      }

      _localScreenStream = await navigator.mediaDevices.getDisplayMedia(mediaConstraints);
      return _localScreenStream;
    } catch (e) {
      debugPrint("Screen share failed: $e");
      return null;
    }
  }

  void stopScreenShare() {
    _localScreenStream?.getTracks().forEach((track) {
      track.stop();
    });
    _localScreenStream?.dispose();
    _localScreenStream = null;
  }
}
