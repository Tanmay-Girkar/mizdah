import 'dart:async';
import 'package:mediasoup_client_flutter/mediasoup_client_flutter.dart';
import 'package:socket_io_client/socket_io_client.dart' as socket_io;

class SFUService {
  late Device _device;
  Transport? _sendTransport;
  Transport? _recvTransport;
  final socket_io.Socket socket;
  final Map<String, Completer<Consumer>> _pendingConsumers = {};

  SFUService({required this.socket});

  Future<void> initDevice(Map<String, dynamic> routerRtpCapabilities) async {
    _device = Device();
    await _device.load(routerRtpCapabilities: RtpCapabilities.fromMap(routerRtpCapabilities));
  }

  Future<void> createSendTransport(Map<String, dynamic> transportOptions) async {
    _sendTransport = _device.createSendTransportFromMap(
      transportOptions,
      producerCallback: _handleProduce,
    );

    _sendTransport!.on('connect', (Map<String, dynamic> data) async {
      socket.emit('transport-connect', {
        'dtlsParameters': data['dtlsParameters'],
        'transportId': _sendTransport!.id,
      });
      data['callback']?.call();
    });

    _sendTransport!.on('produce', (Map<String, dynamic> data) async {
      socket.emitWithAck('transport-produce', {
        'transportId': _sendTransport!.id,
        'kind': data['kind'],
        'rtpParameters': data['rtpParameters'],
        'appData': data['appData'],
      }, ack: (response) {
        if (response != null && response['id'] != null) {
          data['callback']?.call(response['id']);
        } else {
          data['errback']?.call("Failed to produce");
        }
      });
    });
  }

  Future<void> createRecvTransport(Map<String, dynamic> transportOptions) async {
    _recvTransport = _device.createRecvTransportFromMap(
      transportOptions,
      consumerCallback: (Consumer consumer, [Function? accept]) {
        final completer = _pendingConsumers.remove(consumer.id);
        completer?.complete(consumer);
        accept?.call();
      },
    );

    _recvTransport!.on('connect', (Map<String, dynamic> data) {
      socket.emit('transport-connect', {
        'dtlsParameters': data['dtlsParameters'],
        'transportId': _recvTransport!.id,
      });
      data['callback']?.call();
    });
  }

  Future<void> produce(MediaStreamTrack track, MediaStream stream) async {
    if (_sendTransport == null) throw Exception("Send transport not created");
    _sendTransport!.produce(
      track: track,
      stream: stream,
      source: 'webcam',
      appData: {'mediaType': track.kind},
    );
  }

  Future<void> consume(Map<String, dynamic> consumerOptions, Function(MediaStreamTrack track) onTrack) async {
    if (_recvTransport == null) throw Exception("Recv transport not created");
    
    // 1. Request server to create a consumer
    socket.emitWithAck('transport-consume', {
      'transportId': _recvTransport!.id,
      'producerId': consumerOptions['producerId'],
      'rtpCapabilities': _device.rtpCapabilities.toMap(),
    }, ack: (response) async {
      if (response == null) return;
      
      final String consumerId = response['id'];
      final completer = Completer<Consumer>();
      _pendingConsumers[consumerId] = completer;

      // 2. Trigger local consumption
      _recvTransport!.consume(
        id: consumerId,
        producerId: response['producerId'],
        kind: RTCRtpMediaTypeExtension.fromString(response['kind']),
        rtpParameters: RtpParameters.fromMap(response['rtpParameters']),
        peerId: response['peerId'] ?? 'remote',
        appData: response['appData'] ?? {},
      );
      
      // 3. Wait for the consumer to be created via callback
      final consumer = await completer.future;
      
      // 4. Notify UI of new track
      onTrack(consumer.track);
      
      // 5. Resume consumer on server
      socket.emit('resume-consumer', {'consumerId': consumer.id});
    });
  }

  dynamic _handleProduce(Producer producer) {
    // Called when a producer is created
  }


  void dispose() {
    _sendTransport?.close();
    _recvTransport?.close();
  }
}
