import 'dart:async';
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
  final bool isHost;

  final bool hostAllowsMic;
  final bool hostAllowsCam;
  final bool hostAllowsChat;

  final int mockParticipantCount;
  final String? meetingId;
  final String? meetingCode;
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
    this.meetingCode,
    this.userId,
    this.hostId,
    this.isSpeakerphoneOn = true,
    this.isHost = false,
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
    String? meetingCode,
    String? userId,
    String? hostId,
    bool? isSpeakerphoneOn,
    bool? hostAllowsMic,
    bool? hostAllowsCam,
    bool? hostAllowsChat,
    bool? isHost,
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
      meetingCode: meetingCode ?? this.meetingCode,
      userId: userId ?? this.userId,
      hostId: hostId ?? this.hostId,
      isSpeakerphoneOn: isSpeakerphoneOn ?? this.isSpeakerphoneOn,
      isHost: isHost ?? this.isHost,
      hostAllowsMic: hostAllowsMic ?? this.hostAllowsMic,
      hostAllowsCam: hostAllowsCam ?? this.hostAllowsCam,
      hostAllowsChat: hostAllowsChat ?? this.hostAllowsChat,
    );
  }
}

class MeetingNotifier extends StateNotifier<MeetingState> {
  final MeetingRepository _meetingRepository = MeetingRepository();
  final ParticipantRepository _participantRepository = ParticipantRepository();
  final ChatRepository _chatRepository = ChatRepository();
  final ScreenShareService _screenShareService = ScreenShareService();
  
  io.Socket? _socket;
  io.Socket? _chatSocket;
  io.Socket? _mediaSocket;
  MediaStream? _localStream;
  SFUService? _sfuService;
  NetworkResilienceService? _networkResilienceService;
  Timer? _waitingListTimer;
  
  final Map<String, RTCPeerConnection> _peerConnections = {};

  MeetingNotifier() : super(MeetingState(localRenderer: RTCVideoRenderer())) {
    _initRenderer();
  }

  io.Socket? get socket => _socket;

  Future<void> _initRenderer() async {
    await state.localRenderer.initialize();
  }

  Future<void> prepareLocalPreview() async {
    if (_localStream == null) {
      await _setupMedia(video: true, audio: true);
    }
  }

  void joinMeeting(String meetingId, String userId, String name, String jwtToken, {bool video = true, bool audio = true}) async {
    debugPrint("🚩 1. joinMeeting entered: $meetingId");
    
    final cleanCode = meetingId.toLowerCase().trim();

    // Phase 1: Fetch meeting info with retries (in case just created)
    debugPrint("🚩 2. Fetching meeting info for: $cleanCode from: ${ApiConfig.getMeeting}/$cleanCode");
    var meetingInfo = await _meetingRepository.getMeetingInfo(cleanCode);
    
    int retries = 3;
    while (meetingInfo == null && retries > 0) {
      debugPrint("🚩 2a. Meeting info not found. Retrying in 1s... ($retries left)");
      await Future.delayed(const Duration(seconds: 1));
      meetingInfo = await _meetingRepository.getMeetingInfo(cleanCode);
      retries--;
    }

    final realMeetingId = meetingInfo?.id ?? cleanCode;
    final hostId = meetingInfo?.hostId;
    
    debugPrint("🚩 3. Meeting info: ID=$realMeetingId, Host=$hostId");

    // Phase 2: Log Participation (REST API) - Use code as per guide
    debugPrint("🚩 4. Logging participation (REST) to: ${ApiConfig.participantJoin} for $cleanCode");
    await _participantRepository.logJoin(cleanCode, userId);
    debugPrint("✅ Participation logged successfully");
    
    if (!mounted) return;
    state = state.copyWith(
      meetingId: realMeetingId,
      meetingCode: cleanCode,
      userId: userId,
      hostId: hostId,
    );

    // Phase 3: Initialize Socket
    debugPrint("🚩 5. Initializing Socket.IO to: ${ApiConfig.signalingUrl}");
    _socket = io.io(ApiConfig.signalingUrl, 
      io.OptionBuilder()
        .setTransports(['websocket'])
        .setPath('/signaling-fresh')
        .enableAutoConnect()
        .build()
    );

    _chatSocket = io.io(ApiConfig.chatSocketUrl, 
      io.OptionBuilder()
        .setTransports(['websocket', 'polling'])
        .enableAutoConnect()
        .setAuth({'token': jwtToken})
        .build()
    );

    debugPrint("Socket IO attempting connection to: ${ApiConfig.signalingUrl}");

    _socket?.onConnect((_) {
      debugPrint("✅ Signaling Socket CONNECTED for room: $cleanCode (Internal ID: $realMeetingId)");
      if (!mounted) return;
      state = state.copyWith(isConnected: true);
      
      _loadChatHistory(realMeetingId, userId);
      _loadParticipants(realMeetingId);

      final isHost = hostId != null && hostId == userId;
      final clientId = _socket?.id ?? 'flutter_${DateTime.now().millisecondsSinceEpoch}';

      final socketRoomId = cleanCode.replaceAll('-', '');
      debugPrint("📤 Emitting join-meeting: $socketRoomId, $userId, $name, $isHost, $clientId");
      
      if (isHost) {
        _startWaitingListPolling(socketRoomId);
      }
      
      _socket?.emit('join-meeting', [
        socketRoomId,
        userId,
        name,
        isHost,
        clientId,
      ]);
      
      if (_chatSocket?.connected ?? false) {
        _emitJoinChat(realMeetingId, userId, jwtToken);
      } else {
        _chatSocket?.once('connect', (_) => _emitJoinChat(realMeetingId, userId, jwtToken));
      }
    });

    _socket?.onConnectError((err) => debugPrint('❌ Signaling Socket CONNECT ERROR: $err'));
    _socket?.onAny((event, data) => debugPrint('📡 Signaling Socket EVENT: $event | DATA: $data'));
    
    _initSocketListeners();
    if (_localStream == null) {
      await _setupMedia(video: video, audio: audio);
    }
  }

