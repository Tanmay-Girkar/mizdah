// ════════════════════════════════════════════════════════════════════
//  MizdahPicker — premium "tap to choose" row + bottom-sheet picker
// ════════════════════════════════════════════════════════════════════
//  Replaces the dense segmented-pill pattern with the iOS Settings /
//  WhatsApp / Notion convention:
//
//    1. The row shows: icon tile · title · subtitle · current-value
//       pill · chevron. Tapping anywhere opens the picker sheet.
//
//    2. The sheet has: drag handle · gradient-accent title · optional
//       subtitle · a list of options. Each option carries a label
//       AND a description so the user knows the consequence of each
//       choice — something the segmented pill couldn't fit.
//
//  Generic over the value type so the same picker drives noise-
//  suppression levels, video-quality presets, blur intensity, etc.

import 'package:flutter/material.dart';

import '../ui/mizdah_design.dart';

/// One option inside a [MizdahPickerSheet].
class MizdahPickerOption<T> {
  final T value;
  final String label;
  final String? description;
  const MizdahPickerOption({
    required this.value,
    required this.label,
    this.description,
  });
}

/// Tappable row that displays the current value + a chevron. Tap
/// opens a [MizdahPickerSheet] for the same options.
class MizdahPickerRow<T> extends StatelessWidget {
  /// Icon shown in the leading tile.
  final IconData icon;

  /// Big bold row title (e.g. "Noise suppression").
  final String label;

  /// Smaller helper text under the title. Usually a short
  /// description of what the *current* selection does — kept in
  /// sync by the parent.
  final String sublabel;

  /// Current value. Must equal one of `options[i].value`.
  final T value;

  /// Options shown in the sheet.
  final List<MizdahPickerOption<T>> options;

  /// Fires when the user picks a new option.
  final ValueChanged<T> onChanged;

  /// Title shown at the top of the sheet. Defaults to [label] if
  /// omitted.
  final String? sheetTitle;

  /// Optional one-liner under the sheet title — frames the choice
  /// for the user.
  final String? sheetSubtitle;

  const MizdahPickerRow({
    super.key,
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.value,
    required this.options,
    required this.onChanged,
    this.sheetTitle,
    this.sheetSubtitle,
  });

  String _labelOf(T v) {
    return options
        .firstWhere(
          (o) => o.value == v,
          orElse: () => MizdahPickerOption(value: v, label: '?'),
        )
        .label;
  }

  Future<void> _open(BuildContext context) async {
    final picked = await showModalBottomSheet<T>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (_) => MizdahPickerSheet<T>(
        title: sheetTitle ?? label,
        subtitle: sheetSubtitle,
        value: value,
        options: options,
      ),
    );
    if (picked != null && picked != value) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _open(context),
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
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
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
            const SizedBox(width: 8),
            // Current-value pill — gradient so it reads as the
            // active selection without needing extra text.
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                gradient: MizdahTokens.heroGradient,
                borderRadius: BorderRadius.circular(99),
                boxShadow: [
                  BoxShadow(
                    color: MizdahTokens.primary.withValues(alpha: 0.30),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Text(
                _labelOf(value),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.chevron_right_rounded,
              color: MizdahTokens.mutedOf(context),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom-sheet picker — list of options with radio-style markers.
/// Pops with the chosen value.
class MizdahPickerSheet<T> extends StatelessWidget {
  final String title;
  final String? subtitle;
  final T value;
  final List<MizdahPickerOption<T>> options;
  const MizdahPickerSheet({
    super.key,
    required this.title,
    required this.value,
    required this.options,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: MizdahTokens.surface(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
              Text(
                title,
                style: TextStyle(
                  color: MizdahTokens.inkOf(context),
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  style: TextStyle(
                    color: MizdahTokens.mutedOf(context),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    height: 1.4,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              for (var i = 0; i < options.length; i++) ...[
                _OptionTile<T>(
                  option: options[i],
                  selected: options[i].value == value,
                ),
                if (i < options.length - 1) const SizedBox(height: 6),
              ],
              const SizedBox(height: 6),
            ],
          ),
        ),
      ),
    );
  }
}

class _OptionTile<T> extends StatelessWidget {
  final MizdahPickerOption<T> option;
  final bool selected;
  const _OptionTile({required this.option, required this.selected});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => Navigator.of(context).pop(option.value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: selected
              ? MizdahTokens.primary.withValues(alpha: 0.08)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? MizdahTokens.primary.withValues(alpha: 0.30)
                : MizdahTokens.border(context),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            // Radio indicator — gradient-filled circle when active,
            // hollow stroke when inactive.
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                gradient: selected ? MizdahTokens.heroGradient : null,
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected
                      ? Colors.transparent
                      : MizdahTokens.border(context),
                  width: 1.6,
                ),
              ),
              child: selected
                  ? const Icon(Icons.check_rounded,
                      color: Colors.white, size: 14)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    option.label,
                    style: TextStyle(
                      color: MizdahTokens.inkOf(context),
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.1,
                    ),
                  ),
                  if (option.description != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      option.description!,
                      style: TextStyle(
                        color: MizdahTokens.mutedOf(context),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
