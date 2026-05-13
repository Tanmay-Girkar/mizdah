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
import '../../auth/auth_provider.dart';
import '../p2p_call_provider.dart';

class P2PCallScreen extends ConsumerStatefulWidget {
  const P2PCallScreen({super.key});

  @override
  ConsumerState<P2PCallScreen> createState() => _P2PCallScreenState();
}

class _P2PCallScreenState extends ConsumerState<P2PCallScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _ringPulse;
  Timer? _autoPopTimer;
  bool _popScheduled = false;
  // Tracks the last observed lifecycle so we can log meaningful
  // transitions (paused → resumed = "back from screen-lock /
  // app-switch") rather than every spurious tick.
  AppLifecycleState? _lastLifecycle;

  @override
  void initState() {
    super.initState();
    _ringPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    // Subscribe to lifecycle events so we can recover the audio
    // session and renderers after screen lock / app-switcher /
    // incoming-notification interrupts. WhatsApp-style: the call
    // never visibly breaks across a power-button press.
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoPopTimer?.cancel();
    _ringPulse.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    final prev = _lastLifecycle;
    _lastLifecycle = state;
    debugPrint('==============================');
    debugPrint('CALL LIFECYCLE: $prev → $state');
    debugPrint('==============================');
    final notifier = ref.read(p2pCallProvider.notifier);
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        // App backgrounded — most often a power-button press / lock
        // screen / app-switcher / incoming system notification. We
        // INTENTIONALLY do not pause any tracks here: the audio
        // session stays alive on the platform side as long as we
        // don't touch it, and the OS will keep delivering remote
        // audio through the earpiece / speaker. See `onAppPaused`
        // for the matching log.
        notifier.onAppPaused();
        break;
      case AppLifecycleState.resumed:
        // Coming back from background. Re-poke the audio route +
        // both renderers so the call instantly looks alive again
        // (no frozen-frame quirk on Android SurfaceView).
        // ignore: discarded_futures
        notifier.onAppResumed();
        break;
      case AppLifecycleState.detached:
        // Engine teardown — the OS is killing the process. Nothing
        // to recover from; the call will end naturally as services
        // dispose.
        break;
    }
  }

  void _maybeSchedulePop(P2PCallPhase phase) {
    if (_popScheduled) return;
    if (phase == P2PCallPhase.failed || phase == P2PCallPhase.ended) {
      _popScheduled = true;
      _autoPopTimer?.cancel();
      // 2.4s — long enough for the user to register the "Call ended"
      // / "User unavailable" / "Camera blocked" message before we
      // yank them back to the previous screen.
      _autoPopTimer = Timer(const Duration(milliseconds: 2400), () {
        if (!mounted) return;
        if (Navigator.of(context).canPop()) {
          context.pop();
        }
      });
    }
    // NB: we deliberately do NOT auto-pop on `phase == idle`. The
    // previous version did, with a zero-delay timer, which raced
    // with the user landing on this screen after accept: if the
    // provider's `_scheduleResetToIdle` ticked over before our
    // screen mounted (or in between phase transitions), the screen
    // would pop itself on the very first build — the "UI vanished
    // after accept" bug. `idle` should be treated as a no-op here;
    // a real call screen only exits via `ended` (after the user
    // sees the goodbye banner) or via the user's own back gesture.
  }

  @override
  Widget build(BuildContext context) {
    final call = ref.watch(p2pCallProvider);
    _maybeSchedulePop(call.phase);

    // When the provider flips `minimized` to true (the user tapped
    // the in-call minimize button, or hit system back), pop this
    // route so the mini-call overlay can take over on whichever
    // screen the user was on previously. The peer connection,
    // tracks, and renderers stay alive in the provider/service —
    // only the full-screen UI route exits.
    ref.listen<bool>(p2pCallProvider.select((s) => s.minimized),
        (prev, next) {
      if (next == true && Navigator.of(context).canPop()) {
        debugPrint('[P2P] call screen popping in response to minimize');
        context.pop();
      }
    });

    return PopScope(
      // System back behaves like "minimize", NOT "end call". The user
      // can always end via the red end-call button. Matches WhatsApp:
      // back leaves the call running and drops you back to the chat
      // / previous screen.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (call.phase == P2PCallPhase.active ||
            call.phase == P2PCallPhase.connecting) {
          ref.read(p2pCallProvider.notifier).minimize();
        } else {
          // Pre-active phases (outgoing / failed / ended) — let the
          // user pop normally; nothing to keep alive.
          context.pop();
        }
      },
      child: _buildBody(context, call),
    );
  }

  Widget _buildBody(BuildContext context, P2PCallState call) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F1A),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Background, layered bottom-to-top ──────────────────
          //
          // Layer 1 (always for active video calls): the camera-off
          // BACKDROP. This is the floor — no matter what happens
          // upstream, we never get a black void. The screen always
          // shows the peer's avatar + name + "Camera is off" the
          // moment we don't have live video to draw on top.
          //
          // Layer 2 (only when actually rendering frames): the live
          // RTCVideoView, faded in via AnimatedSwitcher so the
          // transition between video and avatar is smooth (no
          // flicker, no harsh swap). The RTCVideoView is gated on
          // BOTH the explicit `remoteVideo` flag AND the renderer's
          // own `renderVideo` value via _RemoteVideoLayer — that's
          // the belt-and-braces fix for the previous "black screen
          // when peer turns off camera and signaling event is lost"
          // bug.
          //
          // For non-video-call phases (audio-only / outgoing /
          // ended) we still fall back to the ambient gradient so
          // those layouts feel right.
          if (call.phase == P2PCallPhase.active && call.withVideo)
            _RemoteCameraOffBackdrop(name: call.remoteName ?? 'Peer')
          else
            const _AmbientGradient(),

          // Live remote video — fades over the backdrop when frames
          // are actually flowing. Hidden (transparent) otherwise,
          // letting the backdrop show through.
          if (call.phase == P2PCallPhase.active && call.withVideo)
            _RemoteVideoLayer(
              renderer: call.remoteRenderer,
              visible: call.remoteVideo && call.remoteRenderer != null,
            ),

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
          else if (call.phase == P2PCallPhase.connecting)
            // Either the caller's outgoing was just accepted, or we
            // (the callee) just accepted an incoming. Same UI either
            // way: "Connecting to <name>…" with the pulsing avatar.
            _ConnectingView(call: call, ringPulse: _ringPulse)
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

          // Local self-view — Google-Meet-style draggable PiP.
          // Visible whenever a video call is in flight (connecting
          // or active). The PIP's internal logic shows live video
          // when the camera is on, or a "Camera off" avatar tile
          // when the user disabled their camera. We DO NOT hide
          // the PIP on camera-off — that was the previous bug,
          // where toggling the camera made the self-view container
          // vanish completely and the user couldn't toggle it back
          // visually.
          if ((call.phase == P2PCallPhase.connecting ||
                  call.phase == P2PCallPhase.active) &&
              call.withVideo)
            const _DraggableLocalPip(),

          // Top bar — back-affordance + connection chip.
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 16,
            right: 16,
            child: _TopBar(call: call),
          ),

          // Minimize chip — top-left, always present during a live
          // call so the user can drop into the floating mini-bubble
          // with a tap instead of needing the system back gesture.
          // Hidden during outgoing/failed/ended phases (nothing to
          // minimize yet) and during the brief active-but-fading-
          // out window (auto-pop already scheduled).
          if (call.phase == P2PCallPhase.connecting ||
              call.phase == P2PCallPhase.active)
            Positioned(
              top: MediaQuery.of(context).padding.top + 12,
              left: 16,
              child: _MinimizeChip(
                onTap: () => ref
                    .read(p2pCallProvider.notifier)
                    .minimize(),
              ),
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
  const _RemoteVideoBackground({super.key, required this.renderer});

  @override
  Widget build(BuildContext context) {
    return RTCVideoView(
      renderer,
      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
    );
  }
}

