import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as socket_io;
import 'package:mizdah/core/config/api_config.dart';
import '../../../../core/services/caption_service.dart';

// Safe provider initialization
final captionProvider = StateNotifierProvider<CaptionNotifier, CaptionState>((ref) {
  // Use a dummy socket to prevent crashes during initialization
  final dummySocket = socket_io.io(ApiConfig.signalingUrl, socket_io.OptionBuilder().setTransports(['websocket']).disableAutoConnect().build());
  return CaptionNotifier(socket: dummySocket); 
});

class CaptionsView extends ConsumerWidget {
  const CaptionsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(captionProvider);

    if (!state.isEnabled || state.activeCaptions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: state.activeCaptions.entries.map((entry) {
        final socketId = entry.key;
        final text = entry.value;

        return Container(
          margin: const EdgeInsets.only(bottom: 8.0),
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(20),
          ),
          child: RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: 'User $socketId: ',
                  style: const TextStyle(
                    color: Colors.lightBlueAccent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextSpan(
                  text: text,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
