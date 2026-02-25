import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'dart:async';

class CaptionState {
  final Map<String, String> activeCaptions; // { socketId: currentText }
  final bool isEnabled;

  CaptionState({
    required this.activeCaptions,
    this.isEnabled = false,
  });

  CaptionState copyWith({
    Map<String, String>? activeCaptions,
    bool? isEnabled,
  }) {
    return CaptionState(
      activeCaptions: activeCaptions ?? this.activeCaptions,
      isEnabled: isEnabled ?? this.isEnabled,
    );
  }
}

class CaptionNotifier extends StateNotifier<CaptionState> {
  final IO.Socket socket;
  Timer? _clearTimer;

  CaptionNotifier({required this.socket}) : super(CaptionState(activeCaptions: {})) {
    _initListeners();
  }

  void toggleCaptions() {
    state = state.copyWith(isEnabled: !state.isEnabled);
  }

  void _initListeners() {
    socket.on('caption-received', (data) {
      if (!state.isEnabled) return;
      
      final String socketId = data['socketId'];
      final String text = data['text'];
      final bool isFinal = data['isFinal'] ?? false;
      
      final newCaptions = Map<String, String>.from(state.activeCaptions);
      newCaptions[socketId] = text;
      
      state = state.copyWith(activeCaptions: newCaptions);

      if (isFinal) {
        // Clear this caption after 5 seconds
        _clearTimer?.cancel();
        _clearTimer = Timer(const Duration(seconds: 5), () {
          final resetCaptions = Map<String, String>.from(state.activeCaptions);
          resetCaptions.remove(socketId);
          state = state.copyWith(activeCaptions: resetCaptions);
        });
      }
    });
  }

  @override
  void dispose() {
    _clearTimer?.cancel();
    socket.off('caption-received');
    super.dispose();
  }
}
