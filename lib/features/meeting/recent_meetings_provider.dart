// ════════════════════════════════════════════════════════════════════
//  recentMeetingsProvider — REST snapshot ⊕ live presence overlay
// ────────────────────────────────────────────────────────────────────
//  The Meetings → Recent tab needs each card to render with the
//  freshest possible state. We get state from two sources:
//
//    1. REST snapshot — `callHistoryProvider` calls
//       `/api/participant/user/:userId` and `/api/meetings/user/:userId`
//       and merges them into a `List<CallHistory>`. Each row may or
//       may not carry the new `isActive` / `membersCount` / `endedAt`
//       fields, depending on whether the row came from a hosted-
//       meeting payload or a raw participation row (the latter
//       doesn't carry meeting-level state — see protocol §4.1).
//
//    2. Live socket overlay — `meetingPresenceStreamProvider`
//       maintains a `Map<meetingId, MeetingPresence>` populated by
//       the `meeting-updated` socket event (protocol §5.3). Whenever
//       a meeting flips state in the real world, this map updates
//       within ~100ms.
//
//  This provider returns a fresh `List<CallHistory>` where each row
//  has been patched with the matching presence entry (when one
//  exists). UI watches THIS provider, not the raw history one, so
//  cards re-render automatically on every socket event.
// ════════════════════════════════════════════════════════════════════

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/models.dart';
import '../home/presentation/home_screen.dart' show callHistoryProvider;
import 'meeting_presence_provider.dart';

/// Recent meetings list with live presence applied. UI watches this.
final recentMeetingsProvider =
    Provider<AsyncValue<List<CallHistory>>>((ref) {
  final historyAsync = ref.watch(callHistoryProvider);
  final presenceAsync = ref.watch(meetingPresenceStreamProvider);

  return historyAsync.when(
    loading: () => const AsyncValue.loading(),
    error: (e, st) => AsyncValue.error(e, st),
    data: (history) {
      // Presence may not have arrived yet (first build, socket
      // connecting). When it hasn't, we still want to return the
      // history list — the REST snapshot's own `isActive` field
      // covers hosted meetings, and joined-but-not-hosted rows
      // simply render as ended until the socket overlays them.
      final presenceMap = presenceAsync.maybeWhen(
        data: (m) => m,
        orElse: () => const <String, dynamic>{},
      );

      if (presenceMap.isEmpty) {
        // Fast path — no overlay, return the snapshot as-is.
        return AsyncValue.data(history);
      }

      // Walk each row; if presence has it, copy-with the live state.
      // Look up by both id and meetingCode because the Recent list
      // can mix both (hosted-meeting rows use UUID, participation
      // rows use the meeting code).
      final merged = history.map((row) {
        final byId = presenceMap[row.id];
        final byCode = row.meetingCode != null
            ? presenceMap[row.meetingCode!]
            : null;
        final p = byId ?? byCode;
        if (p == null) return row;
        return row.copyWithPresence(
          isActive: p.isActive,
          membersCount: p.membersCount,
          endedAt: p.endedAt,
        );
      }).toList();

      return AsyncValue.data(merged);
    },
  );
});
