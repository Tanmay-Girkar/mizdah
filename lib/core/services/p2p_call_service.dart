// ════════════════════════════════════════════════════════════════════
//  P2P Call Service — direct user-to-user calling over WebRTC
//  ────────────────────────────────────────────────────────────────────
//  Wires the `/signaling-fresh` Socket.IO channel and a single
//  RTCPeerConnection together so a Mizdah user can search someone in
//  the directory and place an audio or video call without going
//  through the SFU. Implements the protocol documented at
//  docs/P2P_CALLING_BACKEND.md (Mizdah P2P Calling Flow).
//
//  Lifecycle:
//    • `connect(token, currentUser)` opens the signaling socket and
//      registers presence with `register-presence`.
//    • `initiateCall(...)` → emits `initiate-call` and listens for
//      `call-accepted` / `call-declined` / `call-user-offline`.
//    • Incoming calls fire `onIncomingCall`. The owning provider
//      decides accept/decline; calls `acceptCall(...)` or
//      `declineCall(...)` here.
//    • Once `call-accepted` arrives (caller side) or the user accepts
//      (callee side), WebRTC negotiation begins: getUserMedia → offer
//      → answer → ICE exchange. ICE candidates that arrive before
//      setRemoteDescription are buffered and flushed.
//    • `endCall()` emits `end-call` and tears down the peer
//      connection.
//
//  State changes are reported via the `onState` callback so the
//  Riverpod provider can rebuild without owning sockets directly.
// ════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../config/api_config.dart';

/// RFC-4122 v4 UUID, just enough for callIds. We avoid pulling in the
/// `uuid` package since the rest of the app doesn't need it.
String _uuidV4() {
  final r = math.Random.secure();
  final bytes = List<int>.generate(16, (_) => r.nextInt(256));
  bytes[6] = (bytes[6] & 0x0F) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3F) | 0x80; // variant 1
  String hex(int i) => bytes[i].toRadixString(16).padLeft(2, '0');
  return '${hex(0)}${hex(1)}${hex(2)}${hex(3)}-'
      '${hex(4)}${hex(5)}-${hex(6)}${hex(7)}-'
      '${hex(8)}${hex(9)}-'
      '${hex(10)}${hex(11)}${hex(12)}${hex(13)}${hex(14)}${hex(15)}';
}

class P2PCallParticipant {
  final String userId;
  final String name;
  final String? email;
  const P2PCallParticipant({
    required this.userId,
    required this.name,
    this.email,
  });
}

class P2PIncomingCall {
  final String callId;
  final String fromUserId;
  final String fromName;
  final String callerSocketId;
  const P2PIncomingCall({
    required this.callId,
    required this.fromUserId,
    required this.fromName,
    required this.callerSocketId,
  });
}

/// Mostly-private WebRTC + signaling worker. The provider holds one of
/// these for the lifetime of the logged-in session.
class P2PCallService {
  P2PCallService({this.onLog});

  /// Optional log sink — useful in dev. The provider wires this up
  /// after construction; mutable on purpose.
  void Function(String)? onLog;

  io.Socket? _socket;
  String? _myUserId;
  String? _myName;
  bool _disposed = false;

  // ── Active-call state ────────────────────────────────────────────
  // Some of these are written-only — the Riverpod provider already
  // tracks the peer identity for UI purposes. We keep them on the
  // service for diagnostic logs and future features (call history).
  String? _currentCallId;
  String? _peerSocketId;
  // ignore: unused_field
  String? _peerUserId;
  // ignore: unused_field
  String? _peerName;
  bool _withVideo = true;
  // ignore: unused_field
  bool _isCaller = false;

  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  // ignore: unused_field
  MediaStream? _remoteStream;

  /// Fresh ICE candidates that arrived before setRemoteDescription.
  /// Flushed inside `_flushIceBuffer` once the remote SDP lands.
  final List<RTCIceCandidate> _iceBuffer = [];

  /// True after we've called `setRemoteDescription` for the current
  /// call. Drives the buffer flush + future incoming candidates.
  bool _remoteDescSet = false;

