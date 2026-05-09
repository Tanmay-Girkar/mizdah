// ════════════════════════════════════════════════════════════════════
//  Report a problem — app + meeting issue reporter
//  ────────────────────────────────────────────────────────────────────
//  Reachable from Settings → Privacy & Security → Report a problem.
//  Replaces the old "Report abuse" people-reporting flow with a
//  proper bug / issue report tailored to a video-conferencing app:
//
//    • Pick a category that matches the issue
//      (audio / video / connection / join / screen-share / etc.)
//    • Severity — Low / Medium / High segmented control
//    • Description (required)
//    • Steps to reproduce (optional)
//    • "Include diagnostic info" toggle — appends app version,
//      device, OS, and the last-meeting code so support has
//      enough context to investigate without a back-and-forth.
//
//  Submission still routes through `SettingsRepository.sendFeedback`
//  (category = "App issue: <picked category>"); the existing backend
//  endpoint already accepts the payload — only the categories and
//  copy changed.
// ════════════════════════════════════════════════════════════════════

import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ui/mizdah_design.dart';
import '../../../data/repositories/settings_repository.dart';
import '../../auth/auth_provider.dart';

class ReportScreen extends ConsumerStatefulWidget {
  const ReportScreen({super.key});

  @override
  ConsumerState<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends ConsumerState<ReportScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entryCtrl;

  _IssueCategory? _category;
  _Severity _severity = _Severity.medium;
  bool _includeDiagnostics = true;
  bool _submitting = false;

