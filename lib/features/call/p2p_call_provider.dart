// ════════════════════════════════════════════════════════════════════
//  P2P Call Provider — Riverpod glue for `P2PCallService`
//  ────────────────────────────────────────────────────────────────────
//  Owns one long-lived `P2PCallService` instance for the logged-in
//  session. Watches `authProvider`: when the user logs in we connect
//  the signaling socket and register presence; when they log out we
//  dispose the service.
//
//  Exposes:
//    • p2pCallProvider — the StateNotifier driving call UI
//    • p2pCallServiceProvider — raw service handle (only screens that
//      need to render WebRTC video read this directly)
//
//  State transitions follow the doc-spec state machine:
//      IDLE → OUTGOING → ACTIVE → IDLE
//      IDLE → INCOMING → ACTIVE → IDLE
//      OUTGOING → IDLE  (declined / offline / cancelled)
//      INCOMING → IDLE  (declined / cancelled by caller)
// ════════════════════════════════════════════════════════════════════

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../core/services/p2p_call_service.dart';
import '../../data/models/models.dart';
import '../auth/auth_provider.dart';
import 'call_log_provider.dart';
import 'data/call_log_models.dart';

enum P2PCallPhase {
  idle,
  outgoing, // I called, waiting for accept
  incoming, // they called, ringing on my side
  connecting, // I accepted (or my outgoing was accepted) — awaiting media
  active, // both sides connected, media flowing
  ended, // transient — UI shows "Call ended" briefly
  failed, // transient — declined / offline / failed
}

class P2PCallState {
  final P2PCallPhase phase;
  final String? callId;
  final String? remoteUserId;
  final String? remoteName;
  final bool withVideo;
  final bool localAudio;
  final bool localVideo;
  /// Whether the REMOTE peer has their camera on. Defaults to
  /// `false` — we assume off until we've seen evidence otherwise.
  /// Evidence can come from either:
  ///   • the renderer's own `RTCVideoValue.renderVideo` flipping
  ///     true (frames are flowing), OR
  ///   • the peer's `call-media-state` socket event with
  ///     `video: true`.
  /// The previous default of `true` made the call screen render a
  /// black `RTCVideoView` for the entire window between "WebRTC
  /// connected" and "first frame decoded" — and stayed black
  /// indefinitely if the peer's camera was off and their
  /// `call-media-state` event never reached us. Defaulting to
  /// false means the camera-off backdrop shows by default, and we
  /// only swap in the live video tile after evidence arrives.
  final bool remoteVideo;
  /// Whether the REMOTE peer has their mic on. Drives the "Muted"
  /// badge on the remote tile.
  final bool remoteAudio;
  /// Audio output routing. `true` → loudspeaker, `false` → earpiece
  /// (or paired Bluetooth, OS-chosen). Defaults differ by call type
  /// at start-of-call (audio → earpiece, video → speaker) to match
  /// WhatsApp / FaceTime behaviour. User can flip it at any time via
  /// the in-call speaker button (`toggleSpeakerphone`).
  final bool isSpeakerphoneOn;
  final RTCVideoRenderer? localRenderer;
  final RTCVideoRenderer? remoteRenderer;
  final bool mediaConnected;
  final String? failureMessage;
  // Raw incoming-call payload (so the UI can pass it back to
  // accept/decline without re-deriving).
  final P2PIncomingCall? incoming;

  const P2PCallState({
    this.phase = P2PCallPhase.idle,
    this.callId,
    this.remoteUserId,
    this.remoteName,
    this.withVideo = true,
    this.localAudio = true,
    this.localVideo = true,
    this.remoteVideo = false,
    this.remoteAudio = true,
    this.isSpeakerphoneOn = false,
    this.localRenderer,
    this.remoteRenderer,
    this.mediaConnected = false,
    this.failureMessage,
    this.incoming,
  });