/// Layer-2 above the camera-off backdrop. Renders the actual
/// `RTCVideoView` ONLY when the provider's `remoteVideo` flag is
/// `true` AND a renderer exists. When the flag flips to `false`
/// (via `track.onMute` or the peer's `call-media-state` event),
/// this widget swaps to an empty `SizedBox.expand` so the backdrop
/// shows through underneath.
///
/// We deliberately do NOT cross-reference `RTCVideoRenderer.value.renderVideo`
/// here — flutter_webrtc keeps that flag `true` as long as ANY frames
/// flow (including the zero-content black frames the WebRTC engine
/// substitutes when the peer toggles `track.enabled = false`). Trusting
/// it caused a particularly nasty false positive: peer turns off
/// camera, RTP packets keep flowing with black content, renderVideo
/// stays true, RTCVideoView paints black squares ON TOP of the
/// nice avatar backdrop. The explicit `remoteVideo` flag — driven by
/// `track.onMute` / `track.onUnMute` and the socket signal — is the
/// only source of truth.
///
/// Wrapped in `AnimatedSwitcher` so the transition between live
/// video and the avatar backdrop is a smooth crossfade — no flicker,
/// no hard jump. Matches WhatsApp / FaceTime polish.
class _RemoteVideoLayer extends StatelessWidget {
  final RTCVideoRenderer? renderer;
  final bool visible;
  const _RemoteVideoLayer({required this.renderer, required this.visible});

