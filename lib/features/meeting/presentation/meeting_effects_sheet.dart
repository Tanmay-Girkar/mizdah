// ════════════════════════════════════════════════════════════════════
//  MeetingEffectsSheet — in-meeting video tweaks
// ════════════════════════════════════════════════════════════════════
//  Modal bottom sheet opened from the meeting room top bar's
//  auto-awesome icon. Hosts the three preferences from
//  docs/meeting-preferences/02-video.md that should be tweakable
//  *during* a call:
//
//    • Touch up appearance       — slider 0..100 (no-op until the
//                                   camera-feed shader pass lands)
//    • Background blur           — None / Light / Strong (no-op until
//                                   MediaPipe segmentation lands)
//    • Outgoing video quality    — Auto / 720p / 1080p (read by the
//                                   camera pipeline at next renegotiation)
//
//  Touch-up + background also live ONLY here per product call —
//  they don't appear in Settings → Meeting preferences. Outgoing
//  video quality lives in both — same provider, so changing it here
//  also persists for future meetings.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/mizdah_design.dart';
import '../../../core/widgets/mizdah_picker.dart';
import '../../settings/video_preferences_provider.dart';

class MeetingEffectsSheet extends ConsumerWidget {
  const MeetingEffectsSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final touchUp = ref.watch(touchUpIntensityProvider);
    final blur = ref.watch(backgroundBlurProvider);
    final quality = ref.watch(outgoingVideoQualityProvider);

