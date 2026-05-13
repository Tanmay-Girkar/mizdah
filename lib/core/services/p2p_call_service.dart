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
//
//  ─── DEBUGGING: call-type loss ───────────────────────────────────
//  If a video call arrives on the receiver as an audio call, the
//  client logs ten ====-bordered blocks across the flow:
//
//    Step  1  CALL BUTTON PRESSED              (call_hub_screen.dart)
//    Step  2  EMITTING CALL PAYLOAD             (this file)
//    Step  5  RECEIVED INCOMING CALL            (this file)
//    Step  6  PARSING CALL MODEL                (this file)
//    Step  7  ENUM PARSE RESULT                 (this file)
//    Step  8  UPDATING INCOMING CALL STATE      (p2p_call_provider.dart)
//    Step  9  BUILDING INCOMING CALL UI         (p2p_incoming_overlay.dart)
//    Step 10  ACCEPT CALL                       (p2p_call_provider.dart)
//
//  Steps 3 / 4 happen on the signaling SERVER (Node.js, NOT in this
//  repo). Drop these logs into the server to close the loop:
//
//    // Step 3 — when server receives `initiate-call`
//    socket.on('initiate-call', (data) => {
//      console.log('==============================');
//      console.log('SERVER RECEIVED CALL');
//      console.log(data);
//      console.log('callType:', data.callType);
//      console.log('==============================');
//      // ... lookup target socket ...
//      // Step 4 — before forwarding to receiver
//      const payloadToReceiver = { ...data };
//      console.log('==============================');
//      console.log('SERVER RELAYING CALL');
//      console.log(payloadToReceiver);
//      console.log('callType:', payloadToReceiver.callType);
//      console.log('==============================');
//      io.to(targetSocketId).emit('incoming-call', payloadToReceiver);
//    });
//
//  If Step 2 prints `callType: video` but Step 5 prints `callType:
//  null`, the server stripped the field — Step 3/4 will pinpoint
//  whether it was on receive or on relay.
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

/// Parse the caller's media intent from an `incoming-call` payload.
///
/// Different backend builds settle on different field names for the same
/// concept — historically we shipped `withVideo` (boolean), but the most
/// recent docs and several intermediate refactors used `callType` /
/// `type` (string: `'audio'` | `'video'`). Rather than couple the
/// client to one specific convention, we accept any of them and resolve
/// in priority order:
///
///   1. `callType` / `type` / `kind` / `callKind` /
///      `media` / `mediaType` (string)            — explicit and unambiguous
///   2. `withVideo` / `video` / `hasVideo` /
///      `isVideo` / `videoCall` (bool)            — legacy
///   3. Same lookups inside common nesting keys —
///      `data`, `payload`, `call`, `meta`, `callMeta`
///
/// When NOTHING is set we default to `false` (audio). This is the
/// safer fallback: defaulting to video means a stray audio call
/// suddenly demands the receiver's camera and shows the video accept
/// button — the surprise-camera UX bug. Defaulting to audio at worst
/// means the receiver sees an audio button for a video call (a
/// recoverable backend regression). Heavy aliasing + nested lookup
/// makes the audio default mostly theoretical in practice.
bool _parseCallTypeAsVideo(Map<String, dynamic> data) {
  bool? resolved = _resolveCallTypeIn(data);
  if (resolved != null) {
    debugPrint('[P2P] ENUM PARSE RESULT: ${resolved ? "video" : "audio"} '
        '(matched at top level)');
    return resolved;
  }
  // Some servers wrap the actual call payload inside another object
  // (e.g. `{event: 'incoming-call', data: {...}}`). Re-scan the
  // canonical nesting keys before giving up.
  for (final key in const ['data', 'payload', 'call', 'meta', 'callMeta']) {
    final nested = data[key];
    if (nested is Map) {
      resolved = _resolveCallTypeIn(Map<String, dynamic>.from(nested));
      if (resolved != null) {
        debugPrint('[P2P] ENUM PARSE RESULT: ${resolved ? "video" : "audio"} '
            '(matched in nested "$key")');
        return resolved;
      }
    }
  }
  // No signal anywhere — default to AUDIO. SCREAM about this so the
  // bug is impossible to miss in field logs. The user explicitly
  // asked us NOT to silently fall back, and this is the loudest we
  // can be without crashing legitimate audio calls (which have
  // `callType: 'audio'` and would never reach this branch).
  debugPrint('==============================');
  debugPrint('!!!!! CALL TYPE FALLBACK HIT !!!!!');
  debugPrint('No callType / type / kind / withVideo / video / hasVideo / '
      'isVideo / callMeta field found in incoming-call payload.');
  debugPrint('Backend is STRIPPING the call-type field. Fix the signaling '
      'server to forward it. Defaulting to AUDIO for safety.');
  debugPrint('Raw payload keys: ${data.keys.toList()}');
  debugPrint('Raw payload: $data');
  debugPrint('==============================');
  return false;
}

