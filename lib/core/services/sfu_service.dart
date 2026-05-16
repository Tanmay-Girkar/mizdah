import 'dart:async';
import 'dart:convert';
// `RTCPriorityType` is re-exported by mediasoup_client_flutter via its
// dependency on flutter_webrtc, so we don't need to import flutter_webrtc
// directly. Don't be tempted to add `package:flutter_webrtc/...` — the
// analyzer flags it as an unnecessary import.
import 'package:mediasoup_client_flutter/mediasoup_client_flutter.dart';
// `RTCIceServer` and `RTCIceCredentialType` live in an internal handler
// header that mediasoup_client_flutter does NOT re-export from the
// barrel file. Import the source file directly so we can hand iceServers
// to the transport — without them mobile gathers only host candidates
// and the WebRTC transports drop to `failed` once the NAT mapping
// expires. (The package is local-pathed in pubspec, so reaching into
// its src/ is safe — but the linter still warns. Suppressed below.)
// ignore: implementation_imports
import 'package:mediasoup_client_flutter/src/handlers/handler_interface.dart'
    show RTCIceServer, RTCIceCredentialType;
import 'package:socket_io_client/socket_io_client.dart' as socket_io;

import '../../features/settings/video_preferences_provider.dart';
import 'video_quality_profile.dart';

/// ICE servers handed to the WebRTC transports. Mirrors the deployed
/// web client's default (Google's public STUN). Mobile previously
/// sent only host candidates so transports survived a few seconds in
/// LAN/cell scenarios then dropped to `failed` once the NAT mapping
/// expired — see commit history. If we ever need TURN for users
/// behind symmetric NAT, add another entry with credentials here.
final List<RTCIceServer> _kIceServers = <RTCIceServer>[
  RTCIceServer(
    urls: const ['stun:stun.l.google.com:19302'],
    username: '',
    credentialType: RTCIceCredentialType.password,
  ),
];

/// Wraps the mediasoup-client lifecycle against this app's specific
/// backend protocol on the `/media` namespace (path `/media-fresh`).
///
/// Protocol (reverse-engineered from the deployed web bundle):
///   • client → server: createRoom        {meetingId} → ack {routerRtpCapabilities}
///   • client → server: createTransport   {meetingId, direction:"send"|"recv"} → ack {params}
///   • client → server: connectTransport  {meetingId, transportId, dtlsParameters} → ack {} | {error}
///   • client → server: produce           {meetingId, transportId, kind, rtpParameters, appData} → ack {id} | {error}
///   • client → server: consume           {meetingId, transportId, producerId, rtpCapabilities} → ack {params} | {error}
///   • client → server: resumeConsumer    {meetingId, consumerId} → ack {}
///   • client → server: joinMedia         {meetingId}
///   • server → client: existingProducers {producers:[{producerId, kind, appData}, ...]}
///   • server → client: newProducer       {producerId, kind, appData}
///   • server → client: consumerClosed    {consumerId}
///
/// `appData.socketId` carries the producer's *signaling* socket id so
/// remote peers can map producers back to a participant tile, and so
/// the producer's own client can skip its own producers.
class SFUService {
  SFUService({
    required socket_io.Socket mediaSocket,
    required this.meetingId,
    required this.signalingSocketId,
    required this.onRemoteTrack,
    required this.onRemoteTrackClosed,
    String Function()? userName,
    void Function(String message)? log,
  })  : _socket = mediaSocket,
        _userName = userName ?? (() => ''),
        _log = log ?? ((_) {});

  final socket_io.Socket _socket;
  final String meetingId;
  /// The CURRENT signaling socket id at produce time. Embedded in
  /// `appData.socketId` so remote peers can map a producer to a tile.
  final String Function() signalingSocketId;
  /// Local user's display name. Embedded in producer `appData.name`
  /// so remote peers can correlate this producer to their own copy
  /// of the participants list when their signaling-sid ↔ media-sid
  /// mapping doesn't line up (the dev SFU treats those as separate
  /// IDs because mobile uses two distinct socket connections).
  final String Function() _userName;

  /// Called when a remote producer becomes consumable. The track is a
  /// freshly-created remote track; the consumer holds it alive.
  final void Function(String remoteSocketId, MediaStreamTrack track,
      Map<String, dynamic> appData) onRemoteTrack;

  /// Called when the SFU notifies us a consumer was closed
  /// server-side (peer left, paused, etc).
  final void Function(String consumerId) onRemoteTrackClosed;

  final void Function(String) _log;

  Device? _device;
  Transport? _sendTransport;
  Transport? _recvTransport;
  bool _initialized = false;
  bool _disposed = false;

