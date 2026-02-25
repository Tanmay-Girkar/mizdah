import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/services/caption_service.dart';

// Assuming we have a provider for CaptionNotifier
final captionProvider = StateNotifierProvider<CaptionNotifier, CaptionState>((ref) {
  throw UnimplementedError('Initialize with socket');
});

class CaptionsView extends ConsumerWidget {
  const CaptionsView({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(captionProvider);

    if (!state.isEnabled || state.activeCaptions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: state.activeCaptions.entries.map((entry) {
        // Find user name by socketId from meeting state ideally
        final socketId = entry.key;
        final text = entry.value;

        return Container(
          margin: const EdgeInsets.only(bottom: 8.0),
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.7),
            borderRadius: BorderRadius.circular(20),
          ),
          child: RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: 'User $socketId: ', // Replace with real name mapper
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
