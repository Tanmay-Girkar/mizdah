// ════════════════════════════════════════════════════════════════════
//  Meeting preferences — user-wide defaults
//  ────────────────────────────────────────────────────────────────────
//  Reachable from Settings → Account → Meeting preferences. Holds the
//  user's defaults that apply to every meeting they join:
//
//    Layout:
//      • Default video grid layout (Auto / Tiled / Spotlight / Sidebar)
//      • Maximum number of tiles before grid overflows
//      • Whether to hide tiles whose camera is off
//
//    Audio (per docs/meeting-preferences/01-audio.md):
//      • Mute on join — bool toggle
//      • Noise suppression — Off / Standard / High segmented
//
//  All preferences are backed by SharedPreferences notifiers — pure
//  client-side, no backend round-trips. The audio prefs are read by
//  the meeting room when the mic is initialised so they apply to
//  every meeting going forward.
// ════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ui/mizdah_design.dart';
import '../../../core/widgets/mizdah_picker.dart';
import '../audio_preferences_provider.dart';
import '../meeting_layout_provider.dart';
import '../privacy_preferences_provider.dart';
import '../video_preferences_provider.dart';

class MeetingPreferencesScreen extends ConsumerStatefulWidget {
  const MeetingPreferencesScreen({super.key});

  @override
  ConsumerState<MeetingPreferencesScreen> createState() =>
      _MeetingPreferencesScreenState();
}

