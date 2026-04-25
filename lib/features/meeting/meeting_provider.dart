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
import '../../core/services/local_media_service.dart';
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
  SFUService? _sfuService;
  NetworkResilienceService? _networkResilienceService;
  Timer? _waitingListTimer;
  bool _hasJoinedRoom = false;
  bool _disposed = false;
  String? _userName;

  /// Shortcut to the singleton's stream. We never own a MediaStream
  /// at this layer — the service does.
  MediaStream? get _localStream => LocalMediaService.instance.stream;

  // Per-peer state: pc, pending-ice queue, and renderer cache.
  final Map<String, RTCPeerConnection> _peerConnections = {};
  final Map<String, List<RTCIceCandidate>> _pendingIce = {};
  final Map<String, MediaStream?> _remoteStreams = {};

  /// Static stage entry point retained so existing pre-join callers
  /// don't break — now just pre-warms the singleton.
  static void stageLocalStream(MediaStream stream) {
    LocalMediaService.instance.cancelShutdown();
  }

  // The local renderer is owned by LocalMediaService — same instance
  // across every MeetingNotifier ever created, so the texture is
  // never re-initialised when navigating between pre-join and the
  // meeting room.
  MeetingNotifier()
      : super(MeetingState(localRenderer: LocalMediaService.instance.renderer));

  io.Socket? get socket => _socket;

  Future<void> prepareLocalPreview() async {
    await LocalMediaService.instance.initialize(video: true, audio: true);
    if (mounted && !_disposed) {
      state = state.copyWith(isCameraOn: true, isMicOn: true);
    }
  }

  /// Compatibility shim — the singleton now owns the stream so
  /// nothing actually moves. Returns the live stream so the caller
  /// can keep its existing `if (stream != null)` guards.
  MediaStream? releaseLocalStream() => LocalMediaService.instance.stream;

  /// Compatibility shim — the singleton already holds the stream by
  /// the time anyone might call this. Kept so external callers don't
  /// break; ensures the camera shutdown timer is cancelled.
  Future<void> adoptLocalStream(MediaStream stream) async {
    LocalMediaService.instance.cancelShutdown();
  }

  /// Top-level join sequence. Order matters: media MUST be ready before
  /// we open the signaling socket so the first incoming offer/answer
  /// can attach our local tracks.
  void joinMeeting(String meetingId, String userId, String name, String jwtToken,
      {bool video = true, bool audio = true}) async {
    _log('joinMeeting → meetingId=$meetingId userId=$userId name=$name video=$video audio=$audio');
    _userName = name;

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
    _log('Local host match: $hostMatch (hostId=$hostId, userId=$userId)');

    // If we're locally the host, start REST polling for waiting room
    // immediately. The signaling server may or may not push
    // `request-to-join` (auth/edge cases), so polling is the reliable path.
    if (hostMatch) {
      _log('🛎  Starting waiting-room polling (local host match)');
      _startWaitingListPolling(cleanCode);
      // Kick an immediate fetch so the UI updates without waiting 5s.
      refreshWaitingList();
    }

    // 3. CRITICAL: set up local media BEFORE opening signaling socket.
    // _setupMedia now consults the persistent cache and reuses the
    // running camera if it's still alive, avoiding the 3-4 second
    // reopen the user saw between pre-join and the meeting room.
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

    // 4. Open the signaling socket.
    //
    // IMPORTANT: previous attempts created a separate _chatSocket on the
    // SAME URL (`mizdah-backend.ogoul.cloud`). socket_io_client's manager
    // cache reused the signaling manager but the chat OptionBuilder didn't
    // setPath, which mutated `options['path']` to `/socket.io` on the
    // shared manager — and the gateway has no `/socket.io` route, so the
    // WS handshake returned 502 for both sockets. Use ONE socket; chat
    // events ride the same `/signaling-fresh` channel (the gateway only
    // exposes /signaling-fresh and /media-fresh as socket prefixes).
    //
    // Use enableForceNew() to bypass the manager cache entirely, and pass
    // a raw Map so what we set is exactly what the manager gets.
    _log('Building signaling socket → ${ApiConfig.signalingUrl}${ApiConfig.signalingPath}');
    final Map<String, dynamic> sigOpts = {
      'path': ApiConfig.signalingPath,
      'transports': ['websocket', 'polling'],
      'autoConnect': false,
      'forceNew': true,
      'reconnection': true,
      'reconnectionAttempts': 5,
      'reconnectionDelay': 1000,
    };
    _socket = io.io(ApiConfig.signalingUrl, sigOpts);
    _chatSocket = _socket; // alias — chat events go through the same socket

    // Attach lifecycle handlers FIRST so we never miss the first connect
    // or connect_error.
    _socket?.onConnect((_) {
      _log('✅ Signaling socket CONNECTED (sid=${_socket?.id})');
      if (!mounted || _disposed) return;
      state = state.copyWith(isConnected: true);

      _loadChatHistory(realMeetingId, userId);
      _loadParticipants(realMeetingId);
      _emitJoin(cleanCode, userId, name, !video);
      _emitJoinChat(realMeetingId, userId, jwtToken);
      // Tell the room our initial mic/camera state so peers don't
      // render us with their default (muted/no-video) assumption.
      Future.delayed(const Duration(milliseconds: 500), _broadcastMediaState);
    });

    _socket?.onConnectError((err) => _log('❌ Signaling CONNECT_ERROR: $err'));
    _socket?.onError((err) => _log('❌ Signaling ERROR: $err'));
    _socket?.onDisconnect((reason) => _log('⚠️ Signaling disconnected: $reason'));
    _socket?.onAny((event, data) => _log('📡 EVENT: $event | DATA: $data'));

    _initSocketListeners(realMeetingId, userId, name, jwtToken, !video);

    // Verify the manager actually has the path we asked for. If you ever
    // see this log say `/socket.io` instead of `/signaling-fresh`, the
    // option propagation is broken and we'd see the 502s from before.
    _log('Manager opts.path=${_socket?.io.options?['path']} '
        'transports=${_socket?.io.options?['transports']}');

    _log('Connecting signaling socket now…');
    _socket?.connect();

    for (final secs in [1, 3, 8]) {
      Future.delayed(Duration(seconds: secs), () {
        if (!mounted || _disposed) return;
        _log('⏱  t=${secs}s: signaling.connected=${_socket?.connected} '
            'sid=${_socket?.id}');
      });
    }
  }

  /// Emit join in the format used by the working test scripts:
  /// `socket.emit("join-meeting", code, userId, name, isCameraOff)` — passed
  /// from Dart as a List which socket_io_client v3 spreads as variadic args.
  /// If the server doesn't respond with `join-confirmation` within 4 s we
  /// log loudly so the issue is visible in the device log.
  void _emitJoin(String code, String userId, String name, bool isCameraOff) {
    if (_hasJoinedRoom) {
      _log('_emitJoin skipped — already joined');
      return;
    }
    _hasJoinedRoom = true;
    _log('📤 emit join-meeting [$code, $userId, $name, isCameraOff=$isCameraOff]');
    _socket?.emit('join-meeting', [code, userId, name, isCameraOff]);

    // Silent-failure detector. If the server never sends join-confirmation,
    // either it didn't receive our emit or our payload is malformed.
    Future.delayed(const Duration(seconds: 4), () {
      if (!mounted || _disposed) return;
      if (state.isConnected && state.participants.isEmpty && !state.isInWaitingRoom) {
        _log('⚠️  No join-confirmation 4 s after emit — server silently dropped join-meeting');
        _log('    → check (1) server log for join handler, (2) auth middleware, (3) payload shape');
      }
    });
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
        refreshWaitingList();
      }

      // We are the NEW joiner here. Per the backend protocol
      // (TECHNICAL_DOCUMENTATION.md §5) existing participants will
      // initiate offers to us via the `user-joined` event they receive.
      // We simply wait for those offers — initiating from this side
      // would cause SDP "glare" (both peers offering simultaneously).
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

    _socket?.on('user-joined', (data) async {
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

      // We're an EXISTING participant; the joiner is the one we need
      // to reach. Per the backend protocol we initiate the offer.
      // (TECHNICAL_DOCUMENTATION.md §5: H -> S: emit offer to P)
      _log('Initiating offer to new participant $remoteSid');
      await _createPeerConnection(remoteSid, isOfferer: true);

      // Re-announce our media state so the new joiner doesn't default
      // their UI to "muted / camera off". Without this, the host's
      // initial mic+cam=on broadcast (fired 500ms after their own
      // connect) is lost — the web user wasn't in the room yet, and
      // socket.io doesn't replay events on connect.
      _broadcastMediaState();
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

    // Peers announce mic/camera/screen-share state changes via this
    // event. We mirror it onto the matching `participants` entry so
    // the grid can swap between live video and an avatar tile when
    // a remote turns their camera off (otherwise the renderer keeps
    // showing the last frame, which the user reported as "stuck").
    _socket?.on('media-toggle-remote', (data) {
      if (!mounted || _disposed || data is! Map) return;
      final from = data['from']?.toString();
      if (from == null) return;
      final updated = state.participants.map((p) {
        if (p is Map && p['socketId'] == from) {
          final m = Map<String, dynamic>.from(p);
          if (data.containsKey('audioEnabled')) m['audioEnabled'] = data['audioEnabled'];
          if (data.containsKey('videoEnabled')) m['videoEnabled'] = data['videoEnabled'];
          if (data.containsKey('isSharing')) m['isSharing'] = data['isSharing'];
          if (data.containsKey('name')) m['name'] = data['name'] ?? m['name'];
          return m;
        }
        return p;
      }).toList();
      try {
        state = state.copyWith(participants: updated);
      } catch (_) {}
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

    // STUN alone can't punch holes between two peers behind symmetric
    // NATs (typical on mobile carrier networks). Without a TURN relay
    // ICE ends up in `failed`, peer connections form but no media
    // flows — exactly the "everyone shows as avatar, no video" the user
    // reported. openrelay.metered.ca is a free public TURN suitable
    // for development; replace with a private TURN before production.
    final config = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
        {'urls': 'stun:stun1.l.google.com:19302'},
        {'urls': 'stun:stun2.l.google.com:19302'},
        {'urls': 'stun:global.stun.twilio.com:3478'},
        {
          'urls': 'turn:openrelay.metered.ca:80',
          'username': 'openrelayproject',
          'credential': 'openrelayproject',
        },
        {
          'urls': 'turn:openrelay.metered.ca:443',
          'username': 'openrelayproject',
          'credential': 'openrelayproject',
        },
        {
          'urls': 'turn:openrelay.metered.ca:443?transport=tcp',
          'username': 'openrelayproject',
          'credential': 'openrelayproject',
        },
      ],
      'sdpSemantics': 'unified-plan',
      'iceTransportPolicy': 'all',
      'bundlePolicy': 'max-bundle',
      'rtcpMuxPolicy': 'require',
    };

    final pc = await createPeerConnection(config);
    _peerConnections[remoteSocketId] = pc;
    _pendingIce[remoteSocketId] = [];

    // Attach local tracks BEFORE creating offer/answer.
    if (_localStream != null) {
      final tracks = _localStream!.getTracks();
      for (final track in tracks) {
        try {
          // Some flutter_webrtc builds need the track explicitly enabled
          // before addTrack — otherwise the resulting RTPSender ends up
          // with direction=recvonly and the remote never gets media.
          track.enabled = true;
          final sender = await pc.addTrack(track, _localStream!);
          _log('  + addTrack ${track.kind} id=${track.id} '
              'enabled=${track.enabled} sender=${sender.senderId}');
        } catch (e) {
          _log('  ❌ addTrack ${track.kind} failed: $e');
        }
      }
      _log('Added ${tracks.length} local tracks to PC[$remoteSocketId]');
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

    pc.onIceConnectionState = (iceState) {
      _log('ICE[$remoteSocketId] = $iceState');
      if (iceState == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        _log('🔥 ICE failed — restarting');
        _restartIce(remoteSocketId);
      }
    };

    pc.onConnectionState = (pcState) {
      _log('PC[$remoteSocketId] = $pcState');
      if (pcState == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _log('🔥 PC failed for $remoteSocketId — restarting ICE');
        _restartIce(remoteSocketId);
      }
    };

    pc.onTrack = (RTCTrackEvent event) async {
      _log('🎬 onTrack[$remoteSocketId] kind=${event.track.kind} '
          'streams=${event.streams.length} trackId=${event.track.id}');
      if (!mounted || _disposed) return;
      MediaStream stream;
      if (event.streams.isNotEmpty) {
        stream = event.streams.first;
      } else {
        // Unified-plan / addTransceiver path: tracks can arrive without
        // an associated stream. Build one so the renderer has a srcObject.
        final synthetic = await createLocalMediaStream('remote-$remoteSocketId');
        await synthetic.addTrack(event.track);
        stream = synthetic;
        _log('   built synthetic stream ${stream.id} for $remoteSocketId');
      }
      await _attachRemoteStream(remoteSocketId, stream);
    };

    // Some flutter_webrtc builds fire onAddStream instead of (or in
    // addition to) onTrack. Cover both paths.
    pc.onAddStream = (MediaStream stream) async {
      _log('🎬 onAddStream[$remoteSocketId] streamId=${stream.id} '
          'tracks=${stream.getTracks().map((t) => t.kind).join(",")}');
      if (!mounted || _disposed) return;
      await _attachRemoteStream(remoteSocketId, stream);
    };

    if (isOfferer) {
      try {
        final offer = await pc.createOffer({
          'offerToReceiveAudio': 1,
          'offerToReceiveVideo': 1,
        });
        await pc.setLocalDescription(offer);
        // Surface the m-lines so we can confirm the offer carries the
        // expected `m=video` / `m=audio` sections — if either is
        // missing the remote side will never get our media.
        final mLines = (offer.sdp ?? '')
            .split('\n')
            .where((l) => l.startsWith('m='))
            .join(' | ');
        _log('📤 emit offer → $remoteSocketId  m=[$mLines]');
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
      await LocalMediaService.instance.initialize(video: video, audio: audio);
      if (mounted && !_disposed) {
        state = state.copyWith(isCameraOn: video, isMicOn: audio);
      }
      // If PCs already exist (rare race), add the new tracks.
      final stream = LocalMediaService.instance.stream;
      if (stream != null) {
        for (final pc in _peerConnections.values) {
          for (final track in stream.getTracks()) {
            await pc.addTrack(track, stream);
          }
        }
      }
    } catch (e) {
      _log('❌ _setupMedia failed: $e');
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
    final newState = LocalMediaService.instance.toggleAudio();
    state = state.copyWith(isMicOn: newState);
    _broadcastMediaState();
  }

  void toggleCamera() {
    final newState = LocalMediaService.instance.toggleVideo();
    state = state.copyWith(isCameraOn: newState);
    _broadcastMediaState();
  }

  /// Tell the rest of the room what our mic / camera / screen share
  /// state is. Important: the event we EMIT is `media-toggle` (the
  /// server adds `from` and re-broadcasts to other clients as
  /// `media-toggle-remote`). The previous version emitted
  /// `media-toggle-remote` directly — the server did NOT relay it,
  /// so peers' UIs never updated and the mute icon stayed stuck.
  void _broadcastMediaState() {
    final cameraTrackId = _localStream?.getVideoTracks().isNotEmpty == true
        ? _localStream!.getVideoTracks().first.id
        : null;
    final payload = {
      'meetingId': state.meetingId,
      'type': 'MEDIA_TOGGLE',
      'name': _userName,
      'audioEnabled': state.isMicOn,
      'videoEnabled': state.isCameraOn,
      'isSharing': state.isScreenSharing,
      'isHandRaised': false,
      'cameraVideoTrackId': cameraTrackId,
    };
    _log('📤 emit media-toggle audio=${state.isMicOn} video=${state.isCameraOn}');
    _socket?.emit('media-toggle', payload);
    // Belt-and-suspenders: some signaling implementations expose only
    // the -remote name. Sending both is harmless to a server that
    // expects just one.
    _socket?.emit('media-toggle-remote', payload);
  }

  void switchCamera() async {
    await LocalMediaService.instance.switchCamera();
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

  Future<void> _restartIce(String remoteSocketId) async {
    final pc = _peerConnections[remoteSocketId];
    if (pc == null) return;
    try {
      final offer = await pc.createOffer({'iceRestart': true});
      await pc.setLocalDescription(offer);
      _socket?.emit('offer', {
        'to': remoteSocketId,
        'offer': offer.toMap(),
      });
      _log('🔄 ICE restart offer sent → $remoteSocketId');
    } catch (e) {
      _log('❌ ICE restart failed: $e');
    }
  }

  void leaveMeeting() {
    // Show 1 frame of stack so we can tell whether a stray timer / a
    // route pop / an explicit hangup tore down the meeting. The user
    // saw the meeting "freeze after a few minutes" with no obvious
    // reason for the disconnect.
    final caller = StackTrace.current.toString().split('\n').skip(1).take(2).join(' | ');
    _log('leaveMeeting ← $caller');
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
    // Don't touch the local camera here — the LocalMediaService owns
    // it. Schedule a delayed shutdown so the next screen (re-create
    // an instant meeting, return to home) gets a free camera reuse.
    LocalMediaService.instance.scheduleShutdown();
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
    if (!mounted || _disposed) return;
    final code = state.meetingCode;
    if (code == null) return;
    var list = await _meetingRepository.getWaitingParticipants(code);
    if (!mounted || _disposed) return;
    if (list == null && code.contains('-')) {
      list = await _meetingRepository.getWaitingParticipants(code.replaceAll('-', ''));
    }
    if (!mounted || _disposed) return;
    if (list == null) {
      _log('🛎  Waiting-room REST unavailable — disabling poll, using sockets only');
      _waitingListTimer?.cancel();
      _waitingListTimer = null;
      return;
    }
    _log('🛎  Waiting-room poll → ${list.length} participants');
    // Wrap the assignment: a Riverpod consumer of this provider may have
    // unmounted between the guard above and the synchronous listener
    // notification below (e.g. during navigation). Disposed/defunct
    // listeners would otherwise crash the runtime.
    try {
      state = state.copyWith(waitingParticipants: list);
    } catch (e) {
      _log('refreshWaitingList: state set skipped ($e)');
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
      // The participant service includes the current user in its list.
      // Adding ourselves to `participants` makes the grid render a self
      // tile (avatar "A — akbar") on top of the PIP, then snap back to
      // the solitary hero view when join-confirmation lands with the
      // server's authoritative list — that's the flicker the user saw.
      final filtered = participants.where((p) {
        if (p is! Map) return true;
        return p['userId'] != state.userId &&
            p['user_id'] != state.userId;
      }).toList();
      state = state.copyWith(participants: filtered);
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
    // DON'T dispose state.localRenderer — it's the singleton's. Doing
    // so here would tear down the texture used by every other screen
    // and the *next* MeetingNotifier instance.
    super.dispose();
  }
}

final meetingProvider =
    StateNotifierProvider.autoDispose.family<MeetingNotifier, MeetingState, String>(
  (ref, id) => MeetingNotifier(),
);