  // ── Callbacks the provider attaches ──────────────────────────────
  void Function(P2PIncomingCall call)? onIncomingCall;
  void Function(String callId, String calleeSocketId)? onCallAccepted;
  void Function(String callId)? onCallDeclined;
  void Function(String callId)? onCallCancelled;
  void Function(String callId, String reason)? onCallEnded;
  void Function(String callId)? onCalleeOffline;

  /// Fires when the WebRTC handshake completes (ICE connected).
  void Function()? onMediaConnected;

  /// Fires when the local renderer is wired up.
  void Function(MediaStream)? onLocalStream;

  /// Fires when the remote renderer is wired up.
  void Function(MediaStream)? onRemoteStream;

  void _log(String s) {
    onLog?.call(s);
    if (kDebugMode) debugPrint('[P2P] $s');
  }

  // ──────────────────────────────────────────────────────────────────
  //  Socket connection + presence
  // ──────────────────────────────────────────────────────────────────

  bool get isConnected => _socket?.connected == true;

  /// Open the signaling socket and register presence. Idempotent: if
  /// the socket already exists for the same user we skip rebuilding.
  Future<void> connect({
    required String jwtToken,
    required P2PCallParticipant me,
  }) async {
    if (_disposed) return;
    if (_socket != null && isConnected && _myUserId == me.userId) {
      _log('connect() skipped — already connected for ${me.userId}');
      return;
    }
    await _disconnectSocketOnly();

    _myUserId = me.userId;
    _myName = me.name;

    _log('opening signaling socket → ${ApiConfig.signalingUrl}'
        '${ApiConfig.signalingPath}');
    final opts = <String, dynamic>{
      'path': ApiConfig.signalingPath,
      'transports': ['websocket', 'polling'],
      'autoConnect': false,
      'forceNew': true,
      'reconnection': true,
      'reconnectionAttempts': 10,
      'reconnectionDelay': 2000,
      'auth': {'token': jwtToken},
    };
    final socket = io.io(ApiConfig.signalingUrl, opts);
    _socket = socket;

    socket.onConnect((_) {
      _log('✅ socket connected sid=${socket.id}');
      // Register presence on every (re)connect — required for the
      // server to route `initiate-call` to us.
      socket.emit('register-presence', {
        'userId': _myUserId,
        'name': _myName,
      });
    });

    socket.onConnectError((e) => _log('connect_error: $e'));
    socket.onDisconnect((_) => _log('socket disconnected'));
    socket.onError((e) => _log('socket error: $e'));

    // ── Inbound call lifecycle ──────────────────────────────────────
    socket.on('incoming-call', (raw) {
      if (raw is! Map) return;
      final data = Map<String, dynamic>.from(raw);
      _log('incoming-call: $data');
      onIncomingCall?.call(P2PIncomingCall(
        callId: data['callId']?.toString() ?? '',
        fromUserId: data['fromUserId']?.toString() ?? '',
        fromName: data['fromName']?.toString() ?? 'Caller',
        callerSocketId: data['callerSocketId']?.toString() ?? '',
      ));
    });

    socket.on('call-accepted', (raw) async {
      if (raw is! Map) return;
      final callId = raw['callId']?.toString() ?? '';
      final calleeSid = raw['calleeSocketId']?.toString() ?? '';
      _log('call-accepted callId=$callId calleeSid=$calleeSid');
      if (callId != _currentCallId) return;
      _peerSocketId = calleeSid;
      onCallAccepted?.call(callId, calleeSid);
      // Caller now sets up WebRTC and sends the offer.
      await _bringUpCallerSide();
    });

    socket.on('call-declined', (raw) {
      if (raw is! Map) return;
      final callId = raw['callId']?.toString() ?? '';
      _log('call-declined callId=$callId');
      onCallDeclined?.call(callId);
      _resetCallState();
    });

    socket.on('call-cancelled', (raw) {
      if (raw is! Map) return;
      final callId = raw['callId']?.toString() ?? '';
      _log('call-cancelled callId=$callId');
      onCallCancelled?.call(callId);
      _resetCallState();
    });

    socket.on('call-ended', (raw) async {
      if (raw is! Map) return;
      final callId = raw['callId']?.toString() ?? '';
      _log('call-ended callId=$callId');
      onCallEnded?.call(callId, 'remote');
      await _tearDownPeer();
      _resetCallState();
    });

    socket.on('call-user-offline', (raw) {
      if (raw is! Map) return;
      final callId = raw['callId']?.toString() ?? '';
      _log('call-user-offline callId=$callId');
      onCalleeOffline?.call(callId);
      _resetCallState();
    });

    // ── WebRTC SDP + ICE ────────────────────────────────────────────
    socket.on('call-offer', (raw) async {
      if (raw is! Map) return;
      final from = raw['from']?.toString();
      final callId = raw['callId']?.toString();
      final offerMap = raw['offer'];
      _log('← call-offer callId=$callId from=$from');
      if (callId != _currentCallId || offerMap is! Map) return;
      _peerSocketId ??= from;
      // Callee path: this is the cue to set up our PC.
      await _bringUpCalleeSide(offerMap);
    });

    socket.on('call-answer', (raw) async {
      if (raw is! Map) return;
      final callId = raw['callId']?.toString();
      final answerMap = raw['answer'];
      _log('← call-answer callId=$callId');
      if (callId != _currentCallId ||
          answerMap is! Map ||
          _pc == null) {
        return;
      }
      try {
        await _pc!.setRemoteDescription(
          RTCSessionDescription(
            answerMap['sdp']?.toString(),
            answerMap['type']?.toString(),
          ),
        );
        _remoteDescSet = true;
        await _flushIceBuffer();
      } catch (e) {
        _log('setRemoteDescription(answer) failed: $e');
      }
    });

    socket.on('call-ice-candidate', (raw) async {
      if (raw is! Map) return;
      final callId = raw['callId']?.toString();
      final c = raw['candidate'];
      if (callId != _currentCallId || c is! Map) return;
      final candidate = RTCIceCandidate(
        c['candidate']?.toString(),
        c['sdpMid']?.toString(),
        (c['sdpMLineIndex'] as num?)?.toInt(),
      );
      if (_pc == null || !_remoteDescSet) {
        _iceBuffer.add(candidate);
        return;
      }
      try {
        await _pc!.addCandidate(candidate);
      } catch (e) {
        _log('addCandidate failed: $e');
      }
    });

    socket.connect();
  }

