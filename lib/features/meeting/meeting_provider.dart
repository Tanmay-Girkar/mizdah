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

// Tag for filtering WebRTC/signaling logs in production builds.
const String _kLogTag = '[MEET]';
void _log(String msg) => debugPrint('$_kLogTag $msg');

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
  bool _hasJoinedRoom = false;
  bool _disposed = false;

  // Per-peer state: pc, pending-ice queue, and renderer cache.
  final Map<String, RTCPeerConnection> _peerConnections = {};
  final Map<String, List<RTCIceCandidate>> _pendingIce = {};
  final Map<String, MediaStream?> _remoteStreams = {};

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

  /// Top-level join sequence. Order matters: media MUST be ready before
  /// we open the signaling socket so the first incoming offer/answer
  /// can attach our local tracks.
  void joinMeeting(String meetingId, String userId, String name, String jwtToken,
      {bool video = true, bool audio = true}) async {
    _log('joinMeeting → meetingId=$meetingId userId=$userId name=$name video=$video audio=$audio');

    final cleanCode = meetingId.toLowerCase().trim();

    // 1. Validate meeting (with brief retry — instant meetings can lag).
    _log('REST GET ${ApiConfig.getMeeting}/$cleanCode');
    var meetingInfo = await _meetingRepository.getMeetingInfo(cleanCode);
    int retries = 3;
    while (meetingInfo == null && retries > 0) {
      _log('Meeting info null, retrying in 1s ($retries left)');
      await Future.delayed(const Duration(seconds: 1));
      meetingInfo = await _meetingRepository.getMeetingInfo(cleanCode);
      retries--;
    }

    final realMeetingId = meetingInfo?.id ?? cleanCode;
    final hostId = meetingInfo?.hostId;
    _log('Meeting resolved: id=$realMeetingId hostId=$hostId');

    // 2. Register session with participant service.
    _log('REST POST ${ApiConfig.participantJoin} (code=$cleanCode userId=$userId)');
    await _participantRepository.logJoin(cleanCode, userId);

    if (!mounted || _disposed) return;
    final hostMatch = hostId != null && hostId == userId;
    state = state.copyWith(
      meetingId: realMeetingId,
      meetingCode: cleanCode,
      userId: userId,
      hostId: hostId,
      isHost: hostMatch,
    );

    // 3. CRITICAL: set up local media BEFORE opening signaling socket.
    // If a peer offers immediately, our PC must already have local tracks.
    if (_localStream == null) {
      _log('Setting up local media (video=$video audio=$audio)');
      await _setupMedia(video: video, audio: audio);
    } else {
      _log('Local stream already exists (${_localStream!.getTracks().length} tracks)');
    }

    if (_localStream == null) {
      _log('❌ Local media setup failed — aborting join');
      return;
    }

    // 4. Open signaling and chat sockets.
    _log('Connecting signaling socket → ${ApiConfig.signalingUrl}${ApiConfig.signalingPath}');
    _socket = io.io(
      ApiConfig.signalingUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setPath(ApiConfig.signalingPath)
          .enableAutoConnect()
          .setAuth({'token': jwtToken})
          .build(),
    );

    _chatSocket = io.io(
      ApiConfig.chatSocketUrl,
      io.OptionBuilder()
          .setTransports(['websocket', 'polling'])
          .enableAutoConnect()
          .setAuth({'token': jwtToken})
          .build(),
    );

    _initSocketListeners(realMeetingId, userId, name, jwtToken, !video);

    _socket?.onConnect((_) {
      _log('✅ Signaling socket CONNECTED (sid=${_socket?.id})');
      if (!mounted || _disposed) return;
      state = state.copyWith(isConnected: true);

      _loadChatHistory(realMeetingId, userId);
      _loadParticipants(realMeetingId);

      _emitJoin(cleanCode, userId, name, !video);

      if (_chatSocket?.connected ?? false) {
        _emitJoinChat(realMeetingId, userId, jwtToken);
      } else {
        _chatSocket?.once('connect', (_) => _emitJoinChat(realMeetingId, userId, jwtToken));
      }
    });

    _socket?.onConnectError((err) => _log('❌ Signaling CONNECT_ERROR: $err'));
    _socket?.onError((err) => _log('❌ Signaling ERROR: $err'));
    _socket?.onDisconnect((reason) => _log('⚠️ Signaling disconnected: $reason'));
    _socket?.onAny((event, data) => _log('📡 EVENT: $event | DATA: $data'));
  }

  /// Emit join in the format documented by the backend signaling service:
  /// `[code, userId, name, isCameraOff]` (positional args).
  void _emitJoin(String code, String userId, String name, bool isCameraOff) {
    if (_hasJoinedRoom) {
      _log('_emitJoin skipped — already joined');
      return;
    }
    _hasJoinedRoom = true;
    _log('📤 emit join-meeting [$code, $userId, $name, isCameraOff=$isCameraOff]');
    _socket?.emit('join-meeting', [code, userId, name, isCameraOff]);
  }

  void _initSocketListeners(
      String realMeetingId, String userId, String name, String jwtToken, bool isCameraOff) {
    _socket?.on('join-confirmation', (data) async {
      _log('🟢 join-confirmation: $data');
      if (!mounted || _disposed) return;

      // Backend may send a String status or a structured Map.
      if (data is String) {
        if (data == 'WAITING_FOR_APPROVAL' || data == 'WAITING') {
          state = state.copyWith(isInWaitingRoom: true);
        } else if (data == 'JOINED') {
          state = state.copyWith(isConnected: true, isInWaitingRoom: false);
        }
        return;
      }

      if (data is! Map) return;
      final status = data['status']?.toString() ?? 'JOINED';

      if (status == 'WAITING_FOR_APPROVAL' || status == 'WAITING') {
        state = state.copyWith(isInWaitingRoom: true);
        return;
      }

      if (status != 'JOINED' && status != 'ADMITTED') return;

      final participants = (data['participants'] as List<dynamic>?) ?? const [];
      final waitingParticipants = (data['waitingParticipants'] as List<dynamic>?) ?? const [];
      final isHostConfirmed = data['isHost'] == true;

      _log('Existing participants: ${participants.length}, host=$isHostConfirmed');

      state = state.copyWith(
        participants: participants,
        waitingParticipants: waitingParticipants,
        isConnected: true,
        isInWaitingRoom: false,
        isHost: isHostConfirmed || state.isHost,
        hostId: data['hostId']?.toString() ?? state.hostId,
      );

      if (isHostConfirmed) {
        _startWaitingListPolling(realMeetingId);
      }

      // BOOTSTRAP: as the new joiner, initiate offers to every existing
      // participant. This avoids the brittle "host-only initiates" rule
      // and supports guests where host detection is unreliable.
      for (final p in participants) {
        if (p is! Map) continue;
        final remoteSid = p['socketId']?.toString();
        if (remoteSid == null || remoteSid.isEmpty) continue;
        if (remoteSid == _socket?.id) continue;
        _log('Bootstrapping connection to existing participant: $remoteSid');
        await _createPeerConnection(remoteSid, isOfferer: true);
      }
    });

    _socket?.on('request-to-join', (data) {
      _log('🔔 request-to-join: $data');
      if (!mounted || _disposed) return;
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
        state = state.copyWith(
            waitingParticipants: [...state.waitingParticipants, newWaiting]);
      }
    });

    _socket?.on('waiting-list-update', (data) {
      if (!mounted || _disposed) return;
      List<dynamic> waitingList = const [];
      if (data is List) {
        waitingList = data;
      } else if (data is Map && data['waitingParticipants'] != null) {
        waitingList = data['waitingParticipants'] as List;
      }
      state = state.copyWith(waitingParticipants: waitingList);
    });

    _socket?.on('user-joined', (data) {
      _log('👋 user-joined: $data');
      if (!mounted || _disposed) return;

      Map<String, dynamic>? newParticipant;
      if (data is Map) {
        newParticipant = Map<String, dynamic>.from(data);
      } else if (data is List && data.isNotEmpty && data.first is Map) {
        newParticipant = Map<String, dynamic>.from(data.first as Map);
      }
      if (newParticipant == null) return;

      final remoteSid = newParticipant['socketId']?.toString();
      if (remoteSid == null || remoteSid.isEmpty) return;
      if (remoteSid == _socket?.id) return; // ignore self echo

      final exists = state.participants.any((p) => p['socketId'] == remoteSid);
      if (!exists) {
        state = state.copyWith(participants: [...state.participants, newParticipant]);
      }

      // We do NOT initiate here. The new joiner is responsible for offering
      // to all existing participants (see join-confirmation handler). This
      // prevents glare (both sides offering simultaneously).
    });

    _socket?.on('user-left', (data) {
      _log('👋 user-left: $data');
      if (!mounted || _disposed) return;
      final socketId = data is Map ? data['socketId']?.toString() : data?.toString();
      if (socketId == null) return;
      final updated = state.participants.where((p) => p['socketId'] != socketId).toList();
      state = state.copyWith(participants: updated);
      _teardownPeer(socketId);
    });

    _socket?.on('offer', (data) async {
      _log('📥 offer ← from=${data is Map ? data['from'] : '?'}');
      if (data is! Map) return;
      final from = data['from']?.toString();
      final offer = data['offer'];
      if (from == null || offer == null) return;
      await _handleOffer(from, offer);
    });

    _socket?.on('answer', (data) async {
      _log('📥 answer ← from=${data is Map ? data['from'] : '?'}');
      if (data is! Map) return;
      final from = data['from']?.toString();
      final answer = data['answer'];
      if (from == null || answer == null) return;
      await _handleAnswer(from, answer);
    });

    _socket?.on('ice-candidate', (data) async {
      if (data is! Map) return;
      final from = data['from']?.toString();
      final candidate = data['candidate'];
      if (from == null || candidate == null) return;
      await _handleIceCandidate(from, candidate);
    });

    _socket?.on('switch-to-sfu', (_) {
      _log('🔁 switch-to-sfu requested by server');
      if (!mounted || _disposed) return;
      state = state.copyWith(isSfuMode: true);
      _setupSfu();
    });

    _chatSocket?.on('chat-receive', _handleNewMessage);
  }

  void _handleNewMessage(data) {
    if (data == null || !mounted || _disposed) return;
    final Map<String, dynamic> msg = Map<String, dynamic>.from(data);
    final formattedMsg = {
      'text': msg['content'] ?? msg['text'] ?? '',
      'sender': msg['senderName'] ?? msg['sender'] ?? 'Unknown',
      'time': msg['time'] ?? msg['createdAt'] ?? DateTime.now().toIso8601String(),
    };
    state = state.copyWith(chatMessages: [...state.chatMessages, formattedMsg]);
  }

  Future<RTCPeerConnection> _createPeerConnection(String remoteSocketId,
      {required bool isOfferer}) async {
    if (_peerConnections.containsKey(remoteSocketId)) {
      _log('PC already exists for $remoteSocketId');
      return _peerConnections[remoteSocketId]!;
    }

    _log('🆕 createPeerConnection for $remoteSocketId (offerer=$isOfferer)');

    final config = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
        {'urls': 'stun:stun1.l.google.com:19302'},
        {'urls': 'stun:stun2.l.google.com:19302'},
        {'urls': 'stun:global.stun.twilio.com:3478'},
      ],
      'sdpSemantics': 'unified-plan',
    };

    final pc = await createPeerConnection(config);
    _peerConnections[remoteSocketId] = pc;
    _pendingIce[remoteSocketId] = [];

    // Attach local tracks BEFORE creating offer/answer.
    if (_localStream != null) {
      for (final track in _localStream!.getTracks()) {
        await pc.addTrack(track, _localStream!);
      }
      _log('Added ${_localStream!.getTracks().length} local tracks to PC[$remoteSocketId]');
    } else {
      _log('⚠️ No local stream when creating PC[$remoteSocketId] — remote will see no media');
    }

    pc.onIceCandidate = (RTCIceCandidate? candidate) {
      if (candidate == null || candidate.candidate == null) return;
      _socket?.emit('ice-candidate', {
        'to': remoteSocketId,
        'candidate': candidate.toMap(),
      });
    };

    pc.onIceConnectionState = (state) {
      _log('ICE[$remoteSocketId] = $state');
    };

    pc.onConnectionState = (state) {
      _log('PC[$remoteSocketId] = $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _log('🔥 PC failed for $remoteSocketId — consider TURN server');
      }
    };

    pc.onTrack = (RTCTrackEvent event) async {
      _log('🎬 onTrack[$remoteSocketId] kind=${event.track.kind} streams=${event.streams.length}');
      if (event.streams.isEmpty || !mounted || _disposed) return;
      final stream = event.streams.first;
      await _attachRemoteStream(remoteSocketId, stream);
    };

    if (isOfferer) {
      try {
        final offer = await pc.createOffer({
          'offerToReceiveAudio': 1,
          'offerToReceiveVideo': 1,
        });
        await pc.setLocalDescription(offer);
        _log('📤 emit offer → $remoteSocketId');
        _socket?.emit('offer', {
          'to': remoteSocketId,
          'offer': offer.toMap(),
        });
      } catch (e) {
        _log('❌ createOffer error for $remoteSocketId: $e');
      }
    }

    return pc;
  }

  Future<void> _attachRemoteStream(String remoteSocketId, MediaStream stream) async {
    final existingStream = _remoteStreams[remoteSocketId];
    if (existingStream?.id == stream.id && state.remoteRenderers.containsKey(remoteSocketId)) {
      // Same stream firing for additional track (e.g. audio after video).
      // Renderer already shows it — nothing to do.
      _log('Stream ${stream.id} already attached for $remoteSocketId');
      return;
    }

    var renderer = state.remoteRenderers[remoteSocketId];
    if (renderer == null) {
      renderer = RTCVideoRenderer();
      await renderer.initialize();
    }
    renderer.srcObject = stream;
    _remoteStreams[remoteSocketId] = stream;

    state = state.copyWith(
      remoteRenderers: {
        ...state.remoteRenderers,
        remoteSocketId: renderer,
      },
    );
    _log('✅ Attached stream ${stream.id} → renderer for $remoteSocketId');
  }

  Future<void> _handleOffer(String from, dynamic offerMap) async {
    final pc = await _createPeerConnection(from, isOfferer: false);
    try {
      final offer = RTCSessionDescription(offerMap['sdp'], offerMap['type']);
      await pc.setRemoteDescription(offer);
      await _drainPendingIce(from);

      final answer = await pc.createAnswer({
        'offerToReceiveAudio': 1,
        'offerToReceiveVideo': 1,
      });
      await pc.setLocalDescription(answer);
      _log('📤 emit answer → $from');
      _socket?.emit('answer', {
        'to': from,
        'answer': answer.toMap(),
      });
    } catch (e) {
      _log('❌ _handleOffer error from $from: $e');
    }
  }

  Future<void> _handleAnswer(String from, dynamic answerMap) async {
    final pc = _peerConnections[from];
    if (pc == null) {
      _log('⚠️ answer from $from but no PC');
      return;
    }
    try {
      final answer = RTCSessionDescription(answerMap['sdp'], answerMap['type']);
      await pc.setRemoteDescription(answer);
      await _drainPendingIce(from);
    } catch (e) {
      _log('❌ _handleAnswer error from $from: $e');
    }
  }

  Future<void> _handleIceCandidate(String from, dynamic candidateMap) async {
    final candidate = RTCIceCandidate(
      candidateMap['candidate'],
      candidateMap['sdpMid'],
      candidateMap['sdpMLineIndex'] is int
          ? candidateMap['sdpMLineIndex']
          : (candidateMap['sdpMLineIndex'] as num?)?.toInt(),
    );
    final pc = _peerConnections[from];
    if (pc == null) {
      _log('⚠️ ICE from unknown peer $from — queuing');
      _pendingIce.putIfAbsent(from, () => []).add(candidate);
      return;
    }
    final remote = await pc.getRemoteDescription();
    if (remote == null) {
      _log('🧊 ICE before remote desc for $from — queuing');
      _pendingIce.putIfAbsent(from, () => []).add(candidate);
      return;
    }
    try {
      await pc.addCandidate(candidate);
    } catch (e) {
      _log('❌ addCandidate error for $from: $e');
    }
  }

  Future<void> _drainPendingIce(String from) async {
    final queue = _pendingIce[from];
    if (queue == null || queue.isEmpty) return;
    final pc = _peerConnections[from];
    if (pc == null) return;
    _log('🧊 draining ${queue.length} pending ICE for $from');
    for (final c in queue) {
      try {
        await pc.addCandidate(c);
      } catch (e) {
        _log('❌ drain addCandidate: $e');
      }
    }
    queue.clear();
  }

  Future<void> _setupMedia({bool video = true, bool audio = true}) async {
    try {
      final constraints = {
        'audio': audio,
        'video': video
            ? {
                'facingMode': 'user',
                'width': {'ideal': 1280},
                'height': {'ideal': 720},
              }
            : false,
      };

      final stream = await navigator.mediaDevices.getUserMedia(constraints);
      _localStream = stream;
      state.localRenderer.srcObject = stream;
      _log('🎥 getUserMedia OK — tracks=${stream.getTracks().map((t) => t.kind).join(",")}');

      if (mounted && !_disposed) {
        state = state.copyWith(isCameraOn: video, isMicOn: audio);
      }

      // If PCs already exist (rare race), add the new tracks.
      for (final pc in _peerConnections.values) {
        for (final track in stream.getTracks()) {
          await pc.addTrack(track, stream);
        }
      }
    } catch (e) {
      _log('❌ getUserMedia failed: $e');
    }
  }

  void admitParticipant(String socketId) {
    _log('📤 admit-user $socketId');
    _socket?.emit('admit-user', {'socketId': socketId});
    if (mounted && !_disposed) {
      final updatedList =
          state.waitingParticipants.where((p) => p['socketId'] != socketId).toList();
      state = state.copyWith(waitingParticipants: updatedList);
    }
  }

  void denyParticipant(String socketId) {
    _log('📤 deny-user $socketId');
    _socket?.emit('deny-user', {'socketId': socketId});
    if (mounted && !_disposed) {
      final updatedList =
          state.waitingParticipants.where((p) => p['socketId'] != socketId).toList();
      state = state.copyWith(waitingParticipants: updatedList);
    }
  }

  void toggleMic() {
    if (_localStream == null) return;
    final tracks = _localStream!.getAudioTracks();
    if (tracks.isEmpty) return;
    tracks.first.enabled = !tracks.first.enabled;
    state = state.copyWith(isMicOn: tracks.first.enabled);
  }

  void toggleCamera() {
    if (_localStream == null) return;
    final tracks = _localStream!.getVideoTracks();
    if (tracks.isEmpty) return;
    tracks.first.enabled = !tracks.first.enabled;
    state = state.copyWith(isCameraOn: tracks.first.enabled);
  }

  void switchCamera() async {
    if (_localStream == null) return;
    final track = _localStream!.getVideoTracks().first;
    await Helper.switchCamera(track);
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

  void muteAll() => _socket?.emit('mute-all');

  void endMeetingForAll() {
    _socket?.emit('end-meeting-for-all');
    leaveMeeting();
  }

  void toggleLockMeeting(bool lock) => _socket?.emit('lock-meeting', {'lock': lock});

  void updateParticipantPermissions(String key, bool value) =>
      _socket?.emit('update-settings', {'key': key, 'value': value});

  void _teardownPeer(String socketId) {
    _peerConnections[socketId]?.close();
    _peerConnections.remove(socketId);
    _pendingIce.remove(socketId);
    _remoteStreams.remove(socketId);
    final renderer = state.remoteRenderers[socketId];
    if (renderer != null) {
      renderer.srcObject = null;
      renderer.dispose();
      final updated = Map<String, RTCVideoRenderer>.from(state.remoteRenderers)
        ..remove(socketId);
      state = state.copyWith(remoteRenderers: updated);
    }
  }

  void leaveMeeting() {
    _log('leaveMeeting');
    _waitingListTimer?.cancel();
    _socket?.disconnect();
    _chatSocket?.disconnect();
    _mediaSocket?.disconnect();
    for (final pc in _peerConnections.values) {
      pc.close();
    }
    _peerConnections.clear();
    _pendingIce.clear();
    _remoteStreams.clear();
    for (final r in state.remoteRenderers.values) {
      r.srcObject = null;
      r.dispose();
    }
    _localStream?.getTracks().forEach((t) => t.stop());
    _localStream?.dispose();
    _localStream = null;
    _networkResilienceService?.dispose();
    _sfuService?.dispose();
    _hasJoinedRoom = false;
  }

  void _startWaitingListPolling(String meetingId) {
    _waitingListTimer?.cancel();
    _waitingListTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (!mounted || _disposed) {
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
    if (mounted && !_disposed) {
      state = state.copyWith(waitingParticipants: list);
    }
  }

  void _loadChatHistory(String meetingId, String userId) async {
    final history = await _chatRepository.getChatHistory(meetingId, userId);
    if (mounted && !_disposed) {
      final formatted = history
          .map((m) => {
                'text': m['content'] ?? m['text'] ?? '',
                'sender': m['senderName'] ?? m['sender'] ?? 'Unknown',
                'time': m['createdAt'] ?? m['time'] ?? '',
              })
          .toList();
      state = state.copyWith(chatMessages: formatted);
    }
  }

  void _loadParticipants(String meetingId) async {
    final participants = await _participantRepository.getMeetingParticipants(meetingId);
    if (mounted && !_disposed) {
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
    _disposed = true;
    _waitingListTimer?.cancel();
    leaveMeeting();
    state.localRenderer.dispose();
    super.dispose();
  }
}

final meetingProvider =
    StateNotifierProvider.autoDispose.family<MeetingNotifier, MeetingState, String>(
  (ref, id) => MeetingNotifier(),
);
