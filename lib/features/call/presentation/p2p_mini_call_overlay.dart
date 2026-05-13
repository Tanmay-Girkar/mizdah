// ════════════════════════════════════════════════════════════════════
//  Mini-call overlay (WhatsApp-style minimized call bubble)
//  ────────────────────────────────────────────────────────────────────
//  Mounted at the same level as `P2PIncomingOverlay` — wraps the
//  whole router so it can paint on top of any screen. Watches the
//  P2P call state and shows a draggable, corner-snapping floating
//  container whenever:
//
//    • The call phase is `connecting` or `active`, AND
//    • The user has minimized the call (state.minimized == true).
//
//  The minimized state itself is driven by the call screen's
//  PopScope (system back) and an explicit "minimize" button. The
//  full-screen call route reads `state.minimized` and auto-pops
//  when it flips to `true`, so the user lands back on whichever
//  screen they were on before opening the call.
//
//  Tapping the mini bubble:
//    1) Sets `minimized = false` on the provider.
//    2) Pushes /p2p-call on the global router.
//  No state is recreated — the peer connection, tracks, and
//  renderers all survive the trip.
// ════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../../core/navigation/app_router.dart';
import '../../../core/ui/mizdah_design.dart';
import '../p2p_call_provider.dart';

class P2PMiniCallOverlay extends ConsumerStatefulWidget {
  final Widget child;
  const P2PMiniCallOverlay({super.key, required this.child});

  @override
  ConsumerState<P2PMiniCallOverlay> createState() =>
      _P2PMiniCallOverlayState();
}