  // ──────────────────────────────────────────────────────────────────
  //  Caller actions
  // ──────────────────────────────────────────────────────────────────

  /// Initiate an outgoing call. Returns the generated `callId`. The
  /// provider should drive the UI off `onCallAccepted` /
  /// `onCallDeclined` / `onCalleeOffline` callbacks.
  String initiateCall({
    required P2PCallParticipant target,
    required bool withVideo,
  }) {
    if (_socket == null || !isConnected) {
      throw StateError('Signaling socket not connected');
    }
    if (_myUserId == null || _myName == null) {
      throw StateError('Presence not registered');
    }
    if (_currentCallId != null) {
      _log('initiateCall: another call is already in progress, ignoring');
      return _currentCallId!;
    }
    final callId = _uuidV4();
    _currentCallId = callId;
    _peerUserId = target.userId;
    _peerName = target.name;
    _peerSocketId = null;
    _withVideo = withVideo;
    _isCaller = true;
    _remoteDescSet = false;
    _iceBuffer.clear();

    _log('→ initiate-call to ${target.userId} (${target.name}) '
        'video=$withVideo callId=$callId');
    _socket!.emit('initiate-call', {
      'toUserId': target.userId,
      'fromUserId': _myUserId,
      'fromName': _myName,
      'callId': callId,
    });
    return callId;
  }

  /// Cancel an outgoing call before the callee answers.
  void cancelCall() {
    final callId = _currentCallId;
    final calleeSid = _peerSocketId;
    if (callId == null) return;
    _log('→ cancel-call callId=$callId');
    _socket?.emit('cancel-call', {
      'callId': callId,
      // If we never received call-accepted yet we still don't know
      // their socket id — backend tolerates an empty value here.
      'calleeSocketId': calleeSid ?? '',
    });
    _resetCallState();
  }

