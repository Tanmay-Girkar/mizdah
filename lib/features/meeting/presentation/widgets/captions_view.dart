import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/meeting_services_provider.dart';

/// Live captions overlay. Renders one rounded pill per active
/// speaker with their display name + the latest transcript chunk
/// — disappears 5s after the speaker stops (handled in the
/// notifier).
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
        final line = entry.value;
        final speaker = (line.name?.isNotEmpty ?? false)
            ? line.name!
            : 'Speaker';
        return Container(
          margin: const EdgeInsets.only(bottom: 8.0),
          padding: const EdgeInsets.symmetric(
              horizontal: 16.0, vertical: 8.0),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(20),
          ),
          child: RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: '$speaker: ',
                  style: const TextStyle(
                    color: Colors.lightBlueAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                TextSpan(
                  text: line.text,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 16),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