  void _initSocketListeners() {
    _socket?.on('join-confirmation', (data) {
      debugPrint("🚩 6. join-confirmation received: $data");
      if (!mounted) return;
      
      if (data is String) {
        if (data == 'WAITING_FOR_APPROVAL' || data == 'WAITING') {
          state = state.copyWith(isInWaitingRoom: true);
        } else if (data == 'JOINED') {
          state = state.copyWith(isConnected: true, isInWaitingRoom: false);
        }
        return;
      }

      final status = data['status']?.toString() ?? 'DENIED';
      
      if (status == 'JOINED') {
        final participants = data['participants'] as List<dynamic>? ?? [];
        final waitingParticipants = data['waitingParticipants'] as List<dynamic>? ?? [];
        final isHostConfirmed = data['isHost'] == true;
        
        state = state.copyWith(
          participants: participants,
          waitingParticipants: waitingParticipants,
          isConnected: true,
          isInWaitingRoom: false,
          isHost: isHostConfirmed,
          hostId: data['hostId'] ?? state.hostId,
        );
      } else if (status == 'WAITING_FOR_APPROVAL' || status == 'WAITING') {
        state = state.copyWith(isInWaitingRoom: true);
      }
    });

    _socket?.on('request-to-join', (data) {
      debugPrint("Signaling Socket REQUEST TO JOIN: $data");
      if (!mounted) return;
      
      Map<String, dynamic> newWaiting;
      if (data is List && data.isNotEmpty) {
        newWaiting = Map<String, dynamic>.from(data.first as Map);
      } else if (data is Map) {
        newWaiting = Map<String, dynamic>.from(data);
      } else {
        return;
      }

      final exists = state.waitingParticipants.any((p) => p['socketId'] == newWaiting['socketId']);
      if (!exists) {
        state = state.copyWith(waitingParticipants: [...state.waitingParticipants, newWaiting]);
      }
    });

    _socket?.on('waiting-list-update', (data) {
      if (!mounted) return;
      List<dynamic> waitingList = [];
      if (data is List) {
        waitingList = data;
      } else if (data is Map && data['waitingParticipants'] != null) {
        waitingList = data['waitingParticipants'] as List;
      }
      state = state.copyWith(waitingParticipants: waitingList);
    });

    _socket?.on('user-joined', (data) {
      if (!mounted) return;
      final newParticipant = data;
      final exists = state.participants.any((p) => p['socketId'] == newParticipant['socketId']);
      if (!exists) {
        state = state.copyWith(participants: [...state.participants, newParticipant]);
        if (state.isHost) {
           _createPeerConnection(newParticipant['socketId'], isOfferer: true);
        }
      }
    });

    _socket?.on('user-left', (data) {
      if (!mounted) return;
      final socketId = data['socketId'];
      final updatedList = state.participants.where((p) => p['socketId'] != socketId).toList();
      state = state.copyWith(participants: updatedList);
      
      _peerConnections[socketId]?.close();
      _peerConnections.remove(socketId);
      if (state.remoteRenderers.containsKey(socketId)) {
        state.remoteRenderers[socketId]?.dispose();
        final updatedRenderers = Map<String, RTCVideoRenderer>.from(state.remoteRenderers)..remove(socketId);
        state = state.copyWith(remoteRenderers: updatedRenderers);
      }
    });

    _socket?.on('offer', (data) async {
      final from = data['from'];
      final offer = data['offer'];
      await _handleOffer(from, offer);
    });

    _socket?.on('answer', (data) async {
      final from = data['from'];
      final answer = data['answer'];
      await _handleAnswer(from, answer);
    });

    _socket?.on('ice-candidate', (data) async {
      final from = data['from'];
      final candidate = data['candidate'];
      await _handleIceCandidate(from, candidate);
    });

    _socket?.on('switch-to-sfu', (_) {
      if (!mounted) return;
      state = state.copyWith(isSfuMode: true);
      _setupSfu();
    });
    
    _chatSocket?.on('chat-receive', _handleNewMessage);
  }