  // ──────────────────────────────────────────────────────────────────
  //  Callee actions
  // ──────────────────────────────────────────────────────────────────

  /// Accept an incoming call. The caller's offer will arrive shortly
  /// after — `_bringUpCalleeSide` will handle it.
  void acceptCall({
    required P2PIncomingCall call,
    required bool withVideo,
  }) {
    if (_socket == null || !isConnected) return;
    _currentCallId = call.callId;
    _peerSocketId = call.callerSocketId;
    _peerUserId = call.fromUserId;
    _peerName = call.fromName;
    _withVideo = withVideo;
    _isCaller = false;
    _remoteDescSet = false;
    _iceBuffer.clear();

    _log('→ accept-call callId=${call.callId}');
    _socket!.emit('accept-call', {
      'callId': call.callId,
      'callerSocketId': call.callerSocketId,
    });
  }

  /// Decline an incoming call.
  void declineCall(P2PIncomingCall call) {
    if (_socket == null || !isConnected) return;
    _log('→ decline-call callId=${call.callId}');
    _socket!.emit('decline-call', {
      'callId': call.callId,
      'callerSocketId': call.callerSocketId,
    });
    if (_currentCallId == call.callId) _resetCallState();
  }

  // ──────────────────────────────────────────────────────────────────
  //  In-call actions
  // ──────────────────────────────────────────────────────────────────

  /// Toggle the local mic. Returns the new enabled state.
  bool setLocalAudio(bool enabled) {
    final tracks = _localStream?.getAudioTracks() ?? const [];
    for (final t in tracks) {
      t.enabled = enabled;
    }
    return enabled;
  }

  /// Toggle the local camera. Returns the new enabled state.
  bool setLocalVideo(bool enabled) {
    final tracks = _localStream?.getVideoTracks() ?? const [];
    for (final t in tracks) {
      t.enabled = enabled;
    }
    return enabled;
  }

  /// End the active call and emit `end-call`.
  Future<void> endCall() async {
    final callId = _currentCallId;
    final peerSid = _peerSocketId;
    if (callId == null) return;
    _log('→ end-call callId=$callId');
    _socket?.emit('end-call', {
      'callId': callId,
      'peerSocketId': peerSid ?? '',
    });
    await _tearDownPeer();
    _resetCallState();
  }

  // ──────────────────────────────────────────────────────────────────
  //  WebRTC bring-up
  // ──────────────────────────────────────────────────────────────────

  Future<void> _bringUpCallerSide() async {
    try {
      await _ensurePeerConnection();
      await _attachLocalMedia();
      // Caller produces the SDP offer.
      final offer = await _pc!.createOffer({
        'offerToReceiveAudio': 1,
        'offerToReceiveVideo': _withVideo ? 1 : 0,
      });
      await _pc!.setLocalDescription(offer);
      _log('→ call-offer to=$_peerSocketId');
      _socket?.emit('call-offer', {
        'to': _peerSocketId,
        'callId': _currentCallId,
        'offer': {'type': offer.type, 'sdp': offer.sdp},
      });
    } catch (e) {
      _log('caller bring-up failed: $e');
      onCallEnded?.call(_currentCallId ?? '', 'caller-bringup-failed');
      await _tearDownPeer();
      _resetCallState();
    }
  }

  Future<void> _bringUpCalleeSide(Map offerMap) async {
    try {
      await _ensurePeerConnection();
      await _attachLocalMedia();
      // 1) setRemoteDescription with the caller's offer.
      await _pc!.setRemoteDescription(
        RTCSessionDescription(
          offerMap['sdp']?.toString(),
          offerMap['type']?.toString(),
        ),
      );
      _remoteDescSet = true;
      await _flushIceBuffer();
      // 2) Build an answer.
      final answer = await _pc!.createAnswer({
        'offerToReceiveAudio': 1,
        'offerToReceiveVideo': _withVideo ? 1 : 0,
      });
      await _pc!.setLocalDescription(answer);
      _log('→ call-answer to=$_peerSocketId');
      _socket?.emit('call-answer', {
        'to': _peerSocketId,
        'callId': _currentCallId,
        'answer': {'type': answer.type, 'sdp': answer.sdp},
      });
    } catch (e) {
      _log('callee bring-up failed: $e');
      onCallEnded?.call(_currentCallId ?? '', 'callee-bringup-failed');
      await _tearDownPeer();
      _resetCallState();
    }
  }

