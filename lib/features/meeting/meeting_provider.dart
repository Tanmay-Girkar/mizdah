import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
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
  final List<dynamic> waitingParticipants;
  final String? hostId;
  final bool isInWaitingRoom;
  final bool isSpeakerphoneOn;

  final bool hostAllowsMic;
  final bool hostAllowsCam;
  final bool hostAllowsChat;

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
    this.waitingParticipants = const [],
    this.isInWaitingRoom = false,
    this.mockParticipantCount = 0,
    this.meetingId,
    this.userId,
    this.hostId,
    this.isSpeakerphoneOn = true,
    this.hostAllowsMic = true,
    this.hostAllowsCam = true,
    this.hostAllowsChat = true,
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
    List<dynamic>? waitingParticipants,
    bool? isInWaitingRoom,
    int? mockParticipantCount,
    String? meetingId,
    String? userId,
    String? hostId,
    bool? isSpeakerphoneOn,
    bool? hostAllowsMic,
    bool? hostAllowsCam,
    bool? hostAllowsChat,
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
      waitingParticipants: waitingParticipants ?? this.waitingParticipants,
      isInWaitingRoom: isInWaitingRoom ?? this.isInWaitingRoom,
      mockParticipantCount: mockParticipantCount ?? this.mockParticipantCount,
      meetingId: meetingId ?? this.meetingId,
      userId: userId ?? this.userId,
      hostId: hostId ?? this.hostId,
      isSpeakerphoneOn: isSpeakerphoneOn ?? this.isSpeakerphoneOn,
      hostAllowsMic: hostAllowsMic ?? this.hostAllowsMic,
      hostAllowsCam: hostAllowsCam ?? this.hostAllowsCam,
      hostAllowsChat: hostAllowsChat ?? this.hostAllowsChat,
    );
  }
}

class MeetingNotifier extends StateNotifier<MeetingState> {
  final ParticipantRepository _participantRepository = ParticipantRepository();
  final ChatRepository _chatRepository = ChatRepository();
  final MeetingRepository _meetingRepository = MeetingRepository();
  io.Socket? _socket;
  io.Socket? get socket => _socket;
  io.Socket? _chatSocket;
  io.Socket? get chatSocket => _chatSocket;
  
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

