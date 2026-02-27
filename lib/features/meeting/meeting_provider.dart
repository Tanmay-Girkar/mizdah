import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../../data/repositories/chat_repository.dart';
import '../../core/config/api_config.dart';
import '../../data/repositories/participant_repository.dart';
import '../../core/services/sfu_service.dart';
import '../../core/services/screen_share_service.dart';
import '../../core/services/network_resilience_service.dart';
import '../../data/repositories/meeting_repository.dart';

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
  final List<dynamic> participants;
  final String? hostId;
  final bool isSpeakerphoneOn;

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
    this.isSpeakerphoneOn = true,
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
    bool? isSpeakerphoneOn,
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
      isSpeakerphoneOn: isSpeakerphoneOn ?? this.isSpeakerphoneOn,
    );
  }
}

class MeetingNotifier extends StateNotifier<MeetingState> {
  final ParticipantRepository _participantRepository = ParticipantRepository();
  final ChatRepository _chatRepository = ChatRepository();
  final MeetingRepository _meetingRepository = MeetingRepository();
  IO.Socket? _socket;
  IO.Socket? get socket => _socket;
  IO.Socket? _chatSocket;
  IO.Socket? get chatSocket => _chatSocket;
  
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
  ));

  Future<void> _initRenderers() async {
    await state.localRenderer.initialize();
  }

  void joinMeeting(String meetingId, String userId, String name, String jwtToken, {bool video = true, bool audio = true}) async {
    // Explicitly initialize renderer before setting srcObject
    await state.localRenderer.initialize();
    
    _socket = IO.io(ApiConfig.signalingUrl, 
      IO.OptionBuilder()
        .setTransports(['websocket'])
        .enableAutoConnect()
        .setAuth({'token': jwtToken})
        .build()
    );

    _chatSocket = IO.io(ApiConfig.chatSocketUrl, 
      IO.OptionBuilder()
        .setTransports(['websocket'])
        .enableAutoConnect()
        .setAuth({'token': jwtToken})
        .build()
    );

    _socket?.onConnect((_) async {
      final meetingInfo = await _meetingRepository.getMeetingInfo(meetingId);
      if (!mounted) return;
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

      final joinData = {
        'meetingId': meetingId,
        'userId': userId,
        'name': name,
        'token': jwtToken,
      };

      // Always emit to signaling
      print("Emitting join-meeting to Port 4000");
      _socket?.emit('join-meeting', joinData);
      
      // For chat, ensure we are in the correct room
      void joinChatRoom() {
        print("Emitting join-chat to Port 4005 for meeting $meetingId");
        _chatSocket?.emit('join-chat', {
          'meetingId': meetingId,
          'userId': userId,
          'token': jwtToken, // Added token for safety
        });
      }

      if (_chatSocket?.connected ?? false) {
        joinChatRoom();
      } else {
        // Listen once for the next connection event
        _chatSocket?.on('connect', (_) {
          print("Chat Socket CONNECTED via listener");
          joinChatRoom();
        });
      }

      _networkResilienceService ??= NetworkResilienceService(
        socket: _socket!,
        meetingId: meetingId,
        userId: userId,
        onBackgroundStateChanged: (inBackground) {
          // If in background, camera track is disabled via service,
          // but we can update state if necessary
          if (inBackground && state.isCameraOn) {
            if (!mounted) return;
            state = state.copyWith(isCameraOn: false);
          }
        },
      );
      _networkResilienceService!.localStream = _localStream;
    });

    _socket?.onConnectError((err) => print('Socket Connect Error: $err'));
    _socket?.onError((err) => print('Socket Error: $err'));
    
    _initSocketListeners();
    // Use try-catch here as well to ensure media failure doesn't stop the joining process
    try {
      await _setupMedia(video: video, audio: audio);
    } catch (e) {
      print("Media setup failed during join: $e");
    }
  }

  void _initSocketListeners() {
    _socket?.on('switch-to-sfu', (_) {
      if (!mounted) return;
      state = state.copyWith(isSfuMode: true);
      _setupSfu();
    });

    // Move chat listener to _chatSocket (Port 4005)
    // Support both hyphen and colon formats for robustness
    void _handleNewMessage(data) {
      if (data != null) {
        print("Received real-time message: $data");
        final Map<String, dynamic> msg = Map<String, dynamic>.from(data);
        final formattedMsg = {
          'text': msg['content'] ?? msg['text'] ?? '',
          'sender': msg['senderName'] ?? msg['sender'] ?? 'Unknown',
          'time': msg['time'] ?? msg['createdAt'] ?? DateTime.now().toIso8601String(),
          'attachmentUrl': msg['attachmentUrl'],
        };
        
        // Prevent duplicates (especially if we are the sender receiving our own broadcast)
        final isDuplicate = state.chatMessages.any((m) => 
          m['text'] == formattedMsg['text'] && 
          m['sender'] == formattedMsg['sender'] &&
          m['time'] == String.fromCharCodes(formattedMsg['time'].toString().runes).substring(0, 16) // Rough time check
        );
        
        // Simpler check: if it's from me and I just sent it, ignore the socket reflection
        if (!isDuplicate && mounted) {
           state = state.copyWith(chatMessages: [...state.chatMessages, formattedMsg]);
        }
      }
    }

    _chatSocket?.onAny((event, data) {
      print("CHAT SOCKET Port 4005 EVENT: $event");
      print("CHAT SOCKET Port 4005 DATA: $data");
    });

    _chatSocket?.on('chat-receive', _handleNewMessage);
    _chatSocket?.on('chat:receive', _handleNewMessage);
    
    _chatSocket?.onConnect((_) {
      print('Chat Socket (4005) CONNECTED SUCCESSFULLY');
    });
    _chatSocket?.onConnectError((err) => print('Chat Socket (4005) Connect Error: $err'));
    _chatSocket?.onDisconnect((reason) => print('Chat Socket (4005) Disconnected: $reason'));

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

  Future<void> _setupMedia({bool video = true, bool audio = true}) async {
    try {
      final Map<String, dynamic> constraints = {
        'audio': audio,
        'video': video ? {
          'facingMode': 'user',
          'width': {'ideal': 1280},
          'height': {'ideal': 720},
        } : false,
      };
      
      final stream = await navigator.mediaDevices.getUserMedia(constraints);
      _localStream = stream;
      
      if (mounted) {
        state = state.copyWith(
          isCameraOn: video,
          isMicOn: audio,
        );
      }
      state.localRenderer.srcObject = stream;
    } catch (e) {
      print("Unable to getUserMedia: $e");
      // Don't crash, just proceed without local stream
      if (mounted) {
        state = state.copyWith(isCameraOn: false, isMicOn: false);
      }
    }
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

  Future<void> switchCamera() async {
    if (_localStream != null && state.isCameraOn) {
      final videoTrack = _localStream!.getVideoTracks().first;
      await Helper.switchCamera(videoTrack);
    }
  }

  Future<void> toggleSpeakerphone() async {
    final newValue = !state.isSpeakerphoneOn;
    await Helper.setSpeakerphoneOn(newValue);
    state = state.copyWith(isSpeakerphoneOn: newValue);
  }

  void sendMessage(String message, String name, {String? attachmentUrl}) async {
    final msgData = {
      'text': message,
      'sender': name,
      'time': DateTime.now().toIso8601String(),
      if (attachmentUrl != null) 'attachmentUrl': attachmentUrl,
    };

    // Socket data with backend-expected keys
    final socketData = {
      'meetingId': state.meetingId,
      'senderId': state.userId,
      'senderName': name,
      'content': message,
      'time': msgData['time'],
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

    _chatSocket?.emit('chat-send', socketData);
    _chatSocket?.emit('chat:send', socketData); // Support both
    if (mounted) {
      state = state.copyWith(chatMessages: [...state.chatMessages, msgData]);
    }
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
      if (mounted) {
        state = state.copyWith(chatMessages: [...formattedHistory, ...state.chatMessages]);
      }
    }
  }

  Future<void> _loadParticipants(String meetingId) async {
    try {
      final participants = await _participantRepository.getMeetingParticipants(meetingId);
      if (mounted) {
        state = state.copyWith(participants: participants);
      }
    } catch (e) {
      print("Error loading participants: $e");
    }
  }

  void leaveMeeting() {
    if (state.meetingId != null && state.userId != null) {
      _participantRepository.logLeave(state.meetingId!, state.userId!);
    }
    _socket?.disconnect();
    _chatSocket?.disconnect();
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

  @override
  void dispose() {
    leaveMeeting();
    super.dispose();
  }
}

final meetingProvider = StateNotifierProvider.autoDispose.family<MeetingNotifier, MeetingState, String>((ref, id) {
  return MeetingNotifier();
});
