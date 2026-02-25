import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../../data/repositories/chat_repository.dart';
import '../../core/config/api_config.dart';
import '../../data/repositories/participant_repository.dart';
import '../../core/services/sfu_service.dart';
import '../../core/services/screen_share_service.dart';
import '../../core/services/network_resilience_service.dart';

class MeetingState {
  final bool isConnected;
  final RTCVideoRenderer localRenderer;
  final Map<String, RTCVideoRenderer> remoteRenderers;
  final bool isMicOn;
  final bool isCameraOn;
  final bool isRecording;
  final bool isScreenSharing;
  final bool isSfuMode;
  final List<Map<String, dynamic>> chatMessages;

  final int mockParticipantCount;
  final String? meetingId;
  final String? userId;

  MeetingState({
    this.isConnected = false,
    required this.localRenderer,
    this.remoteRenderers = const {},
    this.isMicOn = true,
    this.isCameraOn = true,
    this.isRecording = false,
    this.isScreenSharing = false,
    this.isSfuMode = false,
     this.chatMessages = const [],
    this.participants = const [],
    this.mockParticipantCount = 4,
    this.meetingId,
    this.userId,
    this.hostId,
  });

  MeetingState copyWith({
    bool? isConnected,
    Map<String, RTCVideoRenderer>? remoteRenderers,
    bool? isMicOn,
    bool? isCameraOn,
    bool? isRecording,
    bool? isScreenSharing,
    bool? isSfuMode,
    List<Map<String, dynamic>>? chatMessages,
    List<dynamic>? participants,
    int? mockParticipantCount,
    String? meetingId,
    String? userId,
    String? hostId,
  }) {
    return MeetingState(
      isConnected: isConnected ?? this.isConnected,
      localRenderer: localRenderer,
      remoteRenderers: remoteRenderers ?? this.remoteRenderers,
      isMicOn: isMicOn ?? this.isMicOn,
      isCameraOn: isCameraOn ?? this.isCameraOn,
      isRecording: isRecording ?? this.isRecording,
      isScreenSharing: isScreenSharing ?? this.isScreenSharing,
      isSfuMode: isSfuMode ?? this.isSfuMode,
      chatMessages: chatMessages ?? this.chatMessages,
      participants: participants ?? this.participants,
      mockParticipantCount: mockParticipantCount ?? this.mockParticipantCount,
      meetingId: meetingId ?? this.meetingId,
      userId: userId ?? this.userId,
      hostId: hostId ?? this.hostId,
    );
  }
}

class MeetingNotifier extends StateNotifier<MeetingState> {
  final ParticipantRepository _participantRepository = ParticipantRepository();
  final ChatRepository _chatRepository = ChatRepository();
  IO.Socket? _socket;
  IO.Socket? get socket => _socket;
  
  MediaStream? _localStream;
  final Map<String, RTCPeerConnection> _peerConnections = {};

  SFUService? _sfuService;
  final ScreenShareService _screenShareService = ScreenShareService();
  NetworkResilienceService? _networkResilienceService;

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

  void joinMeeting(String meetingId, String userId, String name, String jwtToken) async {
    _socket = IO.io(ApiConfig.signalingUrl, 
      IO.OptionBuilder()
        .setTransports(['websocket'])
        .enableAutoConnect()
        // Phase 6: Auth & Contract Validation 
        // JWT matches backend middleware expectations
        .setAuth({'token': jwtToken})
        .build()
    );

    _socket?.onConnect((_) async {
      final meetingInfo = await _meetingRepository.getMeetingInfo(meetingId);
      state = state.copyWith(
        isConnected: true, 
        meetingId: meetingId, 
        userId: userId,
        hostId: meetingInfo?.hostId,
      );
      
      // Phase 2: Log Participation
      _participantRepository.logJoin(meetingId, userId);

      // Phase 4: Load Chat History
      _loadChatHistory(meetingId, userId);

      // New: Load Participants
      _loadParticipants(meetingId);

      // Ensure socket auth handshake includes token validation
      _socket?.emit('join-meeting', {
        'meetingId': meetingId,
        'userId': userId,
        'name': name,
        'token': jwtToken, // redundant if setAuth supported, but safe fallback
      });

      _networkResilienceService ??= NetworkResilienceService(
        socket: _socket!,
        meetingId: meetingId,
        userId: userId,
        onBackgroundStateChanged: (inBackground) {
          // If in background, camera track is disabled via service,
          // but we can update state if necessary
          if (inBackground && state.isCameraOn) {
            state = state.copyWith(isCameraOn: false);
          }
        },
      );
      _networkResilienceService!.localStream = _localStream;
    });

    _socket?.onConnectError((err) => print('Socket Connect Error: $err'));
    _socket?.onError((err) => print('Socket Error: $err'));
    
    _initSocketListeners();
    _setupMedia();
  }