  void joinMeeting(String meetingId, String userId, String name, String jwtToken, {bool video = true, bool audio = true}) async {
    // Explicitly initialize renderer before setting srcObject
    await state.localRenderer.initialize();
    
    // Trim for safety
    final sanitizedMeetingId = meetingId.trim();
    
    _socket = io.io(ApiConfig.signalingUrl, 
      io.OptionBuilder()
        .setTransports(['websocket'])
        .enableAutoConnect()
        .build()
    );

    _chatSocket = io.io(ApiConfig.chatSocketUrl, 
      io.OptionBuilder()
        .setTransports(['websocket'])
        .enableAutoConnect()
        .setAuth({'token': jwtToken})
        .build()
    );

    debugPrint("Socket IO attempting connection to: ${ApiConfig.signalingUrl}");

    _socket?.onConnect((_) async {
      debugPrint("Signaling Socket CONNECTED SUCCESSFULLY for room: $sanitizedMeetingId");
      final meetingInfo = await _meetingRepository.getMeetingInfo(sanitizedMeetingId);
      if (!mounted) return;
      state = state.copyWith(
        isConnected: true, 
        meetingId: sanitizedMeetingId, 
        userId: userId,
        hostId: meetingInfo?.hostId,
      );
      
      // Phase 2: Log Participation
      _participantRepository.logJoin(sanitizedMeetingId, userId);

      // Phase 4: Load Chat History
      _loadChatHistory(sanitizedMeetingId, userId);

      // New: Load Participants
      _loadParticipants(sanitizedMeetingId);

      final isHost = meetingInfo?.hostId != null && meetingInfo?.hostId == userId;
      final clientId = _socket?.id ?? 'flutter_client_${DateTime.now().millisecondsSinceEpoch}';

      // Follow guide: socket.emit("join-meeting", [meetingCode, userId, userName, isHost, clientId]);
      final joinData = [
        sanitizedMeetingId,
        userId,
        name,
        isHost,
        clientId,
      ];

      // Always emit to signaling
      debugPrint("Emitting join-meeting with ID: $sanitizedMeetingId");
      _socket?.emit('join-meeting', joinData);
      
      // For chat, ensure we are in the correct room
      void joinChatRoom() {
        debugPrint("Emitting join-chat for meeting $sanitizedMeetingId");
        _chatSocket?.emit('join-chat', {
          'meetingId': sanitizedMeetingId,
          'userId': userId,
          'token': jwtToken, // Added token for safety
        });
      }

      if (_chatSocket?.connected ?? false) {
        joinChatRoom();
      } else {
        // Listen once for the next connection event
        _chatSocket?.on('connect', (_) {
          debugPrint("Chat Socket CONNECTED via listener");
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

    _socket?.onConnect((_) => debugPrint('Signaling Socket (4012) CONNECTED SUCCESSFULLY'));
    _socket?.onConnectError((err) => debugPrint('Signaling Socket (4012) CONNECT ERROR: $err'));
    _socket?.on('connect_timeout', (err) => debugPrint('Signaling Socket (4012) CONNECT TIMEOUT: $err'));
    _socket?.onError((err) => debugPrint('Signaling Socket (4012) ERROR: $err'));
    _socket?.onDisconnect((reason) => debugPrint('Signaling Socket (4012) DISCONNECTED: $reason'));
    _socket?.onAny((event, data) => debugPrint('Signaling Socket (4012) EVENT: $event | DATA: $data'));
    
    _initSocketListeners();
    // Use try-catch here as well to ensure media failure doesn't stop the joining process
    try {
      await _setupMedia(video: video, audio: audio);
    } catch (e) {
      debugPrint("Media setup failed during join: $e");
    }
  }

  void _initSocketListeners() {
    _socket?.on('switch-to-sfu', (_) {
      if (!mounted) return;
      state = state.copyWith(isSfuMode: true);
      _setupSfu();
    });

    _socket?.on('join-confirmation', (data) {
      debugPrint("Signaling Socket JOIN CONFIRMED: $data");
      if (!mounted) return;
      
      final participants = data['participants'] as List<dynamic>? ?? [];
      final waitingParticipants = data['waitingParticipants'] as List<dynamic>? ?? [];
      
      state = state.copyWith(
        participants: participants,
        waitingParticipants: waitingParticipants,
        hostId: data['hostId'] ?? state.hostId,
        isInWaitingRoom: data['status'] == 'WAITING',
      );

      if (data['status'] == 'WAITING') {
        debugPrint("You are in the waiting room.");
      } else {
        debugPrint("You joined the meeting successfully.");
      }
    });

    _socket?.on('waiting-list-update', (data) {
      debugPrint("Signaling Socket WAITING LIST UPDATE: $data");
      if (!mounted) return;
      final waitingList = data as List<dynamic>? ?? [];
      state = state.copyWith(waitingParticipants: waitingList);
    });

    _socket?.on('user-joined', (data) {
      debugPrint("Signaling Socket USER JOINED: $data");
      if (!mounted) return;
      final newParticipant = data;
      // Avoid duplicates
      final exists = state.participants.any((p) => p['socketId'] == newParticipant['socketId']);
      if (!exists) {
        state = state.copyWith(participants: [...state.participants, newParticipant]);
      }
    });

    _socket?.on('user-left', (data) {
      debugPrint("Signaling Socket USER LEFT: $data");
      if (!mounted) return;
      final socketId = data['socketId'];
      final updatedList = state.participants.where((p) => p['socketId'] != socketId).toList();
      state = state.copyWith(participants: updatedList);
    });

    // Move chat listener to _chatSocket (Port 4005)
    // Support both hyphen and colon formats for robustness
    void handleNewMessage(data) {
      if (data != null) {
        debugPrint("Received real-time message: $data");
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
      debugPrint("CHAT SOCKET Port 4005 EVENT: $event");
      debugPrint("CHAT SOCKET Port 4005 DATA: $data");
    });

    _chatSocket?.on('chat-receive', handleNewMessage);
    _chatSocket?.on('chat:receive', handleNewMessage);
    
    _chatSocket?.onConnect((_) {
      debugPrint('Chat Socket (4005) CONNECTED SUCCESSFULLY');
    });
    _chatSocket?.onConnectError((err) => debugPrint('Chat Socket (4005) Connect Error: $err'));
    _chatSocket?.onDisconnect((reason) => debugPrint('Chat Socket (4005) Disconnected: $reason'));

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

    _socket?.on('mute-remote', (_) {
      if (_localStream != null) {
        final audioTracks = _localStream!.getAudioTracks();
        if (audioTracks.isNotEmpty) {
          audioTracks.first.enabled = false;
          if (mounted) {
            state = state.copyWith(isMicOn: false);
          }
        }
      }
    });

    _socket?.on('camera-off-remote', (_) {
      if (_localStream != null) {
        final videoTracks = _localStream!.getVideoTracks();
        if (videoTracks.isNotEmpty) {
          videoTracks.first.enabled = false;
          if (mounted) {
            state = state.copyWith(isCameraOn: false);
          }
        }
      }
    });

    _socket?.on('meeting-ended', (data) {
       // Clean up and disconnect.
       // The UI needs to listen to isConnected to navigate away, or go router will handle it.
       if (mounted) {
         state = state.copyWith(isConnected: false);
       }
       leaveMeeting();
    });

    _socket?.on('meeting-locked', (data) {
       debugPrint("Meeting Locked State: ${data['locked']}");
    });

    _socket?.on('setting-updated', (data) {
       debugPrint("Setting updated: ${data['key']} = ${data['value']}");
       if (!mounted) return;
       final key = data['key'];
       final value = data['value'] as bool;

       if (key == 'allowMic') {
         state = state.copyWith(hostAllowsMic: value);
         if (!value && _localStream != null) {
           final audioTracks = _localStream!.getAudioTracks();
           if (audioTracks.isNotEmpty) {
             audioTracks.first.enabled = false;
             state = state.copyWith(isMicOn: false);
           }
         }
       } else if (key == 'allowCam') {
         state = state.copyWith(hostAllowsCam: value);
         if (!value && _localStream != null) {
           final videoTracks = _localStream!.getVideoTracks();
           if (videoTracks.isNotEmpty) {
             videoTracks.first.enabled = false;
             state = state.copyWith(isCameraOn: false);
           }
         }
       } else if (key == 'allowChat') {
         state = state.copyWith(hostAllowsChat: value);
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
          debugPrint("Error producing track: $e");
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
    if (!video && !audio) {
      debugPrint("Skipping getUserMedia: both audio and video are disabled.");
      return;
    }
    try {
      final Map<String, dynamic> constraints = {
        'audio': audio,
        'video': video,
      };
      
      debugPrint("Requesting getUserMedia with constraints: $constraints");
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
      debugPrint("Unable to getUserMedia: $e");
      // Don't crash, just proceed without local stream
      if (mounted) {
        state = state.copyWith(isCameraOn: false, isMicOn: false);
      }
    }
  }

  void toggleMic() {
    if (!state.hostAllowsMic && state.userId != state.hostId) {
      return; // Add a way to show a snackbar in UI eventually
    }
    if (_localStream != null) {
      final audioTracks = _localStream!.getAudioTracks();
      if (audioTracks.isNotEmpty) {
        audioTracks.first.enabled = !audioTracks.first.enabled;
        state = state.copyWith(isMicOn: audioTracks.first.enabled);
      }
    }
  }

  void toggleCamera() {
    if (!state.hostAllowsCam && state.userId != state.hostId) {
      return;
    }
    if (_localStream != null) {
      final videoTracks = _localStream!.getVideoTracks();
      if (videoTracks.isNotEmpty) {
        videoTracks.first.enabled = !videoTracks.first.enabled;
        state = state.copyWith(isCameraOn: videoTracks.first.enabled);
      }
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

  bool sendMessage(String message, String name, {String? attachmentUrl}) {
    if (!state.hostAllowsChat && state.userId != state.hostId) return false;

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
      _chatRepository.sendMessage(
        meetingId: state.meetingId!,
        senderId: state.userId!,
        senderName: name,
        content: message,
        attachmentUrl: attachmentUrl,
      ).catchError((e) {
        debugPrint("Error sending persistent chat: $e");
        return <String, dynamic>{};
      });
    }

    _chatSocket?.emit('chat-send', socketData);
    _chatSocket?.emit('chat:send', socketData); // Support both
    if (mounted) {
      state = state.copyWith(chatMessages: [...state.chatMessages, msgData]);
    }
    return true;
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
      debugPrint("Error loading participants: $e");
    }
  }

  void admitParticipant(String socketId) {
    debugPrint("Admitting participant: $socketId");
    _socket?.emit('admit-user', {'socketId': socketId});
  }

  void muteAll() {
    _socket?.emit('mute-all');
  }

  void endMeetingForAll() {
    _socket?.emit('end-meeting-for-all');
    if (mounted) {
      state = state.copyWith(isConnected: false);
    }
    leaveMeeting();
  }

  void toggleLockMeeting(bool lock) {
    _socket?.emit('lock-meeting', {'lock': lock});
  }

  void updateParticipantPermissions(String key, bool value) {
    _socket?.emit('update-settings', {'key': key, 'value': value});
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
