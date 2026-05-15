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
import 'package:permission_handler/permission_handler.dart';

import 'dart:async';

import '../../core/services/ongoing_call_fg_service.dart';
import '../../core/services/p2p_call_service.dart';
import '../../core/services/renderer_manager.dart';
import '../../core/services/ringtone_service.dart';
import '../settings/video_preferences_provider.dart';
import '../../data/models/call_rating_models.dart';
import '../../data/models/models.dart';
import '../auth/auth_provider.dart';
import '../feedback/call_rating_provider.dart';
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

/// Drives the incoming-call overlay's camera-preview UI.
///   • `idle`     — no warm-up requested (audio call, or pre-permission).
///   • `warming`  — `getUserMedia()` in flight, show a loading shimmer.
///   • `ready`    — local renderer is attached, paint live preview.
///   • `denied`   — user denied camera/mic, fall back to avatar UI.
enum P2PPreviewState { idle, warming, ready, denied }

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
  // Tri-state for the warm-up camera preview shown over the
  // incoming-call overlay. `idle` is the resting state; `warming`
  // means we're awaiting `getUserMedia()`; `ready` means the
  // renderer is attached and frames are flowing; `denied` means the
  // camera/mic permission was declined and the overlay should fall
  // back to its plain avatar UI. Only meaningful while
  // `phase == incoming`.
  final P2PPreviewState previewState;
  /// Whether the user has minimized the active call. When `true` the
  /// floating mini-call overlay paints (so the call is visually
  /// present from any screen) and the full-screen call route is NOT
  /// mounted. Tapping the mini-call sets this back to `false` and
  /// the global router pushes /p2p-call.
  final bool minimized;

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
    this.previewState = P2PPreviewState.idle,
    this.minimized = false,
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
    P2PPreviewState? previewState,
    bool? minimized,
    bool clearCallId = false,
    bool clearRemote = false,
    bool clearRenderers = false,
    bool clearLocalRenderer = false,
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
      localRenderer: (clearRenderers || clearLocalRenderer)
          ? null
          : (localRenderer ?? this.localRenderer),
      remoteRenderer: clearRenderers
          ? null
          : (remoteRenderer ?? this.remoteRenderer),
      mediaConnected: mediaConnected ?? this.mediaConnected,
      failureMessage:
          clearFailure ? null : (failureMessage ?? this.failureMessage),
      incoming: clearIncoming ? null : (incoming ?? this.incoming),
      previewState: previewState ?? this.previewState,
      minimized: minimized ?? this.minimized,
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
    // Mirror the outgoing-video-quality preference into the live
    // P2P sender whenever the user moves the dial. Without this the
    // setting is just decorative — see video_quality_profile.dart
    // for what the bitrate caps actually do.
    _service.applyVideoQuality(_ref.read(outgoingVideoQualityProvider));
    _qualityListenerOff = _ref.listen<OutgoingVideoQuality>(
      outgoingVideoQualityProvider,
      (_, next) {
        // ignore: discarded_futures
        _service.applyVideoQuality(next);
      },
    );
  }

  ProviderSubscription<OutgoingVideoQuality>? _qualityListenerOff;

  final Ref _ref;
  final P2PCallService _service = P2PCallService();
  P2PCallService get service => _service;

  // ── Ringtone + timers (docs/CALL_RINGTONE_FLUTTER.md §4–§5) ──────
  //
  // _autoDeclineTimer    — 30 s timer started when `incoming-call`
  //                        arrives. If the user doesn't accept or
  //                        decline before it fires, we decline on
  //                        their behalf so the caller sees the
  //                        "Declined" state instead of ringing
  //                        forever.
  // _callerBailoutTimer  — 45 s timer started when `startCall` fires.
  //                        Matches the web client's behaviour: if no
  //                        server event has arrived in that window we
  //                        give up gracefully and surface
  //                        "User unavailable".
  // _seenCallIds         — dedup for the dual transport. Same callId
  //                        usually arrives over BOTH socket and FCM;
  //                        the second arrival is a no-op. 60 s
  //                        eviction so a re-attempt with the same id
  //                        (rare but possible after a backend bounce)
  //                        still works.
  Timer? _autoDeclineTimer;
  Timer? _callerBailoutTimer;
  final Set<String> _seenIncomingCallIds = {};

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
      // Dedup: the same `incoming-call` can arrive over BOTH the
      // signaling socket AND the FCM background handler. First
      // arrival wins; the second is a no-op. 60 s eviction so a
      // re-attempt with the same callId after a backend bounce
      // still works. Spec §4.3.
      if (_seenIncomingCallIds.contains(call.callId)) {
        debugPrint('[P2P] dedup: callId=${call.callId} already seen — '
            'ignoring duplicate incoming-call event');
        return;
      }
      _seenIncomingCallIds.add(call.callId);
      Future.delayed(const Duration(seconds: 60),
          () => _seenIncomingCallIds.remove(call.callId));

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
        previewState: P2PPreviewState.idle,
      );
      // For video calls, kick off the WhatsApp-style live self
      // preview NOW — even before the user taps Accept. The stream
      // we acquire here is reused as the call's outgoing video track
      // once acceptance fires, so the transition is flicker-free
      // (no second `getUserMedia()` round-trip on accept).
      //
      // We do NOT block the incoming-state update on this — the
      // overlay should render the moment the ring lands; the
      // preview slides in underneath when getUserMedia resolves.
      if (call.withVideo) {
        // Fire-and-forget; errors / denials surface via state.
        // ignore: discarded_futures
        startIncomingPreview();
      }
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
      // ── Start incoming ringtone + 30 s auto-decline timer
      // per docs/CALL_RINGTONE_FLUTTER.md §4.1 + §4 entry in
      // the foreground table.
      // ignore: discarded_futures
      RingtoneService.instance.startIncoming();
      _autoDeclineTimer?.cancel();
      _autoDeclineTimer = Timer(const Duration(seconds: 30), () {
        if (state.phase != P2PCallPhase.incoming) return;
        debugPrint('[P2P] auto-decline after 30s of no user action');
        // ignore: discarded_futures
        declineIncoming();
      });
    };

    _service.onCallAccepted = (callId, calleeSid) {
      // Caller side: callee accepted, WebRTC handshake in progress.
      // Move to `connecting` so the call screen swaps the "Calling…"
      // copy for "Connecting…" — visual progress while the offer/
      // answer + ICE negotiation runs. `onMediaConnected` flips us
      // to `active` once media flows.
      _stopRingtoneSilently();
      _cancelLifecycleTimers();
      if (state.phase == P2PCallPhase.outgoing) {
        state = state.copyWith(phase: P2PCallPhase.connecting);
        // Connecting = mic/camera about to be in heavy use; start the
        // foreground service NOW so the OS keeps those resources alive
        // even if the user immediately presses the power button.
        // ignore: discarded_futures
        _startFgService();
      }
    };

    _service.onCallDeclined = (callId) async {
      // Caller side: my outgoing call was rejected by the peer.
      _stopRingtoneSilently();
      _cancelLifecycleTimers();
      _appendLog(CallOutcome.declined, overrideCallId: callId);
      // ignore: discarded_futures
      _stopFgService();
      // Renderer leak fix: if the WebRTC handshake had started and
      // `onLocalStream` already fired, `state.localRenderer` exists.
      // Without this disposal the renderer outlives the call and
      // BLASTBufferQueue spams "Can't acquire next buffer" lines.
      await _disposeRenderers();
      state = state.copyWith(
        phase: P2PCallPhase.failed,
        failureMessage: 'Call declined',
        minimized: false,
        clearRenderers: true,
        mediaConnected: false,
      );
      _scheduleResetToIdle();
    };

    _service.onCallCancelled = (callId) async {
      // Callee side: caller hung up before I answered → I missed it.
      _stopRingtoneSilently();
      _cancelLifecycleTimers();
      _appendLog(CallOutcome.missed, overrideCallId: callId);
      // Kill any warm-up preview we kicked off when the ring landed.
      await stopIncomingPreview();
      state = state.copyWith(
        phase: P2PCallPhase.failed,
        failureMessage: 'Caller cancelled',
        clearIncoming: true,
        previewState: P2PPreviewState.idle,
      );
      _scheduleResetToIdle();
    };

    _service.onCallEnded = (callId, reason) async {
      // Belt-and-braces: any path that gets us here means the call
      // is over for both sides; ringtones must stop and timers must
      // be cleared. Safe to call even if neither is active.
      _stopRingtoneSilently();
      _cancelLifecycleTimers();
      // If media ever connected, this is an "answered" call with a
      // real duration; otherwise it's a connection failure.
      final answered = _callConnectedAt != null;
      final outcome =
          answered ? CallOutcome.answered : CallOutcome.failed;
      // Compute the actual duration BEFORE we null `_callConnectedAt`
      // later in this method — rating eligibility needs it.
      final ratedDuration = answered
          ? DateTime.now().difference(_callConnectedAt!)
          : Duration.zero;
      final ratedPeerName = _logPeerName ?? state.remoteName ?? 'Mizdah user';
      final ratedKind = _logWithVideo
          ? RatingKind.p2pVideo
          : RatingKind.p2pAudio;

      _appendLog(outcome, overrideCallId: callId);
      await _stopFgService();
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
        minimized: false,
      );
      _scheduleResetToIdle();

      // Fire-and-forget post-call rating eligibility check. All the
      // gates (duration, sample rate, cooldown) live in the rating
      // provider; we hand it the context and walk away.
      // ignore: discarded_futures
      _ref.read(callRatingProvider.notifier).maybePromptFor(
            RatingPromptRequest(
              callId: callId,
              kind: ratedKind,
              peerOrMeetingName: ratedPeerName,
              duration: ratedDuration,
              wasAnswered: answered,
            ),
          );
    };

    _service.onCalleeOffline = (callId) async {
      // Caller side: peer was offline / unreachable.
      _stopRingtoneSilently();
      _cancelLifecycleTimers();
      _appendLog(CallOutcome.missed, overrideCallId: callId);
      // ignore: discarded_futures
      _stopFgService();
      // Same renderer-leak fix as `onCallDeclined`.
      await _disposeRenderers();
      state = state.copyWith(
        phase: P2PCallPhase.failed,
        failureMessage: 'User unavailable',
        minimized: false,
        clearRenderers: true,
        mediaConnected: false,
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
      //
      // Route through RendererManager so disposal is keyed and the
      // leak-dump diagnostic can spot a P2P renderer that outlived
      // its call. `acquire` is idempotent — same key returns the
      // same instance, so this is safe to call on every
      // onLocalStream (which can fire twice during accept).
      final r =
          await RendererManager.instance.acquire(_kP2PLocalRendererKey);
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
      final r =
          await RendererManager.instance.acquire(_kP2PRemoteRendererKey);
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
    // ── Ringback + bail-out timer per docs/CALL_RINGTONE_FLUTTER.md §5
    // ignore: discarded_futures
    RingtoneService.instance.startRingback();
    _armCallerBailoutTimer();
  }

  /// 45 s safety net for outgoing calls. If no server event lands
  /// in that window — typical when the callee's device is offline
  /// AND the backend's `call-user-offline` event doesn't fire
  /// (network drop on the signaling server, race condition) — we
  /// give up gracefully and surface "User unavailable". Cleared
  /// every time a terminal event arrives.
  void _armCallerBailoutTimer() {
    _callerBailoutTimer?.cancel();
    _callerBailoutTimer = Timer(const Duration(seconds: 45), () {
      if (state.phase != P2PCallPhase.outgoing) return;
      debugPrint('[P2P] caller bail-out (45s, no response)');
      _service.cancelCall();
      _stopRingtoneSilently();
      _appendLog(CallOutcome.missed, overrideCallId: state.callId);
      state = state.copyWith(
        phase: P2PCallPhase.failed,
        failureMessage: 'User unavailable',
      );
      _scheduleResetToIdle();
    });
  }

  void _stopRingtoneSilently() {
    // ignore: discarded_futures
    RingtoneService.instance.stop();
  }

  void _cancelLifecycleTimers() {
    _autoDeclineTimer?.cancel();
    _autoDeclineTimer = null;
    _callerBailoutTimer?.cancel();
    _callerBailoutTimer = null;
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
    // Stop the incoming ringtone + cancel the 30 s auto-decline
    // timer the moment the user picks up.
    _stopRingtoneSilently();
    _cancelLifecycleTimers();
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
      minimized: false,
    );
    // Start the foreground service so mic + camera survive the user
    // immediately pressing the power button after answering.
    // ignore: discarded_futures
    _startFgService();
    debugPrint('[P2P] incomingCallType=${withVideo ? "video" : "audio"} '
        'accepted speakerphoneState=${withVideo ? "ON" : "OFF"}');
  }

  /// Callee side — reject the ringing call.
  Future<void> declineIncoming() async {
    _stopRingtoneSilently();
    _cancelLifecycleTimers();
    final incoming = state.incoming;
    if (incoming != null) _service.declineCall(incoming);
    _appendLog(CallOutcome.declined, overrideCallId: state.callId);
    // Tear down the warm-up preview (camera + mic + renderer) — the
    // call never reached the active phase, so no PC holds the
    // stream and we own teardown end-to-end.
    await stopIncomingPreview();
    state = state.copyWith(
      phase: P2PCallPhase.idle,
      clearCallId: true,
      clearRemote: true,
      clearIncoming: true,
      clearFailure: true,
      previewState: P2PPreviewState.idle,
    );
  }

  /// Caller side — cancel before the callee answers.
  Future<void> cancelOutgoing() async {
    _stopRingtoneSilently();
    _cancelLifecycleTimers();
    _service.cancelCall();
    await _stopFgService();
    // Defensive: usually no renderers exist yet at cancel time
    // (handshake hasn't reached onLocalStream / onRemoteStream),
    // but if the user managed to tap Cancel after the first frame,
    // the renderer is alive. The release calls are idempotent so
    // this is safe in both cases.
    await _disposeRenderers();
    _appendLog(CallOutcome.cancelled, overrideCallId: state.callId);
    state = state.copyWith(
      phase: P2PCallPhase.idle,
      clearCallId: true,
      clearRemote: true,
      clearFailure: true,
      clearRenderers: true,
      mediaConnected: false,
      minimized: false,
    );
  }

  /// Either side — hang up an active call.
  Future<void> endCall() async {
    _stopRingtoneSilently();
    _cancelLifecycleTimers();
    // Capture rating context before we tear state down — `_log*`
    // fields get cleared by `_appendLog` and `_callConnectedAt`
    // gets reset by `_resetCallState`.
    final answered = _callConnectedAt != null;
    final ratedDuration = answered
        ? DateTime.now().difference(_callConnectedAt!)
        : Duration.zero;
    final ratedCallId = state.callId ?? _logCallId ?? '';
    final ratedPeerName =
        _logPeerName ?? state.remoteName ?? 'Mizdah user';
    final ratedKind = (_logWithVideo || state.withVideo)
        ? RatingKind.p2pVideo
        : RatingKind.p2pAudio;

    await _service.endCall();
    await _stopFgService();
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
      minimized: false,
    );
    _scheduleResetToIdle();

    // Locally-initiated hang-up: the service doesn't fire
    // `onCallEnded` back to us (it's strictly a remote-end signal),
    // so we prompt here. The remote side will get its own onCallEnded
    // and may also prompt for them — both gates run independently
    // through the rating provider's per-device cooldown.
    if (ratedCallId.isNotEmpty) {
      // ignore: discarded_futures
      _ref.read(callRatingProvider.notifier).maybePromptFor(
            RatingPromptRequest(
              callId: ratedCallId,
              kind: ratedKind,
              peerOrMeetingName: ratedPeerName,
              duration: ratedDuration,
              wasAnswered: answered,
            ),
          );
    }
  }

  // ── Minimize / restore ───────────────────────────────────────────

  /// Drop out of the full-screen call route into the floating mini
  /// overlay. The call itself (peer connection, tracks, renderers)
  /// is untouched — only the UI route changes. The mini overlay
  /// reads `state.minimized` to decide whether to paint.
  void minimize() {
    if (state.phase != P2PCallPhase.active &&
        state.phase != P2PCallPhase.connecting) {
      return;
    }
    if (state.minimized) return;
    debugPrint('==============================');
    debugPrint('[P2P] MINIMIZE callId=${state.callId} '
        'phase=${state.phase}');
    debugPrint('==============================');
    state = state.copyWith(minimized: true);
  }

  /// Inverse of [minimize]. The mini-overlay's tap handler calls
  /// this AND pushes /p2p-call on the global router.
  void restoreFromMinimized() {
    if (!state.minimized) return;
    debugPrint('==============================');
    debugPrint('[P2P] RESTORE FROM MINIMIZED callId=${state.callId} '
        'phase=${state.phase}');
    debugPrint('==============================');
    state = state.copyWith(minimized: false);
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

  // ── Ringing preview (WhatsApp-style self-camera while incoming) ───

  /// Kick off the live self-preview shown over the incoming-call
  /// overlay. Requests camera + mic permission first; on denial the
  /// overlay falls back to its plain avatar UI. On success the
  /// service's `onLocalStream` callback fires and the renderer gets
  /// attached through the normal pipeline — the overlay reads
  /// `state.localRenderer` to paint frames.
  ///
  /// Idempotent: returns early if a warm-up is already in flight or
  /// completed for this ring cycle.
  Future<void> startIncomingPreview() async {
    debugPrint('==============================');
    debugPrint('[P2P] PREVIEW startIncomingPreview() called');
    debugPrint('       phase=${state.phase}');
    debugPrint('       previewState=${state.previewState}');
    debugPrint('       withVideo=${state.withVideo}');
    debugPrint('       localRenderer=${state.localRenderer != null}');
    debugPrint('==============================');
    if (state.phase != P2PCallPhase.incoming) {
      debugPrint('[P2P] PREVIEW ignored — phase=${state.phase}');
      return;
    }
    if (state.previewState == P2PPreviewState.warming ||
        state.previewState == P2PPreviewState.ready) {
      debugPrint('[P2P] PREVIEW ignored — already ${state.previewState}');
      return;
    }
    debugPrint('[P2P] PREVIEW WARMING — requesting camera+mic permission');
    state = state.copyWith(previewState: P2PPreviewState.warming);
    // permission_handler returns a map; we accept "granted" OR
    // "limited" (iOS) as a green light. Anything else is denial.
    final results = await [
      Permission.camera,
      Permission.microphone,
    ].request();
    final camStatus = results[Permission.camera];
    final micStatus = results[Permission.microphone];
    debugPrint('[P2P] PREVIEW permission results '
        'camera=$camStatus microphone=$micStatus');
    final camOk = camStatus?.isGranted == true ||
        camStatus?.isLimited == true;
    final micOk = micStatus?.isGranted == true ||
        micStatus?.isLimited == true;
    if (!camOk || !micOk) {
      debugPrint('[P2P] PREVIEW DENIED camera=$camOk microphone=$micOk '
          '(camStatus=$camStatus micStatus=$micStatus)');
      state = state.copyWith(previewState: P2PPreviewState.denied);
      return;
    }
    // Re-check phase — the ring could have been cancelled while
    // we were waiting on the permission dialog.
    if (state.phase != P2PCallPhase.incoming) {
      debugPrint('[P2P] PREVIEW abort — phase flipped during permission wait');
      return;
    }
    try {
      debugPrint('[P2P] PREVIEW calling service.startLocalPreview()');
      await _service.startLocalPreview(withVideo: true);
      // `onLocalStream` fires synchronously from the service when the
      // stream resolves; that handler attaches the renderer into
      // `state.localRenderer`. We just flip the preview-state flag
      // so the UI knows to show the live feed instead of a shimmer.
      if (state.phase == P2PCallPhase.incoming) {
        state = state.copyWith(previewState: P2PPreviewState.ready);
        debugPrint('[P2P] PREVIEW READY — local renderer attached '
            '(rendererAttached=${state.localRenderer != null})');
      } else {
        debugPrint('[P2P] PREVIEW stream ready but phase flipped to '
            '${state.phase} — leaving state alone');
      }
    } catch (e, st) {
      debugPrint('[P2P] PREVIEW FAILED — $e\n$st');
      state = state.copyWith(previewState: P2PPreviewState.denied);
    }
  }

  /// Stop a warm-up preview that didn't lead to an accepted call —
  /// safe to call multiple times. Disposes the local renderer ONLY
  /// when no peer connection is alive; once the call is connected
  /// the renderer belongs to the call lifecycle.
  Future<void> stopIncomingPreview() async {
    debugPrint('[P2P] stopIncomingPreview previewState=${state.previewState}');
    await _service.stopLocalPreview();
    // Renderer routed through the manager so the same key can be
    // re-acquired by the next call without churning a fresh
    // native handle.
    await RendererManager.instance.release(_kP2PLocalRendererKey);
    state = state.copyWith(
      previewState: P2PPreviewState.idle,
      clearLocalRenderer: true,
    );
  }

  /// Flip the camera between front and back. Works during ringing
  /// preview AND during an active call — the underlying flutter_webrtc
  /// `Helper.switchCamera` operates on the live MediaStreamTrack.
  Future<void> switchCamera() async {
    await _service.switchCamera();
  }

  // ── Lifecycle recovery (screen-lock / app background) ────────────

  /// Called by the call screen's `WidgetsBindingObserver` when the
  /// host app returns to the foreground. Re-applies audio routing,
  /// pokes the renderer's srcObject so the platform view re-paints
  /// (an Android quirk: after a long screen-off the SurfaceView can
  /// keep its last frame frozen until the source is re-bound), and
  /// logs the state of every load-bearing handle for field triage.
  Future<void> onAppResumed() async {
    if (state.phase != P2PCallPhase.active &&
        state.phase != P2PCallPhase.connecting) {
      return;
    }
    debugPrint('==============================');
    debugPrint('CALL: APP RESUMED');
    debugPrint('phase=${state.phase} '
        'callId=${state.callId} '
        'localAudio=${state.localAudio} '
        'localVideo=${state.localVideo} '
        'remoteVideo=${state.remoteVideo} '
        'speakerphone=${state.isSpeakerphoneOn}');
    await _service.recoverFromBackground(
      wantSpeakerphone: state.isSpeakerphoneOn,
    );
    // Defensive re-attach: re-set srcObject on both renderers. Same
    // MediaStream object; this just nudges the underlying SurfaceView
    // / OpenGL texture to repaint. No flicker since the stream is
    // identical — flutter_webrtc compares by reference and short-
    // circuits when the value is unchanged on iOS, but the Android
    // implementation reschedules a redraw which is exactly what we
    // want here.
    final l = state.localRenderer;
    final r = state.remoteRenderer;
    if (l != null) {
      final s = l.srcObject;
      if (s != null) l.srcObject = s;
    }
    if (r != null) {
      final s = r.srcObject;
      if (s != null) r.srcObject = s;
    }
    debugPrint('==============================');
  }

  /// Called by the call screen when the host app moves to the
  /// background. We DELIBERATELY do not pause tracks here — pausing
  /// would mute the user without their consent and is the WhatsApp
  /// anti-pattern we're fixing. We just log the transition so the
  /// field log makes background timing obvious.
  void onAppPaused() {
    if (state.phase != P2PCallPhase.active &&
        state.phase != P2PCallPhase.connecting) {
      return;
    }
    debugPrint('==============================');
    debugPrint('CALL: APP PAUSED');
    debugPrint('phase=${state.phase} '
        'callId=${state.callId} '
        'tracks stay LIVE (audio continues, video stays available)');
    debugPrint('==============================');
  }

  // ── Helpers ──────────────────────────────────────────────────────

  /// Start the Android foreground service that keeps mic + camera
  /// alive while the app is backgrounded. Idempotent — re-firing for
  /// the same call is harmless because the service wrapper coalesces
  /// double-starts. No-op on iOS (the audio + voip background modes
  /// in Info.plist handle the equivalent there, modulo CallKit).
  Future<void> _startFgService() async {
    await OngoingCallForegroundService.instance.start(
      peerName: state.remoteName ?? 'Mizdah user',
      withVideo: state.withVideo,
    );
  }

  /// Stop the Android foreground service. Drops the persistent
  /// notification. No-op on iOS. Idempotent.
  Future<void> _stopFgService() async {
    await OngoingCallForegroundService.instance.stop();
  }

  /// Centralised renderer-key constants for this provider. Keeping
  /// them as private statics (not local literals at each call site)
  /// means a future rename or a switch to a per-call-instance key
  /// touches one line, not five.
  static const String _kP2PLocalRendererKey = 'p2p-local';
  static const String _kP2PRemoteRendererKey = 'p2p-remote';

  /// Tear down both P2P renderers via the manager. Idempotent and
  /// safe to call from any code path (decline, offline, cancel,
  /// end, dispose, network drop).
  Future<void> _disposeRenderers() async {
    await RendererManager.instance.release(_kP2PLocalRendererKey);
    await RendererManager.instance.release(_kP2PRemoteRendererKey);
  }

  void _scheduleResetToIdle() {
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      if (state.phase == P2PCallPhase.failed ||
          state.phase == P2PCallPhase.ended) {
        state = const P2PCallState();
        // Leak detector: by the time we're back to idle, every
        // renderer this provider created must have been released.
        // Anything still present in the manager is a leak — log it
        // loudly in debug so the field log makes the cause grepable.
        // Production builds short-circuit dump() inside the manager.
        if (kDebugMode) {
          final stillAlive = RendererManager.instance.keys
              .where((k) =>
                  k == _kP2PLocalRendererKey ||
                  k == _kP2PRemoteRendererKey)
              .toList();
          if (stillAlive.isNotEmpty) {
            debugPrint('[P2P] LEAK after reset-to-idle: $stillAlive '
                '(should be empty)');
            RendererManager.instance.dump();
          }
        }
      }
    });
  }

  @override
  void dispose() {
    _qualityListenerOff?.close();
    _qualityListenerOff = null;
    _cancelLifecycleTimers();
    _stopRingtoneSilently();
    _disposeRenderers();
    _service.dispose();
    super.dispose();
  }
}

final p2pCallProvider =
    StateNotifierProvider<P2PCallNotifier, P2PCallState>(
        (ref) => P2PCallNotifier(ref));