  // Tracks the producer ids we've already started consuming so a
  // duplicate `existingProducers` + `newProducer` for the same
  // producer doesn't double-consume.
  final Set<String> _consumedProducerIds = {};

  // Pending consumers, keyed by id, completed when the recv
  // transport's consumerCallback fires.
  final Map<String, Completer<Consumer>> _pendingConsumers = {};

  // Active VIDEO consumer ids — the keyframe-pump watchdog walks
  // this set every few seconds and asks the SFU for a fresh keyframe
  // so the H264 decoder can recover from packet loss / simulcast
  // layer switches without freezing for the natural 5-15s gap
  // between encoder keyframes. Audio is omitted (Opus is a coded
  // stream that doesn't need keyframes).
  final Set<String> _videoConsumerIds = {};
  Timer? _keyframePumpTimer;

  // Active AUDIO consumers, keyed by remoteSocketId. Used by the
  // meeting notifier's 250ms audio-level poll to feed the voice-
  // wave indicator per participant. Video consumers don't carry
  // audio-level stats so they're tracked separately above.
  // Cleared on consumer close + service dispose.
  final Map<String, Consumer> _audioConsumersBySocketId = {};

  // Master registry of every active Consumer keyed by consumerId.
  // Required so dispose() can explicitly close each one — without
  // this, `transport.close()` alone cleans up Dart-side state but
  // leaves the underlying RTCRtpReceiver + MediaStreamTrack alive,
  // which keeps the MediaCodec decoder threads (and PipelineWatcher
  // / EglRenderer log spam) running forever after meeting leave.
  // Cleaned in [_handleConsumerClosed] + [dispose].
  final Map<String, Consumer> _allConsumersById = {};

  // Track our own active producers so we can replace tracks on
  // mute/unmute and screen-share. Mediasoup-client delivers each
  // producer via `producerCallback` on the send transport — we
  // route it to the correct field by inspecting kind + appData.
  Producer? _audioProducer;
  Producer? _videoProducer;
  Producer? _screenProducer;

  /// Current outgoing-video quality preset. Set by the meeting
  /// notifier from `outgoingVideoQualityProvider`. Applied to the
  /// video producer's underlying RTCRtpSender as soon as we have
  /// one (in `_handleProducerCreated`) AND whenever the user moves
  /// the dial mid-call (via `applyVideoQuality`). Default Auto
  /// matches the provider's default.
  OutgoingVideoQuality _quality = OutgoingVideoQuality.auto;

  // Per-kind in-flight gates. produceX() awaits the matching
  // completer and clears it once the producer has been recorded so
  // double-calls don't try to produce twice.
  Completer<void>? _pendingAudio;
  Completer<void>? _pendingVideo;
  Completer<void>? _pendingScreen;

  Producer? get audioProducer => _audioProducer;
  Producer? get videoProducer => _videoProducer;
  Producer? get screenProducer => _screenProducer;

  bool get isReady => _initialized && _sendTransport != null && _recvTransport != null;

