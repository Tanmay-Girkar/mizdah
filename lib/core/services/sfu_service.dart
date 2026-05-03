import 'dart:async';
import 'dart:convert';
// `RTCPriorityType` is re-exported by mediasoup_client_flutter via its
// dependency on flutter_webrtc, so we don't need to import flutter_webrtc
// directly. Don't be tempted to add `package:flutter_webrtc/...` — the
// analyzer flags it as an unnecessary import.
import 'package:mediasoup_client_flutter/mediasoup_client_flutter.dart';
import 'package:socket_io_client/socket_io_client.dart' as socket_io;

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
    void Function(String message)? log,
  })  : _socket = mediaSocket,
        _log = log ?? ((_) {});

  final socket_io.Socket _socket;
  final String meetingId;
  /// The CURRENT signaling socket id at produce time. Embedded in
  /// `appData.socketId` so remote peers can map a producer to a tile.
  final String Function() signalingSocketId;

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

  // Track our own active producers so we can replace tracks on
  // mute/unmute and screen-share. Mediasoup-client delivers each
  // producer via `producerCallback` on the send transport — we
  // route it to the correct field by inspecting kind + appData.
  Producer? _audioProducer;
  Producer? _videoProducer;
  Producer? _screenProducer;

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
    _sendTransport = _device!.createSendTransportFromMap(
      Map<String, dynamic>.from(sendAck['params'] as Map),
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
    _recvTransport = _device!.createRecvTransportFromMap(
      Map<String, dynamic>.from(recvAck['params'] as Map),
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
    _log('[SFU] dispose()');
    _socket.off('existingProducers', _handleExistingProducers);
    _socket.off('newProducer', _handleNewProducer);
    _socket.off('consumerClosed', _handleConsumerClosed);
    try {
      _audioProducer?.close();
      _videoProducer?.close();
      _screenProducer?.close();
    } catch (_) {}
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
      _sendTransport!.produce(
        track: track,
        stream: stream,
        source: track.kind == 'audio' ? 'mic' : (isScreen ? 'screen' : 'webcam'),
        appData: <String, dynamic>{
          'socketId': signalingSocketId(),
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
      }
    }
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

    // The mediasoup convention is to create consumers paused so the
    // first frame isn't dropped while the receiving end attaches. The
    // server resumes when we say so.
    _socket.emit('resumeConsumer', {
      'meetingId': meetingId,
      'consumerId': consumerId,
    });
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
