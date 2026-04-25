import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/meeting_services_provider.dart';

class CaptionsView extends ConsumerWidget {
  final String meetingId;
  const CaptionsView({super.key, required this.meetingId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(captionServiceProvider(meetingId));

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