  @override
  Widget build(BuildContext context) {
    final r = renderer;
    final shouldShow = visible && r != null;
    debugPrint('[P2P] _RemoteVideoLayer build: visible=$visible '
        'rendererAttached=${r != null} shouldShow=$shouldShow');
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: !shouldShow
          ? const SizedBox.expand(key: ValueKey('remote-video-hidden'))
          : _RemoteVideoBackground(
              key: const ValueKey('remote-video-visible'),
              renderer: r,
            ),
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
    // Audio-only calls — show a pulsing avatar + name centered.
    // Video calls handle their own avatar via the camera-off
    // backdrop in the background layer (see `_RemoteCameraOffBackdrop`
    // in the build() Stack above). Rendering an avatar here too
    // would double-stack — the previous bug.
    if (!call.withVideo) {
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
    // Video call — the background layer handles both states:
    //   • remote camera on   → `_RemoteVideoLayer` paints live video
    //   • remote camera off  → `_RemoteCameraOffBackdrop` shows below
    // Nothing for the foreground to add here.
    return const SizedBox.expand();
  }
}

// ────────────────────────────────────────────────────────────────────
//  Connecting — "Connecting to X…" (post-accept / answered)
// ────────────────────────────────────────────────────────────────────

class _ConnectingView extends StatelessWidget {
  final P2PCallState call;
  final AnimationController ringPulse;
  const _ConnectingView({required this.call, required this.ringPulse});

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
              name: call.remoteName ?? 'Connecting',
              ringPulse: ringPulse,
            ),
            const SizedBox(height: 28),
            Text(
              call.remoteName ?? 'Connecting',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 8),
            _ConnectingDots(ringPulse: ringPulse, withVideo: call.withVideo),
            const Spacer(),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}

class _ConnectingDots extends StatelessWidget {
  final AnimationController ringPulse;
  final bool withVideo;
  const _ConnectingDots({required this.ringPulse, required this.withVideo});

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
          'Connecting',
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
//  Local picture-in-picture — Google-Meet-style draggable self-view
// ────────────────────────────────────────────────────────────────────

/// Draggable, corner-snapping self-view. The user can grab it from
/// any of the four corners and toss it to another; on release we
/// animate it into the nearest corner so it never ends up covering
/// the top "Connecting" chip or the bottom controls dock.
class _DraggableLocalPip extends ConsumerStatefulWidget {
  const _DraggableLocalPip();