  Future<void> _ensurePeerConnection() async {
    if (_pc != null) return;
    final config = <String, dynamic>{
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
        {'urls': 'stun:stun1.l.google.com:19302'},
      ],
      'sdpSemantics': 'unified-plan',
    };
    final pc = await createPeerConnection(config);
    _pc = pc;

    pc.onIceCandidate = (RTCIceCandidate c) {
      if (c.candidate == null || c.candidate!.isEmpty) return;
      _socket?.emit('call-ice-candidate', {
        'to': _peerSocketId,
        'callId': _currentCallId,
        'candidate': {
          'candidate': c.candidate,
          'sdpMid': c.sdpMid,
          'sdpMLineIndex': c.sdpMLineIndex,
        },
      });
    };

    pc.onTrack = (RTCTrackEvent event) {
      if (event.streams.isEmpty) return;
      _remoteStream = event.streams.first;
      _log('onTrack ← remote ${event.track.kind} '
          'streamId=${event.streams.first.id}');
      onRemoteStream?.call(event.streams.first);
    };

    pc.onConnectionState = (state) {
      _log('connectionState: $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        onMediaConnected?.call();
      }
      if (state ==
              RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state ==
              RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        // Surface as a remote-end "ended" so the UI tears down cleanly.
        final callId = _currentCallId;
        Future.microtask(() async {
          if (callId != null) onCallEnded?.call(callId, 'ice-$state');
          await _tearDownPeer();
          _resetCallState();
        });
      }
    };
  }

  Future<void> _attachLocalMedia() async {
    if (_localStream != null) return;
    final constraints = <String, dynamic>{
      'audio': true,
      'video': _withVideo
          ? {
              'mandatory': {
                'minWidth': '640',
                'minHeight': '480',
                'minFrameRate': '20',
              },
              'facingMode': 'user',
            }
          : false,
    };
    final stream = await navigator.mediaDevices.getUserMedia(constraints);
    _localStream = stream;
    onLocalStream?.call(stream);
    for (final track in stream.getTracks()) {
      await _pc!.addTrack(track, stream);
    }
  }

  Future<void> _flushIceBuffer() async {
    if (_pc == null || !_remoteDescSet) return;
    if (_iceBuffer.isEmpty) return;
    final buffered = List<RTCIceCandidate>.from(_iceBuffer);
    _iceBuffer.clear();
    for (final c in buffered) {
      try {
        await _pc!.addCandidate(c);
      } catch (e) {
        _log('flushIceBuffer addCandidate failed: $e');
      }
    }
  }

  // ──────────────────────────────────────────────────────────────────
  //  Teardown
  // ──────────────────────────────────────────────────────────────────

  Future<void> _tearDownPeer() async {
    try {
      for (final t in _localStream?.getTracks() ?? const []) {
        try {
          await t.stop();
        } catch (_) {}
      }
      try {
        await _localStream?.dispose();
      } catch (_) {}
      try {
        await _pc?.close();
      } catch (_) {}
    } finally {
      _localStream = null;
      _remoteStream = null;
      _pc = null;
      _iceBuffer.clear();
      _remoteDescSet = false;
    }
  }

  void _resetCallState() {
    _currentCallId = null;
    _peerSocketId = null;
    _peerUserId = null;
    _peerName = null;
    _withVideo = true;
    _isCaller = false;
  }

  Future<void> _disconnectSocketOnly() async {
    try {
      _socket?.dispose();
    } catch (_) {}
    _socket = null;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _tearDownPeer();
    await _disconnectSocketOnly();
  }
}