  P2PCallState copyWith({
    P2PCallPhase? phase,
    String? callId,
    String? remoteUserId,
    String? remoteName,
    bool? withVideo,
    bool? localAudio,
    bool? localVideo,
    bool? remoteVideo,
    bool? remoteAudio,
    bool? isSpeakerphoneOn,
    RTCVideoRenderer? localRenderer,
    RTCVideoRenderer? remoteRenderer,
    bool? mediaConnected,
    String? failureMessage,
    P2PIncomingCall? incoming,
    bool clearCallId = false,
    bool clearRemote = false,
    bool clearRenderers = false,
    bool clearFailure = false,
    bool clearIncoming = false,
  }) {
    return P2PCallState(
      phase: phase ?? this.phase,
      callId: clearCallId ? null : (callId ?? this.callId),
      remoteUserId: clearRemote ? null : (remoteUserId ?? this.remoteUserId),
      remoteName: clearRemote ? null : (remoteName ?? this.remoteName),
      withVideo: withVideo ?? this.withVideo,
      localAudio: localAudio ?? this.localAudio,
      localVideo: localVideo ?? this.localVideo,
      remoteVideo: remoteVideo ?? this.remoteVideo,
      remoteAudio: remoteAudio ?? this.remoteAudio,
      isSpeakerphoneOn: isSpeakerphoneOn ?? this.isSpeakerphoneOn,
      localRenderer: clearRenderers
          ? null
          : (localRenderer ?? this.localRenderer),
      remoteRenderer: clearRenderers
          ? null
          : (remoteRenderer ?? this.remoteRenderer),
      mediaConnected: mediaConnected ?? this.mediaConnected,
      failureMessage:
          clearFailure ? null : (failureMessage ?? this.failureMessage),
      incoming: clearIncoming ? null : (incoming ?? this.incoming),
    );
  }
}

class P2PCallNotifier extends StateNotifier<P2PCallState> {
  P2PCallNotifier(this._ref) : super(const P2PCallState()) {
    _service.onLog = (s) => debugPrint('[P2P] $s');
    _wireServiceCallbacks();
    _ref.listen<AuthState>(authProvider, (prev, next) {
      _onAuthChanged(prev, next);
    }, fireImmediately: true);
  }

  final Ref _ref;
  final P2PCallService _service = P2PCallService();
  P2PCallService get service => _service;

  // ── Per-call tracking — used to assemble a CallLogEntry on every
  //    terminal event. Reset after each append. peerEmail is null on
  //    incoming (the signaling payload doesn't carry it yet).
  DateTime? _callStartedAt;
  DateTime? _callConnectedAt;
  CallDirection? _logDirection;
  String? _logPeerUserId;
  String? _logPeerName;
  String? _logPeerEmail;
  bool _logWithVideo = true;
  // Keep the callId after the state copy nukes it, so the terminal
  // log helper can still produce a stable entry id.
  String? _logCallId;

  void _trackOutgoing({
    required String callId,
    required User target,
    required bool withVideo,
  }) {
    _callStartedAt = DateTime.now();
    _callConnectedAt = null;
    _logDirection = CallDirection.outgoing;
    _logPeerUserId = target.id;
    _logPeerName = target.name;
    _logPeerEmail = target.email.isEmpty ? null : target.email;
    _logWithVideo = withVideo;
    _logCallId = callId;
  }

  void _trackIncoming(P2PIncomingCall call) {
    _callStartedAt = DateTime.now();
    _callConnectedAt = null;
    _logDirection = CallDirection.incoming;
    _logPeerUserId = call.fromUserId;
    _logPeerName = call.fromName;
    _logPeerEmail = null;
    // The caller's intent now arrives in the signaling payload —
    // use it directly so the call log records the right kind.
    _logWithVideo = call.withVideo;
    _logCallId = call.callId;
  }

  /// Append one entry to the call log. Repository dedups by id, so
  /// firing this twice for the same call is harmless. After append,
  /// the per-call trackers are cleared so the next call starts clean.
  void _appendLog(CallOutcome outcome, {String? overrideCallId}) {
    final id = overrideCallId ?? _logCallId;
    final dir = _logDirection;
    final peerId = _logPeerUserId;
    if (id == null || dir == null || peerId == null) return;
    final startedAt = _callStartedAt ?? DateTime.now();
    final connectedAt = _callConnectedAt;
    final durationSeconds =
        (outcome == CallOutcome.answered && connectedAt != null)
            ? DateTime.now().difference(connectedAt).inSeconds
            : 0;
    final entry = CallLogEntry(
      id: id,
      peerUserId: peerId,
      peerName: _logPeerName ?? 'Unknown',
      peerEmail: _logPeerEmail,
      startedAt: startedAt,
      durationSeconds: durationSeconds,
      direction: dir,
      outcome: outcome,
      withVideo: _logWithVideo,
    );
    // Fire-and-forget — repository writes to SharedPreferences.
    _ref.read(callLogRepositoryProvider).append(entry);
    _callStartedAt = null;
    _callConnectedAt = null;
    _logDirection = null;
    _logPeerUserId = null;
    _logPeerName = null;
    _logPeerEmail = null;
    _logCallId = null;
  }