class _MeetingPreferencesScreenState
    extends ConsumerState<MeetingPreferencesScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entryCtrl;

  @override
  void initState() {
    super.initState();
    _entryCtrl = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    )..forward();
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final layout = ref.watch(meetingLayoutProvider);
    final maxTiles = ref.watch(maxTilesProvider);
    final hideNoVideo = ref.watch(hideTilesWithoutVideoProvider);
    final muteOnJoin = ref.watch(muteOnJoinProvider);
    final noiseLevel = ref.watch(noiseSuppressionProvider);
    final videoQuality = ref.watch(outgoingVideoQualityProvider);
    final confirmBeforeLeaving = ref.watch(confirmBeforeLeavingProvider);
    // Subtitle helper for the noise-suppression row — describes
    // what the *current* selection does so the row reads complete
    // without opening the picker.
    String noiseSubtitle(NoiseSuppressionLevel l) {
      switch (l) {
        case NoiseSuppressionLevel.off:
          return 'Raw mic — only echo cancellation applied.';
        case NoiseSuppressionLevel.standard:
          return 'Mild filter; voice stays natural.';
        case NoiseSuppressionLevel.high:
          return 'Aggressive — even chewing and traffic silenced.';
      }
    }

    return Scaffold(
      backgroundColor: MizdahTokens.bg(context),
      body: Stack(
        children: [
          // Same gradient backdrop as the rest of the tabs.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: MizdahTokens.pageGradient(context),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                // ── Top bar with back button ─────────────────────
                MizdahFadeUp(
                  controller: _entryCtrl,
                  delay: 0.0,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Row(
                      children: [
                        _CircleIconButton(
                          icon: Icons.arrow_back_rounded,
                          onTap: () => context.pop(),
                        ),
                        const Spacer(),
                      ],
                    ),
                  ),
                ),
                // ── Title + subtitle ─────────────────────────────
                MizdahFadeUp(
                  controller: _entryCtrl,
                  delay: 0.05,
                  child: const MizdahPageHeader(
                    leading: 'Meeting',
                    accent: 'preferences',
                    subtitle: 'Defaults applied every time you join',
                  ),
                ),
                const SizedBox(height: 14),
                // ── Scrollable content ───────────────────────────
                Expanded(
                  child: ListView(
                    physics: const ClampingScrollPhysics(
                      parent: AlwaysScrollableScrollPhysics(),
                    ),
                    padding: const EdgeInsets.only(bottom: 24),
                    children: [
                      // Layout picker
                      MizdahFadeUp(
                        controller: _entryCtrl,
                        delay: 0.12,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _SectionLabel(label: 'Default video layout'),
                              const SizedBox(height: 8),
                              MizdahCard(
                                padding: EdgeInsets.zero,
                                child: Column(
                                  children: [
                                    for (final entry
                                        in MeetingLayout.values
                                            // Don't surface the legacy
                                            // PremiumCards layout — kept
                                            // for back-compat only.
                                            .where((e) =>
                                                e != MeetingLayout.premiumCards)
                                            .toList()
                                            .asMap()
                                            .entries) ...[
                                      _LayoutRow(
                                        layout: entry.value,
                                        active: layout == entry.value,
                                        onTap: () => ref
                                            .read(meetingLayoutProvider
                                                .notifier)
                                            .set(entry.value),
                                      ),
                                      if (entry.key < 3)
                                        _RowDivider(),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),

                      // Max tiles slider
                      MizdahFadeUp(
                        controller: _entryCtrl,
                        delay: 0.18,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _SectionLabel(label: 'Maximum tiles'),
                              const SizedBox(height: 8),
                              _MaxTilesCard(
                                value: maxTiles,
                                onChanged: (v) => ref
                                    .read(maxTilesProvider.notifier)
                                    .set(v),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),

                      // Hide tiles without video toggle
                      MizdahFadeUp(
                        controller: _entryCtrl,
                        delay: 0.24,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _SectionLabel(label: 'Tile visibility'),
                              const SizedBox(height: 8),
                              MizdahCard(
                                padding: EdgeInsets.zero,
                                child: _SwitchRow(
                                  icon: Icons.videocam_off_rounded,
                                  label: 'Hide cameras-off tiles',
                                  sublabel:
                                      'Collapse participants without video into a single chip.',
                                  value: hideNoVideo,
                                  onChanged: (v) => ref
                                      .read(hideTilesWithoutVideoProvider
                                          .notifier)
                                      .set(v),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),

                      // ── Audio section ─────────────────────────
                      // Mute on join + Noise suppression. Local
                      // preferences only — no backend round-trips.
                      MizdahFadeUp(
                        controller: _entryCtrl,
                        delay: 0.30,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _SectionLabel(label: 'Audio'),
                              const SizedBox(height: 8),
                              MizdahCard(
                                padding: EdgeInsets.zero,
                                child: Column(
                                  children: [
                                    _SwitchRow(
                                      icon: Icons.mic_off_rounded,
                                      label: 'Mute on join',
                                      sublabel:
                                          'Start every meeting with your microphone off.',
                                      value: muteOnJoin,
                                      onChanged: (v) => ref
                                          .read(muteOnJoinProvider.notifier)
                                          .set(v),
                                    ),
                                    _RowDivider(),
                                    MizdahPickerRow<NoiseSuppressionLevel>(
                                      icon: Icons.graphic_eq_rounded,
                                      label: 'Noise suppression',
                                      sublabel:
                                          noiseSubtitle(noiseLevel),
                                      value: noiseLevel,
                                      sheetTitle: 'Noise suppression',
                                      sheetSubtitle:
                                          'How aggressively to filter the mic feed.',
                                      options: const [
                                        MizdahPickerOption(
                                          value: NoiseSuppressionLevel.off,
                                          label: 'Off',
                                          description:
                                              'Raw mic — only echo cancellation applied.',
                                        ),
                                        MizdahPickerOption(
                                          value: NoiseSuppressionLevel
                                              .standard,
                                          label: 'Standard',
                                          description:
                                              'Mild filter; voice stays natural.',
                                        ),
                                        MizdahPickerOption(
                                          value: NoiseSuppressionLevel.high,
                                          label: 'High',
                                          description:
                                              'Aggressive — even chewing and traffic silenced.',
                                        ),
                                      ],
                                      onChanged: (v) => ref
                                          .read(noiseSuppressionProvider
                                              .notifier)
                                          .set(v),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),

                      // ── Video section ─────────────────────────
                      // Outgoing video quality only — touch up +
                      // background blur live in the in-meeting
                      // effects sheet, not here.
                      MizdahFadeUp(
                        controller: _entryCtrl,
                        delay: 0.36,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _SectionLabel(label: 'Video'),
                              const SizedBox(height: 8),
                              MizdahCard(
                                padding: EdgeInsets.zero,
                                child:
                                    MizdahPickerRow<OutgoingVideoQuality>(
                                  icon: Icons.high_quality_rounded,
                                  label: 'Outgoing video quality',
                                  sublabel: videoQuality.description,
                                  value: videoQuality,
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
                                      .read(outgoingVideoQualityProvider
                                          .notifier)
                                      .set(q),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),

                      // ── Privacy & security section ────────────
                      MizdahFadeUp(
                        controller: _entryCtrl,
                        delay: 0.42,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _SectionLabel(label: 'Privacy & security'),
                              const SizedBox(height: 8),
                              MizdahCard(
                                padding: EdgeInsets.zero,
                                child: _SwitchRow(
                                  icon: Icons.exit_to_app_rounded,
                                  label: 'Confirm before leaving',
                                  sublabel:
                                      'Ask for confirmation when you tap end-call.',
                                  value: confirmBeforeLeaving,
                                  onChanged: (v) => ref
                                      .read(confirmBeforeLeavingProvider
                                          .notifier)
                                      .set(v),
                                ),
                              ),
                            ],
                          ),
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
    );
  }
}

// ────────────────────────────────────────────────────────────────────
//  Pieces
// ────────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        label,
        style: TextStyle(
          color: MizdahTokens.inkOf(context),
          fontSize: 14,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.2,
        ),
      ),
    );
  }
}

class _LayoutRow extends StatelessWidget {
  final MeetingLayout layout;
  final bool active;
  final VoidCallback onTap;
  const _LayoutRow({
    required this.layout,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: active ? MizdahTokens.heroGradient : null,
                color: active ? null : MizdahTokens.iconTileBg(context),
                borderRadius: BorderRadius.circular(11),
                boxShadow: active
                    ? [
                        BoxShadow(
                          color: MizdahTokens.primary.withValues(alpha: 0.30),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              child: Icon(
                layout.icon,
                size: 18,
                color: active ? Colors.white : MizdahTokens.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    layout.label,
                    style: TextStyle(
                      color: MizdahTokens.inkOf(context),
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    layout.description,
                    style: TextStyle(
                      color: MizdahTokens.mutedOf(context),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            // Trailing check mark when active.
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: active ? MizdahTokens.heroGradient : null,
                color: active ? null : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(
                  color: active
                      ? Colors.transparent
                      : MizdahTokens.border(context),
                  width: 1.5,
                ),
              ),
              child: active
                  ? const Icon(Icons.check_rounded,
                      color: Colors.white, size: 14)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _MaxTilesCard extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  const _MaxTilesCard({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return MizdahCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
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
                  Icons.grid_view_rounded,
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
                      'Up to $value participants',
                      style: TextStyle(
                        color: MizdahTokens.inkOf(context),
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Beyond this, the rest stack as a “+N” chip.',
                      style: TextStyle(
                        color: MizdahTokens.mutedOf(context),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
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
              min: 4,
              max: 49,
              divisions: 45,
              onChanged: (v) => onChanged(v.round()),
            ),
          ),
        ],
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sublabel;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _SwitchRow({
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: MizdahTokens.iconTileBg(context),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, color: MizdahTokens.primary, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: MizdahTokens.inkOf(context),
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sublabel,
                    style: TextStyle(
                      color: MizdahTokens.mutedOf(context),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Switch.adaptive(
              value: value,
              onChanged: onChanged,
              activeTrackColor: MizdahTokens.primary,
            ),
          ],
        ),
      ),
    );
  }
}


class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CircleIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return MizdahPressScale(
      scaleTo: 0.92,
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: MizdahTokens.surface(context),
          shape: BoxShape.circle,
          border: Border.all(color: MizdahTokens.border(context)),
          boxShadow: MizdahTokens.shadow(context, elevation: 0.5),
        ),
        child: Icon(icon, color: MizdahTokens.inkOf(context), size: 20),
      ),
    );
  }
}

class _RowDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Container(height: 1, color: MizdahTokens.border(context)),
    );
  }
}
