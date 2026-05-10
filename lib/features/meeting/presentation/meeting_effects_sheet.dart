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
              _TouchUpRow(
                value: touchUp,
                onChanged: (v) =>
                    ref.read(touchUpIntensityProvider.notifier).set(v),
              ),
              const SizedBox(height: 14),

              // ── Background blur ────────────────────────────────
              _BackgroundBlurRow(
                level: blur,
                onChanged: (v) =>
                    ref.read(backgroundBlurProvider.notifier).set(v),
              ),
              const SizedBox(height: 14),

              // ── Outgoing video quality ─────────────────────────
              _QualityRow(
                quality: quality,
                onChanged: (q) =>
                    ref.read(outgoingVideoQualityProvider.notifier).set(q),
              ),
            ],
          ),
        ),
      ),
    );
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

// ─────────────────────────────────────────────────────────────────
//  Background blur — 3-segment row
// ─────────────────────────────────────────────────────────────────

class _BackgroundBlurRow extends StatelessWidget {
  final BackgroundBlurLevel level;
  final ValueChanged<BackgroundBlurLevel> onChanged;
  const _BackgroundBlurRow({required this.level, required this.onChanged});

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
                  Icons.blur_on_rounded,
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
                      'Background blur',
                      style: TextStyle(
                        color: MizdahTokens.inkOf(context),
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _subtitleFor(level),
                      style: TextStyle(
                        color: MizdahTokens.mutedOf(context),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _Segmented<BackgroundBlurLevel>(
            values: BackgroundBlurLevel.values,
            active: level,
            labelOf: (v) => v.label,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  String _subtitleFor(BackgroundBlurLevel l) {
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
//  Outgoing video quality — 3-segment row
// ─────────────────────────────────────────────────────────────────

class _QualityRow extends StatelessWidget {
  final OutgoingVideoQuality quality;
  final ValueChanged<OutgoingVideoQuality> onChanged;
  const _QualityRow({required this.quality, required this.onChanged});

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
                  Icons.high_quality_rounded,
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
                      'Outgoing video quality',
                      style: TextStyle(
                        color: MizdahTokens.inkOf(context),
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      quality.description,
                      style: TextStyle(
                        color: MizdahTokens.mutedOf(context),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _Segmented<OutgoingVideoQuality>(
            values: OutgoingVideoQuality.values,
            active: quality,
            labelOf: (v) => v.label,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
//  Generic 3-segment animated pill — reused by blur + quality
// ─────────────────────────────────────────────────────────────────

class _Segmented<T> extends StatelessWidget {
  final List<T> values;
  final T active;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;
  const _Segmented({
    required this.values,
    required this.active,
    required this.labelOf,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final activeIndex = values.indexOf(active);
    return LayoutBuilder(
      builder: (context, constraints) {
        final segWidth = constraints.maxWidth / values.length;
        return Container(
          height: 38,
          decoration: BoxDecoration(
            color: MizdahTokens.iconTileBg(context),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                left: segWidth * activeIndex + 4,
                top: 4,
                bottom: 4,
                width: segWidth - 8,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: MizdahTokens.heroGradient,
                    borderRadius: BorderRadius.circular(9),
                    boxShadow: [
                      BoxShadow(
                        color: MizdahTokens.primary.withValues(alpha: 0.30),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                children: [
                  for (final v in values)
                    Expanded(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(9),
                        onTap: () => onChanged(v),
                        child: Center(
                          child: Text(
                            labelOf(v),
                            style: TextStyle(
                              color: v == active
                                  ? Colors.white
                                  : MizdahTokens.mutedOf(context),
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.1,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
