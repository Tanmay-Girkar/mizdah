// ════════════════════════════════════════════════════════════════════
//  Incoming-call overlay
//  ────────────────────────────────────────────────────────────────────
//  Mounted near the root of the app (above the router). Watches the
//  P2P call state and surfaces an animated full-screen sheet whenever
//  `phase == incoming`. The sheet has Accept (audio) / Accept (video)
//  / Decline. Accepting nav-pushes to the active call screen;
//  declining drops back to wherever the user was.
//
//  We mount this OUTSIDE the router stack so the overlay survives
//  route changes — important because incoming calls can land while
//  the user is on Home, Meetings, anywhere.
// ════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/navigation/app_router.dart';
import '../../../core/ui/mizdah_design.dart';
import '../p2p_call_provider.dart';

class P2PIncomingOverlay extends ConsumerStatefulWidget {
  /// The app body the overlay sits in front of (the router widget).
  final Widget child;
  const P2PIncomingOverlay({super.key, required this.child});

  @override
  ConsumerState<P2PIncomingOverlay> createState() =>
      _P2PIncomingOverlayState();
}

class _P2PIncomingOverlayState extends ConsumerState<P2PIncomingOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _ringPulse;
  late final AnimationController _slideCtrl;

  bool _shown = false;

  @override
  void initState() {
    super.initState();
    _ringPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
  }

  @override
  void dispose() {
    _ringPulse.dispose();
    _slideCtrl.dispose();
    super.dispose();
  }

  void _syncWithPhase(P2PCallPhase phase) {
    final shouldShow = phase == P2PCallPhase.incoming;
    if (shouldShow == _shown) return;
    _shown = shouldShow;
    if (shouldShow) {
      _slideCtrl.forward(from: 0);
    } else {
      _slideCtrl.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final call = ref.watch(p2pCallProvider);
    _syncWithPhase(call.phase);

    return Stack(
      children: [
        widget.child,
        IgnorePointer(
          ignoring: !_shown,
          child: AnimatedBuilder(
            animation: _slideCtrl,
            builder: (context, _) {
              final t = Curves.easeOutCubic.transform(_slideCtrl.value);
              if (t == 0) return const SizedBox.shrink();
              return Opacity(
                opacity: t,
                child: Transform.translate(
                  offset: Offset(0, (1 - t) * 60),
                  child: _IncomingSheet(
                    call: call,
                    ringPulse: _ringPulse,
                    onAccept: (withVideo) {
                      debugPrint('[P2P] accept tapped '
                          '(incomingCallType=${call.withVideo ? "video" : "audio"} '
                          'acceptedAs=${withVideo ? "video" : "audio"})');
                      // 1. Move state to `connecting` and kick off
                      //    WebRTC setup BEFORE navigating. The
                      //    provider's `acceptIncoming` emits
                      //    `accept-call` to the caller; the caller
                      //    replies with `call-offer` which triggers
                      //    `_bringUpCalleeSide` → getUserMedia +
                      //    setRemoteDescription + answer + onTrack.
                      //    By the time the call screen renders its
                      //    first frame, the local stream is already
                      //    in flight.
                      ref
                          .read(p2pCallProvider.notifier)
                          .acceptIncoming(withVideo: withVideo);
                      // 2. Navigate via the GLOBAL router rather than
                      //    this overlay's BuildContext. The overlay
                      //    sits OUTSIDE the GoRouter shell and
                      //    collapses on accept (_slideCtrl.reverse →
                      //    AnimatedBuilder returns SizedBox.shrink
                      //    within 320ms). If we tried to `context.push`
                      //    from this disposing subtree, the navigation
                      //    could be silently dropped — that was the
                      //    "incoming UI vanishes but call UI never
                      //    opens" bug. Going through the singleton
                      //    `appRouter` keeps the push independent of
                      //    widget-tree lifecycle. We schedule it for
                      //    the next frame so the state update above
                      //    has already settled, which lets the screen
                      //    pick up the right phase on its first build.
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        debugPrint('[P2P] navigatingToVideoCallScreen '
                            'withVideo=$withVideo');
                        appRouter.push('/p2p-call');
                      });
                    },
                    onDecline: () {
                      ref.read(p2pCallProvider.notifier).declineIncoming();
                    },
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────────────
//  Sheet
// ────────────────────────────────────────────────────────────────────

class _IncomingSheet extends StatelessWidget {
  final P2PCallState call;
  final AnimationController ringPulse;
  final void Function(bool withVideo) onAccept;
  final VoidCallback onDecline;
  const _IncomingSheet({
    required this.call,
    required this.ringPulse,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    // ─── STEP 9: UI RENDER LOGS ────────────────────────────────────
    // What the incoming UI actually sees just before painting. If
    // `Current callType` reads `video` here but the screen shows
    // audio chrome, the bug is in the conditional below this build
    // method (Icons.call_rounded vs Icons.videocam_rounded). If it
    // reads `audio` here, the bug is upstream (Step 8 state update).
    debugPrint('==============================');
    debugPrint('BUILDING INCOMING CALL UI');
    debugPrint('Current callType: ${call.withVideo ? "video" : "audio"}');
    debugPrint('Current withVideo: ${call.withVideo}');
    debugPrint('Current callId: ${call.callId}');
    debugPrint('==============================');
    return Material(
      type: MaterialType.transparency,
      child: SafeArea(
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF1A1545), Color(0xFF0B0F1A)],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 36, 24, 36),
            child: Column(
              children: [
                // Tag chip
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.20)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.call_received_rounded,
                          color: Colors.white, size: 14),
                      SizedBox(width: 6),
                      Text(
                        'INCOMING CALL',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.6,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 36),
                _PulseAvatar(
                  name: call.remoteName ?? 'Unknown',
                  ringPulse: ringPulse,
                ),
                const SizedBox(height: 28),
                Text(
                  call.remoteName ?? 'Unknown caller',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 6),
                // Subtle hint about the call type so the user knows
                // what they're accepting before tapping. Matches the
                // accept-button choice below.
                //
                // Copy is intentionally asymmetric: audio is the
                // baseline call experience so it gets the plain
                // "is calling you", while video gets the explicit
                // "is video calling you" qualifier. The leading icon
                // mirrors the same distinction (phone vs videocam).
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      call.withVideo
                          ? Icons.videocam_rounded
                          : Icons.call_rounded,
                      size: 14,
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      call.withVideo
                          ? 'is video calling you'
                          : 'is calling you',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                // Show the SINGLE accept button that matches the
                // caller's media intent (video / audio). Previously
                // we showed both regardless, which was confusing
                // (and let the user accept a video call as audio
                // — which isn't actually supported by the WebRTC
                // handshake in the current backend). `call.withVideo`
                // comes from the signaling payload via
                // p2p_call_service.dart's `incoming-call` handler.
                Row(
                  mainAxisAlignment:
                      MainAxisAlignment.spaceEvenly,
                  children: [
                    _IncomingAction(
                      label: 'Decline',
                      icon: Icons.call_end_rounded,
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFFEF4444),
                          Color(0xFFB91C1C),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      onTap: onDecline,
                    ),
                    if (call.withVideo)
                      _IncomingAction(
                        label: 'Accept',
                        icon: Icons.videocam_rounded,
                        gradient: MizdahTokens.heroGradient,
                        onTap: () => onAccept(true),
                      )
                    else
                      _IncomingAction(
                        label: 'Accept',
                        icon: Icons.call_rounded,
                        gradient: const LinearGradient(
                          colors: [
                            Color(0xFF10B981),
                            Color(0xFF059669),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        onTap: () => onAccept(false),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _IncomingAction extends StatelessWidget {
  final String label;
  final IconData icon;
  final Gradient gradient;
  final VoidCallback onTap;
  const _IncomingAction({
    required this.label,
    required this.icon,
    required this.gradient,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MizdahPressScale(
      scaleTo: 0.92,
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: gradient,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.45),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _PulseAvatar extends StatelessWidget {
  final String name;
  final AnimationController ringPulse;
  const _PulseAvatar({required this.name, required this.ringPulse});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ringPulse,
      builder: (context, _) {
        final t = ringPulse.value;
        return SizedBox(
          width: 220,
          height: 220,
          child: Stack(
            alignment: Alignment.center,
            children: [
              for (final phase in const [0.0, 0.33, 0.66])
                Opacity(
                  opacity: (1 - ((t + phase) % 1)) * 0.45,
                  child: Container(
                    width: 130 + ((t + phase) % 1) * 90,
                    height: 130 + ((t + phase) % 1) * 90,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.45),
                        width: 1.4,
                      ),
                    ),
                  ),
                ),
              Container(
                width: 124,
                height: 124,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: MizdahTokens.heroGradient,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: MizdahTokens.primary.withValues(alpha: 0.55),
                      blurRadius: 36,
                      offset: const Offset(0, 14),
                    ),
                  ],
                ),
                child: Text(
                  _initials(name),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 42,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
        );
      },
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
