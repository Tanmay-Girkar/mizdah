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

enum P2PCallPhase {
  idle,
  outgoing, // I called, waiting for accept
  incoming, // they called, ringing on my side
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
      state = state.copyWith(
        phase: P2PCallPhase.incoming,
        callId: call.callId,
        remoteUserId: call.fromUserId,
        remoteName: call.fromName,
        incoming: call,
        // We don't know if the caller wanted video — assume yes; the
        // user can disable it on their side mid-call.
        withVideo: true,
      );
    };

    _service.onCallAccepted = (callId, calleeSid) {
      // Caller side: we're awaiting media — phase moves to active
      // once the WebRTC handshake completes.
      // No state change needed yet beyond keeping outgoing.
    };

    _service.onCallDeclined = (callId) {
      state = state.copyWith(
        phase: P2PCallPhase.failed,
        failureMessage: 'Call declined',
      );
      _scheduleResetToIdle();
    };

    _service.onCallCancelled = (callId) {
      state = state.copyWith(
        phase: P2PCallPhase.failed,
        failureMessage: 'Caller cancelled',
        clearIncoming: true,
      );
      _scheduleResetToIdle();
    };

    _service.onCallEnded = (callId, reason) async {
      await _disposeRenderers();
      state = state.copyWith(
        phase: P2PCallPhase.ended,
        failureMessage: null,
        clearRenderers: true,
        mediaConnected: false,
      );
      _scheduleResetToIdle();
    };

    _service.onCalleeOffline = (callId) {
      state = state.copyWith(
        phase: P2PCallPhase.failed,
        failureMessage: 'User unavailable',
      );
      _scheduleResetToIdle();
    };

    _service.onMediaConnected = () {
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
    };

    _service.onRemoteStream = (stream) async {
      final r = state.remoteRenderer ?? RTCVideoRenderer();
      if (state.remoteRenderer == null) await r.initialize();
      r.srcObject = stream;
      state = state.copyWith(remoteRenderer: r);
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
    state = state.copyWith(
      phase: P2PCallPhase.outgoing,
      callId: callId,
      remoteUserId: target.id,
      remoteName: target.name,
      withVideo: withVideo,
      localAudio: true,
      localVideo: withVideo,
      mediaConnected: false,
      clearFailure: true,
      clearIncoming: true,
      clearRenderers: true,
    );
  }

  /// Callee side — accept the ringing call.
  void acceptIncoming({required bool withVideo}) {
    final incoming = state.incoming;
    if (incoming == null) return;
    _service.acceptCall(call: incoming, withVideo: withVideo);
    state = state.copyWith(
      phase: P2PCallPhase.outgoing, // transient — moves to active on media
      withVideo: withVideo,
      localAudio: true,
      localVideo: withVideo,
      mediaConnected: false,
    );
  }

  /// Callee side — reject the ringing call.
  void declineIncoming() {
    final incoming = state.incoming;
    if (incoming != null) _service.declineCall(incoming);
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
    state = state.copyWith(
      phase: P2PCallPhase.ended,
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