  // ── Auth → service lifecycle ─────────────────────────────────────

  Future<void> _onAuthChanged(AuthState? prev, AuthState next) async {
    if (next.status == AuthStatus.authenticated &&
        next.token != null &&
        next.user != null) {
      try {
        await _service.connect(
          jwtToken: next.token!,
          me: P2PCallParticipant(
            userId: next.user!.id,
            name: next.user!.name,
            email: next.user!.email,
          ),
        );
      } catch (e) {
        debugPrint('[P2P] connect failed: $e');
      }
    } else if (next.status == AuthStatus.unauthenticated) {
      await _service.dispose();
    }
  }

  void _wireServiceCallbacks() {
    _service.onIncomingCall = (call) async {
      // If we're already in a call, auto-decline. Concurrent calls
      // are out of scope for now.
      if (state.phase != P2PCallPhase.idle &&
          state.phase != P2PCallPhase.ended &&
          state.phase != P2PCallPhase.failed) {
        _service.declineCall(call);
        return;
      }
      _trackIncoming(call);
      state = state.copyWith(
        phase: P2PCallPhase.incoming,
        callId: call.callId,
        remoteUserId: call.fromUserId,
        remoteName: call.fromName,
        incoming: call,
        // Use the caller's declared media intent so the ringing UI
        // can show only the matching accept button. The service's
        // `_parseCallTypeAsVideo` resolves the actual value from the
        // socket payload (it accepts `callType` / `type` strings and
        // `withVideo` / `video` booleans) and defaults to `false`
        // (audio) when the backend forwards none of them.
        withVideo: call.withVideo,
      );
      // ─── STEP 8: STATE MANAGEMENT LOGS ──────────────────────────
      // What the Riverpod state now holds for the incoming call.
      // If `State callType` here disagrees with the receiver socket
      // log (Step 5), there's a bug in this notifier; otherwise the
      // state is faithful to the wire payload.
      debugPrint('==============================');
      debugPrint('UPDATING INCOMING CALL STATE');
      debugPrint('State callType: ${state.withVideo ? "video" : "audio"}');
      debugPrint('State withVideo: ${state.withVideo}');
      debugPrint('State callId: ${state.callId}');
      debugPrint('State remoteName: ${state.remoteName}');
      debugPrint('==============================');
    };

    _service.onCallAccepted = (callId, calleeSid) {
      // Caller side: callee accepted, WebRTC handshake in progress.
      // Move to `connecting` so the call screen swaps the "Calling…"
      // copy for "Connecting…" — visual progress while the offer/
      // answer + ICE negotiation runs. `onMediaConnected` flips us
      // to `active` once media flows.
      if (state.phase == P2PCallPhase.outgoing) {
        state = state.copyWith(phase: P2PCallPhase.connecting);
      }
    };

    _service.onCallDeclined = (callId) {
      // Caller side: my outgoing call was rejected by the peer.
      _appendLog(CallOutcome.declined, overrideCallId: callId);
      state = state.copyWith(
        phase: P2PCallPhase.failed,
        failureMessage: 'Call declined',
      );
      _scheduleResetToIdle();
    };

    _service.onCallCancelled = (callId) {
      // Callee side: caller hung up before I answered → I missed it.
      _appendLog(CallOutcome.missed, overrideCallId: callId);
      state = state.copyWith(
        phase: P2PCallPhase.failed,
        failureMessage: 'Caller cancelled',
        clearIncoming: true,
      );
      _scheduleResetToIdle();
    };

    _service.onCallEnded = (callId, reason) async {
      // If media ever connected, this is an "answered" call with a
      // real duration; otherwise it's a connection failure.
      final outcome = _callConnectedAt != null
          ? CallOutcome.answered
          : CallOutcome.failed;
      _appendLog(outcome, overrideCallId: callId);
      await _disposeRenderers();
      // Mirror endCall(): drop the speaker route so the OS goes back
      // to its normal audio profile.
      await _applyAudioRoute(false);
      state = state.copyWith(
        phase: P2PCallPhase.ended,
        failureMessage: null,
        isSpeakerphoneOn: false,
        clearRenderers: true,
        mediaConnected: false,
      );
      _scheduleResetToIdle();
    };

    _service.onCalleeOffline = (callId) {
      // Caller side: peer was offline / unreachable.
      _appendLog(CallOutcome.missed, overrideCallId: callId);
      state = state.copyWith(
        phase: P2PCallPhase.failed,
        failureMessage: 'User unavailable',
      );
      _scheduleResetToIdle();
    };

    _service.onMediaConnected = () {
      _callConnectedAt = DateTime.now();
      state = state.copyWith(
        phase: P2PCallPhase.active,
        mediaConnected: true,
      );
    };

    _service.onLocalStream = (stream) async {
      // Note: the local preview is mirrored at the RTCVideoView
      // level (see _LocalPip in p2p_call_screen.dart), not on the
      // renderer — flutter_webrtc doesn't expose a mirror property
      // on the renderer itself.
      final r = state.localRenderer ?? RTCVideoRenderer();
      if (state.localRenderer == null) await r.initialize();
      r.srcObject = stream;
      state = state.copyWith(localRenderer: r);
      debugPrint('[P2P] localStreamInitialized renderer=ready '
          'videoTracks=${stream.getVideoTracks().length} '
          'audioTracks=${stream.getAudioTracks().length}');
      // Apply the desired audio route NOW that the platform audio
      // session is alive (getUserMedia kicks the session into
      // `playAndRecord` on iOS / `MODE_IN_COMMUNICATION` on Android).
      // Calling `Helper.setSpeakerphoneOn` BEFORE this point is a
      // no-op — the OS hasn't built the session yet. Defaults:
      //   audio call → earpiece (speakerOn=false)
      //   video call → speaker  (speakerOn=true)
      // Mirrors WhatsApp / FaceTime — users don't want their cheek
      // pressed to the screen during a video call.
      await _applyAudioRoute(state.isSpeakerphoneOn);
    };

    _service.onRemoteStream = (stream) async {
      final r = state.remoteRenderer ?? RTCVideoRenderer();
      final isNew = state.remoteRenderer == null;
      if (isNew) await r.initialize();
      r.srcObject = stream;
      // We DELIBERATELY do NOT trust `RTCVideoRenderer.value.renderVideo`
      // for the camera-off swap. flutter_webrtc keeps that flag `true`
      // as long as ANY frames are flowing — including the zero-filled
      // black frames that the WebRTC engine substitutes when the peer
      // does `track.enabled = false`. We hit that exact false positive
      // before: peer toggles off, renderVideo stays true, RTCVideoView
      // happily paints black squares on top of the backdrop → fully
      // black screen.
      //
      // Instead we rely on TWO explicit signals only:
      //   1. `track.onMute` / `track.onUnMute` — fired by native
      //      WebRTC when RTP packets stop / resume (driven from
      //      `onTrack` in p2p_call_service.dart). Slightly delayed
      //      (iOS ~5s, Android ~3s) but always eventually correct.
      //   2. `call-media-state` socket event from the peer — immediate
      //      but depends on the signaling server forwarding it.
      //
      // Both feed into `onRemoteVideoToggled` below. Initial value
      // for `remoteVideo` is `true` because the moment `onRemoteStream`
      // fires we know a video track was negotiated and `onTrack` will
      // attach mute listeners — until those say otherwise, assume
      // video is flowing (matches WhatsApp's optimistic assumption).
      final hasVideoTrack = stream.getVideoTracks().isNotEmpty;
      state = state.copyWith(
        remoteRenderer: r,
        remoteVideo: hasVideoTrack,
      );
      debugPrint('[P2P] remoteStreamReceived rendererAttached=true '
          'videoTracks=${stream.getVideoTracks().length} '
          'audioTracks=${stream.getAudioTracks().length} '
          'initialRemoteVideo=$hasVideoTrack');
    };

    _service.onRemoteVideoToggled = (enabled) {
      // Peer turned their camera on/off — swap the remote tile
      // between the live RTCVideoView and an avatar backdrop.
      // Triggered by EITHER:
      //   • `track.onMute` / `track.onUnMute` (native WebRTC event
      //     when RTP video packets stop / resume)
      //   • `call-media-state` socket event from the peer (immediate
      //     in-band signal that the peer toggled their camera).
      // Whichever fires first wins — they're idempotent so a repeat
      // notification is harmless.
      debugPrint('==============================');
      debugPrint(enabled ? 'REMOTE CAMERA ON' : 'REMOTE CAMERA OFF');
      debugPrint('REMOTE VIDEO ENABLED: $enabled');
      debugPrint('==============================');
      state = state.copyWith(remoteVideo: enabled);
    };

    _service.onRemoteAudioToggled = (enabled) {
      debugPrint('[P2P] REMOTE AUDIO ENABLED: $enabled');
      state = state.copyWith(remoteAudio: enabled);
    };
  }

