// ════════════════════════════════════════════════════════════════════
//  Incoming-call overlay
//  ────────────────────────────────────────────────────────────────────
//  Mounted near the root of the app (above the router). Watches the
//  P2P call state and surfaces an animated full-screen sheet whenever
//  `phase == incoming`. The sheet has Accept / Decline.
//
//  Video calls (`call.withVideo == true`) get a WhatsApp-style live
//  self-camera preview painted fullscreen BEHIND the caller card,
//  starting the moment the ring lands. The preview is the same
//  MediaStream that gets attached to the WebRTC peer connection on
//  accept — no flicker, no re-init, no second `getUserMedia()` call.
//  Audio-only calls show the original avatar-pulse UI.
//
//  We mount this OUTSIDE the router stack so the overlay survives
//  route changes — important because incoming calls can land while
//  the user is on Home, Meetings, anywhere.
// ════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

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
  late final AnimationController _previewFade;

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
    // Driven by `_syncPreviewFade`. Independent of the slide so the
    // caller card can pop in instantly while the camera preview
    // fades up underneath as soon as the first frame is ready.
    _previewFade = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
    );
  }

  @override
  void dispose() {
    _ringPulse.dispose();
    _slideCtrl.dispose();
    _previewFade.dispose();
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

  void _syncPreviewFade(P2PCallState call) {
    final ready = call.phase == P2PCallPhase.incoming &&
        call.withVideo &&
        call.previewState == P2PPreviewState.ready &&
        call.localRenderer != null;
    if (ready && _previewFade.status != AnimationStatus.completed) {
      _previewFade.forward();
    } else if (!ready && _previewFade.status != AnimationStatus.dismissed) {
      _previewFade.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final call = ref.watch(p2pCallProvider);
    _syncWithPhase(call.phase);
    _syncPreviewFade(call);

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
                    previewFade: _previewFade,
                    onAccept: (withVideo) {
                      debugPrint('[P2P] accept tapped '
                          '(incomingCallType=${call.withVideo ? "video" : "audio"} '
                          'acceptedAs=${withVideo ? "video" : "audio"} '
                          'previewState=${call.previewState})');
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
                      //
                      //    For video calls where the preview is
                      //    already warmed, `_attachLocalMedia` sees
                      //    `_localStream != null` and just re-adds
                      //    the existing tracks to the new PC. The
                      //    user's selfie keeps painting without a
                      //    single dropped frame between the overlay
                      //    and the call screen — the renderer object
                      //    in `state.localRenderer` is the same one
                      //    the call screen's PIP will pick up.
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
                      // ignore: discarded_futures
                      ref
                          .read(p2pCallProvider.notifier)
                          .declineIncoming();
                    },
                    onFlipCamera: () {
                      // ignore: discarded_futures
                      ref.read(p2pCallProvider.notifier).switchCamera();
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
  final AnimationController previewFade;
  final void Function(bool withVideo) onAccept;
  final VoidCallback onDecline;
  final VoidCallback onFlipCamera;
  const _IncomingSheet({
    required this.call,
    required this.ringPulse,
    required this.previewFade,
    required this.onAccept,
    required this.onDecline,
    required this.onFlipCamera,
  });

  bool get _hasLivePreview =>
      call.withVideo &&
      call.previewState == P2PPreviewState.ready &&
      call.localRenderer != null;

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
    debugPrint('Current previewState: ${call.previewState}');
    debugPrint('Live preview painting: $_hasLivePreview');
    debugPrint('==============================');
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // ── Layer 1: solid gradient backdrop ─────────────────────
          // Ensures the screen NEVER goes black, even before the
          // camera preview fades in or if permission was denied.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF1A1545), Color(0xFF0B0F1A)],
              ),
            ),
          ),

          // ── Layer 2: live self-camera preview (fades in) ────────
          // Only mounted for video calls once the warmed stream is
          // ready. Mirrored to match every selfie convention. Fades
          // up via `previewFade` so the transition from gradient to
          // live video is smooth — no harsh flash when frames start.
          if (call.withVideo)
            AnimatedBuilder(
              animation: previewFade,
              builder: (context, _) {
                final t = Curves.easeOut.transform(previewFade.value);
                if (t == 0) return const SizedBox.shrink();
                return Opacity(
                  opacity: t,
                  child: _LivePreviewLayer(
                    renderer: call.localRenderer,
                  ),
                );
              },
            ),

          // ── Layer 3: foreground tint so caller text reads ────────
          // Heavier at the top and bottom (where the caller card and
          // action buttons live), lighter in the middle to let the
          // self-preview shine through.
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.55),
                    Colors.black.withValues(alpha: 0.10),
                    Colors.black.withValues(alpha: 0.65),
                  ],
                  stops: const [0.0, 0.45, 1.0],
                ),
              ),
            ),
          ),

          // ── Layer 4: foreground caller card + actions ────────────
          SafeArea(
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
                  const SizedBox(height: 28),
                  // Avatar — shrinks when the live preview is up so
                  // the caller's face stays visible without
                  // dominating the screen. Hidden completely if
                  // permission was denied — the user has already
                  // seen the camera fail; doubling up on the avatar
                  // is unnecessary chrome.
                  if (!_hasLivePreview)
                    _PulseAvatar(
                      name: call.remoteName ?? 'Unknown',
                      ringPulse: ringPulse,
                    )
                  else
                    _CompactCallerChip(
                      name: call.remoteName ?? 'Unknown',
                    ),
                  const SizedBox(height: 20),
                  Text(
                    call.remoteName ?? 'Unknown caller',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                      shadows: [
                        Shadow(
                          color: Colors.black54,
                          offset: Offset(0, 1),
                          blurRadius: 6,
                        ),
                      ],
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
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        call.withVideo
                            ? 'is video calling you'
                            : 'is calling you',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ],
                  ),

                  // Preview status banner — surfaces what's happening
                  // with the warmup attempt (loading shimmer, "camera
                  // blocked" fallback). Only shown for video calls.
                  if (call.withVideo) ...[
                    const SizedBox(height: 14),
                    _PreviewStatusBanner(
                      previewState: call.previewState,
                    ),
                  ],

                  const Spacer(),

                  // Flip-camera affordance — only when the live
                  // preview is actually painting, so users can
                  // double-check their hair / lighting from the
                  // right side of their face before picking up.
                  if (_hasLivePreview) ...[
                    Center(
                      child: _FlipCameraButton(onTap: onFlipCamera),
                    ),
                    const SizedBox(height: 28),
                  ],

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
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────
//  Live preview layer
//  ────────────────────────────────────────────────────────────────────
//  Fullscreen mirrored RTCVideoView that paints the warmed-up local
//  camera stream behind the caller card. `BoxFit.cover` ensures the
//  video fills the screen on any aspect ratio without letterboxing.
// ────────────────────────────────────────────────────────────────────