  @override
  ConsumerState<_DraggableLocalPip> createState() =>
      _DraggableLocalPipState();
}

class _DraggableLocalPipState extends ConsumerState<_DraggableLocalPip>
    with SingleTickerProviderStateMixin {
  // Tile dimensions — Google Meet uses ~110x150 on mobile.
  static const double _w = 110;
  static const double _h = 150;
  static const double _edgeMargin = 14;
  // Reserve space at top + bottom for the in-call chrome so the PiP
  // can never sit on top of the status chip or the controls dock.
  static const double _topExclusion = 60;
  static const double _bottomExclusion = 130;

  Offset _position = const Offset(-1, -1); // -1 = "not initialised"
  bool _dragging = false;

  void _initIfNeeded(Size screen, MediaQueryData mq) {
    if (_position.dx >= 0) return;
    // Default to BOTTOM-RIGHT — matches WhatsApp / FaceTime layouts.
    // Sitting at the top-right (the old default) put the self-view
    // right under the status-bar / "Connected" chip, which fights
    // for attention. Bottom-right keeps the user's own face in
    // their normal phone-grip thumb reach and out of the way of
    // the remote video's centre frame. The user can still drag the
    // tile to any other corner; the snap-to-corner logic respects
    // their last position.
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
    final x = goRight
        ? screen.width - _w - _edgeMargin
        : _edgeMargin;
    final yMin = mq.padding.top + _topExclusion;
    final yMax = screen.height - _h - _bottomExclusion - mq.padding.bottom;
    final y = goBottom ? yMax : yMin;
    setState(() => _position = Offset(x, y));
  }

  @override
  Widget build(BuildContext context) {
    final call = ref.watch(p2pCallProvider);
    final renderer = call.localRenderer;
    final mq = MediaQuery.of(context);
    final screen = mq.size;
    _initIfNeeded(screen, mq);

    // "Camera off" placeholder if the user has disabled their camera
    // OR we haven't received a renderer yet (early connecting). Live
    // video otherwise. The container's outer chrome is identical
    // either way so the user always knows where the PIP is.
    final showVideo = renderer != null && call.localVideo;

    return AnimatedPositioned(
      duration: Duration(milliseconds: _dragging ? 0 : 220),
      curve: Curves.easeOutCubic,
      left: _position.dx,
      top: _position.dy,
      child: GestureDetector(
        onPanStart: (_) => setState(() => _dragging = true),
        onPanUpdate: (d) {
          setState(() {
            final yMin = mq.padding.top + _topExclusion;
            final yMax =
                screen.height - _h - _bottomExclusion - mq.padding.bottom;
            _position = Offset(
              (_position.dx + d.delta.dx)
                  .clamp(_edgeMargin, screen.width - _w - _edgeMargin),
              (_position.dy + d.delta.dy).clamp(yMin, yMax),
            );
          });
        },
        onPanEnd: (_) {
          setState(() => _dragging = false);
          _snapToCorner(screen, mq);
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Container(
            width: _w,
            height: _h,
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
            // AnimatedSwitcher = soft 220ms cross-fade between the
            // live RTCVideoView and the placeholder; no flicker.
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              child: showVideo
                  ? RTCVideoView(
                      renderer,
                      key: const ValueKey('local-video'),
                      mirror: true,
                      objectFit:
                          RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    )
                  : const _LocalCameraOffTile(
                      key: ValueKey('local-camoff'),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Mini placeholder shown INSIDE the draggable PIP when the local
/// user has turned their camera off. Same dimensions as the
/// RTCVideoView so the surrounding container doesn't resize on
/// toggle.
class _LocalCameraOffTile extends ConsumerWidget {
  const _LocalCameraOffTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(authProvider).user;
    final name = me?.name ?? 'You';
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: MizdahTokens.heroGradient,
      ),
      child: Stack(
        alignment: Alignment.center,
        fit: StackFit.expand,
        children: [
          // Soft dark vignette so the white initials read.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.45),
                ],
                radius: 0.95,
              ),
            ),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: Colors.white.withValues(alpha: 0.18),
                child: Text(
                  _initialsOf(name),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Icon(
                Icons.videocam_off_rounded,
                color: Colors.white,
                size: 16,
              ),
              const SizedBox(height: 4),
              const Text(
                'Camera off',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _initialsOf(String n) {
    final parts = n.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }
}

/// Full-screen backdrop shown when the REMOTE peer has their camera
/// off. Replaces the would-be black rectangle with the same kind of
/// pulsing avatar treatment the incoming overlay uses, so the screen
/// always reads as "we're still on a call together."
class _RemoteCameraOffBackdrop extends StatefulWidget {
  final String name;
  const _RemoteCameraOffBackdrop({required this.name});

  @override
  State<_RemoteCameraOffBackdrop> createState() =>
      _RemoteCameraOffBackdropState();
}

class _RemoteCameraOffBackdropState extends State<_RemoteCameraOffBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('[P2P] _RemoteCameraOffBackdrop build: name=${widget.name}');
    // SizedBox.expand wraps the whole thing — without this an
    // unconstrained parent could let the DecoratedBox shrink to its
    // child's intrinsic size (the centered Column), leaving the
    // rest of the screen unpainted and exposing whatever's beneath
    // the Stack. With expand the gradient ALWAYS fills the whole
    // call screen.
    return SizedBox.expand(
      child: DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1A1545), Color(0xFF0B0F1A)],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        alignment: Alignment.center,
        children: [
          // Soft brand-coloured glow accents — pure decoration, kept
          // subtle so the avatar reads as the focal point.
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
          // Pulsing avatar + label centre. Layout is intentionally
          // shifted up a bit so the bottom controls don't crowd it.
          Padding(
            padding: const EdgeInsets.only(bottom: 120),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _PulseAvatar(name: widget.name, ringPulse: _pulse),
                const SizedBox(height: 28),
                Text(
                  widget.name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 12),
                // Pill-shaped "Camera off" badge — frosted-glass look
                // matching the WhatsApp / Telegram pattern. Reads
                // clearly against both the gradient and the soft
                // glow accents above.
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.22),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.videocam_off_rounded,
                        size: 14,
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Camera off',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.92),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
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
        label = 'Ringing';
        dot = const Color(0xFFF59E0B);
        break;
      case P2PCallPhase.connecting:
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
    // "Cancel" while we're still ringing on the caller side (no
    // media yet, no peer to hang up on); "End call" everywhere else.
    // `connecting` is treated as "end call" because the peer ack'd —
    // we cancel the in-flight WebRTC handshake by ending normally.
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
              // Speaker / earpiece toggle. Default-OFF for audio
              // calls (earpiece, WhatsApp-style) and default-ON for
              // video (loudspeaker, FaceTime-style). User can flip
              // either way — useful on a busy bus (speaker off) or
              // when handing the phone around (speaker on).
              _CircleControl(
                icon: call.isSpeakerphoneOn
                    ? Icons.volume_up_rounded
                    : Icons.volume_down_rounded,
                active: call.isSpeakerphoneOn,
                onTap: notifier.toggleSpeakerphone,
                tooltip: call.isSpeakerphoneOn
                    ? 'Speaker off'
                    : 'Speaker on',
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

/// Top-left "minimize" chip — drops the user into the floating
/// mini-call overlay (WhatsApp-style). Tapping it leaves the call
/// running; the peer connection, tracks, and renderers all survive.
class _MinimizeChip extends StatelessWidget {
  final VoidCallback onTap;
  const _MinimizeChip({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return MizdahPressScale(
      scaleTo: 0.90,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.25),
          ),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.expand_more_rounded,
                color: Colors.white, size: 18),
            SizedBox(width: 4),
            Text(
              'Minimize',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
          ],
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