  // ── Actions ──────────────────────────────────────────────────────

  /// Caller side — kick off an outgoing call.
  Future<void> startCall(User target, {required bool withVideo}) async {
    if (state.phase != P2PCallPhase.idle &&
        state.phase != P2PCallPhase.ended &&
        state.phase != P2PCallPhase.failed) {
      return;
    }
    if (!_service.isConnected) {
      state = state.copyWith(
        phase: P2PCallPhase.failed,
        failureMessage: 'Not connected to server',
      );
      _scheduleResetToIdle();
      return;
    }
    final callId = _service.initiateCall(
      target: P2PCallParticipant(
        userId: target.id,
        name: target.name,
        email: target.email,
      ),
      withVideo: withVideo,
    );
    _trackOutgoing(callId: callId, target: target, withVideo: withVideo);
    state = state.copyWith(
      phase: P2PCallPhase.outgoing,
      callId: callId,
      remoteUserId: target.id,
      remoteName: target.name,
      withVideo: withVideo,
      localAudio: true,
      localVideo: withVideo,
      // Speaker default mirrors WhatsApp / FaceTime: speakerphone
      // ON for video (you're holding the phone arm's-length to see
      // the screen), OFF for audio (phone-to-ear posture). User can
      // flip via `toggleSpeakerphone`. Actual routing happens in
      // `onLocalStream` once the audio session is alive.
      isSpeakerphoneOn: withVideo,
      mediaConnected: false,
      clearFailure: true,
      clearIncoming: true,
      clearRenderers: true,
    );
    debugPrint('[P2P] outgoingCallType=${withVideo ? "video" : "audio"} '
        'speakerphoneState=${withVideo ? "ON (default for video)" : "OFF (default for audio)"}');
  }