class _P2PMiniCallOverlayState extends ConsumerState<P2PMiniCallOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fade;

  // Tile dimensions — matches the call screen's local PIP for
  // visual consistency, but a touch larger so the user can read
  // the peer's video at a glance.
  static const double _w = 130;
  static const double _h = 178;
  static const double _edgeMargin = 14;
  static const double _topExclusion = 60;
  static const double _bottomExclusion = 24;

  Offset _position = const Offset(-1, -1); // -1 = "not initialised"
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _fade = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  bool _shouldShow(P2PCallState call) =>
      call.minimized &&
      (call.phase == P2PCallPhase.active ||
          call.phase == P2PCallPhase.connecting);

  void _initIfNeeded(Size screen, MediaQueryData mq) {
    if (_position.dx >= 0) return;
    // Default to BOTTOM-RIGHT — matches WhatsApp's resting position.
    _position = Offset(
      screen.width - _w - _edgeMargin,
      screen.height - _h - _bottomExclusion - mq.padding.bottom,
    );
  }

  void _snapToCorner(Size screen, MediaQueryData mq) {
    final centerX = _position.dx + _w / 2;
    final centerY = _position.dy + _h / 2;
    final goRight = centerX > screen.width / 2;
    final goBottom = centerY > screen.height / 2;
    final x =
        goRight ? screen.width - _w - _edgeMargin : _edgeMargin;
    final yMin = mq.padding.top + _topExclusion;
    final yMax =
        screen.height - _h - _bottomExclusion - mq.padding.bottom;
    final y = goBottom ? yMax : yMin;
    setState(() => _position = Offset(x, y));
  }

  void _restoreFullScreen() {
    debugPrint('[P2P] MINI tapped — restoring fullscreen call');
    ref.read(p2pCallProvider.notifier).restoreFromMinimized();
    // Use the global router because the mini overlay sits OUTSIDE
    // the GoRouter shell. Schedule for the next frame so the state
    // update lands first.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      appRouter.push('/p2p-call');
    });
  }

  @override
  Widget build(BuildContext context) {
    final call = ref.watch(p2pCallProvider);
    final shouldShow = _shouldShow(call);
    if (shouldShow && _fade.status != AnimationStatus.completed) {
      _fade.forward();
    } else if (!shouldShow && _fade.status != AnimationStatus.dismissed) {
      _fade.reverse();
    }

    return Stack(
      children: [
        widget.child,
        // Mini bubble — only built when there's something to show.
        // The animation runs independently so the bubble fades in /
        // out smoothly without flickering when the user toggles
        // minimize on/off rapidly.
        AnimatedBuilder(
          animation: _fade,
          builder: (context, _) {
            final t = _fade.value;
            if (t == 0) return const SizedBox.shrink();
            return _MiniBubble(
              call: call,
              opacity: t,
              position: _position,
              dragging: _dragging,
              width: _w,
              height: _h,
              onTap: _restoreFullScreen,
              onPanStart: () => setState(() => _dragging = true),
              onPanUpdate: (delta) {
                final mq = MediaQuery.of(context);
                final screen = mq.size;
                _initIfNeeded(screen, mq);
                setState(() {
                  final yMin = mq.padding.top + _topExclusion;
                  final yMax = screen.height -
                      _h -
                      _bottomExclusion -
                      mq.padding.bottom;
                  _position = Offset(
                    (_position.dx + delta.dx).clamp(
                      _edgeMargin,
                      screen.width - _w - _edgeMargin,
                    ),
                    (_position.dy + delta.dy).clamp(yMin, yMax),
                  );
                });
              },
              onPanEnd: () {
                final mq = MediaQuery.of(context);
                setState(() => _dragging = false);
                _snapToCorner(mq.size, mq);
              },
              onEndCall: () {
                // ignore: discarded_futures
                ref.read(p2pCallProvider.notifier).endCall();
              },
              initIfNeeded: () {
                final mq = MediaQuery.of(context);
                _initIfNeeded(mq.size, mq);
              },
            );
          },
        ),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────────────
//  The bubble itself
// ────────────────────────────────────────────────────────────────────

class _MiniBubble extends ConsumerWidget {
  final P2PCallState call;
  final double opacity;
  final Offset position;
  final bool dragging;
  final double width;
  final double height;
  final VoidCallback onTap;
  final VoidCallback onPanStart;
  final void Function(Offset delta) onPanUpdate;
  final VoidCallback onPanEnd;
  final VoidCallback onEndCall;
  final VoidCallback initIfNeeded;
  const _MiniBubble({
    required this.call,
    required this.opacity,
    required this.position,
    required this.dragging,
    required this.width,
    required this.height,
    required this.onTap,
    required this.onPanStart,
    required this.onPanUpdate,
    required this.onPanEnd,
    required this.onEndCall,
    required this.initIfNeeded,
  });

  bool get _hasRemoteVideo =>
      call.withVideo &&
      call.remoteVideo &&
      call.remoteRenderer != null;

  bool get _hasLocalVideo =>
      call.withVideo &&
      call.localVideo &&
      call.localRenderer != null;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Schedule the position init on the next frame so we have a
    // valid MediaQuery to base it on (build itself can't call
    // setState).
    WidgetsBinding.instance.addPostFrameCallback((_) => initIfNeeded());
    return AnimatedPositioned(
      duration: Duration(milliseconds: dragging ? 0 : 220),
      curve: Curves.easeOutCubic,
      left: position.dx,
      top: position.dy,
      child: Opacity(
        opacity: opacity,
        child: GestureDetector(
          onTap: onTap,
          onPanStart: (_) => onPanStart(),
          onPanUpdate: (d) => onPanUpdate(d.delta),
          onPanEnd: (_) => onPanEnd(),
          child: _BubbleChrome(
            width: width,
            height: height,
            call: call,
            hasRemoteVideo: _hasRemoteVideo,
            hasLocalVideo: _hasLocalVideo,
            onEndCall: onEndCall,
          ),
        ),
      ),
    );
  }
}

class _BubbleChrome extends ConsumerWidget {
  final double width;
  final double height;
  final P2PCallState call;
  final bool hasRemoteVideo;
  final bool hasLocalVideo;
  final VoidCallback onEndCall;
  const _BubbleChrome({
    required this.width,
    required this.height,
    required this.call,
    required this.hasRemoteVideo,
    required this.hasLocalVideo,
    required this.onEndCall,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Visual hierarchy inside the bubble (z-order, bottom to top):
    //   1) Background — live remote video if available, else live
    //      local video, else dark gradient with peer initials.
    //   2) Subtle top gradient so the connection-state chip reads.
    //   3) Connection chip (top-left) — "Connecting" / call duration.
    //   4) End-call mini-button (bottom-right) so the user can drop
    //      the call without restoring fullscreen.
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 1) Background
            _MiniBackdrop(
              call: call,
              hasRemoteVideo: hasRemoteVideo,
              hasLocalVideo: hasLocalVideo,
            ),
            // 2) Top gradient for chip legibility
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.55),
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.55),
                    ],
                    stops: const [0, 0.4, 1],
                  ),
                ),
              ),
            ),
            // 3) Connection chip
            Positioned(
              top: 8,
              left: 8,
              right: 36,
              child: _MiniStatusChip(call: call),
            ),
            // 4) End-call mini button
            Positioned(
              bottom: 8,
              right: 8,
              child: _MiniEndCallButton(onTap: onEndCall),
            ),
            // 5) Subtle border for separation from screen content
            // behind. Drawn last so it sits on top of everything else.
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.20),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.45),
                      blurRadius: 22,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniBackdrop extends ConsumerWidget {
  final P2PCallState call;
  final bool hasRemoteVideo;
  final bool hasLocalVideo;
  const _MiniBackdrop({
    required this.call,
    required this.hasRemoteVideo,
    required this.hasLocalVideo,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Priority order:
    //   1) Remote video (the peer's face — most useful preview)
    //   2) Local video (so the user can see themselves while
    //      browsing other screens; mirrored like every selfie)
    //   3) Avatar placeholder (audio call, or video not yet flowing)
    if (hasRemoteVideo) {
      return RTCVideoView(
        call.remoteRenderer!,
        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
      );
    }
    if (hasLocalVideo) {
      return RTCVideoView(
        call.localRenderer!,
        mirror: true,
        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
      );
    }
    return _MiniAvatarBackdrop(name: call.remoteName ?? 'Mizdah');
  }
}

class _MiniAvatarBackdrop extends StatelessWidget {
  final String name;
  const _MiniAvatarBackdrop({required this.name});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: MizdahTokens.heroGradient,
      ),
      child: Center(
        child: Text(
          _initials(name),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 30,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
            shadows: [
              Shadow(
                color: Colors.black54,
                offset: Offset(0, 2),
                blurRadius: 6,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _initials(String n) {
    final parts = n.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }
}

class _MiniStatusChip extends ConsumerStatefulWidget {
  final P2PCallState call;
  const _MiniStatusChip({required this.call});

  @override
  ConsumerState<_MiniStatusChip> createState() => _MiniStatusChipState();
}

class _MiniStatusChipState extends ConsumerState<_MiniStatusChip> {
  // The call provider doesn't track a `startedAt` timestamp — we
  // approximate locally from when this widget first sees the
  // `active` phase, so the duration string updates inside the
  // bubble. Good enough for UI; the authoritative log entry comes
  // from the provider.
  DateTime? _activeSince;

  String _shortDuration() {
    final since = _activeSince;
    if (since == null) return '';
    final s = DateTime.now().difference(since).inSeconds;
    final m = s ~/ 60;
    final ss = (s % 60).toString().padLeft(2, '0');
    return '$m:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final call = widget.call;
    if (call.phase == P2PCallPhase.active && _activeSince == null) {
      _activeSince = DateTime.now();
    } else if (call.phase != P2PCallPhase.active) {
      _activeSince = null;
    }
    final connecting = call.phase == P2PCallPhase.connecting;
    final label = connecting
        ? 'Connecting…'
        : (call.remoteName ?? 'On a call');
    final sub = connecting ? null : _shortDuration();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            call.withVideo
                ? Icons.videocam_rounded
                : Icons.call_rounded,
            color: Colors.white,
            size: 11,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ),
          if (sub != null && sub.isNotEmpty) ...[
            const SizedBox(width: 4),
            Text(
              sub,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MiniEndCallButton extends StatelessWidget {
  final VoidCallback onTap;
  const _MiniEndCallButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFEF4444), Color(0xFFB91C1C)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.call_end_rounded,
          color: Colors.white,
          size: 14,
        ),
      ),
    );
  }
}
