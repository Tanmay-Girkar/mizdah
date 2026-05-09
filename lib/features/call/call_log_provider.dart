// ════════════════════════════════════════════════════════════════════
//  Call log Riverpod providers
// ════════════════════════════════════════════════════════════════════
//  UI screens consume `callLogProvider`. Hooks in
//  `P2PCallNotifier._appendCallLog(...)` write to
//  `callLogRepositoryProvider`.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/call_log_models.dart';
import 'data/call_log_repository.dart';

final callLogRepositoryProvider = Provider<CallLogRepository>((ref) {
  return LocalCallLogRepository();
});

final callLogProvider = StreamProvider<List<CallLogEntry>>((ref) {
  return ref.watch(callLogRepositoryProvider).watch();
});
