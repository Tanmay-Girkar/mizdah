import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/services/caption_service.dart';
import '../../../../core/services/whiteboard_service.dart';
import '../../../../core/services/recording_service.dart';
import '../meeting_provider.dart';

// Providers for exposing the individual services

final captionServiceProvider = StateNotifierProvider.family<CaptionNotifier, CaptionState, String>((ref, meetingId) {
  final socket = ref.read(meetingProvider(meetingId).notifier).socket;
  if (socket == null) throw Exception("Socket not initialized");
  return CaptionNotifier(socket: socket);
});

final whiteboardServiceProvider = StateNotifierProvider.family<WhiteboardNotifier, WhiteboardState, String>((ref, meetingId) {
  final socket = ref.read(meetingProvider(meetingId).notifier).socket;
  if (socket == null) throw Exception("Socket not initialized");
  return WhiteboardNotifier(socket: socket);
});

final recordingServiceProvider = StateNotifierProvider.family<RecordingNotifier, RecordingState, String>((ref, meetingId) {
  final meetingState = ref.watch(meetingProvider(meetingId));
  final socket = ref.read(meetingProvider(meetingId).notifier).socket;
  if (socket == null) throw Exception("Socket not initialized");
  
  // Real host check: compare current user ID with the meeting's hostId
  final isHost = meetingState.userId != null && 
                 meetingState.hostId != null &&
                 meetingState.userId == meetingState.hostId;
                 
  return RecordingNotifier(socket: socket, isHost: isHost, meetingId: meetingId); 
});
