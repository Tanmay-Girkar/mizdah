// ════════════════════════════════════════════════════════════════════
//  P2P Call Screen — outgoing / active / ended view
//  ────────────────────────────────────────────────────────────────────
//  Single-route screen that follows the call state from the moment
//  `p2pCallProvider.startCall(...)` fires to teardown. Renders four
//  visual modes off the same scaffold:
//
//    • OUTGOING (no media yet) — gradient ringing card, big avatar,
//      "Calling [name]…", animated dots, cancel button.
//    • OUTGOING + media wiring — same chrome but the local preview
//      starts to slot in.
//    • ACTIVE — full-screen remote video with a small picture-in-
//      picture local preview, plus the in-call controls dock.
//    • FAILED / ENDED — banner ("User unavailable" / "Call ended")
//      then auto-pop after 1.5s.
//
//  Audio-only calls render the same UI with the remote tile replaced
//  by an oversized avatar + waveform-ish accent.
// ════════════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ui/mizdah_design.dart';
import '../p2p_call_provider.dart';

class P2PCallScreen extends ConsumerStatefulWidget {
  const P2PCallScreen({super.key});

  @override
  ConsumerState<P2PCallScreen> createState() => _P2PCallScreenState();
}

class _P2PCallScreenState extends ConsumerState<P2PCallScreen>
    with TickerProviderStateMixin {
  late final AnimationController _ringPulse;
  Timer? _autoPopTimer;
  bool _popScheduled = false;

  @override
  void initState() {
    super.initState();
    _ringPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _autoPopTimer?.cancel();
    _ringPulse.dispose();
    super.dispose();
  }

  void _maybeSchedulePop(P2PCallPhase phase) {
    if (_popScheduled) return;
    if (phase == P2PCallPhase.failed || phase == P2PCallPhase.ended) {
      _popScheduled = true;
      _autoPopTimer?.cancel();
      _autoPopTimer = Timer(const Duration(milliseconds: 1500), () {
        if (!mounted) return;
        if (Navigator.of(context).canPop()) {
          context.pop();
        }
      });
    } else if (phase == P2PCallPhase.idle) {
      // Provider may have already reset to idle by the time we mount
      // (e.g. the user pressed back from outgoing). Pop immediately.
      _autoPopTimer?.cancel();
      _autoPopTimer = Timer(Duration.zero, () {
        if (!mounted) return;
        if (Navigator.of(context).canPop()) context.pop();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final call = ref.watch(p2pCallProvider);
    _maybeSchedulePop(call.phase);

    return Scaffold(
      backgroundColor: const Color(0xFF0B0F1A),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background — either remote video (active) or a deep
          // gradient (outgoing / failed / ended).
          if (call.phase == P2PCallPhase.active &&
              call.withVideo &&
              call.remoteRenderer != null)
            _RemoteVideoBackground(renderer: call.remoteRenderer!)
          else
            const _AmbientGradient(),

          // Subtle vignette so foreground text reads on either bg.
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.38),
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.55),
                  ],
                  stops: const [0, 0.45, 1],
                ),
              ),
            ),
          ),

          // Main content — varies by phase.
          if (call.phase == P2PCallPhase.failed ||
              call.phase == P2PCallPhase.ended)
            _FailedOrEndedView(call: call)
          else if (call.phase == P2PCallPhase.outgoing)
            _OutgoingView(call: call, ringPulse: _ringPulse)
          else if (call.phase == P2PCallPhase.active)
            _ActiveView(call: call, ringPulse: _ringPulse)
          else
            // Idle — usually transient. Show a tiny spinner so we
            // never paint an empty black screen.
            const Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  valueColor: AlwaysStoppedAnimation(Colors.white),
                ),
              ),
            ),

          // Local PiP — only when the call is active and we have a
          // local renderer + the user hasn't disabled their camera.
          if (call.phase == P2PCallPhase.active &&
              call.withVideo &&
              call.localRenderer != null &&
              call.localVideo)
            const Positioned(
              right: 18,
              top: 60,
              child: _LocalPip(),
            ),

          // Top bar — back-affordance + connection chip.
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 16,
            right: 16,
            child: _TopBar(call: call),
          ),

          // Bottom dock — controls.
          Positioned(
            left: 0,
            right: 0,
            bottom: MediaQuery.of(context).padding.bottom + 18,
            child: _ControlsDock(call: call),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────
//  Backgrounds
// ────────────────────────────────────────────────────────────────────

class _RemoteVideoBackground extends StatelessWidget {
  final RTCVideoRenderer renderer;
  const _RemoteVideoBackground({required this.renderer});

  @override
  Widget build(BuildContext context) {
    return RTCVideoView(
      renderer,
      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
    );
  }
}

class _AmbientGradient extends StatelessWidget {
  const _AmbientGradient();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF1A1545),
            Color(0xFF0B0F1A),
          ],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -120,
            left: -80,
            child: IgnorePointer(
              child: Container(
                width: 360,
                height: 360,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      MizdahTokens.primary.withValues(alpha: 0.45),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -160,
            right: -100,
            child: IgnorePointer(
              child: Container(
                width: 420,
                height: 420,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      MizdahTokens.tertiary.withValues(alpha: 0.32),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────
//  Outgoing — "Calling X…" with pulsing avatar halo
// ────────────────────────────────────────────────────────────────────

class _OutgoingView extends StatelessWidget {
  final P2PCallState call;
  final AnimationController ringPulse;
  const _OutgoingView({required this.call, required this.ringPulse});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 80, 24, 160),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Spacer(),
            _PulseAvatar(
              name: call.remoteName ?? 'Calling…',
              ringPulse: ringPulse,
            ),
            const SizedBox(height: 28),
            Text(
              call.remoteName ?? 'Calling…',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 8),
            _RingingDots(ringPulse: ringPulse, withVideo: call.withVideo),
            const Spacer(),
            const Spacer(),
          ],
        ),
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

class _RingingDots extends StatelessWidget {
  final AnimationController ringPulse;
  final bool withVideo;
  const _RingingDots({required this.ringPulse, required this.withVideo});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          withVideo ? Icons.videocam_rounded : Icons.call_rounded,
          color: Colors.white.withValues(alpha: 0.85),
          size: 16,
        ),
        const SizedBox(width: 8),
        Text(
          withVideo ? 'Video calling' : 'Calling',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.85),
            fontSize: 14,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(width: 4),
        AnimatedBuilder(
          animation: ringPulse,
          builder: (context, _) {
            final t = ringPulse.value;
            return Row(
              children: [
                for (var i = 0; i < 3; i++)
                  Padding(
                    padding: const EdgeInsets.only(left: 2),
                    child: Opacity(
                      opacity: ((t + i / 3) % 1).clamp(0.2, 1.0),
                      child: const Text(
                        '·',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────────────
//  Active — controls on bottom; remote video / avatar fills behind
// ────────────────────────────────────────────────────────────────────

class _ActiveView extends StatelessWidget {
  final P2PCallState call;
  final AnimationController ringPulse;
  const _ActiveView({required this.call, required this.ringPulse});

  @override
  Widget build(BuildContext context) {
    // Audio-only calls (or remote camera disabled) — show a pulsing
    // avatar + name centered.
    if (!call.withVideo || call.remoteRenderer == null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 160),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _PulseAvatar(
                name: call.remoteName ?? 'Mizdah user',
                ringPulse: ringPulse,
              ),
              const SizedBox(height: 22),
              Text(
                call.remoteName ?? 'On a call',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Connected · audio only',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
        ),
      );
    }
    // Video call — the renderer fills the entire background; nothing
    // to lay out here.
    return const SizedBox.expand();
  }
}

// ────────────────────────────────────────────────────────────────────
//  Local picture-in-picture — bottom-right floating preview
// ────────────────────────────────────────────────────────────────────

class _LocalPip extends ConsumerWidget {
  const _LocalPip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final renderer = ref.watch(p2pCallProvider).localRenderer;
    if (renderer == null) return const SizedBox.shrink();
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: 110,
        height: 150,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
              color: Colors.white.withValues(alpha: 0.22), width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.50),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: RTCVideoView(
          renderer,
          mirror: true,
          objectFit:
              RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────
//  Top bar — connection chip + label
// ────────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final P2PCallState call;
  const _TopBar({required this.call});

  @override
  Widget build(BuildContext context) {
    String label;
    Color dot;
    switch (call.phase) {
      case P2PCallPhase.outgoing:
        label = 'Connecting';
        dot = const Color(0xFFF59E0B);
        break;
      case P2PCallPhase.active:
        label = call.mediaConnected ? 'Connected' : 'Connecting media';
        dot = const Color(0xFF10B981);
        break;
      case P2PCallPhase.ended:
        label = 'Ended';
        dot = const Color(0xFF8A8FA0);
        break;
      case P2PCallPhase.failed:
        label = call.failureMessage ?? 'Failed';
        dot = const Color(0xFFEF4444);
        break;
      case P2PCallPhase.incoming:
        label = 'Incoming…';
        dot = MizdahTokens.primary;
        break;
      case P2PCallPhase.idle:
        label = '';
        dot = Colors.transparent;
        break;
    }
    return Row(
      children: [
        if (label.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.40),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.18),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: dot,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: dot.withValues(alpha: 0.7),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
          ),
        const Spacer(),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────────────
//  Controls dock — mic, video, end call
// ────────────────────────────────────────────────────────────────────

class _ControlsDock extends ConsumerWidget {
  final P2PCallState call;
  const _ControlsDock({required this.call});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(p2pCallProvider.notifier);
    final isRinging = call.phase == P2PCallPhase.outgoing;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(34),
            border: Border.all(
                color: Colors.white.withValues(alpha: 0.22), width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _CircleControl(
                icon: call.localAudio
                    ? Icons.mic_rounded
                    : Icons.mic_off_rounded,
                active: call.localAudio,
                onTap: notifier.toggleAudio,
                tooltip: call.localAudio ? 'Mute' : 'Unmute',
              ),
              const SizedBox(width: 12),
              if (call.withVideo)
                _CircleControl(
                  icon: call.localVideo
                      ? Icons.videocam_rounded
                      : Icons.videocam_off_rounded,
                  active: call.localVideo,
                  onTap: notifier.toggleVideo,
                  tooltip:
                      call.localVideo ? 'Camera off' : 'Camera on',
                ),
              if (call.withVideo) const SizedBox(width: 12),
              _CircleControl(
                icon: Icons.call_end_rounded,
                tone: _ControlTone.danger,
                size: 64,
                onTap: () {
                  if (isRinging) {
                    notifier.cancelOutgoing();
                  } else {
                    notifier.endCall();
                  }
                },
                tooltip: isRinging ? 'Cancel call' : 'End call',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _ControlTone { neutral, danger }

class _CircleControl extends StatelessWidget {
  final IconData icon;
  final bool active;
  final _ControlTone tone;
  final double size;
  final VoidCallback onTap;
  final String tooltip;
  const _CircleControl({
    required this.icon,
    required this.onTap,
    required this.tooltip,
    this.active = true,
    this.tone = _ControlTone.neutral,
    this.size = 54,
  });

  @override
  Widget build(BuildContext context) {
    final isDanger = tone == _ControlTone.danger;
    return Tooltip(
      message: tooltip,
      child: MizdahPressScale(
        scaleTo: 0.90,
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: isDanger
                ? const LinearGradient(
                    colors: [Color(0xFFEF4444), Color(0xFFB91C1C)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: isDanger
                ? null
                : (active
                    ? Colors.white.withValues(alpha: 0.18)
                    : const Color(0xFFEF4444).withValues(alpha: 0.85)),
            shape: BoxShape.circle,
            border: isDanger
                ? null
                : Border.all(
                    color: Colors.white.withValues(alpha: 0.30),
                    width: 1,
                  ),
            boxShadow: isDanger
                ? [
                    BoxShadow(
                      color: const Color(0xFFEF4444)
                          .withValues(alpha: 0.45),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : null,
          ),
          child: Icon(icon, color: Colors.white, size: size * 0.40),
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────
//  Failed / ended view
// ────────────────────────────────────────────────────────────────────

class _FailedOrEndedView extends StatelessWidget {
  final P2PCallState call;
  const _FailedOrEndedView({required this.call});

  @override
  Widget build(BuildContext context) {
    final isFailure = call.phase == P2PCallPhase.failed;
    final label = call.failureMessage ??
        (isFailure ? 'Call failed' : 'Call ended');
    final icon = isFailure
        ? Icons.error_outline_rounded
        : Icons.call_end_rounded;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 92,
            height: 92,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.20),
              ),
            ),
            child: Icon(icon, color: Colors.white, size: 38),
          ),
          const SizedBox(height: 18),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
          if (call.remoteName != null) ...[
            const SizedBox(height: 6),
            Text(
              call.remoteName!,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