  /// Callee side — accept the ringing call.
  ///
  /// Uses the `connecting` phase (not `outgoing`) so the call screen
  /// can render the right copy — `Connecting to [name]…` not
  /// `Calling [name]…`. `onMediaConnected` flips us to `active`.
  void acceptIncoming({required bool withVideo}) {
    final incoming = state.incoming;
    if (incoming == null) return;
    // ─── STEP 10: ACCEPT FLOW LOGS ──────────────────────────────────
    // Captures the call type at the exact moment the user taps
    // Accept. `Accepted callType` should match what the incoming UI
    // showed (Step 9). If they differ, the accept button's onTap is
    // sending the wrong `withVideo` (the overlay's
    // `if (call.withVideo)` / else branch wires this).
    debugPrint('==============================');
    debugPrint('ACCEPT CALL');
    debugPrint('Accepted callType: ${withVideo ? "video" : "audio"}');
    debugPrint('Accepted withVideo: $withVideo');
    debugPrint('Incoming callId: ${incoming.callId}');
    debugPrint('Incoming originalCallType: '
        '${incoming.withVideo ? "video" : "audio"}');
    debugPrint('Mismatch?: '
        '${incoming.withVideo != withVideo ? "YES — accept button wired wrong" : "no"}');
    debugPrint('==============================');
    _service.acceptCall(call: incoming, withVideo: withVideo);
    // Now we know the real media kind for the call log entry that
    // will be appended on `onCallEnded`.
    _logWithVideo = withVideo;
    state = state.copyWith(
      phase: P2PCallPhase.connecting,
      withVideo: withVideo,
      localAudio: true,
      localVideo: withVideo,
      // Match caller-side default — speaker ON for video, OFF for
      // audio. Applied for real once `onLocalStream` lands.
      isSpeakerphoneOn: withVideo,
      mediaConnected: false,
    );
    debugPrint('[P2P] incomingCallType=${withVideo ? "video" : "audio"} '
        'accepted speakerphoneState=${withVideo ? "ON" : "OFF"}');
  }