  void _handleNewMessage(data) {
    if (data != null && mounted) {
      final Map<String, dynamic> msg = Map<String, dynamic>.from(data);
      final formattedMsg = {
        'text': msg['content'] ?? msg['text'] ?? '',
        'sender': msg['senderName'] ?? msg['sender'] ?? 'Unknown',
        'time': msg['time'] ?? msg['createdAt'] ?? DateTime.now().toIso8601String(),
      };
      state = state.copyWith(chatMessages: [...state.chatMessages, formattedMsg]);
    }
  }

  Future<void> _createPeerConnection(String remoteSocketId, {bool isOfferer = false}) async {
    if (_peerConnections.containsKey(remoteSocketId)) return;

    final config = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
        {'urls': 'stun:stun1.l.google.com:19302'},
      ]
    };

    final pc = await createPeerConnection(config);
    _peerConnections[remoteSocketId] = pc;

    if (_localStream != null) {
      for (var track in _localStream!.getTracks()) {
        await pc.addTrack(track, _localStream!);
      }
    }

    pc.onIceCandidate = (candidate) {
      _socket?.emit('ice-candidate', {
        'to': remoteSocketId,
        'candidate': candidate.toMap(),
      });
    };

    pc.onTrack = (event) async {
      if (event.streams.isNotEmpty && mounted) {
        final stream = event.streams.first;
        final renderer = RTCVideoRenderer();
        await renderer.initialize();
        renderer.srcObject = stream;
        
        state = state.copyWith(
          remoteRenderers: {
            ...state.remoteRenderers,
            remoteSocketId: renderer,
          },
        );
      }
    };

    if (isOfferer) {
      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      _socket?.emit('offer', {
        'to': remoteSocketId,
        'offer': offer.toMap(),
      });
    }
  }

  Future<void> _handleOffer(String from, dynamic offerMap) async {
    await _createPeerConnection(from, isOfferer: false);
    final pc = _peerConnections[from]!;
    final offer = RTCSessionDescription(offerMap['sdp'], offerMap['type']);
    await pc.setRemoteDescription(offer);
    
    final answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);
    _socket?.emit('answer', {
      'to': from,
      'answer': answer.toMap(),
    });
  }

  Future<void> _handleAnswer(String from, dynamic answerMap) async {
    final pc = _peerConnections[from];
    if (pc != null) {
      final answer = RTCSessionDescription(answerMap['sdp'], answerMap['type']);
      await pc.setRemoteDescription(answer);
    }
  }

  Future<void> _handleIceCandidate(String from, dynamic candidateMap) async {
    final pc = _peerConnections[from];
    if (pc != null) {
      final candidate = RTCIceCandidate(candidateMap['candidate'], candidateMap['sdpMid'], candidateMap['sdpMLineIndex']);
      await pc.addCandidate(candidate);
    }
  }

  Future<void> _setupMedia({bool video = true, bool audio = true}) async {
    try {
      final constraints = {
        'audio': audio,
        'video': video ? {
          'facingMode': 'user',
          'width': 1280,
          'height': 720,
        } : false,
      };
      
      final stream = await navigator.mediaDevices.getUserMedia(constraints);
      _localStream = stream;
      state.localRenderer.srcObject = stream;
      
      if (mounted) {
        state = state.copyWith(isCameraOn: video, isMicOn: audio);
      }
      
      for (var pc in _peerConnections.values) {
        for (var track in stream.getTracks()) {
          await pc.addTrack(track, stream);
        }
      }
    } catch (e) {
      debugPrint("Media Setup Error: $e");
    }
  }

  void admitParticipant(String socketId) {
    debugPrint("📤 Admitting participant: $socketId");
    _socket?.emit('admit-user', {'socketId': socketId});
    if (mounted) {
      final updatedList = state.waitingParticipants.where((p) => p['socketId'] != socketId).toList();
      state = state.copyWith(waitingParticipants: updatedList);
    }
  }

  void denyParticipant(String socketId) {
    debugPrint("📤 Denying participant: $socketId");
    _socket?.emit('deny-user', {'socketId': socketId});
    if (mounted) {
      final updatedList = state.waitingParticipants.where((p) => p['socketId'] != socketId).toList();
      state = state.copyWith(waitingParticipants: updatedList);
    }
  }

  void toggleMic() {
    if (_localStream != null) {
      final tracks = _localStream!.getAudioTracks();
      if (tracks.isNotEmpty) {
        tracks.first.enabled = !tracks.first.enabled;
        state = state.copyWith(isMicOn: tracks.first.enabled);
      }
    }
  }

  void toggleCamera() {
    if (_localStream != null) {
      final tracks = _localStream!.getVideoTracks();
      if (tracks.isNotEmpty) {
        tracks.first.enabled = !tracks.first.enabled;
        state = state.copyWith(isCameraOn: tracks.first.enabled);
      }
    }
  }

  void switchCamera() async {
    if (_localStream != null) {
      final track = _localStream!.getVideoTracks().first;
      await Helper.switchCamera(track);
    }
  }

  void toggleSpeakerphone() {
    state = state.copyWith(isSpeakerphoneOn: !state.isSpeakerphoneOn);
  }

  bool sendMessage(String text, String senderName) {
    if (!state.hostAllowsChat && !state.isHost) {
      return false;
    }
    if (state.meetingId != null && state.userId != null) {
      _chatSocket?.emit('chat-send', {
        'meetingId': state.meetingId,
        'userId': state.userId,
        'content': text,
        'senderName': senderName,
      });
      
      final localMsg = {
        'text': text,
        'sender': 'You',
        'time': DateTime.now().toIso8601String(),
      };
      state = state.copyWith(chatMessages: [...state.chatMessages, localMsg]);
    }
    return true;
  }

  void toggleScreenShare() async {
    if (state.isScreenSharing) {
      _screenShareService.stopScreenShare();
      state = state.copyWith(isScreenSharing: false);
    } else {
      final stream = await _screenShareService.startScreenShare();
      if (stream != null) {
        state = state.copyWith(isScreenSharing: true);
      }
    }
  }

  void muteAll() {
    _socket?.emit('mute-all');
  }

  void endMeetingForAll() {
    _socket?.emit('end-meeting-for-all');
    leaveMeeting();
  }

  void toggleLockMeeting(bool lock) {
    _socket?.emit('lock-meeting', {'lock': lock});
  }

  void updateParticipantPermissions(String key, bool value) {
    _socket?.emit('update-settings', {'key': key, 'value': value});
  }

  void leaveMeeting() {
    _socket?.disconnect();
    _chatSocket?.disconnect();
    _mediaSocket?.disconnect();
    _localStream?.dispose();
    state.localRenderer.dispose();
    for (var pc in _peerConnections.values) {
      pc.close();
    }
    _peerConnections.clear();
    for (var r in state.remoteRenderers.values) {
      r.dispose();
    }
    _networkResilienceService?.dispose();
    _sfuService?.dispose();
  }

  void _startWaitingListPolling(String meetingId) {
    _waitingListTimer?.cancel();
    _waitingListTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      refreshWaitingList();
    });
  }

  Future<void> refreshWaitingList() async {
    final meetingId = state.meetingCode?.replaceAll('-', '');
    if (meetingId == null) return;
    final list = await _meetingRepository.getWaitingParticipants(meetingId);
    if (mounted) {
      state = state.copyWith(waitingParticipants: list);
    }
  }

  void _loadChatHistory(String meetingId, String userId) async {
    final history = await _chatRepository.getChatHistory(meetingId, userId);
    if (mounted) {
      final formatted = history.map((m) => {
        'text': m['content'] ?? m['text'] ?? '',
        'sender': m['senderName'] ?? m['sender'] ?? 'Unknown',
        'time': m['createdAt'] ?? m['time'] ?? '',
      }).toList();
      state = state.copyWith(chatMessages: formatted);
    }
  }

  void _loadParticipants(String meetingId) async {
    final participants = await _participantRepository.getMeetingParticipants(meetingId);
    if (mounted) {
      state = state.copyWith(participants: participants);
    }
  }

  void _emitJoinChat(String meetingId, String userId, String token) {
    _chatSocket?.emit('join-chat', {
      'meetingId': meetingId,
      'userId': userId,
      'token': token,
    });
  }

  void _setupSfu() {
    _sfuService ??= SFUService(socket: _socket!);
  }

  @override
  void dispose() {
    _waitingListTimer?.cancel();
    leaveMeeting();
    super.dispose();
  }
}

final meetingProvider = StateNotifierProvider.autoDispose.family<MeetingNotifier, MeetingState, String>((ref, id) {
  return MeetingNotifier();
});