/// Inspects a single map for any of the known call-type field names.
/// Returns `null` when no field is present (so the caller can fall
/// through to nested-object scanning), `true` for video, `false` for
/// audio.
bool? _resolveCallTypeIn(Map<String, dynamic> data) {
  // 1) String fields take priority — they're explicit. Values are
  //    lower-cased + trimmed because backends have a habit of
  //    normalising on the way through.
  const stringKeys = ['callType', 'type', 'kind', 'callKind', 'media', 'mediaType'];
  for (final k in stringKeys) {
    final raw = data[k];
    if (raw == null) continue;
    final s = raw.toString().trim().toLowerCase();
    if (s.isEmpty) continue;
    if (s == 'video' || s == 'videocall' || s == 'video-call') return true;
    if (s == 'audio' || s == 'voice' || s == 'audiocall' || s == 'audio-call') {
      return false;
    }
    // Unknown string — try next key / fall through to bools.
  }

  // 2) Boolean (or stringly-typed boolean) fields.
  const boolKeys = ['withVideo', 'video', 'hasVideo', 'isVideo', 'videoCall', 'isVideoCall'];
  for (final k in boolKeys) {
    final raw = data[k];
    if (raw == null) continue;
    if (raw is bool) return raw;
    if (raw is num) return raw != 0;
    if (raw is String) {
      final v = raw.toLowerCase().trim();
      if (v == 'true' || v == '1' || v == 'yes') return true;
      if (v == 'false' || v == '0' || v == 'no') return false;
    }
  }
  return null;
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

  /// True when the caller initiated a VIDEO call; false for AUDIO.
  ///
  /// The signaling backend forwards this from the caller's
  /// `initiate-call` payload to our `incoming-call` payload. We
  /// resolve the actual value via `_parseCallTypeAsVideo` at receive
  /// time. The default here is `false` (audio) — see the helper's
  /// doc-comment for the reasoning. Construction-site callers should
  /// almost always pass `withVideo:` explicitly; the default exists
  /// only so the field can stay `final`.
  final bool withVideo;

  const P2PIncomingCall({
    required this.callId,
    required this.fromUserId,
    required this.fromName,
    required this.callerSocketId,
    this.withVideo = false,
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
  // Tracks an in-flight `getUserMedia()` so concurrent callers (e.g.
  // the overlay starting a warm-up preview just as the user taps
  // Accept and `_attachLocalMedia` fires) reuse the same Future
  // instead of racing two camera acquisitions. Cleared on dispose /
  // stop / failure.
  Future<MediaStream>? _localStreamFuture;
  // Latched true once the warmed stream has been requested as a
  // ringing preview (vs. acquired as part of a live call). Used by
  // `stopLocalPreview` to refuse teardown when a real call is in
  // flight — only the call's own teardown should kill the stream
  // in that case.
  bool _previewActive = false;
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

  /// Fires whenever the REMOTE peer toggles their camera. `enabled`
  /// is the peer's new video state. Used by the UI to swap the
  /// remote video tile for an avatar placeholder when they turn
  /// their camera off (instead of showing a frozen / black frame).
  ///
  /// Driven by the `call-media-state` socket event — the peer emits
  /// it from `setLocalVideo` so both sides stay in sync without
  /// renegotiating the WebRTC track.
  void Function(bool enabled)? onRemoteVideoToggled;

  /// Same idea for the peer's mic. Optional — used by the UI to
  /// render a "Muted" badge on the remote tile.
  void Function(bool enabled)? onRemoteAudioToggled;

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
      // ─── STEP 5: RECEIVER SOCKET LOGS ───────────────────────────
      // What the receiver's socket ACTUALLY got from the signaling
      // server. If `callType` reads `video` here, the field made it
      // through the wire. If it's null/missing, the signaling server
      // is stripping it (Step 3/4 backend log will pinpoint where).
      debugPrint('==============================');
      debugPrint('RECEIVED INCOMING CALL');
      debugPrint('$data');
      debugPrint('Incoming callType: ${data["callType"]}');
      debugPrint('Incoming type: ${data["type"]}');
      debugPrint('Incoming withVideo: ${data["withVideo"]}');
      debugPrint('Incoming video: ${data["video"]}');
      debugPrint('Incoming callMeta: ${data["callMeta"]}');
      debugPrint('==============================');

      // ─── STEP 6: CALL MODEL PARSING LOGS ────────────────────────
      // Detect call type defensively. `_parseCallTypeAsVideo` checks
      // every known alias + nested object. If it falls through to
      // the audio default (returns false with no field set), it
      // prints a SCREAMING warning so the bug is unmissable.
      final withVideo = _parseCallTypeAsVideo(data);
      debugPrint('==============================');
      debugPrint('PARSING CALL MODEL');
      debugPrint('Raw callType: ${data["callType"]}');
      debugPrint('Parsed callType: ${withVideo ? "video" : "audio"}');
      debugPrint('Parsed withVideo: $withVideo');
      debugPrint('==============================');
      onIncomingCall?.call(P2PIncomingCall(
        callId: data['callId']?.toString() ?? '',
        fromUserId: data['fromUserId']?.toString() ?? '',
        fromName: data['fromName']?.toString() ?? 'Caller',
        callerSocketId: data['callerSocketId']?.toString() ?? '',
        withVideo: withVideo,
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

    // ── Peer media-state — peer toggled their mic / camera ─────────
    // This is OUT-OF-BAND from the WebRTC track itself; it tells our
    // UI to swap the remote video tile for an avatar placeholder
    // when the peer disables their camera (instead of showing a
    // frozen / black frame). The peer's WebRTC track stays attached
    // throughout — only its `enabled` flag flips on their side.
    socket.on('call-media-state', (raw) {
      if (raw is! Map) return;
      final data = Map<String, dynamic>.from(raw);
      final callId = data['callId']?.toString();
      if (callId != _currentCallId) {
        _log('ignoring media-state for foreign callId=$callId '
            '(current=$_currentCallId)');
        return;
      }
      _log('==============================');
      _log('← media-state SOCKET EVENT');
      _log('payload: $data');
      _log('video: ${data['video']}');
      _log('audio: ${data['audio']}');
      _log('==============================');
      final video = data['video'];
      final audio = data['audio'];
      if (video is bool) onRemoteVideoToggled?.call(video);
      if (audio is bool) onRemoteAudioToggled?.call(audio);
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
    final mediaType = withVideo ? 'video' : 'audio';
    final payload = <String, dynamic>{
      'toUserId': target.userId,
      'fromUserId': _myUserId,
      'fromName': _myName,
      'callId': callId,
      // Forward the caller's media intent under every field name the
      // backend / receiver might inspect. The signaling server is
      // expected to round-trip these into `incoming-call`, but some
      // intermediate revisions only forward a subset — sending the
      // intent through MANY channels guarantees the receiver's
      // `_parseCallTypeAsVideo` finds *something* and never falls
      // through to the audio default for a video call.
      //
      //   callType / type / kind  — string ('audio' | 'video')
      //   withVideo / video       — boolean
      //   callMeta                — nested object with the same intent
      //                             for backends that strip top-level
      //                             fields but pass meta through whole.
      'callType': mediaType,
      'type': mediaType,
      'kind': mediaType,
      'withVideo': withVideo,
      'video': withVideo,
      'hasVideo': withVideo,
      'callMeta': {
        'callType': mediaType,
        'withVideo': withVideo,
      },
    };
    // ─── STEP 2: OUTGOING PAYLOAD LOGS ─────────────────────────────
    // Last chance to confirm the field is set BEFORE leaving the
    // device. If `callType in payload` here reads `video` but the
    // receiver's incoming log (Step 5) reads anything else, the
    // problem is on the wire / in the signaling server — not the
    // client.
    debugPrint('==============================');
    debugPrint('EMITTING CALL PAYLOAD');
    debugPrint('$payload');
    debugPrint('callType in payload: ${payload["callType"]}');
    debugPrint('withVideo in payload: ${payload["withVideo"]}');
    debugPrint('==============================');
    _socket!.emit('initiate-call', payload);
    _log('initiate-call emitted callType=$mediaType withVideo=$withVideo');
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
  /// Also broadcasts the new state to the peer over signaling so
  /// their UI can render a "Muted" badge in real time.
  bool setLocalAudio(bool enabled) {
    final tracks = _localStream?.getAudioTracks() ?? const [];
    for (final t in tracks) {
      t.enabled = enabled;
    }
    _emitMediaState(audio: enabled);
    return enabled;
  }

  /// Toggle the local camera. Returns the new enabled state.
  /// Also broadcasts the new state to the peer so their UI can swap
  /// the remote video tile for an avatar placeholder when we turn
  /// the camera off (and back to live video when we turn it on).
  ///
  /// IMPORTANT: this only flips `track.enabled` — the WebRTC track
  /// stays attached and the peer connection isn't renegotiated. So
  /// turning the camera on/off mid-call is instant and costs nothing
  /// on the wire. Disposing the track / renderer would force a full
  /// SDP renegotiation which is slow and visually jarring.
  bool setLocalVideo(bool enabled) {
    final tracks = _localStream?.getVideoTracks() ?? const [];
    for (final t in tracks) {
      t.enabled = enabled;
    }
    _emitMediaState(video: enabled);
    return enabled;
  }

  /// Fires a `call-media-state` socket event so the peer's UI knows
  /// which of our tracks just toggled. Either field can be omitted
  /// when only one media kind changed. No-op when the call hasn't
  /// reached the active phase yet (no socket / no peer to inform).
  void _emitMediaState({bool? audio, bool? video}) {
    final callId = _currentCallId;
    final peerSid = _peerSocketId;
    final socket = _socket;
    if (callId == null || peerSid == null || socket == null) return;
    if (audio == null && video == null) return;
    socket.emit('call-media-state', {
      'callId': callId,
      'peerSocketId': peerSid,
      if (audio != null) 'audio': audio,
      if (video != null) 'video': video,
    });
    _log('→ media-state audio=$audio video=$video');
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
      final track = event.track;
      _log('onTrack ← remote kind=${track.kind} '
          'streamId=${event.streams.first.id} '
          'muted=${track.muted} enabled=${track.enabled}');
      onRemoteStream?.call(event.streams.first);

      // ── Native WebRTC mute/unmute detection ────────────────────
      // When the remote peer disables their video (or mic) track via
      // `track.enabled = false`, the WebRTC engine eventually stops
      // sending RTP packets (or sends substitute zero-content frames).
      // The local engine fires `onMute` on the receiver track once
      // it concludes the upstream is silent. When the peer re-enables,
      // `onUnMute` fires. This is the canonical WebRTC API for
      // "peer turned their camera off" and works regardless of
      // whether the signaling backend forwards our `call-media-state`
      // event — though the event-driven path is much faster (instant
      // vs. ~3–10s for `onMute`), so we keep both.
      //
      // We also seed the initial state from `track.muted` because a
      // peer who joined with their camera already off would never
      // fire `onMute` (it's already in that state on first delivery).
      if (track.kind == 'video') {
        // Seed initial state. `track.muted` reads the current value.
        if (track.muted == true) {
          _log('remote video track delivered ALREADY MUTED');
          onRemoteVideoToggled?.call(false);
        }
        track.onMute = () {
          _log('==============================');
          _log('REMOTE TRACK MUTED (video)');
          _log('REMOTE VIDEO ENABLED: false');
          _log('==============================');
          onRemoteVideoToggled?.call(false);
        };
        track.onUnMute = () {
          _log('==============================');
          _log('REMOTE TRACK UNMUTED (video)');
          _log('REMOTE VIDEO ENABLED: true');
          _log('==============================');
          onRemoteVideoToggled?.call(true);
        };
      } else if (track.kind == 'audio') {
        if (track.muted == true) {
          _log('remote audio track delivered ALREADY MUTED');
          onRemoteAudioToggled?.call(false);
        }
        track.onMute = () {
          _log('REMOTE TRACK MUTED (audio)');
          onRemoteAudioToggled?.call(false);
        };
        track.onUnMute = () {
          _log('REMOTE TRACK UNMUTED (audio)');
          onRemoteAudioToggled?.call(true);
        };
      }
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

  /// Acquire the local camera/mic stream. Race-safe: concurrent
  /// callers share one in-flight `getUserMedia()` Future, so the
  /// ringing-preview warmup and the post-accept `_attachLocalMedia`
  /// never end up holding two cameras open at once.
  ///
  /// Returns the existing stream immediately if one is already
  /// warmed. On failure the Future bubbles the error and the
  /// internal cache is cleared so the next call retries cleanly
  /// (otherwise a denied permission would latch forever).
  Future<MediaStream> _acquireLocalStream({required bool withVideo}) {
    if (_localStream != null) return Future.value(_localStream!);
    final inflight = _localStreamFuture;
    if (inflight != null) return inflight;
    final constraints = <String, dynamic>{
      'audio': true,
      'video': withVideo
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
    _log('getUserMedia() begin audio=true video=$withVideo');
    final future = navigator.mediaDevices.getUserMedia(constraints).then(
      (stream) {
        _localStream = stream;
        _log('getUserMedia() ok videoTracks=${stream.getVideoTracks().length} '
            'audioTracks=${stream.getAudioTracks().length}');
        return stream;
      },
      onError: (Object e, StackTrace st) {
        _localStreamFuture = null;
        _log('getUserMedia() failed: $e');
        throw e;
      },
    );
    _localStreamFuture = future;
    return future;
  }

  /// Warm up the camera + mic BEFORE the call is accepted so the
  /// callee sees their own live preview while the phone is still
  /// ringing (WhatsApp / FaceTime style). The same stream is later
  /// reused as the call's outgoing video track — no flicker, no
  /// black frame, no second `getUserMedia()` round-trip on accept.
  ///
  /// Idempotent: returns the existing warmed stream if one is
  /// already in flight. Fires `onLocalStream` so the provider can
  /// wire a renderer; provider-side handling is idempotent (renderer
  /// is reused, srcObject re-set is a no-op).
  ///
  /// Audio is acquired even for video calls — there's no clean way
  /// to add an audio track later without a renegotiation, and having
  /// the mic alive during the preview matches every popular call
  /// app's behaviour (you can hear your earpiece tone, the device's
  /// audio session warms up early so accepting is instant).
  Future<MediaStream> startLocalPreview({required bool withVideo}) async {
    if (_disposed) throw StateError('service disposed');
    _previewActive = true;
    _withVideo = withVideo;
    _log('startLocalPreview withVideo=$withVideo');
    final stream = await _acquireLocalStream(withVideo: withVideo);
    onLocalStream?.call(stream);
    return stream;
  }

  /// Tear down a warmed preview when the callee declines / misses /
  /// the caller cancels before accept. Safely a no-op while a real
  /// peer connection exists — only the call's normal teardown is
  /// allowed to kill the stream once `_pc` is alive.
  Future<void> stopLocalPreview() async {
    if (!_previewActive) return;
    _previewActive = false;
    if (_pc != null) {
      _log('stopLocalPreview skipped — peer connection is live');
      return;
    }
    _log('stopLocalPreview disposing warmed stream');
    final stream = _localStream;
    _localStream = null;
    _localStreamFuture = null;
    if (stream == null) return;
    try {
      for (final t in stream.getTracks()) {
        try {
          await t.stop();
        } catch (_) {}
      }
      await stream.dispose();
    } catch (e) {
      _log('stopLocalPreview dispose error (ignored): $e');
    }
  }

  /// Flip the camera between front and back. Operates on the live
  /// local video track via `Helper.switchCamera` — no renegotiation,
  /// no track replacement, the peer keeps decoding the same stream.
  /// Safe to call during the ringing preview as well as during an
  /// active call.
  Future<void> switchCamera() async {
    final tracks = _localStream?.getVideoTracks() ?? const [];
    if (tracks.isEmpty) {
      _log('switchCamera no-op (no local video track)');
      return;
    }
    try {
      await Helper.switchCamera(tracks.first);
      _log('switchCamera ok');
    } catch (e) {
      _log('switchCamera failed: $e');
    }
  }

  Future<void> _attachLocalMedia() async {
    // Reuse a warmed preview stream if one exists; otherwise
    // acquire it now. The `_previewActive` flag is cleared because
    // from this moment on the stream belongs to the call lifecycle —
    // `stopLocalPreview` will refuse to touch it.
    _previewActive = false;
    final stream = await _acquireLocalStream(withVideo: _withVideo);
    onLocalStream?.call(stream);
    // Add each track to the PC only if not already a sender. After
    // warm-up, calling addTrack twice for the same track would
    // throw / produce duplicate transceivers, so we dedupe by
    // existing sender track id.
    final senders = await _pc!.getSenders();
    final attachedIds = senders
        .map((s) => s.track?.id)
        .whereType<String>()
        .toSet();
    for (final track in stream.getTracks()) {
      if (attachedIds.contains(track.id)) continue;
      await _pc!.addTrack(track, stream);
    }
    // Proactively tell the peer about our starting media state.
    // Without this, the peer doesn't know our camera is on until we
    // first toggle it — which means the peer's `call-media-state`
    // listener never fires for the initial "on" state and they have
    // to rely on slower `track.onMute` / `onUnMute` events. Emitting
    // here lets the peer's UI flip to "remote video on" the moment
    // the signaling round-trip completes, instead of waiting for
    // WebRTC to confirm via track events.
    _emitMediaState(audio: true, video: _withVideo);
    _log('initial media-state emitted audio=true video=$_withVideo');
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
      _localStreamFuture = null;
      _previewActive = false;
      _remoteStream = null;
      _pc = null;
      _iceBuffer.clear();
      _remoteDescSet = false;
    }
  }

  // ──────────────────────────────────────────────────────────────────
  //  Lifecycle recovery (screen lock / app background → foreground)
  // ──────────────────────────────────────────────────────────────────

  /// Best-effort recovery after the host app comes back to the
  /// foreground from a paused / inactive state (screen lock,
  /// app-switcher, incoming-call interrupt). The renderers and PC
  /// itself survive the transition — flutter_webrtc holds them on
  /// the platform side — but a couple of side-effects need re-poking:
  ///
  ///   • The audio session may have been moved out of
  ///     `MODE_IN_COMMUNICATION` (Android) or `playAndRecord`
  ///     (iOS) by the OS while we were backgrounded. Re-applying
  ///     the speakerphone route forces the WebRTC engine to refresh
  ///     its session state.
  ///   • Local tracks that were intentionally disabled before
  ///     background should NOT be flipped back on automatically —
  ///     `setLocalAudio` / `setLocalVideo` handle that explicitly
  ///     via the provider. We only verify the track is still alive.
  ///
  /// Logs the state of every load-bearing handle so the field log
  /// makes it obvious whether the renderer / PC / tracks actually
  /// survived.
  Future<void> recoverFromBackground({
    required bool wantSpeakerphone,
  }) async {
    _log('==============================');
    _log('LIFECYCLE RECOVER');
    _log('pc=${_pc != null} '
        'localStream=${_localStream != null} '
        'remoteStream=${_remoteStream != null} '
        'callId=$_currentCallId '
        'previewActive=$_previewActive');
    if (_localStream != null) {
      final v = _localStream!.getVideoTracks();
      final a = _localStream!.getAudioTracks();
      _log('local tracks video=${v.length} '
          '(enabled=${v.isNotEmpty ? v.first.enabled : 'n/a'}) '
          'audio=${a.length} '
          '(enabled=${a.isNotEmpty ? a.first.enabled : 'n/a'})');
    }
    if (_pc != null) {
      try {
        final st = await _pc!.getConnectionState();
        _log('pc connectionState=$st');
      } catch (_) {}
    }
    // Re-apply audio routing — see method header for why.
    try {
      await Helper.setSpeakerphoneOn(wantSpeakerphone);
      _log('recover: speakerphone re-applied → '
          '${wantSpeakerphone ? "SPEAKER" : "EARPIECE"}');
    } catch (e) {
      _log('recover: setSpeakerphoneOn failed: $e');
    }
    _log('==============================');
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