  /// Callee side — reject the ringing call.
  void declineIncoming() {
    final incoming = state.incoming;
    if (incoming != null) _service.declineCall(incoming);
    _appendLog(CallOutcome.declined, overrideCallId: state.callId);
    state = state.copyWith(
      phase: P2PCallPhase.idle,
      clearCallId: true,
      clearRemote: true,
      clearIncoming: true,
      clearFailure: true,
    );
  }

  /// Caller side — cancel before the callee answers.
  void cancelOutgoing() {
    _service.cancelCall();
    _appendLog(CallOutcome.cancelled, overrideCallId: state.callId);
    state = state.copyWith(
      phase: P2PCallPhase.idle,
      clearCallId: true,
      clearRemote: true,
      clearFailure: true,
    );
  }

  /// Either side — hang up an active call.
  Future<void> endCall() async {
    await _service.endCall();
    await _disposeRenderers();
    // Take the audio session out of speakerphone so the device's
    // next non-call audio (notification, ringtone) plays through
    // the normal speaker / earpiece path. Forgetting this leaves
    // the speakerphone latched after a video call ends, which
    // surprises users when the next FCM notification blasts.
    await _applyAudioRoute(false);
    state = state.copyWith(
      phase: P2PCallPhase.ended,
      isSpeakerphoneOn: false,
      clearRenderers: true,
      mediaConnected: false,
    );
    _scheduleResetToIdle();
  }

  void toggleAudio() {
    final next = !state.localAudio;
    _service.setLocalAudio(next);
    state = state.copyWith(localAudio: next);
  }

  void toggleVideo() {
    final next = !state.localVideo;
    _service.setLocalVideo(next);
    state = state.copyWith(localVideo: next);
  }

  /// Flip the audio route between earpiece (false) and loudspeaker
  /// (true). Optimistically updates UI state, then applies via
  /// `Helper.setSpeakerphoneOn` which is best-effort (void return).
  /// Safe to call before the audio session is alive — the helper
  /// no-ops gracefully on the platform side.
  Future<void> toggleSpeakerphone() async {
    final next = !state.isSpeakerphoneOn;
    state = state.copyWith(isSpeakerphoneOn: next);
    await _applyAudioRoute(next);
  }

  /// Push the desired audio route to the platform. Uses
  /// flutter_webrtc's `Helper.setSpeakerphoneOn` which sets:
  ///   • Android: `AudioManager.isSpeakerphoneOn = true/false`
  ///              (assumes `MODE_IN_COMMUNICATION`, which the WebRTC
  ///              engine sets at getUserMedia time)
  ///   • iOS:     `AVAudioSession.overrideOutputAudioPort(...)`
  ///              with `.speaker` or `.none` (default earpiece)
  /// The call is wrapped in a try because the helper throws on some
  /// platform combinations when the audio session isn't ready yet
  /// (e.g. called during the brief window between `accept` and
  /// `getUserMedia`). We retry once `onLocalStream` lands.
  Future<void> _applyAudioRoute(bool useSpeaker) async {
    try {
      await Helper.setSpeakerphoneOn(useSpeaker);
      debugPrint('[P2P] audio route → ${useSpeaker ? "SPEAKER" : "EARPIECE"}');
    } catch (e) {
      debugPrint('[P2P] setSpeakerphoneOn($useSpeaker) failed: $e');
    }
  }

  void clearTransientState() {
    if (state.phase == P2PCallPhase.failed ||
        state.phase == P2PCallPhase.ended) {
      state = const P2PCallState();
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────

  Future<void> _disposeRenderers() async {
    final l = state.localRenderer;
    final r = state.remoteRenderer;
    if (l != null) {
      try {
        l.srcObject = null;
        await l.dispose();
      } catch (_) {}
    }
    if (r != null) {
      try {
        r.srcObject = null;
        await r.dispose();
      } catch (_) {}
    }
  }

  void _scheduleResetToIdle() {
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      if (state.phase == P2PCallPhase.failed ||
          state.phase == P2PCallPhase.ended) {
        state = const P2PCallState();
      }
    });
  }

  @override
  void dispose() {
    _disposeRenderers();
    _service.dispose();
    super.dispose();
  }
}

final p2pCallProvider =
    StateNotifierProvider<P2PCallNotifier, P2PCallState>(
        (ref) => P2PCallNotifier(ref));