  void _initSocketListeners() {
    _socket?.on('switch-to-sfu', (_) {
      state = state.copyWith(isSfuMode: true);
      _setupSfu();
    });

    _socket?.on('chat-receive', (data) {
      if (data != null) {
        state = state.copyWith(chatMessages: [...state.chatMessages, Map<String, dynamic>.from(data)]);
      }
    });

    _socket?.on('router-rtp-capabilities', (data) async {
      if (_sfuService != null) {
        await _sfuService!.initDevice(Map<String, dynamic>.from(data));
        _socket?.emit('create-webrtc-transport', {'forceTcp': false});
      }
    });

    // Assume backend returns transport details to create transports
    _socket?.on('webrtc-transport-created', (data) async {
      if (_sfuService != null) {
        if (data['isSender'] == true) {
          await _sfuService!.createSendTransport(Map<String,dynamic>.from(data['transportOptions']));
          // Produce audio/video
          _produceTracks();
        } else {
          await _sfuService!.createRecvTransport(Map<String,dynamic>.from(data['transportOptions']));
        }
      }
    });
  }

  void _setupSfu() {
    if (_socket != null) {
      _sfuService = SFUService(socket: _socket!);
      _socket!.emit('get-router-rtp-capabilities', {});
      // Destroy P2P connections safely
      for (var pc in _peerConnections.values) {
        pc.close();
      }
      _peerConnections.clear();
    }
  }

  Future<void> _produceTracks() async {
    if (_localStream != null && _sfuService != null) {
      for (var track in _localStream!.getTracks()) {
        try {
          await _sfuService!.produce(track, _localStream!);
        } catch(e) {
          print("Error producing track: $e");
        }
      }
    }
  }

  Future<void> toggleScreenShare() async {
    if (state.isScreenSharing) {
      _screenShareService.stopScreenShare();
      state = state.copyWith(isScreenSharing: false);
      _socket?.emit('screen-share-stopped');
    } else {
      final screenStream = await _screenShareService.startScreenShare();
      if (screenStream != null) {
        state = state.copyWith(isScreenSharing: true);
        _socket?.emit('screen-share-started');
        
        if (state.isSfuMode && _sfuService != null) {
           for(var tk in screenStream.getVideoTracks()) {
             await _sfuService!.produce(tk, screenStream);
           }
        }
      }
    }
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

  void sendMessage(String message, String name, {String? attachmentUrl}) async {
    final msgData = {
      'text': message,
      'sender': name,
      'time': DateTime.now().toIso8601String(),
      if (attachmentUrl != null) 'attachmentUrl': attachmentUrl,
    };

    // Phase 4: Persistent Chat
    if (state.meetingId != null && state.userId != null) {
      try {
        await _chatRepository.sendMessage(
          meetingId: state.meetingId!,
          senderId: state.userId!,
          senderName: name,
          content: message,
          attachmentUrl: attachmentUrl,
        );
      } catch (e) {
        print("Error sending persistent chat: $e");
      }
    }

    _socket?.emit('chat-send', msgData);
    state = state.copyWith(chatMessages: [...state.chatMessages, msgData]);
  }

  Future<void> _loadChatHistory(String meetingId, String userId) async {
    final history = await _chatRepository.getChatHistory(meetingId, userId);
    if (history.isNotEmpty) {
      // Convert backend format to UI format if needed
      final formattedHistory = history.map((m) => {
        'text': m['content'] ?? m['text'],
        'sender': m['senderName'] ?? m['sender'],
        'time': m['createdAt'] ?? m['time'],
      }).toList();
      state = state.copyWith(chatMessages: [...formattedHistory, ...state.chatMessages]);
    }
  }

  Future<void> _loadParticipants(String meetingId) async {
    try {
      final participants = await _participantRepository.getMeetingParticipants(meetingId);
      state = state.copyWith(participants: participants);
    } catch (e) {
      print("Error loading participants: $e");
    }
  }

  void leaveMeeting() {
    if (state.meetingId != null && state.userId != null) {
      _participantRepository.logLeave(state.meetingId!, state.userId!);
    }
    _socket?.disconnect();
    _localStream?.dispose();
    _screenShareService.stopScreenShare();
    _sfuService?.dispose();
    _networkResilienceService?.dispose();
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
