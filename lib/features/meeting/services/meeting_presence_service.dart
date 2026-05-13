// ════════════════════════════════════════════════════════════════════
//  Meeting Presence Service — long-lived "is meeting X live right now?"
// ────────────────────────────────────────────────────────────────────
//  Opens a dedicated Socket.IO connection on the mediasoup namespace
//  (`/signaling-fresh`) the moment the user logs in and keeps it open
//  until they log out. The connection's sole job: listen for
//  `meeting-updated` events (protocol §5.3) and maintain an in-memory
//  `Map<meetingId, MeetingPresence>` that the Recent tab reads to
//  decide which cards render as LIVE vs ended.
//
//  Why a SEPARATE socket from MeetingNotifier's:
//    • MeetingNotifier's socket opens inside joinMeeting() and dies
//      when the user leaves a meeting. That covers in-call signaling
//      but NOT the "user is on the Recent tab and a meeting they
//      hosted yesterday just ended right now" case.
//    • This service mirrors P2PCallService's architecture — one
//      socket per concern, auth-watching, robust to reconnects.
//
//  Subscription model (server side — protocol §5.2):
//    • Server auto-subscribes this socket to one socket.io room per
//      meeting in the user's last-30-days participation. Client just
//      receives `meeting-updated` events; no `subscribe` emit needed.
// ════════════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../../../core/config/api_config.dart';
import '../data/meeting_presence.dart';

/// Snapshot of a meeting's live state, indexed by `meetingId`.
typedef PresenceMap = Map<String, MeetingPresence>;

class MeetingPresenceService {
  MeetingPresenceService({this.onLog});

  /// Optional log sink — the provider wires this up after
  /// construction so log lines fan out to its `debugPrint`.
  void Function(String)? onLog;

  io.Socket? _socket;
  String? _myUserId;
  bool _disposed = false;

  /// In-memory snapshot of every meeting we've heard a presence
  /// update for. Cleared on logout / dispose. The provider reads
  /// this directly via `current()` and listens to [stream] for
  /// reactive updates.
  final PresenceMap _state = <String, MeetingPresence>{};

  final StreamController<PresenceMap> _ctrl =
      StreamController<PresenceMap>.broadcast();

  /// Reactive stream — emits the full presence map every time any
  /// meeting's state changes. UI providers debounce / map this
  /// stream into per-meeting state.
  Stream<PresenceMap> get stream => _ctrl.stream;

  /// Synchronous snapshot for first build before any event arrives.
  PresenceMap current() => Map<String, MeetingPresence>.unmodifiable(_state);

  bool get isConnected => _socket?.connected == true;

  void _log(String s) {
    onLog?.call(s);
    if (kDebugMode) debugPrint('[presence] $s');
  }

  /// Open the presence socket. Idempotent — calling twice with the
  /// same `userId` is a no-op once the first connect succeeds.
  Future<void> connect({
    required String jwtToken,
    required String userId,
  }) async {
    if (_disposed) return;
    if (_socket != null && isConnected && _myUserId == userId) {
      _log('connect() skipped — already connected for $userId');
      return;
    }
    await _disconnectSocketOnly();

    _myUserId = userId;
    _log('opening presence socket → ${ApiConfig.signalingUrl}'
        '${ApiConfig.signalingPath}');

    final opts = <String, dynamic>{
      'path': ApiConfig.signalingPath,
      'transports': ['websocket', 'polling'],
      'autoConnect': false,
      // forceNew=true so we don't accidentally share the socket with
      // the in-call MeetingNotifier — they have totally different
      // event sets and lifetimes. Cleaner to keep them isolated.
      'forceNew': true,
      'reconnection': true,
      'reconnectionAttempts': 10,
      'reconnectionDelay': 2000,
      'auth': {'token': jwtToken},
    };
    final socket = io.io(ApiConfig.signalingUrl, opts);
    _socket = socket;

    socket.onConnect((_) {
      _log('connected sid=${socket.id}');
      // Belt-and-braces: emit a `subscribe-presence` event with our
      // userId in case the backend's auto-subscribe (protocol §5.2)
      // hasn't shipped yet OR forgets to re-subscribe us after a
      // reconnect. The handler should be idempotent on the server
      // side — multiple subscribes for the same user just keep the
      // same set of rooms.
      socket.emit('subscribe-presence', {'userId': _myUserId});
    });

    socket.onConnectError((e) => _log('connect_error: $e'));
    socket.onDisconnect((_) => _log('disconnected'));
    socket.onError((e) => _log('socket error: $e'));

    // ── The one event this service exists for. ─────────────────────
    //
    // Payload shape (protocol §5.3):
    //   { meetingId, meetingCode, isActive, membersCount, endedAt }
    //
    // `endedAt` is null while isActive=true, non-null ISO timestamp
    // when isActive=false. We patch our `_state` map in-place and
    // re-emit on the broadcast stream.
    socket.on('meeting-updated', (raw) {
      if (raw is! Map) {
        _log('meeting-updated: ignoring non-map payload $raw');
        return;
      }
      final data = Map<String, dynamic>.from(raw);
      final presence = MeetingPresence.fromJson(data);
      if (presence == null) {
        _log('meeting-updated: could not parse $data');
        return;
      }
      _log('meeting-updated id=${presence.meetingId} '
          'isActive=${presence.isActive} '
          'membersCount=${presence.membersCount} '
          'endedAt=${presence.endedAt}');
      _state[presence.meetingId] = presence;
      // Also index by meetingCode if it differs — the Recent tab's
      // `CallHistory.id` is sometimes the meeting UUID and sometimes
      // the meeting code (depends on which endpoint a row came from),
      // and we want lookups to succeed either way.
      if (presence.meetingCode != null &&
          presence.meetingCode != presence.meetingId) {
        _state[presence.meetingCode!] = presence;
      }
      _ctrl.add(Map<String, MeetingPresence>.from(_state));
    });

    socket.connect();
  }

  /// Apply a presence snapshot derived from REST (e.g. each meeting
  /// in `/api/meetings/user/:userId` carries the live fields). Lets
  /// the UI render correctly on cold start before any socket event
  /// arrives. Idempotent — overwrites if the meetingId is already
  /// in the map.
  void seedFromSnapshot(Iterable<MeetingPresence> snapshot) {
    var changed = false;
    for (final p in snapshot) {
      final prev = _state[p.meetingId];
      if (prev != p) {
        _state[p.meetingId] = p;
        if (p.meetingCode != null && p.meetingCode != p.meetingId) {
          _state[p.meetingCode!] = p;
        }
        changed = true;
      }
    }
    if (changed) {
      _ctrl.add(Map<String, MeetingPresence>.from(_state));
    }
  }

  /// Look up by meetingId OR meetingCode. The Recent tab's
  /// `CallHistory` rows come from a mix of endpoints — sometimes
  /// `id` is the UUID, sometimes the code — so the caller passes
  /// whichever it has.
  MeetingPresence? lookup(String idOrCode) {
    return _state[idOrCode] ??
        _state[idOrCode.replaceAll('-', '')];
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
    _state.clear();
    await _ctrl.close();
    await _disconnectSocketOnly();
  }
}
