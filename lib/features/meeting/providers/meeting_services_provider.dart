import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:mizdah/core/config/api_config.dart';
import '../../../../core/services/caption_service.dart';
import '../../../../core/services/whiteboard_service.dart';
import '../../../../core/services/recording_service.dart';
import '../meeting_provider.dart';

// Safe provider initialization that respects autoDispose

final captionServiceProvider = StateNotifierProvider.autoDispose.family<CaptionNotifier, CaptionState, String>((ref, meetingId) {
  // watch ensures this provider is disposed when meetingProvider is disposed
  final notifier = ref.watch(meetingProvider(meetingId).notifier);
  final socket = notifier.socket;
  
  // Use a fallback socket if meetingProvider isn't ready
  return CaptionNotifier(socket: socket ?? IO.io(ApiConfig.signalingUrl, IO.OptionBuilder().setTransports(['websocket']).disableAutoConnect().build()));
});

final whiteboardServiceProvider = StateNotifierProvider.autoDispose.family<WhiteboardNotifier, WhiteboardState, String>((ref, meetingId) {
  final notifier = ref.watch(meetingProvider(meetingId).notifier);
  final socket = notifier.socket;
  
  return WhiteboardNotifier(socket: socket ?? IO.io(ApiConfig.signalingUrl, IO.OptionBuilder().setTransports(['websocket']).disableAutoConnect().build()));
});

final recordingServiceProvider = StateNotifierProvider.autoDispose.family<RecordingNotifier, RecordingState, String>((ref, meetingId) {
  final meetingState = ref.watch(meetingProvider(meetingId));
  final notifier = ref.watch(meetingProvider(meetingId).notifier);
  final socket = notifier.socket;
  
  final isHost = meetingState.userId != null && 
                 meetingState.hostId != null &&
                 meetingState.userId == meetingState.hostId;
                 
  return RecordingNotifier(
    socket: socket ?? IO.io(ApiConfig.signalingUrl, IO.OptionBuilder().setTransports(['websocket']).disableAutoConnect().build()), 
    isHost: isHost, 
    meetingId: meetingId
  ); 
});