class _LivePreviewLayer extends StatelessWidget {
  final RTCVideoRenderer? renderer;
  const _LivePreviewLayer({required this.renderer});

  @override
  Widget build(BuildContext context) {
    final r = renderer;
    if (r == null) return const SizedBox.shrink();
    return RTCVideoView(
      r,
      mirror: true,
      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
    );
  }
}

// ────────────────────────────────────────────────────────────────────
//  Preview status banner
//  ────────────────────────────────────────────────────────────────────
//  Tiny pill under the caller name explaining what's happening with
//  the camera warmup — a loading shimmer while `getUserMedia()` is
//  in flight, a "camera blocked" hint if permission was denied.
//  Hidden once the preview is live (the video itself is the signal).
// ────────────────────────────────────────────────────────────────────

class _PreviewStatusBanner extends StatelessWidget {
  final P2PPreviewState previewState;
  const _PreviewStatusBanner({required this.previewState});

  @override
  Widget build(BuildContext context) {
    String label;
    IconData icon;
    Color tint;
    switch (previewState) {
      case P2PPreviewState.warming:
        label = 'Starting camera…';
        icon = Icons.videocam_rounded;
        tint = Colors.white.withValues(alpha: 0.85);
        break;
      case P2PPreviewState.denied:
        label = 'Camera blocked — accept to retry';
        icon = Icons.videocam_off_rounded;
        tint = const Color(0xFFFCA5A5);
        break;
      case P2PPreviewState.ready:
      case P2PPreviewState.idle:
        return const SizedBox.shrink();
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: Container(
        key: ValueKey(previewState),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: tint.withValues(alpha: 0.55)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (previewState == P2PPreviewState.warming)
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.6,
                  valueColor: AlwaysStoppedAnimation(Colors.white),
                ),
              )
            else
              Icon(icon, color: tint, size: 14),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: tint,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────
//  Compact caller chip (used when the live preview is painting)
//  ────────────────────────────────────────────────────────────────────
//  A small avatar circle that sits where the big pulse-avatar
//  normally lives. Keeps the visual identity of the caller present
//  without obscuring the self-preview.
// ────────────────────────────────────────────────────────────────────

class _CompactCallerChip extends StatelessWidget {
  final String name;
  const _CompactCallerChip({required this.name});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 78,
      height: 78,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: MizdahTokens.heroGradient,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.35),
          width: 2,
        ),
      ),
      child: Text(
        _initials(name),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 26,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
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

// ────────────────────────────────────────────────────────────────────
//  Flip-camera button (visible only when the preview is live)
// ────────────────────────────────────────────────────────────────────

class _FlipCameraButton extends StatelessWidget {
  final VoidCallback onTap;
  const _FlipCameraButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return MizdahPressScale(
      scaleTo: 0.92,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.30),
          ),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.flip_camera_ios_rounded,
                color: Colors.white, size: 18),
            SizedBox(width: 6),
            Text(
              'Flip',
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
              ),
            ),
          ],
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
