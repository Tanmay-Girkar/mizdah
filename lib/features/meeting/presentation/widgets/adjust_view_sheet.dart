import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../settings/meeting_layout_provider.dart';

/// Google-Meet-style "Adjust view" bottom sheet:
///   - 4 layout options with radio + label + preview thumbnail
///   - Tiles slider (max tiles, 4 → 49)
///   - Hide tiles without video toggle
///
/// All selections persist via the providers in
/// `meeting_layout_provider.dart` so the choice carries to every
/// future meeting too.
class AdjustViewSheet extends ConsumerWidget {
  const AdjustViewSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const AdjustViewSheet(),
    );
  }

  /// Layouts surfaced in the sheet (in display order). We omit
  /// `premiumCards` from the user-facing list — it's still in the
  /// enum for back-compat with the settings screen.
  static const _layouts = [
    MeetingLayout.auto,
    MeetingLayout.equalGrid,
    MeetingLayout.spotlight,
    MeetingLayout.speakerSidebar,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final current = ref.watch(meetingLayoutProvider);
    final maxTiles = ref.watch(maxTilesProvider);
    final hideNoVideo = ref.watch(hideTilesWithoutVideoProvider);
    final bg = isDark ? const Color(0xFF1A1F26) : Colors.white;
    final fg = isDark ? Colors.white : Colors.black87;
    final muted = isDark ? Colors.white60 : Colors.black54;

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Adjust view',
                        style: TextStyle(
                          color: fg,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close_rounded, color: muted),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Selection is saved for future meetings',
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                ),
              ),

              // Layout rows
              for (final l in _layouts)
                _LayoutRow(
                  layout: l,
                  selected: current == l,
                  onTap: () =>
                      ref.read(meetingLayoutProvider.notifier).set(l),
                  isDark: isDark,
                ),

              const SizedBox(height: 8),
              Divider(
                height: 1,
                color: isDark ? Colors.white10 : Colors.black12,
              ),

              // Tiles section
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Tiles',
                    style: TextStyle(
                      color: fg,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Maximum tiles to display, depending on window size.',
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.06)
                            : Colors.black.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.grid_on_rounded,
                          color: muted, size: 18),
                    ),
                    Expanded(
                      child: Slider(
                        value: maxTiles.toDouble(),
                        min: 4,
                        max: 49,
                        divisions: 45,
                        label: '$maxTiles',
                        onChanged: (v) => ref
                            .read(maxTilesProvider.notifier)
                            .set(v.round()),
                        activeColor: const Color(0xFF1A73E8),
                      ),
                    ),
                    Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.06)
                            : Colors.black.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.grid_view_rounded,
                          color: muted, size: 18),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 8),
              Divider(
                height: 1,
                color: isDark ? Colors.white10 : Colors.black12,
              ),

              // Hide tiles without video toggle
              SwitchListTile.adaptive(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                title: Text(
                  'Hide tiles without video',
                  style: TextStyle(color: fg, fontSize: 14),
                ),
                value: hideNoVideo,
                activeThumbColor: const Color(0xFF1A73E8),
                onChanged: (v) => ref
                    .read(hideTilesWithoutVideoProvider.notifier)
                    .set(v),
              ),

              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _LayoutRow extends StatelessWidget {
  final MeetingLayout layout;
  final bool selected;
  final bool isDark;
  final VoidCallback onTap;
  const _LayoutRow({
    required this.layout,
    required this.selected,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = const Color(0xFF1A73E8);
    final fg = isDark ? Colors.white : Colors.black87;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        child: Row(
          children: [
            // Radio dot
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? accent : (isDark ? Colors.white38 : Colors.black38),
                  width: 2,
                ),
              ),
              child: selected
                  ? Container(
                      width: 12,
                      height: 12,
                      decoration: const BoxDecoration(
                        color: Color(0xFF1A73E8),
                        shape: BoxShape.circle,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                layout.label,
                style: TextStyle(
                  color: selected ? accent : fg,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            // Preview thumbnail (visual hint of the layout shape)
            _LayoutThumbnail(layout: layout, isDark: isDark),
          ],
        ),
      ),
    );
  }
}

/// Tiny SVG-like grid sketch indicating the layout shape, matching
/// the squares/cells in the user-supplied screenshot.
class _LayoutThumbnail extends StatelessWidget {
  final MeetingLayout layout;
  final bool isDark;
  const _LayoutThumbnail({required this.layout, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final cellColor =
        isDark ? Colors.white.withValues(alpha: 0.18) : const Color(0xFFD1D5DB);
    final borderColor =
        isDark ? Colors.white.withValues(alpha: 0.10) : const Color(0xFFE5E7EB);

    return Container(
      width: 56,
      height: 36,
      decoration: BoxDecoration(
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(4),
      ),
      padding: const EdgeInsets.all(3),
      child: _buildShape(cellColor),
    );
  }

  Widget _buildShape(Color cellColor) {
    Widget cell({double w = 8, double h = 8}) => Container(
          width: w,
          height: h,
          margin: const EdgeInsets.all(1),
          decoration: BoxDecoration(
            color: cellColor,
            borderRadius: BorderRadius.circular(1.5),
          ),
        );

    switch (layout) {
      case MeetingLayout.auto:
        // 3 narrow vertical strips
        return Row(
          children: List.generate(
              3, (_) => Expanded(child: Container(margin: const EdgeInsets.all(1), color: cellColor))),
        );
      case MeetingLayout.equalGrid:
        // 3x2 grid of small cells
        return Column(
          children: List.generate(
            2,
            (_) => Expanded(
              child: Row(
                children: List.generate(
                  3,
                  (_) => Expanded(
                      child: Container(margin: const EdgeInsets.all(1), color: cellColor)),
                ),
              ),
            ),
          ),
        );
      case MeetingLayout.spotlight:
        // One big rectangle
        return Container(color: cellColor);
      case MeetingLayout.speakerSidebar:
        // Big left + 2 stacked thumbs on the right
        return Row(
          children: [
            Expanded(
              flex: 3,
              child: Container(margin: const EdgeInsets.all(1), color: cellColor),
            ),
            Expanded(
              flex: 1,
              child: Column(
                children: [
                  Expanded(child: cell()),
                  Expanded(child: cell()),
                ],
              ),
            ),
          ],
        );
      case MeetingLayout.premiumCards:
        return Container(color: cellColor);
    }
  }
}
