// ════════════════════════════════════════════════════════════════════
//  Call rating overlay — global trigger for the post-call sheet
//  ────────────────────────────────────────────────────────────────────
//  Mounted in main.dart at the same level as P2PIncomingOverlay and
//  P2PMiniCallOverlay. Watches `callRatingProvider`; when phase
//  flips to `promptRequested`, shows the CallRatingSheet via
//  `showModalBottomSheet` on the current Navigator. When the user
//  dismisses without skipping/submitting (drag-down or hardware
//  back), we still mark the cooldown so we don't immediately
//  re-prompt — handled inside the provider's `skip()`.
//
//  Why a global widget instead of triggering from each screen: the
//  call screen auto-pops a couple of seconds after `phase == ended`.
//  By the time the rating fires, the user is already back on Home
//  (or wherever they came from). This overlay sits above the
//  router so it works regardless of which route is current.
// ════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/navigation/app_router.dart';
import 'call_rating_provider.dart';
import 'call_rating_sheet.dart';

class CallRatingOverlay extends ConsumerStatefulWidget {
  final Widget child;
  const CallRatingOverlay({super.key, required this.child});

  @override
  ConsumerState<CallRatingOverlay> createState() =>
      _CallRatingOverlayState();
}

class _CallRatingOverlayState extends ConsumerState<CallRatingOverlay> {
  bool _sheetOpen = false;

  @override
  Widget build(BuildContext context) {
    ref.listen<CallRatingState>(callRatingProvider, (prev, next) {
      final justRequested = (prev?.phase != CallRatingPhase.promptRequested) &&
          next.phase == CallRatingPhase.promptRequested;
      if (justRequested && !_sheetOpen) {
        // Defer to post-frame. ref.listen callbacks fire during
        // build, and showModalBottomSheet mutates the widget tree
        // (inserts a route). Calling it synchronously trips
        // Flutter's "modify provider during build" guard or
        // similar tree-mutation races — see the dev-log trace
        // where leaveMeeting() also fires inside the same frame.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _openSheet(next);
        });
      }
    });
    return widget.child;
  }

  Future<void> _openSheet(CallRatingState s) async {
    final req = s.request;
    if (req == null) return;
    // Grab a context that lives BELOW the Navigator. The overlay's
    // own `context` sits inside MaterialApp.builder which is above
    // the Navigator GoRouter creates — passing that to
    // showModalBottomSheet would walk the ancestor chain, find no
    // Navigator, and silently throw. Using the root navigator's
    // overlay context gets us a guaranteed-rooted modal target.
    final navState = rootNavigatorKey.currentState;
    final sheetCtx = navState?.overlay?.context;
    if (navState == null || sheetCtx == null) {
      debugPrint('[rating] overlay → no root navigator yet, skipping');
      // ignore: discarded_futures
      ref.read(callRatingProvider.notifier).skip();
      return;
    }
    _sheetOpen = true;
    debugPrint('[rating] overlay → opening sheet '
        'callId=${req.callId} kind=${req.kind.wire}');
    try {
      await showModalBottomSheet<void>(
        context: sheetCtx,
        isScrollControlled: true,
        useSafeArea: true,
        useRootNavigator: true,
        // Match the rest of the app — surface-tinted, rounded top.
        backgroundColor: Colors.transparent,
        builder: (_) => CallRatingSheet(request: req),
      );
    } finally {
      _sheetOpen = false;
      // If the user dismissed by drag-down (didn't tap Skip or
      // Submit), the provider is still in `promptRequested`.
      // Treat it as a Skip so the cooldown applies and we don't
      // immediately re-prompt the next eligible call.
      final after = ref.read(callRatingProvider);
      if (after.phase == CallRatingPhase.promptRequested) {
        debugPrint(
            '[rating] sheet dismissed without action — treating as skip');
        // ignore: discarded_futures
        ref.read(callRatingProvider.notifier).skip();
      }
    }
  }
}
