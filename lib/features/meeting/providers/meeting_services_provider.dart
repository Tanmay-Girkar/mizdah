import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as socket_io;
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
  final captionNotifier = CaptionNotifier(
    socket: socket ??
        socket_io.io(
          ApiConfig.signalingUrl,
          socket_io.OptionBuilder()
              .setTransports(['websocket'])
              .disableAutoConnect()
              .build(),
        ),
  );

  // Hand the caption notifier our local identity so emitted captions
  // are tagged with the right socketId + display name. We also
  // re-push these whenever the meeting state mutates (e.g. the user
  // hasn't joined yet at provider-creation time).
  void pushIdentity() {
    final s = ref.read(meetingProvider(meetingId));
    captionNotifier.setLocalIdentity(
      socketId: notifier.socket?.id,
      name: s.userId == null ? 'You' : (notifier.userName ?? 'You'),
    );
  }

  pushIdentity();
  ref.listen(meetingProvider(meetingId), (_, __) => pushIdentity());

  return captionNotifier;
});

final whiteboardServiceProvider = StateNotifierProvider.autoDispose.family<WhiteboardNotifier, WhiteboardState, String>((ref, meetingId) {
  final notifier = ref.watch(meetingProvider(meetingId).notifier);
  final socket = notifier.socket;
  
  return WhiteboardNotifier(socket: socket ?? socket_io.io(ApiConfig.signalingUrl, socket_io.OptionBuilder().setTransports(['websocket']).disableAutoConnect().build()));
});

final recordingServiceProvider = StateNotifierProvider.autoDispose.family<RecordingNotifier, RecordingState, String>((ref, meetingId) {
  final meetingState = ref.watch(meetingProvider(meetingId));
  final notifier = ref.watch(meetingProvider(meetingId).notifier);
  final socket = notifier.socket;
  
  final isHost = meetingState.userId != null && 
                 meetingState.hostId != null &&
                 meetingState.userId == meetingState.hostId;
                 
  return RecordingNotifier(
    socket: socket ?? socket_io.io(ApiConfig.signalingUrl, socket_io.OptionBuilder().setTransports(['websocket']).disableAutoConnect().build()), 
    isHost: isHost, 
    meetingId: meetingId
  ); 
});