    return Container(
      decoration: BoxDecoration(
        color: MizdahTokens.surface(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: MizdahTokens.border(context),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              RichText(
                text: TextSpan(
                  style: TextStyle(
                    color: MizdahTokens.inkOf(context),
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                    height: 1.1,
                  ),
                  children: [
                    const TextSpan(text: 'Video '),
                    WidgetSpan(
                      alignment: PlaceholderAlignment.baseline,
                      baseline: TextBaseline.alphabetic,
                      child: ShaderMask(
                        shaderCallback: (r) =>
                            MizdahTokens.heroGradient.createShader(r),
                        child: const Text(
                          'effects',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.4,
                            height: 1.1,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Apply during this meeting and remember for next time.',
                style: TextStyle(
                  color: MizdahTokens.mutedOf(context),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 18),

              // ── Touch up appearance ────────────────────────────
              // Continuous slider — different shape from the picker
              // rows below, kept as-is. Wrapped in `_ComingSoonOverlay`
              // because the real-time skin-smoothing shader is still
              // in native R&D (see docs/VIDEO_EFFECTS_BACKEND.md).
              // The slider still works locally so users can preview
              // the affordance; the value never reaches the wire.
              _ComingSoonOverlay(
                child: _TouchUpRow(
                  value: touchUp,
                  onChanged: (v) =>
                      ref.read(touchUpIntensityProvider.notifier).set(v),
                ),
              ),
              const SizedBox(height: 12),

              // ── Background blur + Outgoing quality ─────────────
              // Both are 3-option choices — share a single rounded
              // card with picker rows inside, mirroring the iOS
              // Settings pattern.
              Container(
                decoration: BoxDecoration(
                  color: MizdahTokens.bg(context),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: MizdahTokens.border(context), width: 1),
                ),
                child: Column(
                  children: [
                    // Background blur — segmentation model + custom
                    // VideoCapturer needed; native R&D track.
                    _ComingSoonOverlay(
                      child: MizdahPickerRow<BackgroundBlurLevel>(
                        icon: Icons.blur_on_rounded,
                        label: 'Background blur',
                        sublabel: _blurSubtitle(blur),
                        value: blur,
                        sheetTitle: 'Background blur',
                        sheetSubtitle:
                            'Hide what\'s behind you while you\'re on camera.',
                        options: const [
                          MizdahPickerOption(
                            value: BackgroundBlurLevel.none,
                            label: 'None',
                            description: 'Show the room behind you.',
                          ),
                          MizdahPickerOption(
                            value: BackgroundBlurLevel.light,
                            label: 'Light',
                            description:
                                'Mild blur — subject stays crisp, room becomes soft.',
                          ),
                          MizdahPickerOption(
                            value: BackgroundBlurLevel.strong,
                            label: 'Strong',
                            description:
                                'Heavy blur — background reads as a soft colour wash.',
                          ),
                        ],
                        onChanged: (v) => ref
                            .read(backgroundBlurProvider.notifier)
                            .set(v),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Container(
                        height: 1,
                        color: MizdahTokens.border(context),
                      ),
                    ),
                    MizdahPickerRow<OutgoingVideoQuality>(
                      icon: Icons.high_quality_rounded,
                      label: 'Outgoing video quality',
                      sublabel: quality.description,
                      value: quality,
                      sheetTitle: 'Outgoing video quality',
                      sheetSubtitle:
                          'Cap on the resolution we send to other participants.',
                      options: const [
                        MizdahPickerOption(
                          value: OutgoingVideoQuality.auto,
                          label: 'Auto',
                          description:
                              'Adapts to network conditions. Recommended.',
                        ),
                        MizdahPickerOption(
                          value: OutgoingVideoQuality.hd720,
                          label: '720p',
                          description:
                              'Cap at 1280×720 — gentler on bandwidth.',
                        ),
                        MizdahPickerOption(
                          value: OutgoingVideoQuality.hd1080,
                          label: '1080p',
                          description:
                              'Up to 1920×1080. Uses more data + CPU.',
                        ),
                      ],
                      onChanged: (q) => ref
                          .read(outgoingVideoQualityProvider.notifier)
                          .set(q),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _blurSubtitle(BackgroundBlurLevel l) {
    switch (l) {
      case BackgroundBlurLevel.none:
        return 'Show the room behind you.';
      case BackgroundBlurLevel.light:
        return 'Mild blur — subject stays crisp.';
      case BackgroundBlurLevel.strong:
        return 'Heavy blur — background reads as a soft wash.';
    }
  }
}

// ─────────────────────────────────────────────────────────────────
//  Touch up — slider with current-value pill
// ─────────────────────────────────────────────────────────────────

class _TouchUpRow extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  const _TouchUpRow({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: MizdahTokens.bg(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MizdahTokens.border(context), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: MizdahTokens.iconTileBg(context),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  Icons.face_retouching_natural,
                  color: MizdahTokens.primary,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Touch up appearance',
                      style: TextStyle(
                        color: MizdahTokens.inkOf(context),
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _subtitleFor(value),
                      style: TextStyle(
                        color: MizdahTokens.mutedOf(context),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              // Current-value pill, gradient when above zero so
              // the user has a strong visual cue that it's active.
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(
                    horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  gradient: value > 0 ? MizdahTokens.heroGradient : null,
                  color: value > 0
                      ? null
                      : MizdahTokens.iconTileBg(context),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  value == 0 ? 'Off' : '$value',
                  style: TextStyle(
                    color: value > 0
                        ? Colors.white
                        : MizdahTokens.mutedOf(context),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: MizdahTokens.primary,
              inactiveTrackColor: MizdahTokens.border(context),
              thumbColor: MizdahTokens.primary,
              overlayColor: MizdahTokens.primary.withValues(alpha: 0.16),
              trackHeight: 3,
            ),
            child: Slider(
              value: value.toDouble(),
              min: 0,
              max: 100,
              divisions: 100,
              onChanged: (v) => onChanged(v.round()),
            ),
          ),
        ],
      ),
    );
  }

  String _subtitleFor(int v) {
    if (v == 0) return 'No smoothing applied to your camera.';
    if (v < 31) return 'Light skin smoothing — looks natural.';
    if (v < 71) return 'Stronger smoothing with a brightness lift.';
    return 'Aggressive smoothing — can look painterly.';
  }
}

/// Wraps a row with a small "Coming soon" pill in the top-right
/// corner. Used on Touch up + Background blur until the native
/// segmentation + skin-smoothing plugin lands. The control underneath
/// still receives taps + saves the value so the affordance demos
/// cleanly, but nothing is applied to the outgoing video.
class _ComingSoonOverlay extends StatelessWidget {
  final Widget child;
  const _ComingSoonOverlay({required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          top: 10,
          right: 14,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: MizdahTokens.iconTileBg(context),
              borderRadius: BorderRadius.circular(99),
              border: Border.all(
                color: MizdahTokens.border(context),
                width: 1,
              ),
            ),
            child: Text(
              'Coming soon',
              style: TextStyle(
                color: MizdahTokens.mutedOf(context),
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
