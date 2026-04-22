import 'package:flutter/widgets.dart';
import 'package:socket_io_client/socket_io_client.dart' as socket_io;
import 'package:flutter_webrtc/flutter_webrtc.dart';

class NetworkResilienceService extends WidgetsBindingObserver {
  final socket_io.Socket socket;
  final String meetingId;
  final String userId;
  final Function(bool) onBackgroundStateChanged;
  
  // To handle media stream pause/resume for battery optimization
  MediaStream? localStream;

  NetworkResilienceService({
    required this.socket,
    required this.meetingId,
    required this.userId,
    required this.onBackgroundStateChanged,
  }) {
    WidgetsBinding.instance.addObserver(this);
    _initNetworkListeners();
  }

  void _initNetworkListeners() {
    socket.onDisconnect((_) {
      debugPrint('Socket disconnected. Waiting for auto-reconnect...');
    });

    socket.onConnect((_) {
      // Phase 7: Auto rejoin on network change / restore state
      // When the socket reconnects, we explicitly tell the backend who we are 
      // so it can sync us without going through the full waiting room auth logic again.
      socket.emit('resume-session', {
        'meetingId': meetingId,
        'userId': userId,
      });
      
      // Pull latest state right away to recover missed events
      socket.emit('request-state-sync');
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      // Phase 7: Battery optimization - disable video rendering
      onBackgroundStateChanged(true);
      _muteLocalVideo(true);
      socket.emit('lifecycle-state', {'state': 'background'});
      // Audio stream is usually kept alive unless handled by OS call interruptions
    } else if (state == AppLifecycleState.resumed) {
      // Phase 7: Background -> foreground state resync
      onBackgroundStateChanged(false);
      _muteLocalVideo(false);
      socket.emit('lifecycle-state', {'state': 'foreground'});
      
      // Request missed state
      socket.emit('request-state-sync');
    }
  }

  void _muteLocalVideo(bool mute) {
    if (localStream != null) {
      final videoTracks = localStream!.getVideoTracks();
      if (videoTracks.isNotEmpty) {
        videoTracks.first.enabled = !mute;
      }
    }
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
  }
}
