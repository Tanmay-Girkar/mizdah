// ════════════════════════════════════════════════════════════════════
//  meetingPresenceProvider — Riverpod glue around MeetingPresenceService
// ────────────────────────────────────────────────────────────────────
//  Lifecycle:
//    • Watches authProvider.
//    • On login (token+user available) → opens the presence socket.
//    • On logout → disposes the service + clears the state.
//
//  Exposes:
//    • meetingPresenceServiceProvider — the raw service handle (only
//      the merged provider should read this directly).
//    • meetingPresenceStreamProvider  — StreamProvider<PresenceMap>;
//      UI components watch this for reactive updates.
//
//  Why a StreamProvider rather than a StateNotifierProvider:
//    The service is the source of truth and OWNS its in-memory map.
//    Mirroring it into a StateNotifier would just duplicate state +
//    add a copy-on-write penalty per event. StreamProvider lets the
//    UI consume the service's broadcast stream directly with first-
//    value seeding via `service.current()`.
// ════════════════════════════════════════════════════════════════════

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_provider.dart';
import 'services/meeting_presence_service.dart';

/// Singleton presence service for the logged-in session.
/// Auto-opens / closes the socket based on auth state.
final meetingPresenceServiceProvider =
    Provider<MeetingPresenceService>((ref) {
  final svc = MeetingPresenceService(
    onLog: (s) => debugPrint('[presence] $s'),
  );

  ref.listen<AuthState>(authProvider, (prev, next) async {
    if (next.status == AuthStatus.authenticated &&
        next.token != null &&
        next.user != null) {
      try {
        await svc.connect(jwtToken: next.token!, userId: next.user!.id);
      } catch (e) {
        debugPrint('[presence] connect failed: $e');
      }
    } else if (next.status == AuthStatus.unauthenticated) {
      await svc.dispose();
    }
  }, fireImmediately: true);

  ref.onDispose(() => svc.dispose());
  return svc;
});

/// Reactive stream of the full presence map. Every time any meeting
/// flips state, this emits a fresh snapshot of the full map. UI
/// providers map this into per-meeting lookups.
final meetingPresenceStreamProvider =
    StreamProvider<PresenceMap>((ref) async* {
  final svc = ref.watch(meetingPresenceServiceProvider);
  // Seed with the current snapshot so first build has something to
  // render without waiting for a socket event.
  yield svc.current();
  yield* svc.stream;
});
