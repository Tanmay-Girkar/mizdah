import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as socket_io;
import '../../data/repositories/recording_repository.dart';

enum RecordingStatus { idle, requestingConsent, recording, stopping, uploading }

class RecordingState {
  final RecordingStatus status;
  final bool isHost;
  final int totalExpected;
  final int alreadyAgreed;

  RecordingState({
    this.status = RecordingStatus.idle,
    this.isHost = false,
    this.totalExpected = 0,
    this.alreadyAgreed = 0,
  });

  RecordingState copyWith({
    RecordingStatus? status,
    bool? isHost,
    int? totalExpected,
    int? alreadyAgreed,
  }) {
    return RecordingState(
      status: status ?? this.status,
      isHost: isHost ?? this.isHost,
      totalExpected: totalExpected ?? this.totalExpected,
      alreadyAgreed: alreadyAgreed ?? this.alreadyAgreed,
    );
  }
}

class RecordingNotifier extends StateNotifier<RecordingState> {
  final socket_io.Socket socket;
  final String meetingId;
  final RecordingRepository _recordingRepository = RecordingRepository();

  RecordingNotifier({required this.socket, required bool isHost, required this.meetingId}) : super(RecordingState(isHost: isHost)) {
    _initListeners();
  }

  Future<void> requestRecording() async {
    if (state.isHost) {
      try {
        await _recordingRepository.startRecording(meetingId);
        state = state.copyWith(status: RecordingStatus.requestingConsent);
        socket.emit('request-recording', {});
      } catch (e) {
        debugPrint("Error starting recording: $e");
      }
    }
  }

  void _initListeners() {
    // Other users receive this
    socket.on('recording-requested', (data) {
      state = state.copyWith(
        status: RecordingStatus.requestingConsent,
        totalExpected: data['totalExpected'] ?? 0,
        alreadyAgreed: data['alreadyAgreed'] ?? 0,
      );
    });

    socket.on('recording-consent-update', (data) {
      state = state.copyWith(
        alreadyAgreed: data['agreedCount'] ?? state.alreadyAgreed,
        totalExpected: data['totalExpected'] ?? state.totalExpected,
      );
    });

    socket.on('recording-started', (data) {
      // Backend handles actual composite rendering. 
      // The mobile app only shows UI state.
      state = state.copyWith(status: RecordingStatus.recording);
    });

    socket.on('recording-stopped', (data) {
      state = state.copyWith(status: RecordingStatus.idle);
    });
  }

  void respondConsent(bool agree) {
    socket.emit('respond-recording', {'agree': agree});
  }

  Future<void> stopRecording() async {
    if (state.isHost) {
      try {
        await _recordingRepository.stopRecording(meetingId);
        state = state.copyWith(status: RecordingStatus.stopping);
        socket.emit('stop-recording', {});
      } catch (e) {
        debugPrint("Error stopping recording: $e");
      }
    }
  }
}
