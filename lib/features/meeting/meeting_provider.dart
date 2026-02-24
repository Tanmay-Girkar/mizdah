import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../../core/config/api_config.dart';

class MeetingState {
  final bool isConnected;
  final RTCVideoRenderer localRenderer;
  final Map<String, RTCVideoRenderer> remoteRenderers;
  final bool isMicOn;
  final bool isCameraOn;
  final bool isRecording;
  final List<Map<String, dynamic>> chatMessages;

  final int mockParticipantCount;

  MeetingState({
    this.isConnected = false,
    required this.localRenderer,
    this.remoteRenderers = const {},
    this.isMicOn = true,
    this.isCameraOn = true,
    this.isRecording = false,
    this.chatMessages = const [],
    this.mockParticipantCount = 4, // Default mock participants for UI view
  });

  MeetingState copyWith({
    bool? isConnected,
    Map<String, RTCVideoRenderer>? remoteRenderers,
    bool? isMicOn,
    bool? isCameraOn,
    bool? isRecording,
    List<Map<String, dynamic>>? chatMessages,
    int? mockParticipantCount,
  }) {
    return MeetingState(
      isConnected: isConnected ?? this.isConnected,
      localRenderer: localRenderer,
      remoteRenderers: remoteRenderers ?? this.remoteRenderers,
      isMicOn: isMicOn ?? this.isMicOn,
      isCameraOn: isCameraOn ?? this.isCameraOn,
      isRecording: isRecording ?? this.isRecording,
      chatMessages: chatMessages ?? this.chatMessages,
      mockParticipantCount: mockParticipantCount ?? this.mockParticipantCount,
    );
  }
}

class MeetingNotifier extends StateNotifier<MeetingState> {
  IO.Socket? _socket;
  MediaStream? _localStream;
  final Map<String, RTCPeerConnection> _peerConnections = {};

  MeetingNotifier() : super(MeetingState(
    localRenderer: RTCVideoRenderer(),
    chatMessages: [
      {'sender': 'Mustafa Omen', 'text': 'Hello everyone! 👋', 'time': DateTime.now().subtract(const Duration(minutes: 5)).toIso8601String()},
      {'sender': 'Zohaib Ali', 'text': 'Hey Mustafa, the UI looks great!', 'time': DateTime.now().subtract(const Duration(minutes: 4)).toIso8601String()},
      {'sender': 'Ayesha Khan', 'text': 'Can we start the presentation?', 'time': DateTime.now().subtract(const Duration(minutes: 2)).toIso8601String()},
    ],
  )) {
    _initRenderers();
  }

  Future<void> _initRenderers() async {
    await state.localRenderer.initialize();
  }

  void joinMeeting(String meetingId, String userId, String name) async {
    // Socket initialization disabled for UI-only mode
    /*
    _socket = IO.io(ApiConfig.signalingUrl, 
      IO.OptionBuilder()
        .setTransports(['websocket'])
        .enableAutoConnect()
        .build()
    );

    _socket?.onConnect((_) {
      state = state.copyWith(isConnected: true);
      _socket?.emit('join-meeting', {
        'meetingId': meetingId,
        'userId': userId,
        'name': name,
      });
    });
    */

    state = state.copyWith(isConnected: true);
    _setupMedia();
  }

  Future<void> _setupMedia() async {
    final Map<String, dynamic> constraints = {
      'audio': true,
      'video': {
        'facingMode': 'user',
      },
    };

    _localStream = await navigator.mediaDevices.getUserMedia(constraints);
    state.localRenderer.srcObject = _localStream;
  }

  void toggleMic() {
    if (_localStream != null) {
      final audioTrack = _localStream!.getAudioTracks().first;
      audioTrack.enabled = !audioTrack.enabled;
      state = state.copyWith(isMicOn: audioTrack.enabled);
    }
  }

  void toggleCamera() {
    if (_localStream != null) {
      final videoTrack = _localStream!.getVideoTracks().first;
      videoTrack.enabled = !videoTrack.enabled;
      state = state.copyWith(isCameraOn: videoTrack.enabled);
    }
  }

  void sendMessage(String message, String name) {
    final msgData = {
      'text': message,
      'sender': name,
      'time': DateTime.now().toIso8601String(),
    };
    _socket?.emit('chat-send', msgData);
    state = state.copyWith(chatMessages: [...state.chatMessages, msgData]);
  }

  void leaveMeeting() {
    _socket?.disconnect();
    _localStream?.dispose();
    state.localRenderer.dispose();
    for (var pc in _peerConnections.values) {
      pc.close();
    }
    _peerConnections.clear();
  }
}

final meetingProvider = StateNotifierProvider.family<MeetingNotifier, MeetingState, String>((ref, id) {
  return MeetingNotifier();
});