  /// Bootstraps the full SFU session. Must be called after the media
  /// socket has connected. Idempotent — safe to call once per join.
  Future<void> initialize() async {
    if (_initialized) {
      _log('[SFU] initialize() — already initialized');
      return;
    }
    _log('[SFU] initialize() — meetingId=$meetingId');

    // 1. Ask the server for the room's router RTP capabilities.
    final createRoomAck = await _emitWithAck('createRoom', {'meetingId': meetingId});
    if (createRoomAck == null || createRoomAck['error'] != null) {
      throw Exception('createRoom failed: ${createRoomAck?['error']}');
    }
    final routerRtpCaps = Map<String, dynamic>.from(
      createRoomAck['routerRtpCapabilities'] as Map,
    );
    _log('[SFU] got routerRtpCapabilities');

    // 2. Load the device against those capabilities.
    _device = Device();
    await _device!.load(
      routerRtpCapabilities: RtpCapabilities.fromMap(routerRtpCaps),
    );
    _log('[SFU] device loaded');

    // 3. Create the send transport.
    final sendAck = await _emitWithAck('createTransport', {
      'meetingId': meetingId,
      'direction': 'send',
    });
    if (sendAck == null || sendAck['error'] != null) {
      throw Exception('createTransport(send) failed: ${sendAck?['error']}');
    }
    final sendParams = Map<String, dynamic>.from(sendAck['params'] as Map);
    _sendTransport = _device!.createSendTransport(
      id: sendParams['id'],
      iceParameters: IceParameters.fromMap(sendParams['iceParameters']),
      iceCandidates: List<IceCandidate>.from(
        (sendParams['iceCandidates'] as List)
            .map((c) => IceCandidate.fromMap(c)),
      ),
      dtlsParameters: DtlsParameters.fromMap(sendParams['dtlsParameters']),
      sctpParameters: sendParams['sctpParameters'] != null
          ? SctpParameters.fromMap(sendParams['sctpParameters'])
          : null,
      iceServers: _kIceServers,
      producerCallback: _handleProducerCreated,
    );
    _wireSendTransport(_sendTransport!);

    // 4. Create the recv transport.
    final recvAck = await _emitWithAck('createTransport', {
      'meetingId': meetingId,
      'direction': 'recv',
    });
    if (recvAck == null || recvAck['error'] != null) {
      throw Exception('createTransport(recv) failed: ${recvAck?['error']}');
    }
    final recvParams = Map<String, dynamic>.from(recvAck['params'] as Map);
    _recvTransport = _device!.createRecvTransport(
      id: recvParams['id'],
      iceParameters: IceParameters.fromMap(recvParams['iceParameters']),
      iceCandidates: List<IceCandidate>.from(
        (recvParams['iceCandidates'] as List)
            .map((c) => IceCandidate.fromMap(c)),
      ),
      dtlsParameters: DtlsParameters.fromMap(recvParams['dtlsParameters']),
      sctpParameters: recvParams['sctpParameters'] != null
          ? SctpParameters.fromMap(recvParams['sctpParameters'])
          : null,
      iceServers: _kIceServers,
      consumerCallback: (Consumer consumer, [Function? accept]) {
        final completer = _pendingConsumers.remove(consumer.id);
        completer?.complete(consumer);
        accept?.call();
      },
    );
    _wireRecvTransport(_recvTransport!);

    // 5. Listen for producer-related events from the server BEFORE we
    //    emit joinMedia — joinMedia triggers the existingProducers
    //    burst, and we don't want to miss it.
    _socket.on('existingProducers', _handleExistingProducers);
    _socket.on('newProducer', _handleNewProducer);
    _socket.on('consumerClosed', _handleConsumerClosed);

    // 6. Tell the server we're ready to receive producer notifications.
    _socket.emit('joinMedia', {'meetingId': meetingId});
    _log('[SFU] joinMedia emitted');

    _initialized = true;
  }

  /// Produce the local audio track. If an audio producer already
  /// exists, swap its track instead.
  Future<void> produceAudio(MediaStreamTrack track, MediaStream stream) async {
    if (_audioProducer != null) {
      if (_audioProducer!.track != track) {
        _log('[SFU] replacing audio track on existing producer');
        await _audioProducer!.replaceTrack(track);
      }
      return;
    }
    if (_pendingAudio != null) {
      await _pendingAudio!.future;
      return;
    }
    if (_sendTransport == null) {
      throw StateError('produceAudio() before transport ready');
    }
    _pendingAudio = Completer<void>();
    _kickProduce(track, stream, isScreen: false);
    await _pendingAudio!.future;
  }

  /// Produce the local video (camera) track. Swaps tracks if
  /// already producing camera video.
  Future<void> produceVideo(MediaStreamTrack track, MediaStream stream) async {
    if (_videoProducer != null) {
      if (_videoProducer!.track != track) {
        _log('[SFU] replacing video track on existing producer');
        await _videoProducer!.replaceTrack(track);
      }
      return;
    }
    if (_pendingVideo != null) {
      await _pendingVideo!.future;
      return;
    }
    if (_sendTransport == null) {
      throw StateError('produceVideo() before transport ready');
    }
    _pendingVideo = Completer<void>();
    _kickProduce(track, stream, isScreen: false);
    await _pendingVideo!.future;
  }

  /// Produce a screen-share track. Distinguished from camera video
  /// by `appData.isScreen=true` so consumers can render it in a
  /// dedicated tile rather than swapping the camera video.
  Future<void> produceScreen(MediaStreamTrack track, MediaStream stream) async {
    if (_screenProducer != null) {
      if (_screenProducer!.track != track) {
        await _screenProducer!.replaceTrack(track);
      }
      return;
    }
    if (_pendingScreen != null) {
      await _pendingScreen!.future;
      return;
    }
    if (_sendTransport == null) {
      throw StateError('produceScreen() before transport ready');
    }
    _pendingScreen = Completer<void>();
    _kickProduce(track, stream, isScreen: true);
    await _pendingScreen!.future;
  }

