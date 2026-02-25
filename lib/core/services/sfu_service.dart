import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:mediasoup_client_flutter/mediasoup_client_flutter.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

class SFUService {
  late Device _device;
  Transport? _sendTransport;
  Transport? _recvTransport;
  final IO.Socket socket;

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
      // Emit 'transport-connect' to signaling server
      socket.emit('transport-connect', {
        'dtlsParameters': data['dtlsParameters'],
        'transportId': _sendTransport!.id,
      });
      // The callback expects nothing on completion usually
      data['callback']?.call();
    });

    _sendTransport!.on('produce', (Map<String, dynamic> data) async {
      // We expect the server to emit back an ID or use ACKs.
      // With raw socket.io without ack wrappers, we typically use a Completer 
      // but assuming server responds to 'transport-produce' or uses a callback:
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
      consumerCallback: _handleConsume,
    );

    _recvTransport!.on('connect', (Map<String, dynamic> data) {
      socket.emit('transport-connect', {
        'dtlsParameters': data['dtlsParameters'],
        'transportId': _recvTransport!.id,
      });
      data['callback']?.call();
    });
  }

  Future<Producer?> produce(MediaStreamTrack track, MediaStream stream) async {
    if (_sendTransport == null) throw Exception("Send transport not created");
    _sendTransport!.produce(
      track: track,
      stream: stream,
      source: 'webcam',
      appData: {'mediaType': track.kind},
    );
    return null;
  }

  Future<Consumer?> consume(Map<String, dynamic> consumerOptions) async {
    if (_recvTransport == null) throw Exception("Recv transport not created");
    _recvTransport!.consume(
      id: consumerOptions['id'],
      producerId: consumerOptions['producerId'],
      kind: RTCRtpMediaTypeExtension.fromString(consumerOptions['kind']),
      peerId: consumerOptions['peerId'] ?? 'unknown',
      rtpParameters: RtpParameters.fromMap(consumerOptions['rtpParameters']),
    );
    return null;
  }

  dynamic _handleProduce(Producer producer) {
    // Called when a producer is created
  }

  dynamic _handleConsume(Consumer consumer) {
    // Called when a consumer is created
  }

  void dispose() {
    _sendTransport?.close();
    _recvTransport?.close();
  }
}
