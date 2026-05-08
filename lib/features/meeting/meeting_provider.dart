import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show MethodChannel, PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../../data/repositories/chat_repository.dart';
import '../../core/config/api_config.dart';
import '../../data/repositories/participant_repository.dart';
import '../../core/services/sfu_service.dart';
import '../../core/services/network_resilience_service.dart';
import '../../core/services/local_media_service.dart';
import '../../data/repositories/meeting_repository.dart';

// Tag for filtering WebRTC/signaling logs in production builds.
const String _kLogTag = '[MEET]';
void _log(String msg) => debugPrint('$_kLogTag $msg');

/// Coarse-grained call phase. UI watches this instead of inferring
/// state from a half-dozen booleans, which makes the transitions
/// (placeholder → live tile, hangup → cleanup) reliably one-shot.
enum MeetingPhase {
  idle,        // initial, before joinMeeting fires
  connecting,  // sockets opening, REST validate, getUserMedia
  inMeeting,   // join-confirmation JOINED
  ended,       // user hung up or remote ended the call
}

/// One transient reaction that floats up over the meeting view for a
/// few seconds before being removed.
class ReactionEvent {
  final String emoji;
  final String name;
  final DateTime at;
  ReactionEvent({required this.emoji, required this.name, required this.at});
}

class MeetingState {
  final bool isConnected;
  final RTCVideoRenderer localRenderer;
  final Map<String, RTCVideoRenderer> remoteRenderers;
  /// Per-peer screen-share renderers, keyed by socketId. Separate
  /// from `remoteRenderers` because a presenting peer publishes
  /// camera AND screen as TWO distinct mediasoup producers — the
  /// camera goes onto remoteRenderers[socketId] and the screen
  /// goes here. The grid surfaces them as TWO tiles ("uyf" and
  /// "uyf · Presenting") rather than swapping the camera tile.
  /// Without this split the renderer plays whichever track was
  /// attached last and the other one disappears — exactly the bug
  /// the user reported when a web peer started sharing.
  final Map<String, RTCVideoRenderer> remoteScreenRenderers;
  /// Renderer attached to the LOCAL screen-share stream. Non-null
  /// only while the local user is presenting; the grid surfaces it
  /// as a dedicated tile so the host can see what they're sharing.
  final RTCVideoRenderer? screenRenderer;
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

  /// Local user has the "raise hand" indicator on. Broadcast to
  /// peers via media-toggle so their grid tile shows the badge.
  final bool isHandRaised;

  final int mockParticipantCount;
  final String? meetingId;
  final String? meetingCode;
  final String? userId;
  final MeetingPhase phase;
  final List<ReactionEvent> reactions;
  /// Most recently received message FROM ANOTHER PARTICIPANT, used to
  /// flash a small banner over the video (Google Meet's "Mustafa: hi"
  /// toast). Null after the toast auto-dismisses.
  final Map<String, dynamic>? incomingChatToast;

  /// Inbound remote-control request — set when another participant
  /// asks to control our screen. UI surfaces the grant/deny dialog
  /// while non-null. Cleared after we respond.
  final Map<String, dynamic>? incomingControlRequest;
  /// SocketId of the participant we've granted control to (we're the
  /// presenter being controlled). Null when no one has control.
  final String? controllingPeerSocketId;
  /// SocketId of the participant currently granting us control of
  /// their screen (we're the controller). Null when we don't have
  /// control of anyone.
  final String? controlOfPeerSocketId;

  /// Latest audio activity level per participant, normalised 0..1.
  /// Keyed by socketId for remotes; the local user is keyed under
  /// `'local'`. Drives the voice-wave indicator on each tile —
  /// stays at 0 while the speaker is silent and ramps up while
  /// they're talking.
  final Map<String, double> audioLevels;

  /// "On the go" mode — Google Meet's compact UI for use while
  /// moving (e.g. driving). Hides the video grid, shows oversized
  /// mic / cam / hangup buttons, and de-emphasises chat. Local
  /// preference only — no socket emission. Toggled from the More
  /// options sheet.
  final bool isOnTheGoMode;

  /// True while the meeting is being recorded server-side (any
  /// participant — the host kicked off the recording, but all
  /// participants need to know so the REC indicator + "this
  /// meeting is being recorded" banner show. Driven by
  /// `recording-started` / `recording-stopped` socket events from
  /// the backend. See docs/RECORDING_BACKEND.md.
  final bool isRecordingActive;

  /// The id of the active recording, when [isRecordingActive] is
  /// true. Used for the recordings list screen "currently being
  /// recorded" badge.
  final String? activeRecordingId;

  /// Display name of whoever started the active recording. Shown
  /// in the consent banner so participants know who initiated.
  final String? recordingHostName;

  MeetingState({
    this.isConnected = false,
    required this.localRenderer,
    this.remoteRenderers = const {},
    this.remoteScreenRenderers = const {},
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
    this.isHandRaised = false,
    this.phase = MeetingPhase.idle,
    this.reactions = const [],
    this.incomingChatToast,
    this.screenRenderer,
    this.incomingControlRequest,
    this.controllingPeerSocketId,
    this.controlOfPeerSocketId,
    this.audioLevels = const {},
    this.isOnTheGoMode = false,
    this.isRecordingActive = false,
    this.activeRecordingId,
    this.recordingHostName,
  });

  MeetingState copyWith({
    bool? isConnected,
    Map<String, RTCVideoRenderer>? remoteRenderers,
    Map<String, RTCVideoRenderer>? remoteScreenRenderers,
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
    bool? isHandRaised,
    MeetingPhase? phase,
    List<ReactionEvent>? reactions,
    Map<String, dynamic>? incomingChatToast,
    bool clearChatToast = false,
    RTCVideoRenderer? screenRenderer,
    bool clearScreenRenderer = false,
    Map<String, dynamic>? incomingControlRequest,
    bool clearIncomingControlRequest = false,
    String? controllingPeerSocketId,
    bool clearControllingPeer = false,
    String? controlOfPeerSocketId,
    bool clearControlOfPeer = false,
    Map<String, double>? audioLevels,
    bool? isOnTheGoMode,
    bool? isRecordingActive,
    String? activeRecordingId,
    bool clearActiveRecordingId = false,
    String? recordingHostName,
    bool clearRecordingHostName = false,
  }) {
    return MeetingState(
      isConnected: isConnected ?? this.isConnected,
      localRenderer: localRenderer,
      remoteRenderers: remoteRenderers ?? this.remoteRenderers,
      remoteScreenRenderers:
          remoteScreenRenderers ?? this.remoteScreenRenderers,
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
      isHandRaised: isHandRaised ?? this.isHandRaised,
      phase: phase ?? this.phase,
      reactions: reactions ?? this.reactions,
      incomingChatToast: clearChatToast
          ? null
          : (incomingChatToast ?? this.incomingChatToast),
      screenRenderer: clearScreenRenderer
          ? null
          : (screenRenderer ?? this.screenRenderer),
      incomingControlRequest: clearIncomingControlRequest
          ? null
          : (incomingControlRequest ?? this.incomingControlRequest),
      controllingPeerSocketId: clearControllingPeer
          ? null
          : (controllingPeerSocketId ?? this.controllingPeerSocketId),
      controlOfPeerSocketId: clearControlOfPeer
          ? null
          : (controlOfPeerSocketId ?? this.controlOfPeerSocketId),
      audioLevels: audioLevels ?? this.audioLevels,
      isOnTheGoMode: isOnTheGoMode ?? this.isOnTheGoMode,
      isRecordingActive: isRecordingActive ?? this.isRecordingActive,
      activeRecordingId: clearActiveRecordingId
          ? null
          : (activeRecordingId ?? this.activeRecordingId),
      recordingHostName: clearRecordingHostName
          ? null
          : (recordingHostName ?? this.recordingHostName),
    );
  }
}

class MeetingNotifier extends StateNotifier<MeetingState> {
  final MeetingRepository _meetingRepository = MeetingRepository();
  final ParticipantRepository _participantRepository = ParticipantRepository();
  final ChatRepository _chatRepository = ChatRepository();

  io.Socket? _socket;
  io.Socket? _chatSocket;
  io.Socket? _mediaSocket;
  SFUService? _sfuService;
  NetworkResilienceService? _networkResilienceService;
  Timer? _waitingListTimer;
  /// Polls each peer connection's `getStats()` every ~250ms and
  /// publishes the normalised audio level into `state.audioLevels`
  /// so the per-tile voice-wave widget can animate.
  Timer? _audioLevelTimer;
  bool _hasJoinedRoom = false;
  bool _disposed = false;
  String? _userName;

  /// Public read-only view of the local participant's display name.
  /// Read by the caption service to attribute outgoing transcripts.
  String? get userName => _userName;

  /// Shortcut to the singleton's stream. We never own a MediaStream
  /// at this layer — the service does.
  MediaStream? get _localStream => LocalMediaService.instance.stream;

  // Per-peer state: pc, pending-ice queue, and renderer cache.
  final Map<String, RTCPeerConnection> _peerConnections = {};
  final Map<String, List<RTCIceCandidate>> _pendingIce = {};
  final Map<String, MediaStream?> _remoteStreams = {};
  // Cross-channel sid mapping for the SFU's split signaling/media
  // sockets. Key: signaling sid (from `from:` in media-toggle events,
  // and the canonical participant key). Value: media sid (from
  // producer.appData.socketId — the original `remoteRenderers` key
  // before we add the signaling-sid alias).
  // Used during teardown so we can remove BOTH map entries when a
  // peer leaves — without this, disposing the renderer at one key
  // leaves a stale reference at the other and the next frame's
  // build crashes with "use after dispose", which Flutter renders
  // as a full-screen RED error widget.
  final Map<String, String> _mediaSidBySignalingSid = {};
  final Map<String, String> _signalingSidByMediaSid = {};
  // SocketIds of peers who stopped sharing — their renderer is
  // currently detached to avoid surfacing the cached screen frame.
  // Re-attached on the NEXT media-toggle from them with
  // videoEnabled=true (proves new frames are coming).
  final Set<String> _stoppedSharingPeers = {};

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
  /// Build-stamp baked at commit time so the user can tell from
  /// the device log which build their APK is from. Update this when
  /// shipping a new feature so a screenshot of "[BUILD] sfu-v2"
  /// confirms the bug-fix code is actually running.
  static const String _kBuildStamp = 'sfu-v9 2026-05-08 (alias-cleanup)';