  /// Stop the screen-share producer. Safe to call when not sharing.
  Future<void> stopScreen() async {
    final p = _screenProducer;
    if (p == null) return;
    _screenProducer = null;
    try {
      p.close();
    } catch (e) {
      _log('[SFU] stopScreen close error: $e');
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _log('[SFU] dispose() — ${_allConsumersById.length} consumer(s) to close, '
        '${_audioProducer != null || _videoProducer != null || _screenProducer != null ? "producers active" : "no producers"}');
    _keyframePumpTimer?.cancel();
    _keyframePumpTimer = null;
    _socket.off('existingProducers', _handleExistingProducers);
    _socket.off('newProducer', _handleNewProducer);
    _socket.off('consumerClosed', _handleConsumerClosed);

    // ── Close every CONSUMER first ────────────────────────────────
    // Order matters: closing consumers BEFORE the transport gives
    // mediasoup-client a chance to tear down each RTCRtpReceiver +
    // its underlying MediaStreamTrack cleanly. If we only closed
    // the transport, the receivers would linger and their native
    // MediaCodec decoder threads would keep dequeuing frames into
    // an EglRenderer that's still bound to a track — the source of
    // the "PipelineWatcher onInputBufferReleased / EglRenderer
    // Frames received" log spam reported after leaveMeeting.
    //
    // We snapshot then drain because consumer.close() can fire its
    // own callbacks that mutate the map.
    final consumersSnapshot = _allConsumersById.values.toList();
    _allConsumersById.clear();
    _audioConsumersBySocketId.clear();
    _videoConsumerIds.clear();
    for (final c in consumersSnapshot) {
      // Stop the underlying track explicitly. consumer.close() does
      // some of this internally, but explicit stop() on the
      // MediaStreamTrack guarantees the encoder/decoder side
      // releases — without it some Android codec impls keep the
      // PipelineWatcher running until GC eventually finalizes the
      // track (which can be minutes).
      try {
        c.track.enabled = false;
      } catch (_) {}
      // ignore: discarded_futures
      c.track.stop().catchError((_) {});
      // ignore: discarded_futures
      c.close().catchError((_) {});
    }

    // ── Close PRODUCERS next ──────────────────────────────────────
    // Same reasoning as consumers — close the senders explicitly so
    // the local MediaCodec encoder and camera capturer release
    // their resources. The camera ITSELF is still owned by
    // LocalMediaService and shut down separately on the meeting
    // notifier's leaveMeeting path.
    for (final p in [_audioProducer, _videoProducer, _screenProducer]) {
      if (p == null) continue;
      try {
        p.track.enabled = false;
      } catch (_) {}
      try {
        p.close();
      } catch (_) {}
    }

    // ── Close TRANSPORTS last ─────────────────────────────────────
    try {
      _sendTransport?.close();
      _recvTransport?.close();
    } catch (_) {}

    _audioProducer = null;
    _videoProducer = null;
    _screenProducer = null;
    _sendTransport = null;
    _recvTransport = null;
    _device = null;
    _initialized = false;
    _consumedProducerIds.clear();
    _pendingConsumers.clear();
  }

  // ---------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------

  void _wireSendTransport(Transport t) {
    t.on('connect', (Map data) {
      _log('[SFU] sendTransport connect — emitting connectTransport');
      final dtlsMap = (data['dtlsParameters'] as DtlsParameters).toMap();
      final sanitisedDtls =
          jsonDecode(jsonEncode(dtlsMap, toEncodable: _encodeForSocketIo));
      _emitWithAck('connectTransport', {
        'meetingId': meetingId,
        'transportId': t.id,
        'dtlsParameters': sanitisedDtls,
      }).then((ack) {
        if (ack != null && ack['error'] != null) {
          _log('[SFU] connectTransport(send) error: ${ack['error']}');
          data['errback']?.call(ack['error']);
        } else {
          data['callback']?.call();
        }
      });
    });

    t.on('produce', (Map data) {
      _log('[SFU] sendTransport produce — kind=${data['kind']}');
      // RtpParameters.toMap() embeds an `RTCPriorityType` enum
      // inside each encoding's `priority`/`networkPriority`. The
      // socket.io serializer is plain jsonEncode and chokes on the
      // enum. Sanitize via a roundtrip with a `toEncodable` that
      // converts the enum to the string the server expects.
      final rtpMap = (data['rtpParameters'] as RtpParameters).toMap();
      final sanitisedRtp = jsonDecode(jsonEncode(rtpMap,
          toEncodable: _encodeForSocketIo));
      _emitWithAck('produce', {
        'meetingId': meetingId,
        'transportId': t.id,
        'kind': data['kind'],
        'rtpParameters': sanitisedRtp,
        'appData': data['appData'],
      }).then((ack) {
        if (ack == null || ack['error'] != null) {
          data['errback']?.call(ack?['error'] ?? 'produce failed');
        } else {
          data['callback']?.call(ack['id']);
        }
      });
    });

    t.on('connectionstatechange', (Map data) {
      _log('[SFU] sendTransport state=${data['connectionState']}');
    });
  }

  void _wireRecvTransport(Transport t) {
    t.on('connect', (Map data) {
      _log('[SFU] recvTransport connect — emitting connectTransport');
      final dtlsMap = (data['dtlsParameters'] as DtlsParameters).toMap();
      final sanitisedDtls =
          jsonDecode(jsonEncode(dtlsMap, toEncodable: _encodeForSocketIo));
      _emitWithAck('connectTransport', {
        'meetingId': meetingId,
        'transportId': t.id,
        'dtlsParameters': sanitisedDtls,
      }).then((ack) {
        if (ack != null && ack['error'] != null) {
          _log('[SFU] connectTransport(recv) error: ${ack['error']}');
          data['errback']?.call(ack['error']);
        } else {
          data['callback']?.call();
        }
      });
    });

    t.on('connectionstatechange', (Map data) {
      _log('[SFU] recvTransport state=${data['connectionState']}');
    });
  }

  /// Kicks off a `transport.produce()` call. The producer instance is
  /// delivered asynchronously through [_handleProducerCreated] (the
  /// `producerCallback` wired on transport creation) — that's where
  /// we record it and clear the matching pending-completer.
  void _kickProduce(
    MediaStreamTrack track,
    MediaStream stream, {
    required bool isScreen,
  }) {
    try {
      // appData.socketId — convention parity with the deployed web
      // client. Web sends its MEDIA socket id (the /media-fresh
      // session id) here, NOT its signaling socket id, because web's
      // own grid is keyed by media sid (every consumer it creates
      // for a peer producer also uses the producer's media sid as
      // the key).
      //
      // Mobile previously sent `signalingSocketId()` — that's why
      // web couldn't find mobile's producer in its grid: web looked
      // up by media sid, mobile sent signaling sid, no match, the
      // tile silently stayed empty even though mobile's video
      // producer was healthy on the SFU. The user's "my video not
      // displaying user side" symptom was this convention drift.
      //
      // We additionally include `signalingSocketId` and `name` as
      // extra fields so any peer that DOES key by signaling sid can
      // still correlate. Web will ignore the extras; mobile uses
      // them on the receive side via the cross-channel-sid linker.
      final mediaSid = _socket.id ?? '';
      _sendTransport!.produce(
        track: track,
        stream: stream,
        source: track.kind == 'audio' ? 'mic' : (isScreen ? 'screen' : 'webcam'),
        appData: <String, dynamic>{
          'socketId': mediaSid,
          'signalingSocketId': signalingSocketId(),
          'name': _userName(),
          'isScreen': isScreen,
        },
      );
    } catch (e) {
      _log('[SFU] _kickProduce error: $e');
      // Release whichever pending gate we entered so the caller's
      // await returns instead of hanging forever.
      if (track.kind == 'audio') {
        _pendingAudio?.complete();
        _pendingAudio = null;
      } else if (isScreen) {
        _pendingScreen?.complete();
        _pendingScreen = null;
      } else {
        _pendingVideo?.complete();
        _pendingVideo = null;
      }
    }
  }

  /// Wired as the send transport's `producerCallback`. Mediasoup-client
  /// invokes it once per successful `produce()` call, after the server
  /// has accepted the producer and the media is flowing. We route the
  /// producer to the appropriate slot by inspecting kind + appData,
  /// then release the pending-gate so the caller's `await` returns.
  void _handleProducerCreated(Producer producer) {
    final isScreen = producer.appData['isScreen'] == true;
    _log('[SFU] producerCallback id=${producer.id} kind=${producer.kind} '
        'isScreen=$isScreen');
    if (producer.kind == 'audio') {
      _audioProducer = producer;
      _pendingAudio?.complete();
      _pendingAudio = null;
    } else if (producer.kind == 'video') {
      if (isScreen) {
        _screenProducer = producer;
        _pendingScreen?.complete();
        _pendingScreen = null;
      } else {
        _videoProducer = producer;
        _pendingVideo?.complete();
        _pendingVideo = null;
        // Apply the user's current quality preset to the freshly-
        // created sender. Fire-and-forget — the bitrate caps don't
        // need to be in place before the producer is reported back
        // to the notifier; WebRTC will start with sane defaults
        // and ramp into our cap on the first congestion check.
        // ignore: discarded_futures
        _applyQualityToVideoProducer();
      }
    }
  }

  Future<void> _applyQualityToVideoProducer() async {
    final sender = _videoProducer?.rtpSender;
    if (sender == null) return;
    final profile = VideoQualityProfile.forQuality(_quality);
    final ok = await profile.applyToSender(sender);
    _log('[SFU] applied quality=${_quality.name} '
        '(maxBitrate=${profile.maxBitrate ~/ 1000}kbps) ok=$ok');
  }

  /// Push the active video producer's encoder caps to match the
  /// supplied preset. Called by `MeetingNotifier` when the user
  /// changes the dial in the effects sheet mid-meeting. Cheap —
  /// just sets new RTP encoding parameters; no track replace.
  Future<void> applyVideoQuality(OutgoingVideoQuality q) async {
    _quality = q;
    await _applyQualityToVideoProducer();
  }

  /// Snapshot every active audio source's normalised level (0..1)
  /// — once per call, no internal polling. The meeting notifier
  /// drives the 250ms cadence itself.
  ///
  /// Returns `{'<remoteSocketId>': level, …, 'local': level}` with
  /// every key whose stats were readable. The local mic level is
  /// pulled from the audio producer's underlying RTCRtpSender;
  /// each remote peer's level is pulled from the matching audio
  /// consumer's RTCRtpReceiver.
  ///
  /// WebRTC exposes audio-level on the `audioLevel` field of the
  /// inbound-rtp / media-source reports. Missing reports are
  /// silently skipped — the caller will decay the previous value
  /// instead of dropping it to zero.
  Future<Map<String, double>> pollAudioLevels() async {
    final out = <String, double>{};

    // Local mic — read from the audio producer's RTCRtpSender.
    final localSender = _audioProducer?.rtpSender;
    if (localSender != null) {
      try {
        final reports = await localSender.getStats();
        double best = 0;
        for (final r in reports) {
          if (r.type != 'media-source' && r.type != 'outbound-rtp') continue;
          final v = r.values;
          final lvl = v['audioLevel'];
          if (lvl is num && lvl.toDouble() > best) best = lvl.toDouble();
        }
        if (best > 0) out['local'] = best.clamp(0.0, 1.0).toDouble();
      } catch (_) {
        // getStats can throw on producer teardown — drop the read.
      }
    }

    // Each remote peer — read from their audio consumer's
    // RTCRtpReceiver. The map is keyed by remoteSocketId, which
    // matches the meeting notifier's audioLevels map key already.
    for (final entry in _audioConsumersBySocketId.entries) {
      final receiver = entry.value.rtpReceiver;
      if (receiver == null) continue;
      try {
        final reports = await receiver.getStats();
        double best = 0;
        for (final r in reports) {
          if (r.type != 'inbound-rtp') continue;
          final v = r.values;
          final lvl = v['audioLevel'];
          if (lvl is num && lvl.toDouble() > best) best = lvl.toDouble();
        }
        if (best > 0) {
          out[entry.key] = best.clamp(0.0, 1.0).toDouble();
        }
      } catch (_) {
        // Consumer just closed, getStats threw — skip this tick.
      }
    }

    return out;
  }

  void _handleExistingProducers(dynamic data) {
    if (_disposed) return;
    if (data is! Map) return;
    final producers = data['producers'];
    if (producers is! List) return;
    _log('[SFU] existingProducers: ${producers.length}');
    for (final p in producers) {
      if (p is Map) _consumeProducer(p);
    }
  }

  void _handleNewProducer(dynamic data) {
    if (_disposed) return;
    if (data is! Map) return;
    _log('[SFU] newProducer: ${data['producerId']} kind=${data['kind']}');
    _consumeProducer(data);
  }

  void _handleConsumerClosed(dynamic data) {
    if (_disposed) return;
    if (data is! Map) return;
    final id = data['consumerId']?.toString();
    if (id == null) return;
    _log('[SFU] consumerClosed: $id');
    _videoConsumerIds.remove(id);
    // Drop the corresponding audio consumer if this id matched one.
    _audioConsumersBySocketId.removeWhere((_, c) => c.id == id);
    // Server-initiated close: the Consumer's track + native receiver
    // teardown is fired by mediasoup-client when it processes this
    // event. We only need to drop the Dart-side reference.
    _allConsumersById.remove(id);
    onRemoteTrackClosed(id);
  }

  Future<void> _consumeProducer(Map producerInfo) async {
    final producerId = producerInfo['producerId']?.toString();
    if (producerId == null) return;
    if (_consumedProducerIds.contains(producerId)) return;
    _consumedProducerIds.add(producerId);

    final appData = producerInfo['appData'] is Map
        ? Map<String, dynamic>.from(producerInfo['appData'] as Map)
        : <String, dynamic>{};
    final remoteSocketId = appData['socketId']?.toString();
    if (remoteSocketId == null || remoteSocketId.isEmpty) {
      _log('[SFU] _consumeProducer skipped — no socketId in appData');
      _consumedProducerIds.remove(producerId);
      return;
    }
    if (remoteSocketId == signalingSocketId()) {
      // Skip our own producers; the SFU echoes them back.
      _consumedProducerIds.remove(producerId);
      return;
    }

    if (_recvTransport == null || _device == null) {
      _log('[SFU] _consumeProducer dropped — transport not ready');
      _consumedProducerIds.remove(producerId);
      return;
    }

    final rtpCapsMap = _device!.rtpCapabilities.toMap();
    final sanitisedCaps =
        jsonDecode(jsonEncode(rtpCapsMap, toEncodable: _encodeForSocketIo));
    final ack = await _emitWithAck('consume', {
      'meetingId': meetingId,
      'transportId': _recvTransport!.id,
      'producerId': producerId,
      'rtpCapabilities': sanitisedCaps,
    });
    if (ack == null || ack['error'] != null) {
      _log('[SFU] consume error: ${ack?['error']}');
      _consumedProducerIds.remove(producerId);
      return;
    }
    final params = Map<String, dynamic>.from(ack['params'] as Map);
    final consumerId = params['id'] as String;
    final completer = Completer<Consumer>();
    _pendingConsumers[consumerId] = completer;

    try {
      _recvTransport!.consume(
        id: consumerId,
        producerId: params['producerId'] as String,
        kind: RTCRtpMediaTypeExtension.fromString(params['kind'] as String),
        rtpParameters: RtpParameters.fromMap(params['rtpParameters'] as Map),
        peerId: remoteSocketId,
        appData: appData,
      );
    } catch (e) {
      _log('[SFU] recvTransport.consume threw: $e');
      _pendingConsumers.remove(consumerId);
      _consumedProducerIds.remove(producerId);
      return;
    }

    final consumer = await completer.future;
    onRemoteTrack(remoteSocketId, consumer.track, appData);

    // Master registry — needed so dispose() can explicitly close
    // every Consumer (mediasoup-client's transport.close() leaves
    // the underlying RTCRtpReceiver + MediaStreamTrack alive, which
    // keeps the MediaCodec decoder running and the EglRenderer
    // pumping frames forever).
    _allConsumersById[consumer.id] = consumer;

    // Stash audio consumers so the audio-level poll can read their
    // RTCRtpReceiver stats without walking every peer connection.
    // Last-write-wins per socketId (a peer reconnecting replaces
    // their stale consumer). Cleaned up in [_handleConsumerClosed].
    if (consumer.kind == 'audio') {
      _audioConsumersBySocketId[remoteSocketId] = consumer;
    }

    // The mediasoup convention is to create consumers paused so the
    // first frame isn't dropped while the receiving end attaches. The
    // server resumes when we say so. Use the ack form even though we
    // ignore the result — the deployed web client does the same, and
    // some socket.io servers treat missing-ack-when-expected as a
    // protocol error and drop the connection.
    _socket.emitWithAck('resumeConsumer', {
      'meetingId': meetingId,
      'consumerId': consumerId,
    }, ack: ([dynamic _]) {});

    // Track video consumers for the keyframe pump (see below). Audio
    // doesn't need keyframes — Opus self-recovers from packet loss.
    if (consumer.kind == 'video') {
      _videoConsumerIds.add(consumerId);
      _ensureKeyframePumpRunning();
      // Three-shot keyframe-after-attach pump (sfu-v15):
      //   • immediate — tells the SFU to push a keyframe as soon as
      //     resumeConsumer is acked, so the decoder sees a frame
      //     within the first RTT instead of waiting 5–15s for the
      //     natural keyframe interval. This is the user-visible
      //     "few-seconds delay before remote video appears" fix.
      //   • 200ms — covers the case where the immediate request lost
      //     the race against resumeConsumer's own internal PLI.
      //   • 1500ms — last-chance for slow links where the first two
      //     keyframes were dropped in transit.
      _requestConsumerKeyFrame(consumerId);
      Future.delayed(const Duration(milliseconds: 200), () {
        if (_disposed) return;
        if (!_videoConsumerIds.contains(consumerId)) return;
        _requestConsumerKeyFrame(consumerId);
      });
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (_disposed) return;
        if (!_videoConsumerIds.contains(consumerId)) return;
        _requestConsumerKeyFrame(consumerId);
      });
    }
  }

  /// Starts the keyframe-pump watchdog if it's not already running.
  /// Runs every 4 seconds and asks the SFU for a fresh keyframe on
  /// every active video consumer. This is what unsticks the
  /// "remote video froze after a few seconds" symptom that comes from
  /// simulcast layer switches: when the SFU drops to a smaller layer
  /// (e.g. 720p → 180p under congestion), the H264 decoder must
  /// reinitialise and needs a keyframe to start producing frames; if
  /// none arrives within the natural keyframe interval (5-15s on most
  /// encoders), the renderer shows the last good frame and looks frozen.
  void _ensureKeyframePumpRunning() {
    if (_keyframePumpTimer?.isActive == true) return;
    _log('[SFU] starting keyframe-pump (4s interval, '
        '${_videoConsumerIds.length} video consumer(s))');
    _keyframePumpTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) {
        if (_disposed) {
          _keyframePumpTimer?.cancel();
          return;
        }
        if (_videoConsumerIds.isEmpty) {
          _keyframePumpTimer?.cancel();
          _keyframePumpTimer = null;
          return;
        }
        for (final id in _videoConsumerIds.toList()) {
          _requestConsumerKeyFrame(id);
        }
      },
    );
  }

  /// Asks the SFU to push a keyframe for the given consumer's
  /// producer. Two emissions in parallel:
  ///   1. `requestConsumerKeyFrame` — preferred, single round-trip
  ///      (server calls `consumer.requestKeyFrame()` server-side).
  ///      If the server ever wires this up (see backend doc), it
  ///      becomes the entire fix.
  ///   2. `pauseConsumer` then `resumeConsumer` — fallback that
  ///      works on the existing server: server-side `consumer.resume()`
  ///      after a pause triggers a PLI to the producer. The pause
  ///      window is ~80ms — invisible to the user but enough to
  ///      force the keyframe.
  void _requestConsumerKeyFrame(String consumerId) {
    if (_disposed) return;
    // Path 1 — preferred custom event (no-op if backend doesn't handle it).
    _socket.emit('requestConsumerKeyFrame', {
      'meetingId': meetingId,
      'consumerId': consumerId,
    });
    // Path 2 — pause/resume fallback. Tiny window so the user
    // doesn't see a flicker. Wrapped in try so a server that
    // doesn't ack pauseConsumer doesn't break us.
    try {
      _socket.emitWithAck('pauseConsumer', {
        'meetingId': meetingId,
        'consumerId': consumerId,
      }, ack: ([dynamic _]) {});
      Future.delayed(const Duration(milliseconds: 80), () {
        if (_disposed) return;
        if (!_videoConsumerIds.contains(consumerId)) return;
        _socket.emitWithAck('resumeConsumer', {
          'meetingId': meetingId,
          'consumerId': consumerId,
        }, ack: ([dynamic _]) {});
      });
    } catch (e) {
      _log('[SFU] keyframe-pump pause/resume error: $e');
    }
  }

  Future<Map<String, dynamic>?> _emitWithAck(
    String event,
    Map<String, dynamic> payload,
  ) {
    final completer = Completer<Map<String, dynamic>?>();
    Timer? timeout;
    timeout = Timer(const Duration(seconds: 10), () {
      if (!completer.isCompleted) {
        _log('[SFU] $event ack timeout');
        completer.complete(null);
      }
    });
    // The socket.io ack callback is invoked via Function.apply with
    // whatever the server sends back. If the server replies with no
    // arguments (a bare ack), Dart will throw NoSuchMethodError on
    // a 1-arg signature — make `response` an OPTIONAL positional
    // arg so 0-arg invocation is legal.
    _socket.emitWithAck(event, payload, ack: ([dynamic response]) {
      timeout?.cancel();
      if (completer.isCompleted) return;
      if (response == null) {
        completer.complete(<String, dynamic>{});
      } else if (response is Map) {
        completer.complete(Map<String, dynamic>.from(response));
      } else {
        completer.complete(<String, dynamic>{'_raw': response});
      }
    });
    return completer.future;
  }

  /// Used as the `toEncodable` callback for jsonEncode when sanitising
  /// mediasoup-client structures before they go onto the socket. The
  /// flutter_webrtc enum `RTCPriorityType` shows up inside
  /// `RtpEncodingParameters.toMap()` and breaks the default encoder.
  static Object? _encodeForSocketIo(Object? value) {
    if (value is RTCPriorityType) {
      switch (value) {
        case RTCPriorityType.veryLow:
          return 'very-low';
        case RTCPriorityType.low:
          return 'low';
        case RTCPriorityType.medium:
          return 'medium';
        case RTCPriorityType.high:
          return 'high';
      }
    }
    // Fall back to the value's string form rather than throwing —
    // a hex-encoded debug string is better than a crashed call.
    return value?.toString();
  }
}