  final _descCtrl = TextEditingController();
  final _stepsCtrl = TextEditingController();

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
    _descCtrl.dispose();
    _stepsCtrl.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      !_submitting &&
      _category != null &&
      _descCtrl.text.trim().length >= 8;

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() => _submitting = true);

    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(settingsRepositoryProvider);
    final user = ref.read(authProvider).user;

    final body = StringBuffer()
      ..writeln('Category: ${_category!.label}')
      ..writeln('Severity: ${_severity.label}')
      ..writeln()
      ..writeln('What happened:')
      ..writeln(_descCtrl.text.trim());

    if (_stepsCtrl.text.trim().isNotEmpty) {
      body
        ..writeln()
        ..writeln('Steps to reproduce:')
        ..writeln(_stepsCtrl.text.trim());
    }

    if (_includeDiagnostics) {
      body
        ..writeln()
        ..writeln('— Diagnostics —')
        ..writeln('App: Mizdah 1.0 (Build 2026.05)')
        ..writeln('Platform: ${_platformLabel()}')
        ..writeln('User: ${user?.id ?? 'anonymous'}');
    }

    try {
      await repo.sendFeedback(
        category: 'App issue: ${_category!.label}',
        description: body.toString(),
        userEmail: user?.email ?? 'anonymous',
      );
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: MizdahTokens.surface(context),
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded,
                  color: Color(0xFF10B981), size: 18),
              const SizedBox(width: 8),
              Text(
                'Report sent — thanks for the heads-up',
                style: TextStyle(
                  color: MizdahTokens.inkOf(context),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
      context.pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      messenger.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFFB42318),
          content: Text(
            'Could not send report: $e',
            style: const TextStyle(color: Colors.white),
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  String _platformLabel() {
    try {
      if (Platform.isAndroid) return 'Android';
      if (Platform.isIOS) return 'iOS';
      if (Platform.isMacOS) return 'macOS';
      if (Platform.isWindows) return 'Windows';
      if (Platform.isLinux) return 'Linux';
    } catch (_) {}
    return 'Unknown';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MizdahTokens.bg(context),
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
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
                Padding(
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
                MizdahFadeUp(
                  controller: _entryCtrl,
                  delay: 0.05,
                  child: const MizdahPageHeader(
                    leading: 'Report a',
                    accent: 'problem',
                    subtitle: 'Tell us what went wrong — we read every report',
                  ),
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: ListView(
                    physics: const ClampingScrollPhysics(
                      parent: AlwaysScrollableScrollPhysics(),
                    ),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.only(bottom: 36),
                    children: [
                      MizdahFadeUp(
                        controller: _entryCtrl,
                        delay: 0.10,
                        child: _CategorySection(
                          selected: _category,
                          onChanged: (c) => setState(() => _category = c),
                        ),
                      ),
                      const SizedBox(height: 22),
                      MizdahFadeUp(
                        controller: _entryCtrl,
                        delay: 0.16,
                        child: _SeveritySection(
                          severity: _severity,
                          onChanged: (s) =>
                              setState(() => _severity = s),
                        ),
                      ),
                      const SizedBox(height: 22),
                      MizdahFadeUp(
                        controller: _entryCtrl,
                        delay: 0.22,
                        child: _DescriptionSection(
                          descCtrl: _descCtrl,
                          stepsCtrl: _stepsCtrl,
                          onChanged: () => setState(() {}),
                        ),
                      ),
                      const SizedBox(height: 22),
                      MizdahFadeUp(
                        controller: _entryCtrl,
                        delay: 0.28,
                        child: _DiagnosticsSection(
                          enabled: _includeDiagnostics,
                          onChanged: (v) =>
                              setState(() => _includeDiagnostics = v),
                        ),
                      ),
                      const SizedBox(height: 28),
                      MizdahFadeUp(
                        controller: _entryCtrl,
                        delay: 0.34,
                        child: Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 18),
                          child: _SubmitButton(
                            enabled: _canSubmit,
                            busy: _submitting,
                            onTap: _submit,
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

// ════════════════════════════════════════════════════════════════════
//  Categories
// ════════════════════════════════════════════════════════════════════

enum _IssueCategory {
  audio,
  video,
  connection,
  joinLeave,
  screenShare,
  chat,
  notifications,
  recording,
  crash,
  uiGlitch,
  performance,
  other,
}

extension _IssueCategoryMeta on _IssueCategory {
  String get label => switch (this) {
        _IssueCategory.audio => 'Audio issue',
        _IssueCategory.video => 'Video / camera issue',
        _IssueCategory.connection => 'Connection / network',
        _IssueCategory.joinLeave => 'Joining or leaving',
        _IssueCategory.screenShare => 'Screen sharing',
        _IssueCategory.chat => 'Chat / messages',
        _IssueCategory.notifications => 'Notifications',
        _IssueCategory.recording => 'Recording',
        _IssueCategory.crash => 'App crash or freeze',
        _IssueCategory.uiGlitch => 'UI / visual glitch',
        _IssueCategory.performance => 'Performance / battery',
        _IssueCategory.other => 'Other',
      };

  IconData get icon => switch (this) {
        _IssueCategory.audio => Icons.mic_rounded,
        _IssueCategory.video => Icons.videocam_rounded,
        _IssueCategory.connection => Icons.signal_wifi_bad_rounded,
        _IssueCategory.joinLeave => Icons.meeting_room_rounded,
        _IssueCategory.screenShare => Icons.screen_share_rounded,
        _IssueCategory.chat => Icons.chat_bubble_rounded,
        _IssueCategory.notifications => Icons.notifications_active_rounded,
        _IssueCategory.recording => Icons.fiber_manual_record_rounded,
        _IssueCategory.crash => Icons.error_outline_rounded,
        _IssueCategory.uiGlitch => Icons.broken_image_rounded,
        _IssueCategory.performance => Icons.speed_rounded,
        _IssueCategory.other => Icons.help_outline_rounded,
      };
}

// ════════════════════════════════════════════════════════════════════
//  Sections
// ════════════════════════════════════════════════════════════════════

class _CategorySection extends StatelessWidget {
  final _IssueCategory? selected;
  final ValueChanged<_IssueCategory> onChanged;
  const _CategorySection({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel('What happened?'),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Text(
              'Pick the category that fits best.',
              style: TextStyle(
                color: MizdahTokens.mutedOf(context),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          // 2-column grid of category chips. Wrap+Flex over GridView
          // because category labels vary in length and we don't want
          // a fixed-height row.
          LayoutBuilder(
            builder: (ctx, c) {
              final chipW = (c.maxWidth - 12) / 2;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final cat in _IssueCategory.values)
                    SizedBox(
                      width: chipW,
                      child: _CategoryChip(
                        category: cat,
                        active: cat == selected,
                        onTap: () => onChanged(cat),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final _IssueCategory category;
  final bool active;
  final VoidCallback onTap;
  const _CategoryChip({
    required this.category,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MizdahPressScale(
      scaleTo: 0.96,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        decoration: BoxDecoration(
          color: active ? null : MizdahTokens.surface(context),
          gradient: active
              ? const LinearGradient(
                  colors: [Color(0xFFEDE9FE), Color(0xFFF5F3FF)],
                )
              : null,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: active
                ? MizdahTokens.primary.withValues(alpha: 0.40)
                : MizdahTokens.border(context),
            width: active ? 1.4 : 1,
          ),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: MizdahTokens.primary.withValues(alpha: 0.12),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ]
              : MizdahTokens.shadow(context, elevation: 0.4),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: active ? MizdahTokens.heroGradient : null,
                color: active ? null : MizdahTokens.iconTileBg(context),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(
                category.icon,
                color: active ? Colors.white : MizdahTokens.primary,
                size: 16,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              category.label,
              style: TextStyle(
                color: MizdahTokens.inkOf(context),
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────

enum _Severity { low, medium, high }

extension _SeverityMeta on _Severity {
  String get label => switch (this) {
        _Severity.low => 'Low',
        _Severity.medium => 'Medium',
        _Severity.high => 'High',
      };
  Color get accent => switch (this) {
        _Severity.low => const Color(0xFF10B981),
        _Severity.medium => const Color(0xFFF59E0B),
        _Severity.high => const Color(0xFFEF4444),
      };
}

class _SeveritySection extends StatelessWidget {
  final _Severity severity;
  final ValueChanged<_Severity> onChanged;
  const _SeveritySection({
    required this.severity,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel('How bad is it?'),
          const SizedBox(height: 8),
          MizdahCard(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                for (final s in _Severity.values) ...[
                  Expanded(
                    child: _SeverityChip(
                      severity: s,
                      active: severity == s,
                      onTap: () => onChanged(s),
                    ),
                  ),
                  if (s != _Severity.values.last)
                    const SizedBox(width: 8),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SeverityChip extends StatelessWidget {
  final _Severity severity;
  final bool active;
  final VoidCallback onTap;
  const _SeverityChip({
    required this.severity,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MizdahPressScale(
      scaleTo: 0.94,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active
              ? severity.accent.withValues(alpha: 0.14)
              : MizdahTokens.softPillBg(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active
                ? severity.accent.withValues(alpha: 0.55)
                : Colors.transparent,
            width: 1.4,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: severity.accent,
                shape: BoxShape.circle,
                boxShadow: active
                    ? [
                        BoxShadow(
                          color: severity.accent.withValues(alpha: 0.6),
                          blurRadius: 6,
                        ),
                      ]
                    : null,
              ),
            ),
            const SizedBox(width: 7),
            Text(
              severity.label,
              style: TextStyle(
                color: active
                    ? severity.accent
                    : MizdahTokens.mutedOf(context),
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────

class _DescriptionSection extends StatelessWidget {
  final TextEditingController descCtrl;
  final TextEditingController stepsCtrl;
  final VoidCallback onChanged;
  const _DescriptionSection({
    required this.descCtrl,
    required this.stepsCtrl,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel('Tell us more'),
          const SizedBox(height: 8),
          MizdahCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _TextArea(
                  controller: descCtrl,
                  label: 'What happened? *',
                  hint:
                      'A clear sentence or two — what you tried, what went wrong.',
                  minLines: 3,
                  maxLines: 6,
                  maxLength: 600,
                  onChanged: onChanged,
                ),
                _RowDivider(),
                _TextArea(
                  controller: stepsCtrl,
                  label: 'Steps to reproduce (optional)',
                  hint: '1) Tap Call → 2) Search alex → 3) …',
                  minLines: 2,
                  maxLines: 5,
                  maxLength: 400,
                  onChanged: onChanged,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TextArea extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final int minLines;
  final int maxLines;
  final int maxLength;
  final VoidCallback onChanged;
  const _TextArea({
    required this.controller,
    required this.label,
    required this.hint,
    required this.minLines,
    required this.maxLines,
    required this.maxLength,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: MizdahTokens.mutedOf(context),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: controller,
            onChanged: (_) => onChanged(),
            minLines: minLines,
            maxLines: maxLines,
            maxLength: maxLength,
            style: TextStyle(
              color: MizdahTokens.inkOf(context),
              fontSize: 14,
              fontWeight: FontWeight.w500,
              height: 1.4,
            ),
            decoration: InputDecoration(
              isCollapsed: true,
              border: InputBorder.none,
              counterStyle: TextStyle(
                color: MizdahTokens.mutedOf(context),
                fontSize: 10,
              ),
              hintText: hint,
              hintStyle: TextStyle(
                color: MizdahTokens.mutedOf(context),
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────

class _DiagnosticsSection extends StatelessWidget {
  final bool enabled;
  final ValueChanged<bool> onChanged;
  const _DiagnosticsSection({
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: MizdahCard(
        padding: EdgeInsets.zero,
        child: InkWell(
          onTap: () => onChanged(!enabled),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                  child: Icon(Icons.bug_report_rounded,
                      color: MizdahTokens.primary, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Include diagnostic info',
                        style: TextStyle(
                          color: MizdahTokens.inkOf(context),
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Attaches app version, platform, and your account ID — speeds up the fix.',
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
                  value: enabled,
                  onChanged: onChanged,
                  activeTrackColor: MizdahTokens.primary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────

class _SubmitButton extends StatelessWidget {
  final bool enabled;
  final bool busy;
  final VoidCallback onTap;
  const _SubmitButton({
    required this.enabled,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MizdahPressScale(
      scaleTo: 0.97,
      onTap: enabled ? onTap : () {},
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: Container(
          height: 54,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: MizdahTokens.heroGradient,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: MizdahTokens.primary.withValues(alpha: 0.35),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: busy
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    valueColor: AlwaysStoppedAnimation(Colors.white),
                  ),
                )
              : const Text(
                  'Submit report',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                  ),
                ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
//  Tiny shared bits
// ════════════════════════════════════════════════════════════════════

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);

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

class _RowDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Container(height: 1, color: MizdahTokens.border(context)),
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