  void joinMeeting(String meetingId, String userId, String name, String jwtToken,
      {bool video = true, bool audio = true, bool isHostHint = false}) async {
    _log('🔖 [BUILD] $_kBuildStamp');
    _log('joinMeeting → meetingId=$meetingId userId=$userId name=$name '
        'video=$video audio=$audio isHostHint=$isHostHint');
    _userName = name;
    if (mounted && !_disposed) {
      state = state.copyWith(phase: MeetingPhase.connecting);
    }

    final cleanCode = meetingId.toLowerCase().trim();

    // ⚡ EARLY BOOTSTRAP — when we have a host hint (i.e. user just
    // created this meeting from pre-join, so we KNOW they're the
    // host), skip the 200ms-3500ms wait on `getMeetingInfo` and fire
    // `_bootstrapSfu()` immediately. The bootstrap can run in parallel
    // with the REST calls below, shaving the perceived "video appears
    // after a few seconds" delay. The actual host check is still done
    // below from the REST response — the hint just unblocks the SFU
    // setup early. If the hint turns out wrong (it shouldn't, since
    // pre-join only sets it when we created the meeting ourselves),
    // _bootstrapSfu's idempotency guard means at worst we did some
    // extra mediasoup work.
    if (isHostHint) {
      if (mounted && !_disposed) {
        state = state.copyWith(
          meetingCode: cleanCode,
          userId: userId,
          isHost: true,
        );
      }
      _log('[SFU] ⚡ EARLY firing _bootstrapSfu() from host hint '
          '(BEFORE REST round-trip)');
      // ignore: unawaited_futures
      _bootstrapSfu();
      // Also start producing local tracks as soon as media is ready —
      // _setupMedia below uses the cached singleton so this race
      // resolves in the bootstrap's favour 99% of the time, but the
      // post-_setupMedia produce kick handles the cold-start case.
    }

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

      // BULLETPROOF SFU bootstrap for hosts — fired right here from
      // joinMeeting(), the moment we know we're the host. Does NOT
      // wait for:
      //   - signaling socket to connect (parallel channels)
      //   - join-confirmation to come back (server sometimes lies)
      //   - the bypass branch in the join-confirmation handler to
      //     fire (depended on isHost being true at the right moment)
      //
      // The `_sfuBootstrapStarted` guard inside `_bootstrapSfu()` makes
      // this safe: whichever path reaches the function first wins,
      // every subsequent call is a no-op. So this can co-exist with
      // BOTH the socket-onConnect trigger AND the join-confirmation
      // bypass trigger — three independent code paths, any one of
      // which is enough to get media working. The bug we keep hitting
      // is "no path triggers" — three paths fixes that.
      _log('[SFU] 🚀 firing _bootstrapSfu() from joinMeeting (host path)');
      // ignore: unawaited_futures
      _bootstrapSfu();
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

    // RACE FIX: with EARLY bootstrap fired before _setupMedia, the
    // SFU may have called _produceLocalTracksToSfu while _localStream
    // was still null — that path silently no-ops. Now that media is
    // up, kick produce again. Idempotent: SFUService.produceAudio /
    // produceVideo are no-ops when the same track is already producing.
    if (state.isSfuMode && _sfuService?.isReady == true) {
      _log('[SFU] kicking _produceLocalTracksToSfu after _setupMedia');
      // ignore: unawaited_futures
      _produceLocalTracksToSfu();
    }

    // Apply default audio routing once we have a stream — the OS
    // doesn't auto-pick speakerphone for VoIP calls, so without
    // this the first joiner hears the remote through the earpiece
    // until they tap the volume icon.
    try {
      await Helper.setSpeakerphoneOn(state.isSpeakerphoneOn);
    } catch (_) {}

    if (_localStream == null) {
      _log('❌ Local media setup failed — aborting join');
      return;
    }

    // Kick off the audio-level poll. Drives the per-tile voice-wave
    // indicator. Cheap (~1ms per tick) but cancelled in leaveMeeting.
    _startAudioLevelPolling();

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

      // Belt-and-suspenders: hosts kick off the SFU bootstrap as
      // soon as the signaling socket is up. We previously gated
      // bootstrap on the join-confirmation handler running, which
      // depended on the server correctly identifying us as the
      // host — but the server has a bug there
      // (see docs/HOST_DETECTION_BACKEND.md), and even though we
      // workaround it in the join-confirmation handler, that
      // workaround can be missed if the server sends a different
      // kind of bad payload, or if the join-confirmation arrives
      // before our handler is wired. SFU is a parallel media
      // channel — it doesn't actually need to wait for the join-
      // confirmation. The `_sfuBootstrapStarted` guard in
      // `_bootstrapSfu()` ensures we don't double-bootstrap if
      // the join-confirmation handler ALSO calls it.
      //
      // We only do this for the LOCAL host (computed from the
      // REST `/api/meeting/<code>` lookup before the socket
      // even connected). Guests still bootstrap from the JOINED
      // branch as before, so guests in the waiting room don't
      // produce media before being admitted.
      if (state.isHost && state.meetingCode != null) {
        _log('[SFU] 🎯 host kicking off bootstrap from socket-onConnect '
            '(belt-and-suspenders — does not wait for join-confirmation)');
        // ignore: unawaited_futures
        Future.delayed(
          const Duration(milliseconds: 200), // tiny grace period for state sync
          _bootstrapSfu,
        );
      }
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

      // BACKEND-BUG WORKAROUND: the server's join-meeting handler
      // doesn't compare the joining userId against meetings.host_id,
      // so it puts the room creator into THEIR OWN waiting room
      // (status WAITING_FOR_APPROVAL with isHost: false). The local
      // hostMatch check in joinMeeting() already knows we're the
      // host — trust that and override. Documented in
      // docs/HOST_DETECTION_BACKEND.md so the BE dev can fix
      // server-side; once they do, this guard becomes a no-op (the
      // server will never send WAITING to a host).
      bool serverFalselyDeniedHost(dynamic d) {
        if (!state.isHost) return false; // genuinely not the host
        if (d is String) return d == 'WAITING_FOR_APPROVAL' || d == 'WAITING';
        if (d is Map) {
          final s = d['status']?.toString();
          return s == 'WAITING_FOR_APPROVAL' || s == 'WAITING';
        }
        return false;
      }

      if (serverFalselyDeniedHost(data)) {
        _log('⚠️  Server put us in waiting room but we ARE the host '
            '— overriding to JOINED locally (backend host-detection bug).');
        state = state.copyWith(
          isConnected: true,
          isInWaitingRoom: false,
          phase: MeetingPhase.inMeeting,
        );
        // Re-run anything that normally fires on a successful host
        // join — including SFU bootstrap. The early return below
        // used to skip _bootstrapSfu() (it lives in the standard
        // JOINED branch ~80 lines down) which left the host stuck
        // in "joined" with no media socket, no producers, no
        // remote video — exactly the "now all not working" report.
        if (state.meetingCode != null && state.userId != null) {
          _startWaitingListPolling(state.meetingCode!);
          refreshWaitingList();
        }
        // Critical: open the media socket and produce local
        // tracks. Without this the host stays mute/black to
        // every other participant.
        // ignore: unawaited_futures
        _bootstrapSfu();
        return;
      }

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

      final rawParticipants = (data['participants'] as List<dynamic>?) ?? const [];
      final waitingParticipants = (data['waitingParticipants'] as List<dynamic>?) ?? const [];
      final isHostConfirmed = data['isHost'] == true;

      // Strip ourselves from the roster before it ever reaches the
      // grid. The backend's join-confirmation payload includes the
      // current user as a participant — we render ourselves through
      // the self-PIP, never as a grid tile, so storing self here was
      // briefly producing the "akbar" avatar tile the user reported.
      final mySocketId = _socket?.id;
      final participants = rawParticipants.where((p) {
        if (p is! Map) return true;
        if (mySocketId != null && p['socketId'] == mySocketId) return false;
        if (p['userId'] == userId || p['user_id'] == userId) return false;
        return true;
      }).toList();

      _log('join-confirmation: ${rawParticipants.length} participants raw, '
          '${participants.length} after self-filter, host=$isHostConfirmed');

      state = state.copyWith(
        participants: participants,
        waitingParticipants: waitingParticipants,
        isConnected: true,
        isInWaitingRoom: false,
        isHost: isHostConfirmed || state.isHost,
        hostId: data['hostId']?.toString() ?? state.hostId,
        phase: MeetingPhase.inMeeting,
      );

      if (isHostConfirmed) {
        _startWaitingListPolling(realMeetingId);
        refreshWaitingList();
      }

      // The web client and the new mediasoup backend exchange media
      // through a separate /media-fresh socket and a mediasoup SFU.
      // Bootstrap that pipeline now — without it mobile can't see (or
      // be seen by) the web client at all. Fire-and-forget: errors
      // are handled inside _bootstrapSfu and leave us on the legacy
      // P2P fallback if SFU init blows up.
      // ignore: unawaited_futures
      _bootstrapSfu();
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

      // SFU mode (always on now): we don't initiate per-peer offers —
      // the new joiner will consume our producers via mediasoup once
      // they call joinMedia and the server replies with
      // existingProducers. Just re-announce our media state so their
      // grid tile shows the right mic/camera badges immediately.
      if (state.isSfuMode) {
        _log('user-joined ($remoteSid) — SFU mode, no P2P offer needed');
        _broadcastMediaState();
        return;
      }

      // Legacy P2P fallback path. Only reached if SFU init failed.
      _log('Initiating offer to new participant $remoteSid');
      await _createPeerConnection(remoteSid, isOfferer: true);
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
      if (state.isSfuMode) return; // SFU mode — ignore stray P2P offers
      _log('📥 offer ← from=${data is Map ? data['from'] : '?'}');
      if (data is! Map) return;
      final from = data['from']?.toString();
      final offer = data['offer'];
      if (from == null || offer == null) return;
      await _handleOffer(from, offer);
    });

    _socket?.on('answer', (data) async {
      if (state.isSfuMode) return;
      _log('📥 answer ← from=${data is Map ? data['from'] : '?'}');
      if (data is! Map) return;
      final from = data['from']?.toString();
      final answer = data['answer'];
      if (from == null || answer == null) return;
      await _handleAnswer(from, answer);
    });

    _socket?.on('ice-candidate', (data) async {
      if (state.isSfuMode) return;
      if (data is! Map) return;
      final from = data['from']?.toString();
      final candidate = data['candidate'];
      if (from == null || candidate == null) return;
      await _handleIceCandidate(from, candidate);
    });

    // Standard reaction relay (Google-Meet style). Backend should
    // relay `send-reaction` (client→server) → `receive-reaction`
    // (server→other clients in room). Listening on a couple of
    // common variants so we don't depend on one exact name.
    void onReaction(dynamic data) {
      if (!mounted || _disposed || data is! Map) return;
      final senderId = (data['userId'] ?? data['senderId'])?.toString();
      if (senderId != null && senderId == state.userId) return;
      final emoji = data['emoji']?.toString();
      final name = data['name']?.toString() ?? data['senderName']?.toString() ?? 'Someone';
      if (emoji == null) return;
      _log('🎉 inbound reaction $emoji from $name');
      _addReaction(emoji, name);
    }
    _socket?.on('receive-reaction', onReaction);
    _socket?.on('reaction-received', onReaction);
    _socket?.on('reaction', onReaction);

    // Web-compatible inbound reaction path. The web client emits
    // REACTIONS via `broadcast-data` (everything not CHAT /
    // MEDIA_TOGGLE / SYNC_STATE / RECORDING_PERMISSION_UPDATE goes
    // through this channel) and the server relays as
    // `broadcast-data-remote`. Without this listener mobile never
    // sees reactions sent from the web. Confirmed against the
    // deployed web bundle on 2026-05-03 — see
    // docs/MORE_OPTIONS_BACKEND.md for the protocol details.
    _socket?.on('broadcast-data-remote', (data) {
      if (!mounted || _disposed || data is! Map) return;
      final type = data['type']?.toString().toUpperCase();
      if (type != 'REACTION') return;
      final from = (data['from'] ?? data['userId'])?.toString();
      // Skip our own echo if the server happens to round-trip it.
      if (from != null && from == _socket?.id) return;
      final reaction =
          data['reaction'] is Map ? data['reaction'] as Map : null;
      final emoji = (reaction?['emoji'] ?? data['emoji'])?.toString();
      final name =
          (data['name'] ?? data['senderName'] ?? 'Someone').toString();
      if (emoji == null || emoji.isEmpty) return;
      _log('🎉 inbound broadcast-data REACTION $emoji from $name');
      _addReaction(emoji, name);
    });

    // The backend uses a single `media-toggle-remote` event for ALL
    // room broadcasts. The `type` field discriminates:
    //   MEDIA_TOGGLE -> mic/camera/screen-share state
    //   CHAT         -> chat message  ({content, name, timestamp})
    //   REACTION     -> floating emoji ({emoji, name})
    // The web client also goes through this channel — that's why my
    // earlier `chat-send` / `reaction` emits never reached anyone.
    _socket?.on('media-toggle-remote', (data) {
      if (!mounted || _disposed || data is! Map) return;
      final from = data['from']?.toString();
      if (from == null) return;
      if (from == _socket?.id) return; // self echo
      final type = data['type']?.toString().toUpperCase() ?? 'MEDIA_TOGGLE';

      switch (type) {
        case 'CHAT':
          _log('💬 inbound CHAT from $from: "${data['content']}" '
              '(name=${data['name']})');
          _handleNewMessage({
            'content': data['content'] ?? data['text'] ?? data['message'],
            'senderName': data['name'] ?? data['senderName'],
            'senderId': data['senderId'] ?? data['userId'] ?? from,
            'createdAt': data['timestamp']?.toString() ??
                data['createdAt']?.toString() ??
                DateTime.now().toIso8601String(),
            'isReaction': data['isReaction'],
          });
          break;

        case 'REACTION':
        case 'EMOJI':
          final emoji = (data['emoji'] ?? data['content'])?.toString();
          final name = (data['name'] ?? data['senderName'] ?? 'Someone').toString();
          _log('🎉 inbound REACTION $emoji from $name');
          if (emoji != null && emoji.isNotEmpty) _addReaction(emoji, name);
          break;

        case 'MEDIA_TOGGLE':
        default:
          // Detect the share-stop transition so we can flush the
          // frozen last screen frame from the remote renderer. The
          // web client typically doesn't replaceTrack(camera) when
          // stopping share, so the renderer's texture would
          // otherwise stay locked on the last screen frame.
          var wasSharing = false;
          for (final p in state.participants) {
            if (p is Map && p['socketId'] == from && p['isSharing'] == true) {
              wasSharing = true;
              break;
            }
          }
          final nowSharing = data['isSharing'] == true;
          final stoppedSharing = wasSharing && !nowSharing;

          final updated = state.participants.map((p) {
            if (p is Map && p['socketId'] == from) {
              final m = Map<String, dynamic>.from(p);
              if (data.containsKey('audioEnabled')) m['audioEnabled'] = data['audioEnabled'];
              // Trust the remote's videoEnabled flag — if their
              // camera is on after stopping share, show the camera
              // (not the avatar). The renderer flush below clears
              // any cached screen frame so new camera frames render
              // cleanly.
              if (data.containsKey('videoEnabled')) {
                m['videoEnabled'] = data['videoEnabled'];
              }
              if (data.containsKey('isSharing')) m['isSharing'] = data['isSharing'];
              if (data.containsKey('isHandRaised')) {
                m['isHandRaised'] = data['isHandRaised'];
              }
              if (data.containsKey('name')) m['name'] = data['name'] ?? m['name'];
              return m;
            }
            return p;
          }).toList();
          try {
            state = state.copyWith(participants: updated);
          } catch (_) {}

          // Reset the renderer when sharing stops so we don't keep
          // showing the cached screen frame. Two cases:
          //
          //   videoEnabled:true  → peer kept their camera on, so we
          //                        flush the texture (null + reattach
          //                        with the same stream) and the
          //                        camera frames paint instantly.
          //   videoEnabled:false → no camera coming, leave the
          //                        renderer detached so the tile
          //                        falls through to the avatar.
          //                        Reattach later if the peer's next
          //                        media-toggle says videoEnabled:true.
          if (stoppedSharing) {
            // Tear down the dedicated screen renderer/stream for
            // this peer. Their camera tile (remoteRenderers[from])
            // is unaffected — separate stream.
            final screenR = state.remoteScreenRenderers[from];
            if (screenR != null) {
              screenR.srcObject = null;
              screenR.dispose();
              state = state.copyWith(
                remoteScreenRenderers:
                    Map<String, RTCVideoRenderer>.from(
                        state.remoteScreenRenderers)
                      ..remove(from),
              );
            }
            _remoteScreenStreams.remove(from);

            // Legacy P2P-mode behaviour: in P2P the camera + screen
            // share the same RTPSender so when share stops we have
            // to flush the cached screen frame from the camera
            // renderer. In SFU mode the camera renderer never had
            // the screen track, so this is a no-op there — but
            // leave it in place for any pre-SFU clients still
            // present in the same room.
            final r = state.remoteRenderers[from];
            final s = _remoteStreams[from];
            if (r != null) {
              r.srcObject = null;
              if (data['videoEnabled'] == true && s != null) {
                Future.delayed(const Duration(milliseconds: 60), () {
                  if (!mounted || _disposed) return;
                  r.srcObject = s;
                });
              } else {
                _stoppedSharingPeers.add(from);
              }
            }
          } else if (_stoppedSharingPeers.contains(from) &&
              data['videoEnabled'] == true) {
            final r = state.remoteRenderers[from];
            final s = _remoteStreams[from];
            if (r != null && s != null) r.srcObject = s;
            _stoppedSharingPeers.remove(from);
          } else if (data.containsKey('videoEnabled')) {
            // CAMERA TOGGLE (NOT a share-stop) — clear the renderer
            // when the peer turned their camera off so we don't keep
            // painting their last frame as a frozen tile, and re-
            // attach when they turn it back on. Without this, the
            // remote video on our screen "sticks" on the last frame
            // even though the peer's videoEnabled is false. The
            // renderer's GPU texture holds the previous frame
            // because no new frames arrive — explicit detach forces
            // it to clear.
            final r = state.remoteRenderers[from];
            final s = _remoteStreams[from];
            if (r != null) {
              if (data['videoEnabled'] == true && s != null) {
                // Camera came back on. Reattach if we previously
                // detached, no-op otherwise.
                if (r.srcObject != s) {
                  _log('🔌 reattaching camera stream for $from '
                      '(videoEnabled=true)');
                  r.srcObject = s;
                }
              } else if (data['videoEnabled'] == false) {
                // Camera went off — flush the frozen frame.
                if (r.srcObject != null) {
                  _log('🧹 detaching camera stream for $from '
                      '(videoEnabled=false) to clear stuck frame');
                  r.srcObject = null;
                }
              }
            }
          }
      }
    });

    // Remote-control protocol. Three events:
    //   request-control       (client → server, target socketId)
    //   control-request       (server → target client; we pop dialog)
    //   control-response      (target → requester; granted bool)
    _socket?.on('control-request', (data) {
      if (!mounted || _disposed || data is! Map) return;
      final from = (data['from'] ?? data['socketId'])?.toString();
      final name = (data['name'] ?? data['senderName'] ?? 'A participant').toString();
      if (from == null) return;
      _log('🖱  control-request from $from ($name)');
      state = state.copyWith(incomingControlRequest: {
        'from': from,
        'name': name,
        'at': DateTime.now().millisecondsSinceEpoch,
      });
    });

    _socket?.on('control-response', (data) {
      if (!mounted || _disposed || data is! Map) return;
      final from = (data['from'] ?? data['socketId'])?.toString();
      final granted = data['granted'] == true;
      _log('🖱  control-response from $from granted=$granted');
      if (granted && from != null) {
        state = state.copyWith(controlOfPeerSocketId: from);
      } else {
        state = state.copyWith(clearControlOfPeer: true);
      }
    });

    _socket?.on('control-revoked', (data) {
      if (!mounted || _disposed) return;
      _log('🖱  control revoked');
      state = state.copyWith(
        clearControllingPeer: true,
        clearControlOfPeer: true,
      );
    });

    // The legacy `switch-to-sfu` event was the old hand-off from
    // peer-to-peer to SFU mid-call. The backend now forwards through
    // mediasoup unconditionally, so we initialise SFU eagerly inside
    // the join-confirmation handler instead of waiting for this event.
    // Kept as a no-op for backwards compatibility with older servers.
    _socket?.on('switch-to-sfu', (_) {
      _log('🔁 switch-to-sfu received (ignored — SFU is initialised eagerly)');
    });

    // Host-initiated room termination. Backend broadcasts this to
    // every participant in the room when the host hangs up. We tear
    // down our peer connections, drop the socket and flip phase to
    // `ended` — the meeting screen watches that and navigates home.
    void onMeetingEnded(_) {
      _log('🛑 meeting ended remotely (host hung up)');
      if (!mounted || _disposed) return;
      state = state.copyWith(phase: MeetingPhase.ended);
      leaveMeeting();
    }
    _socket?.on('end-meeting-for-all', onMeetingEnded);
    _socket?.on('meeting-ended', onMeetingEnded);
    _socket?.on('host-left', onMeetingEnded);

    // ─── Recording lifecycle ─────────────────────────────────────
    // Backend broadcasts these to every socket in the room when
    // recording starts / stops. Drives the REC indicator on every
    // participant's top bar AND the consent banner shown to those
    // who joined after recording was already active. See
    // docs/RECORDING_BACKEND.md for the wire format.
    _socket?.on('recording-started', (data) {
      if (!mounted || _disposed) return;
      _log('🔴 recording-started: $data');
      final map = data is Map ? data : const <String, dynamic>{};
      state = state.copyWith(
        isRecordingActive: true,
        activeRecordingId: map['recordingId']?.toString(),
        recordingHostName:
            (map['hostName'] ?? map['name'])?.toString() ?? 'The host',
        isRecording: state.isHost ? true : state.isRecording,
      );
    });

    _socket?.on('recording-stopped', (data) {
      if (!mounted || _disposed) return;
      _log('⏹  recording-stopped: $data');
      state = state.copyWith(
        isRecordingActive: false,
        clearActiveRecordingId: true,
        clearRecordingHostName: true,
        isRecording: false,
      );
    });

    _socket?.on('recording-ready', (data) {
      if (!mounted || _disposed) return;
      _log('✅ recording-ready: $data');
      // Re-use the chat-toast slot to surface "Recording ready —
      // tap to view" without adding another transient-state field.
      // The meeting screen already renders this toast.
      final map = data is Map ? data : const <String, dynamic>{};
      final url = map['url']?.toString();
      if (url == null) return;
      state = state.copyWith(
        incomingChatToast: {
          'sender': '🎬 Recording ready',
          'text': 'Tap to open the recording',
          'at': DateTime.now().millisecondsSinceEpoch,
          'recordingUrl': url,
          'isRecordingToast': true,
        },
      );
    });

    _socket?.on('recording-failed', (data) {
      if (!mounted || _disposed) return;
      final reason =
          (data is Map ? data['reason']?.toString() : null) ?? 'unknown';
      _log('❌ recording-failed: $reason');
      state = state.copyWith(
        isRecordingActive: false,
        clearActiveRecordingId: true,
        clearRecordingHostName: true,
        isRecording: false,
        incomingChatToast: {
          'sender': '⚠️  Recording failed',
          'text': reason,
          'at': DateTime.now().millisecondsSinceEpoch,
          'isRecordingFailureToast': true,
        },
      );
    });

    _chatSocket?.on('chat-receive', _handleNewMessage);
    _chatSocket?.on('chat-message', _handleNewMessage);
    _chatSocket?.on('new-message', _handleNewMessage);
  }

  void _handleNewMessage(data) {
    if (data == null || !mounted || _disposed) return;
    final Map<String, dynamic> msg = Map<String, dynamic>.from(data);
    // Skip our own messages — we already added them optimistically.
    final senderId = (msg['senderId'] ?? msg['userId'])?.toString();
    if (senderId != null && senderId == state.userId) return;
    final text = (msg['content'] ?? msg['text'] ?? '').toString();
    final sender = (msg['senderName'] ?? msg['sender'] ?? 'Unknown').toString();
    _log('💬 appending chat: "$text" from $sender (total ${state.chatMessages.length + 1})');
    final formattedMsg = {
      'text': text,
      'sender': sender,
      'time': msg['time'] ?? msg['createdAt'] ?? DateTime.now().toIso8601String(),
    };
    final toast = {
      'text': text,
      'sender': sender,
      'at': DateTime.now().millisecondsSinceEpoch,
    };
    state = state.copyWith(
      chatMessages: [...state.chatMessages, formattedMsg],
      incomingChatToast: toast,
    );
    // Auto-dismiss the toast after a few seconds.
    Future.delayed(const Duration(seconds: 4), () {
      if (!mounted || _disposed) return;
      // Only clear if the same toast is still showing — a newer
      // message should not be erased by an older delayed callback.
      if (state.incomingChatToast?['at'] == toast['at']) {
        try {
          state = state.copyWith(clearChatToast: true);
        } catch (_) {}
      }
    });
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

          // Bump encoder bitrate for video senders. WebRTC's default
          // start-bitrate is ~300 kbps which produces visibly blurry
          // 720p — this lets the encoder ramp up to 1.5 Mbps when
          // bandwidth allows, and prefer maintain-resolution so it
          // sacrifices framerate before sharpness when constrained.
          if (track.kind == 'video') {
            try {
              await _tuneVideoSender(sender);
            } catch (e) {
              _log('  ⚠️ tuneVideoSender failed: $e');
            }
          }
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

  /// Bumps a video sender's encoder ceiling so peers see a sharp
  /// stream instead of a blurry low-bitrate fallback. Called once
  /// per peer right after addTrack().
  ///
  /// flutter_webrtc exposes `getParameters` / `setParameters` on
  /// `RTCRtpSender`. We mutate the first encoding's `maxBitrate`
  /// (1.5 Mbps) and `minBitrate` (300 kbps), and request that the
  /// encoder degrade framerate before resolution under congestion
  /// — sharpness matters more than smoothness for a face-on call.
  Future<void> _tuneVideoSender(RTCRtpSender sender) async {
    final params = sender.parameters;
    final encodings = params.encodings;
    if (encodings == null || encodings.isEmpty) {
      // No encoding slot exposed by this build — bail silently.
      return;
    }
    for (final enc in encodings) {
      enc.maxBitrate = 1500 * 1000; // 1.5 Mbps
      enc.minBitrate = 300 * 1000;  // 300 kbps
      enc.maxFramerate = 30;
    }
    params.degradationPreference = RTCDegradationPreference.MAINTAIN_RESOLUTION;
    await sender.setParameters(params);
  }

  /// Polls every peer connection's `getStats()` for `audioLevel`
  /// (normalised 0..1) and folds the result into `state.audioLevels`.
  /// Local mic is keyed under `'local'` (read from outbound /
  /// media-source stats); remotes under their socketId (inbound-rtp).
  ///
  /// 250ms cadence keeps CPU minimal while still feeling reactive
  /// (a normal sentence has ~3-5 syllables a second). Reports we
  /// don't recognise are silently ignored.
  void _startAudioLevelPolling() {
    _audioLevelTimer?.cancel();
    _audioLevelTimer = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => _pollAudioLevels(),
    );
  }

  Future<void> _pollAudioLevels() async {
    if (_disposed || !mounted) return;
    if (_peerConnections.isEmpty) return;

    final next = <String, double>{};
    // Track the last good values so a tile that briefly returns no
    // stats doesn't flicker to silent — we decay slowly instead.
    final prev = state.audioLevels;

    for (final entry in _peerConnections.entries) {
      final socketId = entry.key;
      final pc = entry.value;
      try {
        final reports = await pc.getStats();
        double? remoteLevel;
        double? localLevel;
        for (final r in reports) {
          final v = r.values;
          final kind = (v['kind'] ?? v['mediaType'])?.toString();
          if (kind != 'audio') continue;
          final lvl = v['audioLevel'];
          if (lvl is! num) continue;
          if (r.type == 'inbound-rtp') {
            remoteLevel = (remoteLevel ?? 0).clamp(0.0, 1.0).toDouble();
            if (lvl.toDouble() > remoteLevel) remoteLevel = lvl.toDouble();
          } else if (r.type == 'media-source' || r.type == 'outbound-rtp') {
            localLevel = (localLevel ?? 0).clamp(0.0, 1.0).toDouble();
            if (lvl.toDouble() > localLevel) localLevel = lvl.toDouble();
          }
        }
        if (remoteLevel != null) {
          next[socketId] = remoteLevel;
        } else if (prev.containsKey(socketId)) {
          // Decay toward zero so the wave fades out instead of
          // popping off when stats momentarily skip a frame.
          next[socketId] = (prev[socketId]! * 0.6).clamp(0.0, 1.0);
        }
        if (localLevel != null) {
          // The local level is the same regardless of which PC we
          // read it from, so the last write wins — fine.
          next['local'] = localLevel;
        }
      } catch (_) {
        // getStats can throw on PC teardown — drop the tick.
      }
    }

    if (!mounted || _disposed) return;
    // Only push state if something actually changed beyond a tiny
    // jitter. Avoids re-rendering every tile every 250ms.
    bool changed = next.length != prev.length;
    if (!changed) {
      for (final k in next.keys) {
        if (((next[k] ?? 0) - (prev[k] ?? 0)).abs() > 0.01) {
          changed = true;
          break;
        }
      }
    }
    if (changed) state = state.copyWith(audioLevels: next);
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
    // Recovery path: if the audio track was destroyed mid-call
    // (camera-app stole the input device, OS reclaimed the mic on
    // resume, etc.), `toggleAudio()` would warn `track is null` and
    // do nothing — peers see the user as permanently muted with no
    // way to recover. Re-acquire the local stream first, then
    // re-produce into the SFU so the audio producer picks up the
    // fresh track instead of carrying the dead reference.
    final stream = _localStream;
    final hasLiveAudio = stream != null &&
        stream.getAudioTracks().isNotEmpty &&
        stream.getAudioTracks().first.id != null;
    if (!hasLiveAudio) {
      _log('toggleMic — audio track is null, re-acquiring local media');
      _reacquireLocalMediaAndReproduce();
      return;
    }
    final newState = LocalMediaService.instance.toggleAudio();
    state = state.copyWith(isMicOn: newState);
    _broadcastMediaState();
  }

  void toggleCamera() {
    // See toggleMic — same recovery for the video track. This is
    // the path the user hit when they reported "my video is not
    // displaying in web": the underlying camera track had been
    // released, so flipping `enabled` was a no-op locally AND the
    // SFU producer was sending dead RTP — peers saw a black tile.
    final stream = _localStream;
    final hasLiveVideo = stream != null &&
        stream.getVideoTracks().isNotEmpty &&
        stream.getVideoTracks().first.id != null;
    if (!hasLiveVideo) {
      _log('toggleCamera — video track is null, re-acquiring local media');
      _reacquireLocalMediaAndReproduce();
      return;
    }
    final newState = LocalMediaService.instance.toggleVideo();
    state = state.copyWith(isCameraOn: newState);
    _broadcastMediaState();

    // When the camera goes from off → on, the H264 hardware encoder
    // gets fully released and re-initialised by flutter_webrtc
    // (visible in the device log as `HardwareVideoEncoder: Releasing
    // MediaCodec` followed by `initEncode`). The new encoder generates
    // a fresh IDR (keyframe) on its first frame, but mediasoup's
    // existing consumers on web peers don't always get notified to
    // pick up the new keyframe — they keep showing the last frame
    // they had before the toggle, OR a black tile if there was none.
    //
    // Defensive nudge: re-run _produceLocalTracksToSfu so the SFU
    // producer's track reference is current, AND emit a keyframe
    // request so any consumer of our producer gets pulled into a
    // fresh sync. Both are idempotent — safe even if the producer
    // was healthy throughout.
    if (newState && state.isSfuMode && _sfuService?.isReady == true) {
      _log('📹 camera toggled ON — re-producing to SFU + nudging '
          'consumers for fresh keyframe');
      // Wait one frame so the encoder has time to emit a sync frame
      // before we ask consumers to re-sync.
      Future.delayed(const Duration(milliseconds: 200), () {
        if (!mounted || _disposed) return;
        // ignore: unawaited_futures
        _produceLocalTracksToSfu();
        // Tell the server to broadcast a keyframe to every consumer
        // of OUR video producer. The backend already supports
        // `requestConsumerKeyFrame` (see RECEIVER_HEALTH_BACKEND.md);
        // a producer-side equivalent would let us nudge our own
        // outgoing stream — until that ships, the existing per-
        // consumer keyframe pump on the receiving side eventually
        // pulls us back into sync within ~4s.
        final producerId = _sfuService?.videoProducer?.id;
        if (producerId != null) {
          _socket?.emit('requestProducerKeyFrame', {
            'meetingId': state.meetingCode,
            'producerId': producerId,
          });
          _log('📤 emit requestProducerKeyFrame producer=$producerId');
        }
      });
    }
  }

  /// Tear down the dead local stream, ask LocalMediaService to
  /// re-initialise camera+mic, then re-produce the new tracks into
  /// the SFU so the previous (dead) producers get their tracks
  /// swapped instead of the receiver staying stuck on a black
  /// frame. Called from the toggle handlers when they detect a
  /// null track.
  Future<void> _reacquireLocalMediaAndReproduce() async {
    try {
      _log('🔄 re-acquiring local media after dead-track detection');
      // Force a clean re-init even if the cached stream still
      // exists — the cache may be holding the dead reference.
      await LocalMediaService.instance.initialize(
        video: true,
        audio: true,
        force: true,
      );
      if (!mounted || _disposed) return;
      // Sync UI flags to the just-re-initialised state (both on).
      state = state.copyWith(isMicOn: true, isCameraOn: true);
      // Re-produce so the SFU picks up the fresh tracks. The
      // SFUService internally calls `replaceTrack` if a producer
      // already exists — so the receivers don't have to re-consume,
      // they just start seeing live frames again.
      await _produceLocalTracksToSfu();
      _broadcastMediaState();
    } catch (e) {
      _log('❌ _reacquireLocalMediaAndReproduce failed: $e');
    }
  }

  /// Toggle the local user's "raise hand" indicator. Broadcasts to
  /// all peers via the media-toggle channel so their grid tile
  /// surfaces the hand badge in real time.
  void toggleHandRaised() {
    final next = !state.isHandRaised;
    state = state.copyWith(isHandRaised: next);
    _broadcastMediaState();
  }

  /// Flip the local "On the go" compact UI mode. Local-only — no
  /// socket emission, no other client cares. The meeting room
  /// renders a different layout when this is true (oversized mic /
  /// cam / hangup, no video grid). Useful while driving or moving.
  void toggleOnTheGoMode() {
    state = state.copyWith(isOnTheGoMode: !state.isOnTheGoMode);
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
    // While we're presenting, the video transceiver carries the
    // screen track regardless of whether the camera is on. Telling
    // peers `videoEnabled: false` here would make their UI flip to
    // an avatar even though screen frames are still flowing — the
    // user just turned the camera off, the share is unaffected.
    final hasOutboundVideo = state.isScreenSharing || state.isCameraOn;
    final payload = {
      'meetingId': state.meetingId,
      'type': 'MEDIA_TOGGLE',
      'name': _userName,
      'audioEnabled': state.isMicOn,
      'videoEnabled': hasOutboundVideo,
      'isSharing': state.isScreenSharing,
      'isHandRaised': state.isHandRaised,
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

  void toggleSpeakerphone() async {
    final next = !state.isSpeakerphoneOn;
    // Optimistic UI flip — flutter_webrtc's audio routing call is
    // best-effort (returns void, no success channel) so we update
    // state first and apply the route after.
    state = state.copyWith(isSpeakerphoneOn: next);
    try {
      // Routes the call audio to the loud speaker when true, or back
      // to the earpiece (or paired Bluetooth) when false. Without
      // this call the icon flipped but audio kept coming out of the
      // earpiece — that's why the user reported the volume button
      // doing nothing.
      await Helper.setSpeakerphoneOn(next);
      _log('🔊 speakerphone -> $next');
    } catch (e) {
      _log('⚠️ setSpeakerphoneOn($next) failed: $e');
    }
  }

  bool sendMessage(String text, String senderName) {
    if (!state.hostAllowsChat && !state.isHost) return false;
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    final mid = state.meetingId;
    final uid = state.userId;
    if (mid == null || uid == null) return false;

    final isoNow = DateTime.now().toIso8601String();

    // 1. Socket — single emit, exact shape the web client uses for
    //    chat (id / type:CHAT / content / name / timestamp). Web's
    //    handler hit an unhandled exception when we previously
    //    blasted the same payload on five different event names;
    //    keeping it to one channel and one shape so we never crash a
    //    peer. Server keys room routing on the meeting CODE
    //    (`tjegvvofop`-style), not the UUID.
    final routingId = state.meetingCode ?? mid;
    final socketPayload = {
      'id': '${DateTime.now().millisecondsSinceEpoch}-$uid',
      'meetingId': routingId,
      'type': 'CHAT',
      'content': trimmed,
      'name': senderName,
      'senderName': senderName,
      'senderId': uid,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    _socket?.emit('media-toggle', socketPayload);

    // 2. REST — persistence so the message survives reconnects and
    // shows up in chat history later.
    _chatRepository.sendMessage(
      meetingId: mid,
      senderId: uid,
      senderName: senderName,
      content: trimmed,
    ).catchError((e) {
      _log('chat REST send failed: $e');
      // Cast Map<String, dynamic> in case of error
      return <String, dynamic>{};
    });

    // 3. Optimistic local echo so the sender sees their message
    // instantly without waiting for the round-trip.
    if (mounted && !_disposed) {
      state = state.copyWith(chatMessages: [
        ...state.chatMessages,
        {'text': trimmed, 'sender': 'You', 'time': isoNow},
      ]);
    }
    return true;
  }

  // Active screen-capture stream (null when not sharing).
  MediaStream? _screenStream;
  // Camera track held while screen share is active so we can put it
  // back on the senders when sharing stops.
  MediaStreamTrack? _savedCameraTrack;

  Future<void> toggleScreenShare() async {
    if (state.isScreenSharing) {
      await _stopScreenShare();
    } else {
      await _startScreenShare();
    }
  }

  static const _screenShareFg = MethodChannel('com.mizdah/screen_share_fg');

  /// Whether the OS will let our flutter_webrtc 0.12.7 build start
  /// a screen capture without crashing.
  ///
  /// Android 15 (SDK 35) and 16 (SDK 36) added a strict-mode rule:
  /// the `mediaProjection`-typed foreground service can ONLY start
  /// AFTER the user has granted MediaProjection consent (which sets
  /// the `android:project_media` appop). flutter_webrtc 0.12.7
  /// expects the FGS to be running BEFORE consent, because that's
  /// what Android 14 required — there's a chicken-and-egg conflict
  /// the plugin itself doesn't resolve until 0.13+.
  ///
  /// On Android 14 and below, our existing FGS-first flow works
  /// correctly. On 15+, calling getDisplayMedia results in an
  /// uncaught `SecurityException` from flutter_webrtc's
  /// `OrientationAwareScreenCapturer.startCapture` that kills the
  /// activity. Better to refuse up front with a friendly message
  /// than to crash mid-meeting.
  ///
  /// Re-enable once flutter_webrtc 0.13+ ships and we upgrade.
  bool _screenShareSupportedOnThisOs() {
    if (!Platform.isAndroid) return true;
    final match =
        RegExp(r'API (\d+)').firstMatch(Platform.operatingSystemVersion);
    final api = int.tryParse(match?.group(1) ?? '0') ?? 0;
    // SDK 34 = Android 14 (last good).
    return api <= 34;
  }

  Future<void> _startScreenShare() async {
    try {
      _log('🖥️  starting screen share');

      if (!_screenShareSupportedOnThisOs()) {
        _log('🖥️  screen share blocked — Android 15+ FGS rules + '
            'flutter_webrtc 0.12.7 incompatibility (would crash). '
            'Will be re-enabled on plugin upgrade.');
        // Best we can do without ScaffoldMessenger access: tag the
        // failure on state and let the UI show a snackbar. Use the
        // existing error-surfacing pattern (no new fields needed —
        // toggle isScreenSharing to false to ensure the icon
        // doesn't go active, and surface via incomingChatToast as a
        // pseudo-system message).
        state = state.copyWith(
          isScreenSharing: false,
          incomingChatToast: {
            'sender': 'Mizdah',
            'text': "Screen sharing isn't available on this Android "
                'version yet. We\'re shipping a fix soon.',
            'at': DateTime.now().millisecondsSinceEpoch,
          },
        );
        return;
      }

      // Android 14+ refuses MediaProjection unless a foreground
      // service of TYPE_MEDIA_PROJECTION is ALREADY running by the
      // time the projection is created. Start ours and wait a moment
      // for the OS to register it before the share intent fires.
      // (Requires a fresh `flutter clean && flutter run` so the
      // native MediaProjectionFgService is in the APK.)
      if (Platform.isAndroid) {
        try {
          await _screenShareFg.invokeMethod('start');
          await Future.delayed(const Duration(milliseconds: 600));
        } catch (e) {
          _log('foreground-service start failed (need fresh build?): $e');
        }
      }

      final stream = await navigator.mediaDevices.getDisplayMedia({
        'audio': false,
        'video': true,
      });
      final tracks = stream.getVideoTracks();
      if (tracks.isEmpty) {
        _log('❌ getDisplayMedia returned no video track');
        await stream.dispose();
        return;
      }
      _screenStream = stream;
      final screenTrack = tracks.first;

      // Save the running camera track so we can restore it when the
      // user stops sharing.
      final localStream = LocalMediaService.instance.stream;
      _savedCameraTrack = (localStream != null && localStream.getVideoTracks().isNotEmpty)
          ? localStream.getVideoTracks().first
          : null;

      // SFU mode (always on now): publish the screen track as a
      // SEPARATE producer with `appData.isScreen: true`. The web
      // client and other mobile peers consume that producer into
      // a dedicated presentation tile rather than swapping the
      // camera tile. This is the path that actually reaches other
      // participants — the legacy peer-connection sender swap
      // below is a no-op when there are no peer connections.
      if (state.isSfuMode && _sfuService != null) {
        try {
          await _sfuService!.produceScreen(screenTrack, stream);
          _log('🖥️  SFU screen producer started');
        } catch (e) {
          _log('❌ SFU produceScreen failed: $e');
        }
      }

      // Legacy P2P fallback: hot-swap the video sender on every peer
      // connection. The receiving side's renderer keeps the same
      // SSRC — frames just start coming from the screen instead of
      // the camera. No-op in SFU mode (no peer connections).
      var swapped = 0;
      for (final pc in _peerConnections.values) {
        final senders = await pc.getSenders();
        for (final sender in senders) {
          if (sender.track?.kind == 'video') {
            await sender.replaceTrack(screenTrack);
            swapped++;
          }
        }
      }
      if (swapped > 0) {
        _log('🖥️  replaced video sender on $swapped P2P peer(s)');
      }

      // The OS lets the user revoke screen capture from the system UI;
      // when that happens the track ends and we should stop cleanly.
      screenTrack.onEnded = () {
        if (state.isScreenSharing) {
          _stopScreenShare();
        }
      };

      // Don't allocate a local renderer for the screen capture.
      // Displaying our own screen-capture stream inside the same
      // screen creates infinite recursive nesting — the host sees
      // a static "You are presenting" placeholder tile instead.
      // Remote peers still see the actual screen via WebRTC.

      if (mounted && !_disposed) {
        state = state.copyWith(isScreenSharing: true);
      }
      _broadcastMediaState();
    } on PlatformException catch (e) {
      _log('❌ startScreenShare PlatformException: ${e.code} ${e.message}');
      _screenStream = null;
      _savedCameraTrack = null;
      if (Platform.isAndroid) {
        try {
          await _screenShareFg.invokeMethod('stop');
        } catch (_) {}
      }
    } catch (e) {
      _log('❌ startScreenShare failed: $e');
      _screenStream = null;
      _savedCameraTrack = null;
      if (Platform.isAndroid) {
        try {
          await _screenShareFg.invokeMethod('stop');
        } catch (_) {}
      }
    }
  }

  Future<void> _stopScreenShare() async {
    _log('🖥️  stopping screen share');
    if (Platform.isAndroid) {
      try {
        await _screenShareFg.invokeMethod('stop');
      } catch (_) {}
    }
    // Close the SFU screen producer first so peers stop seeing the
    // screen the moment we tap stop, rather than waiting for the
    // local stream cleanup below.
    if (_sfuService != null) {
      try {
        await _sfuService!.stopScreen();
        _log('🖥️  SFU screen producer stopped');
      } catch (e) {
        _log('❌ SFU stopScreen error (non-fatal): $e');
      }
    }
    try {
      _screenStream?.getTracks().forEach((t) => t.stop());
      await _screenStream?.dispose();
    } catch (_) {}
    _screenStream = null;

    // Put the camera track back on every peer-connection sender.
    if (_savedCameraTrack != null) {
      for (final pc in _peerConnections.values) {
        final senders = await pc.getSenders();
        for (final sender in senders) {
          if (sender.track?.kind == 'video') {
            await sender.replaceTrack(_savedCameraTrack);
          }
        }
      }
    }
    _savedCameraTrack = null;

    // Tear down the local screen renderer so the host's preview
    // tile disappears.
    final r = state.screenRenderer;
    if (r != null) {
      try {
        r.srcObject = null;
        await r.dispose();
      } catch (_) {}
    }

    if (mounted && !_disposed) {
      state = state.copyWith(
        isScreenSharing: false,
        clearScreenRenderer: true,
      );
    }
    _broadcastMediaState();
  }

  /// Send a one-shot emoji reaction to the room. Shows immediately
  /// for the sender and broadcasts to every other client.
  ///
  /// Wire format (verified against the deployed web client's bundle
  /// on 2026-05-03):
  ///
  ///   client → server:
  ///       socket.emit('broadcast-data', {
  ///         meetingId,
  ///         type: 'REACTION',
  ///         reaction: { id, emoji, timestamp },
  ///       })
  ///
  ///   server → other clients:
  ///       socket.on('broadcast-data-remote', ({ from, ...t }) => …)
  ///
  /// The web client routes anything that ISN'T `CHAT` /
  /// `MEDIA_TOGGLE` / `SYNC_STATE` / `RECORDING_PERMISSION_UPDATE`
  /// through `broadcast-data` (vs. the chat path which uses
  /// `media-toggle`). REACTIONs are in that "everything else"
  /// bucket. Without using this exact event pair, mobile→web and
  /// web→mobile reactions never round-trip — verified empirically.
  ///
  /// The legacy `send-reaction` emit is kept as a belt-and-suspenders
  /// fallback for older Flutter peers that still listen on the old
  /// names. Server-side relay of `send-reaction → receive-reaction`
  /// is welcome but no longer required for the cross-platform path.
  void sendReaction(String emoji) {
    if (state.meetingId == null) return;
    final ts = DateTime.now().millisecondsSinceEpoch;
    final name = _userName ?? 'You';
    final routingId = state.meetingCode ?? state.meetingId;
    final uid = state.userId;
    final reactionId =
        '${_socket?.id ?? 'self'}-$ts'; // matches web's UUID semantically

    // 1) Optimistic local floating reaction.
    _addReaction(emoji, name);

    // 2) The web-compatible path. This is the one that actually makes
    //    cross-platform reactions visible.
    final webPayload = {
      'meetingId': routingId,
      'type': 'REACTION',
      'reaction': {
        'id': reactionId,
        'emoji': emoji,
        'timestamp': ts,
      },
      // Some servers relay the full payload as-is and let the
      // receiver pull `from` off the socket.id; sending name +
      // userId here costs nothing and helps if they don't.
      'name': name,
      'userId': uid,
    };
    _log('🎉 emit broadcast-data REACTION $emoji');
    _socket?.emit('broadcast-data', webPayload);

    // 3) Legacy mobile-only path — keep emitting so two old Flutter
    //    builds in the same room (without the web upgrade above)
    //    still see each other's reactions.
    _socket?.emit('send-reaction', {
      'meetingId': routingId,
      'userId': uid,
      'emoji': emoji,
      'name': name,
      'timestamp': ts,
    });
  }

  void _addReaction(String emoji, String name) {
    if (!mounted || _disposed) return;
    final reaction = ReactionEvent(emoji: emoji, name: name, at: DateTime.now());
    state = state.copyWith(reactions: [...state.reactions, reaction]);
    Future.delayed(const Duration(milliseconds: 3500), () {
      if (!mounted || _disposed) return;
      try {
        state = state.copyWith(
          reactions: state.reactions.where((r) => r != reaction).toList(),
        );
      } catch (_) {}
    });
  }

  // ----- Remote-control flow ----------------------------------------

  /// Ask a peer (the presenter) to grant control of their screen.
  /// Their client will pop a grant/deny dialog; the response comes
  /// back via the `control-response` socket event.
  void requestRemoteControl(String targetSocketId) {
    if (state.meetingId == null) return;
    final payload = {
      'meetingId': state.meetingCode ?? state.meetingId,
      'to': targetSocketId,
      'from': _socket?.id,
      'name': _userName ?? 'You',
      'senderId': state.userId,
    };
    _log('🖱  emit request-control → $targetSocketId');
    _socket?.emit('request-control', payload);
  }

  /// Respond to an incoming control request. Clears the dialog state
  /// either way; if granted, remember which peer can drive us so the
  /// UI can show a banner.
  void respondRemoteControl({required bool granted}) {
    final req = state.incomingControlRequest;
    if (req == null) return;
    final to = req['from']?.toString();
    if (to != null) {
      _socket?.emit('control-response', {
        'meetingId': state.meetingCode ?? state.meetingId,
        'to': to,
        'from': _socket?.id,
        'name': _userName ?? 'You',
        'granted': granted,
      });
    }
    _log('🖱  emit control-response granted=$granted to=$to');
    state = state.copyWith(
      clearIncomingControlRequest: true,
      controllingPeerSocketId: granted ? to : null,
      clearControllingPeer: !granted,
    );
  }

  /// Either side can revoke an active control session. Clears local
  /// state and tells the other party.
  void revokeRemoteControl() {
    final to = state.controllingPeerSocketId ?? state.controlOfPeerSocketId;
    if (to != null) {
      _socket?.emit('revoke-control', {
        'meetingId': state.meetingCode ?? state.meetingId,
        'to': to,
        'from': _socket?.id,
      });
    }
    state = state.copyWith(
      clearControllingPeer: true,
      clearControlOfPeer: true,
    );
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

    // The same renderer might be aliased at TWO keys (signaling sid
    // + media sid) thanks to the cross-channel SID linking in
    // _handleSfuRemoteTrack. We must dispose the renderer ONCE and
    // remove BOTH keys, otherwise the leftover key points at a
    // disposed renderer and the next frame crashes with a use-
    // after-dispose error → Flutter paints the screen red.
    final keysToRemove = <String>{socketId};
    final altSid = _mediaSidBySignalingSid[socketId] ??
        _signalingSidByMediaSid[socketId];
    if (altSid != null) keysToRemove.add(altSid);

    // Streams: remove every aliased entry so a future media-toggle
    // re-attach doesn't grab a stale stream.
    for (final k in keysToRemove) {
      _remoteStreams.remove(k);
      _remoteScreenStreams.remove(k);
    }

    // Dispose renderers — using identity tracking to avoid a double-
    // dispose when both keys point at the same instance.
    final disposed = <RTCVideoRenderer>{};
    final newRemote =
        Map<String, RTCVideoRenderer>.from(state.remoteRenderers);
    final newScreen = Map<String, RTCVideoRenderer>.from(
        state.remoteScreenRenderers);
    var anyChange = false;
    for (final k in keysToRemove) {
      final r = newRemote[k];
      if (r != null) {
        if (disposed.add(r)) {
          try {
            r.srcObject = null;
            r.dispose();
          } catch (_) {}
        }
        newRemote.remove(k);
        anyChange = true;
      }
      final sr = newScreen[k];
      if (sr != null) {
        if (disposed.add(sr)) {
          try {
            sr.srcObject = null;
            sr.dispose();
          } catch (_) {}
        }
        newScreen.remove(k);
        anyChange = true;
      }
    }
    if (anyChange && mounted && !_disposed) {
      state = state.copyWith(
        remoteRenderers: newRemote,
        remoteScreenRenderers: newScreen,
      );
    }

    // Clear the cross-channel mapping for this peer.
    _mediaSidBySignalingSid.remove(socketId);
    _signalingSidByMediaSid.remove(socketId);
    if (altSid != null) {
      _mediaSidBySignalingSid.remove(altSid);
      _signalingSidByMediaSid.remove(altSid);
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
    _audioLevelTimer?.cancel();
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
    if (mounted && !_disposed) {
      state = state.copyWith(phase: MeetingPhase.ended);
    }
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
    // BACKEND-BUG WORKAROUND: the same host-detection bug
    // (docs/HOST_DETECTION_BACKEND.md) makes the server include
    // the host in their OWN waiting list. Strip ourselves out so
    // the host doesn't see themselves in the "1 person waiting"
    // banner of their own meeting.
    final mySocketId = _socket?.id;
    final myUserId = state.userId;
    final filtered = list.where((p) {
      // p is already typed as Map<String,dynamic> — no need to
      // re-check. Just match by socketId or userId; either hit
      // means the row is the host themselves and should be hidden
      // from their own waiting-room banner.
      if (mySocketId != null && p['socketId']?.toString() == mySocketId) {
        return false;
      }
      if (myUserId != null &&
          (p['userId'] ?? p['user_id'])?.toString() == myUserId) {
        return false;
      }
      return true;
    }).toList();
    _log('🛎  Waiting-room poll → ${filtered.length} participants '
        '(${list.length} raw, ${list.length - filtered.length} self-stripped)');
    // Wrap the assignment: a Riverpod consumer of this provider may have
    // unmounted between the guard above and the synchronous listener
    // notification below (e.g. during navigation). Disposed/defunct
    // listeners would otherwise crash the runtime.
    try {
      state = state.copyWith(waitingParticipants: filtered);
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
      // The REST endpoint at `/api/participant/<meetingId>` returns
      // a row PER JOIN — including historical rows where `left_at`
      // is already set, AND newly-joined rows that don't have a
      // `name` resolved yet (the backend stores user_id only, no
      // display name). If we naively merge those into the
      // participants state, the grid renders ghost tiles labeled
      // "Participant" with a generic "P" avatar — exactly the
      // bug the user reported.
      //
      // Filter to rows that:
      //   1. aren't us (existing self-filter)
      //   2. haven't already left  (left_at == null)
      //   3. have a usable display name
      // Socket events (`user-joined` / `user-left`) are the
      // authoritative source for live participants and arrive with
      // names attached — REST is just a hint for historical /
      // re-join scenarios.
      final filtered = participants.where((p) {
        if (p is! Map) return true; // pass non-map through unchanged
        // 1. self
        if (p['userId'] == state.userId || p['user_id'] == state.userId) {
          return false;
        }
        // 2. already left
        final leftAt = p['leftAt'] ?? p['left_at'];
        if (leftAt != null && leftAt.toString().isNotEmpty) return false;
        // 3. nameless (no usable display name → would render as
        //    a "Participant" ghost tile)
        final name = (p['name'] ?? p['displayName'])?.toString().trim();
        if (name == null || name.isEmpty) return false;
        return true;
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

  /// Whether we've already attempted to bootstrap the SFU pipeline
  /// for this meeting. The bootstrap involves opening a second socket
  /// against `/media-fresh`, asking the server for the room's RTP
  /// capabilities, and creating both directions of WebRTC transport.
  /// We only ever do it once per join; if it fails the meeting falls
  /// back to the legacy P2P path.
  bool _sfuBootstrapStarted = false;

  /// Bootstraps the mediasoup SFU session. Called once per join from
  /// the `join-confirmation` handler after we know we're admitted.
  ///
  /// Steps:
  ///   1. Open a SECOND socket.io connection on the `/media`
  ///      namespace (engine path `/media-fresh`). The signaling
  ///      socket (`/signaling-fresh`) cannot be reused — the backend
  ///      separates control and media planes.
  ///   2. Wait for the media socket to connect.
  ///   3. Run [SFUService.initialize] which performs the
  ///      createRoom → load device → createTransport(send/recv) →
  ///      joinMedia handshake.
  ///   4. Produce our local audio + video tracks so other peers can
  ///      consume them.
  ///
  /// On any error we log loudly and leave `state.isSfuMode = false`,
  /// which causes `user-joined` to fall back to the legacy P2P offer
  /// path. That fallback is wishful — the backend stopped relaying
  /// P2P offers when it migrated to mediasoup — but at least the
  /// app doesn't crash, and a future server-side rollback would
  /// re-enable it for free.
  Future<void> _bootstrapSfu() async {
    // Diagnostic: always log entry so it's obvious in the device
    // log whether this method was called at all. Past bugs masked
    // a missing call as a silent media-never-starts symptom.
    _log('[SFU] 🚀 _bootstrapSfu() entered '
        '(started=$_sfuBootstrapStarted, code=${state.meetingCode}, '
        'isHost=${state.isHost})');
    if (_sfuBootstrapStarted) return;
    _sfuBootstrapStarted = true;
    final code = state.meetingCode;
    if (code == null) {
      _log('[SFU] bootstrap skipped — no meetingCode');
      return;
    }

    // Flip into SFU mode optimistically. If `user-joined` arrives
    // while we're still opening the media socket the handler will
    // skip the legacy P2P offer creation — exactly what we want.
    // Reverted to false at the end of this method on failure.
    if (mounted && !_disposed) {
      state = state.copyWith(isSfuMode: true);
    }

    _log('[SFU] bootstrap → media socket → ${ApiConfig.signalingUrl}/media path=${ApiConfig.mediaPath}');
    // socket_io_client v3 uses URL "<base>/<namespace>" — appending
    // `/media` selects the namespace, the `path` option selects the
    // engine.io endpoint. forceNew=true keeps it independent of the
    // signaling manager cache (we hit a 502 once when both sockets
    // shared a manager and the path got mutated — see the comment
    // above the signaling socket build).
    // Match the deployed web client byte-for-byte (see its main bundle):
    //   transports websocket+polling, upgrade:false (don't try to upgrade
    //   from polling→websocket — start direct on websocket), timeout
    //   20s, reconnection backoff 1s→5s for up to 10 attempts. Mirroring
    //   these resolved a mystery 12-second media socket drop where our
    //   defaults differed from the server's expected handshake cadence.
    final Map<String, dynamic> mediaOpts = {
      'path': ApiConfig.mediaPath,
      'transports': ['websocket', 'polling'],
      'upgrade': false,
      'timeout': 20000,
      'autoConnect': false,
      'forceNew': true,
      'reconnection': true,
      'reconnectionAttempts': 10,
      'reconnectionDelay': 1000,
      'reconnectionDelayMax': 5000,
    };
    final mediaSocket = io.io('${ApiConfig.signalingUrl}/media', mediaOpts);
    _mediaSocket = mediaSocket;

    final connectedCompleter = Completer<bool>();
    mediaSocket.onConnect((_) async {
      _log('[SFU] media socket CONNECTED (sid=${mediaSocket.id})');
      if (!connectedCompleter.isCompleted) {
        // First connect — bootstrap proceeds below.
        connectedCompleter.complete(true);
        return;
      }
      // RE-connect. The server has lost all session state — close the
      // stale transports/device and re-run the full createRoom →
      // createTransport → joinMedia → produce flow against the new
      // socket. Without this, the WebRTC peer connections continue
      // emitting DTLS keepalives into the void and ICE eventually
      // drops to `failed`. The deployed web client follows the same
      // recovery pattern (see the bundle's a.on("connect", ...)
      // handler that closes es.current/ei.current before re-init).
      _log('[SFU] media socket RECONNECTED — re-bootstrapping SFU');
      try {
        _sfuService?.dispose();
      } catch (_) {}
      if (!mounted || _disposed) return;
      _sfuService = SFUService(
        mediaSocket: mediaSocket,
        meetingId: code,
        signalingSocketId: () => _socket?.id ?? '',
        userName: () => _userName ?? '',
        onRemoteTrack: _handleSfuRemoteTrack,
        onRemoteTrackClosed: _handleSfuConsumerClosed,
        log: (m) => debugPrint('$_kLogTag $m'),
      );
      try {
        await _sfuService!.initialize();
        _log('[SFU] re-init succeeded after reconnect');
        await _produceLocalTracksToSfu();
      } catch (e, st) {
        _log('[SFU] re-init FAILED: $e\n$st');
      }
    });
    mediaSocket.onConnectError((err) {
      _log('[SFU] media socket CONNECT_ERROR: $err');
      if (!connectedCompleter.isCompleted) connectedCompleter.complete(false);
    });
    mediaSocket.onError((err) => _log('[SFU] media socket ERROR: $err'));
    mediaSocket.onDisconnect((reason) =>
        _log('[SFU] media socket disconnected: $reason'));
    mediaSocket.onAny((event, data) =>
        _log('[SFU] 📡 media event: $event'));

    mediaSocket.connect();

    // Cap the wait — if the server is unreachable we'd hang forever.
    final connected = await connectedCompleter.future
        .timeout(const Duration(seconds: 10), onTimeout: () => false);
    if (!connected) {
      _log('[SFU] bootstrap aborted — media socket did not connect');
      if (mounted && !_disposed) {
        state = state.copyWith(isSfuMode: false);
      }
      return;
    }
    if (!mounted || _disposed) return;

    _sfuService = SFUService(
      mediaSocket: mediaSocket,
      meetingId: code,
      signalingSocketId: () => _socket?.id ?? '',
      onRemoteTrack: _handleSfuRemoteTrack,
      onRemoteTrackClosed: _handleSfuConsumerClosed,
      log: (m) => debugPrint('$_kLogTag $m'),
    );

    try {
      await _sfuService!.initialize();
      _log('[SFU] initialize() succeeded');
      if (!mounted || _disposed) return;
      await _produceLocalTracksToSfu();
    } catch (e, st) {
      _log('[SFU] initialize() FAILED: $e\n$st');
      if (mounted && !_disposed) {
        state = state.copyWith(isSfuMode: false);
      }
    }
  }

  /// Produces the current local audio + video tracks via the SFU.
  /// Called once after [SFUService.initialize] completes, and again
  /// from `toggleMic` / `toggleCamera` when the previous track has
  /// died (re-acquire path). Safe to call repeatedly — already-
  /// producing tracks are a no-op inside [SFUService.produceAudio /
  /// produceVideo] when the same track is passed.
  Future<void> _produceLocalTracksToSfu() async {
    final svc = _sfuService;
    final stream = _localStream;
    _log('[SFU] _produceLocalTracksToSfu — '
        'svc=${svc != null} ready=${svc?.isReady} '
        'stream=${stream != null} '
        'tracks=${stream?.getTracks().map((t) => "${t.kind}:${t.id}").join(",") ?? "(none)"}');
    if (svc == null || stream == null || !svc.isReady) {
      _log('[SFU] _produceLocalTracksToSfu — skipped (svc/stream/ready false)');
      return;
    }

    // ⚠️ CRITICAL: wait for the signaling socket id to be available
    // before producing. The producer's `appData.socketId` carries
    // OUR signaling socket id; web peers route incoming producers to
    // their participant tiles by socketId. With the EARLY bootstrap
    // path (host hint), produce can otherwise fire before the
    // signaling socket has connected — `_socket?.id` returns null,
    // mediasoup ships the producer with `appData.socketId=''`, and
    // the web client drops the video on the floor (it can't find a
    // participant tile keyed by empty string).
    //
    // Symptom this fixes: "user side video screen is displaying in
    // my side but my side video screen is not displaying in user
    // side". Mobile encodes & uploads RTP fine (REMB/twcc bitrate
    // adaptation visible in MediaCodec logs), but web silently
    // discards the producer — there's no JS error, just no tile.
    final waitStart = DateTime.now();
    while (mounted &&
        !_disposed &&
        (_socket?.id == null || _socket!.id!.isEmpty)) {
      if (DateTime.now().difference(waitStart) >
          const Duration(seconds: 8)) {
        _log('[SFU] _produceLocalTracksToSfu — timed out waiting for '
            'signaling socket id; producing anyway with empty socketId '
            '(web peers may not see this stream)');
        break;
      }
      await Future.delayed(const Duration(milliseconds: 50));
    }
    _log('[SFU] _produceLocalTracksToSfu — signaling sid=${_socket?.id} '
        '(waited ${DateTime.now().difference(waitStart).inMilliseconds}ms)');
    final audio = stream.getAudioTracks().isNotEmpty
        ? stream.getAudioTracks().first
        : null;
    final video = stream.getVideoTracks().isNotEmpty
        ? stream.getVideoTracks().first
        : null;
    _log('[SFU] _produceLocalTracksToSfu — '
        'audio=${audio?.id ?? "<none>"} video=${video?.id ?? "<none>"}');
    if (audio != null) {
      try {
        await svc.produceAudio(audio, stream);
        _log('[SFU] produceAudio ok (track=${audio.id})');
      } catch (e) {
        _log('[SFU] produceAudio failed: $e');
      }
    }
    if (video != null) {
      try {
        await svc.produceVideo(video, stream);
        _log('[SFU] produceVideo ok (track=${video.id})');
      } catch (e) {
        _log('[SFU] produceVideo failed: $e');
      }
    }
  }

  /// Called by SFUService when a remote producer becomes consumable.
  /// Aggregates audio + video tracks from the same socketId onto a
  /// single MediaStream so the per-tile renderer plays both in sync,
  /// then routes through the existing `_attachRemoteStream` plumbing
  /// (which also creates the renderer and updates state).
  /// Per-peer screen-share streams, keyed by socketId. Held alive
  /// here so the renderer in `state.remoteScreenRenderers` keeps a
  /// valid srcObject. Separate from `_remoteStreams` (camera).
  final Map<String, MediaStream> _remoteScreenStreams = {};

  Future<void> _handleSfuRemoteTrack(
    String remoteSocketId,
    MediaStreamTrack track,
    Map<String, dynamic> appData,
  ) async {
    if (!mounted || _disposed) return;
    final isScreen = appData['isScreen'] == true;
    _log('[SFU] 🎬 remote track ← $remoteSocketId kind=${track.kind} '
        'isScreen=$isScreen');

    // ─────────────────────────────────────────────────────────────
    // CROSS-CHANNEL SID LINK
    //
    // The dev SFU uses TWO separate socket connections per peer
    // (/signaling-fresh + /media-fresh) and each gets its own
    // session id. So `remoteSocketId` here (= producer's
    // appData.socketId) is the peer's MEDIA sid, but our
    // `state.participants` and `media-toggle-remote` events are
    // keyed by the peer's SIGNALING sid. The two never match, which
    // is why:
    //   • mobile saw a phantom "Participant" tile (the orphan
    //     fallback fired with the media-keyed renderer)
    //   • clearing the renderer on `videoEnabled:false` failed
    //     (handler looked up by signaling sid)
    //
    // Fix: when a producer arrives with a name in appData, find the
    // matching participant in state and ALIAS the renderer at the
    // participant's signaling sid. The existing rendering loop +
    // toggle handler (both keyed on signaling sid) then work
    // correctly. The media-sid entry stays as a backup so screen
    // tear-down via consumer-closed still works.
    final remoteName = appData['name']?.toString().trim();
    String? linkedSignalingSid;
    if (remoteName != null && remoteName.isNotEmpty) {
      // Match by name first — the most reliable cross-channel key.
      for (final p in state.participants) {
        if (p is! Map) continue;
        if ((p['name']?.toString() ?? '') == remoteName) {
          linkedSignalingSid = p['socketId']?.toString();
          break;
        }
      }
    }
    if (linkedSignalingSid == null) {
      // Fallback heuristic: if there's exactly ONE participant
      // without a renderer aliased to their signaling sid yet,
      // assume this producer is theirs. Works for the common 1:1
      // and 2-3-person meetings the user is actually testing.
      final unlinked = state.participants
          .where((p) {
            if (p is! Map) return false;
            final sid = p['socketId']?.toString();
            return sid != null &&
                sid != _socket?.id &&
                !state.remoteRenderers.containsKey(sid);
          })
          .toList();
      if (unlinked.length == 1) {
        linkedSignalingSid = unlinked.first['socketId']?.toString();
      }
    }
    if (linkedSignalingSid != null && linkedSignalingSid != remoteSocketId) {
      _log('[SFU] 🔗 linking media-sid $remoteSocketId → '
          'signaling-sid $linkedSignalingSid (name=$remoteName)');
    }

    // Screen-share tracks live on a SEPARATE stream + renderer from
    // the peer's camera. The grid renders them as a second tile
    // ("Name · Presenting") rather than overwriting the camera tile.
    if (isScreen) {
      await _attachRemoteScreenTrack(remoteSocketId, track);
      // Also alias the screen renderer at the peer's signaling sid
      // so the participant-row's "Presenting" tile finds it.
      if (linkedSignalingSid != null &&
          linkedSignalingSid != remoteSocketId) {
        final r = state.remoteScreenRenderers[remoteSocketId];
        if (r != null) {
          state = state.copyWith(
            remoteScreenRenderers: {
              ...state.remoteScreenRenderers,
              linkedSignalingSid: r,
            },
          );
        }
      }
      return;
    }

    final isNewStream = !_remoteStreams.containsKey(remoteSocketId);
    var stream = _remoteStreams[remoteSocketId];
    stream ??= await createLocalMediaStream('sfu-remote-$remoteSocketId');
    try {
      await stream.addTrack(track);
    } catch (e) {
      _log('[SFU] addTrack to remote stream failed (already added?): $e');
    }

    if (isNewStream) {
      // First track for this peer — normal attachment.
      await _attachRemoteStream(remoteSocketId, stream);
      // Alias the renderer at the participant's signaling sid so the
      // existing rendering loop + media-toggle handler (both keyed
      // on signaling sid) find it. See the cross-channel-sid-link
      // comment block above for why this is necessary.
      if (linkedSignalingSid != null &&
          linkedSignalingSid != remoteSocketId &&
          mounted &&
          !_disposed) {
        final r = state.remoteRenderers[remoteSocketId];
        if (r != null) {
          // Record the bidirectional mapping FIRST so the teardown
          // path knows about both map keys when it runs.
          _mediaSidBySignalingSid[linkedSignalingSid] = remoteSocketId;
          _signalingSidByMediaSid[remoteSocketId] = linkedSignalingSid;
          state = state.copyWith(
            remoteRenderers: {
              ...state.remoteRenderers,
              linkedSignalingSid: r,
            },
          );
          // Also alias the underlying stream so srcObject look-ups in
          // the media-toggle handler can detach/reattach via either key.
          _remoteStreams[linkedSignalingSid] = stream;
        }
      }
      return;
    }

    // Adding ANOTHER track (typically video after audio) to a stream
    // the renderer is already displaying. RTCVideoRenderer enumerates
    // its srcObject's tracks at assignment time and does NOT pick up
    // tracks added later — so without re-binding, audio plays but
    // remote video stays black even though `🎬 remote track` fired.
    // Clearing srcObject and reassigning forces the renderer to
    // re-enumerate, and the late-added video track starts rendering.
    final renderer = state.remoteRenderers[remoteSocketId];
    if (renderer == null) {
      // Renderer was disposed since the first track. Re-create.
      _remoteStreams[remoteSocketId] = stream;
      await _attachRemoteStream(remoteSocketId, stream);
      return;
    }
    _log('[SFU] re-binding renderer for $remoteSocketId to pick up '
        'new ${track.kind} track');
    renderer.srcObject = null;
    // Yield a frame so the platform-side renderer fully detaches
    // before we re-attach. Without the delay some flutter_webrtc
    // platforms drop the second assignment as a no-op.
    await Future<void>.delayed(const Duration(milliseconds: 30));
    if (!mounted || _disposed) return;
    renderer.srcObject = stream;
  }

  /// Attach a remote SCREEN-SHARE track (`appData.isScreen == true`)
  /// to its own MediaStream + RTCVideoRenderer keyed by the
  /// presenter's socketId. This intentionally bypasses the camera
  /// path so the camera tile keeps rendering normally — the grid
  /// renders the presentation as an additional tile beside it.
  Future<void> _attachRemoteScreenTrack(
    String remoteSocketId,
    MediaStreamTrack track,
  ) async {
    var stream = _remoteScreenStreams[remoteSocketId];
    if (stream == null) {
      stream =
          await createLocalMediaStream('sfu-remote-screen-$remoteSocketId');
      _remoteScreenStreams[remoteSocketId] = stream;
    }
    try {
      await stream.addTrack(track);
    } catch (e) {
      _log('[SFU] addTrack to screen stream failed (already added?): $e');
    }

    var renderer = state.remoteScreenRenderers[remoteSocketId];
    if (renderer == null) {
      renderer = RTCVideoRenderer();
      await renderer.initialize();
    }
    // Always force a rebind — this method is called once per
    // SFU consumer, so the track is brand-new for the renderer
    // and the binding may need to flush a previous frame buffer.
    renderer.srcObject = null;
    await Future<void>.delayed(const Duration(milliseconds: 30));
    if (!mounted || _disposed) return;
    renderer.srcObject = stream;

    state = state.copyWith(
      remoteScreenRenderers: {
        ...state.remoteScreenRenderers,
        remoteSocketId: renderer,
      },
    );
    _log('🖥️  ← attached screen renderer for $remoteSocketId');
  }

  /// SFU notified us a consumer was closed (peer left, server
  /// terminated, etc.). We can't easily map consumerId back to a
  /// socketId from the lean info we get, so we lean on the
  /// `user-left` event for tile teardown. Logged here purely for
  /// debugging.
  void _handleSfuConsumerClosed(String consumerId) {
    _log('[SFU] consumer closed: $consumerId');
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
