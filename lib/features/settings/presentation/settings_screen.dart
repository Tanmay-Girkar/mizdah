// ════════════════════════════════════════════════════════════════════
//  Settings — premium redesign
//  ────────────────────────────────────────────────────────────────────
//  Single-page scroll matching the home/meetings/people aesthetic:
//    • Profile card (avatar + name + email + plan badge)
//    • Quick stats grid (meetings hosted, hours)
//    • Appearance (theme switcher with RadioGroup)
//    • Account (edit profile, sign out)
//    • Privacy & Security
//    • About (privacy policy, terms, version)
//  Replaces the legacy 4-tab AppBar version. The bottom-nav floats
//  over this just like every other tab page.
// ════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/theme_provider.dart';
import '../../../core/ui/mizdah_design.dart';
import '../../auth/auth_provider.dart';
import '../../home/presentation/home_screen.dart' show callHistoryProvider;

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entryCtrl;

  @override
  void initState() {
    super.initState();
    _entryCtrl = AnimationController(
      duration: const Duration(milliseconds: 700),
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
    final auth = ref.watch(authProvider);
    final themeMode = ref.watch(themeProvider);

    return MizdahTabScaffold(
      activeIndex: 4,
      body: SafeArea(
        bottom: false,
        // Pinned header (title + theme pill + subtitle) above a
        // scrollable list of profile/stats/sections. Header doesn't
        // bounce with drag — only the body does.
        child: Column(
          children: [
            // ── PINNED page header — title + theme pill + subtitle.
            MizdahFadeUp(
              controller: _entryCtrl,
              delay: 0.0,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 18, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: RichText(
                        maxLines: 2,
                        text: TextSpan(
                          style: TextStyle(
                            color: MizdahTokens.inkOf(context),
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.6,
                            height: 1.1,
                          ),
                          children: [
                            const TextSpan(text: 'Your '),
                            WidgetSpan(
                              alignment: PlaceholderAlignment.baseline,
                              baseline: TextBaseline.alphabetic,
                              child: ShaderMask(
                                shaderCallback: (r) =>
                                    MizdahTokens.heroGradient.createShader(r),
                                child: const Text(
                                  'settings',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 28,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.6,
                                    height: 1.1,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _ThemePill(
                      current: themeMode,
                      onChanged: (m) =>
                          ref.read(themeProvider.notifier).setTheme(m),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
              child: Text(
                'Profile · Stats · Privacy',
                style: TextStyle(
                  color: MizdahTokens.mutedOf(context),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 14),

            // ── Scrollable body ─────────────────────────────────
            Expanded(
              child: ListView(
                physics: const ClampingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                padding: const EdgeInsets.only(bottom: 8),
                children: [

            // ── Profile card (gradient hero) ─────────────────────
            MizdahFadeUp(
              controller: _entryCtrl,
              delay: 0.10,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: _ProfileCard(
                  name: auth.user?.name ?? 'Guest',
                  email: auth.user?.email ?? '—',
                  role: auth.user?.role ?? 'USER',
                ),
              ),
            ),
            const SizedBox(height: 14),

            // ── 3-column stats: Hosted · Joined · Total ──────────
            MizdahFadeUp(
              controller: _entryCtrl,
              delay: 0.16,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 18),
                child: _StatsRow(),
              ),
            ),
            const SizedBox(height: 22),

            // ── Account (Sign out moved to its own card at the
            //    bottom — feels less destructive when separated). ──
            MizdahFadeUp(
              controller: _entryCtrl,
              delay: 0.22,
              child: _Section(
                title: 'Account',
                child: MizdahCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      _SettingRow(
                        icon: Icons.account_circle_rounded,
                        label: 'Edit profile',
                        sublabel: 'Name, photo, display preferences',
                        onTap: () => _comingSoon(context, 'Edit profile'),
                      ),
                      const _Divider(),
                      _SettingRow(
                        icon: Icons.tune_rounded,
                        label: 'Meeting preferences',
                        sublabel:
                            'Default layout, max tiles, tile visibility',
                        onTap: () => context.push('/meeting-preferences'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),

            // ── Privacy & Security ───────────────────────────────
            MizdahFadeUp(
              controller: _entryCtrl,
              delay: 0.28,
              child: _Section(
                title: 'Privacy & Security',
                child: MizdahCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      _SettingRow(
                        icon: Icons.shield_outlined,
                        label: 'Privacy policy',
                        sublabel: 'How we handle your data',
                        onTap: () => context.push('/privacy'),
                      ),
                      const _Divider(),
                      _SettingRow(
                        icon: Icons.flag_outlined,
                        label: 'Report a problem',
                        sublabel: 'Tell us what went wrong',
                        onTap: () => context.push('/report'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),

            // ── About ────────────────────────────────────────────
            MizdahFadeUp(
              controller: _entryCtrl,
              delay: 0.34,
              child: _Section(
                title: 'About',
                child: MizdahCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      _SettingRow(
                        icon: Icons.info_outline_rounded,
                        label: 'About Mizdah',
                        sublabel: 'Version 1.0 · Build 2026.05',
                        onTap: () {},
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 22),

            // ── Sign out — pinned at the very bottom of the
            //    page so it's intentionally far from accidentally-
            //    tapped items. The dedicated card visually
            //    separates it from the regular nav rows.
            MizdahFadeUp(
              controller: _entryCtrl,
              delay: 0.40,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: MizdahCard(
                  padding: EdgeInsets.zero,
                  child: _SettingRow(
                    icon: Icons.logout_rounded,
                    label: 'Sign out',
                    sublabel: 'End your current session',
                    destructive: true,
                    onTap: () => _confirmSignOut(context, ref),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 22),
            Center(
              child: Text(
                'Made with care · Mizdah',
                style: TextStyle(
                  color: MizdahTokens.mutedOf(context).withValues(alpha: 0.8),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.4,
                ),
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

  static void _comingSoon(BuildContext context, String label) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('$label · coming soon'),
      ),
    );
  }

  static Future<void> _confirmSignOut(
      BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MizdahTokens.surface(ctx),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22)),
        title: Text(
          'Sign out?',
          style: TextStyle(color: MizdahTokens.inkOf(ctx)),
        ),
        content: Text(
          'You\'ll need to sign in again to start or join meetings.',
          style: TextStyle(color: MizdahTokens.mutedOf(ctx)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: TextStyle(color: MizdahTokens.mutedOf(ctx))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign out',
                style: TextStyle(color: Color(0xFFB42318))),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(authProvider.notifier).logout();
    if (!context.mounted) return;
    context.go('/login');
  }
}

// ────────────────────────────────────────────────────────────────────
//  Profile card — avatar + name + email + plan badge
// ────────────────────────────────────────────────────────────────────

class _ProfileCard extends StatelessWidget {
  final String name;
  final String email;
  final String role;
  const _ProfileCard({
    required this.name,
    required this.email,
    required this.role,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: MizdahTokens.heroGradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: MizdahTokens.primary.withValues(alpha: 0.30),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -40,
            top: -40,
            child: Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.10),
              ),
            ),
          ),
          Row(
            children: [
              Container(
                width: 64,
                height: 64,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Text(
                  _initials(name),
                  style: const TextStyle(
                    color: MizdahTokens.primary,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.20),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Text(
                        role.toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
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
//  Stats row — derived from callHistoryProvider
// ────────────────────────────────────────────────────────────────────

/// 3-column stats card showing Hosted | Joined | Total. Derives the
/// counts from `callHistoryProvider`; the user's `id` decides which
/// items count as hosted vs joined.
class _StatsRow extends ConsumerWidget {
  const _StatsRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(callHistoryProvider);
    final me = ref.watch(authProvider).user?.id;

    final counts = async.when(
      loading: () => null,
      error: (_, __) => null,
      data: (h) {
        var hosted = 0;
        var joined = 0;
        for (final c in h) {
          if (c.hostId != null && me != null && c.hostId == me) {
            hosted++;
          } else {
            joined++;
          }
        }
        return (hosted: hosted, joined: joined, total: h.length);
      },
    );

    return Row(
      children: [
        Expanded(
          child: _StatCard(
            label: 'Hosted',
            value: counts == null ? '—' : '${counts.hosted}',
            accent: const Color(0xFF6C63FF),
            icon: Icons.video_call_rounded,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatCard(
            label: 'Joined',
            value: counts == null ? '—' : '${counts.joined}',
            accent: const Color(0xFF10B981),
            icon: Icons.call_received_rounded,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatCard(
            label: 'Total',
            value: counts == null ? '—' : '${counts.total}',
            accent: const Color(0xFFF59E0B),
            icon: Icons.bar_chart_rounded,
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color accent;
  final IconData icon;
  const _StatCard({
    required this.label,
    required this.value,
    required this.accent,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    // 3-up layout — slightly tighter padding so each card stays
    // readable on narrow screens.
    return MizdahCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: accent, size: 17),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              color: MizdahTokens.inkOf(context),
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            label,
            style: TextStyle(
              color: MizdahTokens.mutedOf(context),
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────
//  Section wrapper — gradient title + child
// ────────────────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  final String title;
  final Widget child;
  const _Section({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Text(
              title,
              style: TextStyle(
                color: MizdahTokens.inkOf(context),
                fontSize: 16,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────
//  Compact theme pill — replaces the old "Appearance" section card.
//  Three-segment switcher (sun / moon / auto) that lives in the
//  page header next to the title. Premium placement: visible at a
//  glance, single-tap to switch, no scrolling required, doesn't
//  take a full-width row of vertical real estate.
// ────────────────────────────────────────────────────────────────────

class _ThemePill extends StatelessWidget {
  final ThemeMode current;
  final ValueChanged<ThemeMode> onChanged;
  const _ThemePill({required this.current, required this.onChanged});

  static const _modes = <ThemeMode, IconData>{
    ThemeMode.light: Icons.light_mode_rounded,
    ThemeMode.dark: Icons.dark_mode_rounded,
    ThemeMode.system: Icons.brightness_auto_rounded,
  };

  static const _tooltips = <ThemeMode, String>{
    ThemeMode.light: 'Light theme',
    ThemeMode.dark: 'Dark theme',
    ThemeMode.system: 'Follow system',
  };

  @override
  Widget build(BuildContext context) {
    final modes = _modes.keys.toList();
    final activeIndex = modes.indexOf(current);
    return SizedBox(
      width: 132,
      height: 38,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: MizdahTokens.surface(context),
          borderRadius: BorderRadius.circular(20),
          border:
              Border.all(color: MizdahTokens.border(context), width: 1),
          boxShadow: MizdahTokens.shadow(context, elevation: 0.4),
        ),
        child: LayoutBuilder(builder: (ctx, c) {
          final pillW = c.maxWidth / modes.length;
          return Stack(
            children: [
              // Animated indicator — slides between the three slots
              // with a 240ms ease, staying premium-looking on tap.
              AnimatedPositioned(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                left: activeIndex * pillW,
                top: 0,
                bottom: 0,
                width: pillW,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: MizdahTokens.heroGradient,
                    borderRadius: BorderRadius.circular(17),
                    boxShadow: [
                      BoxShadow(
                        color:
                            MizdahTokens.primary.withValues(alpha: 0.32),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                children: [
                  for (final mode in modes)
                    SizedBox(
                      width: pillW,
                      child: Tooltip(
                        message: _tooltips[mode]!,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => onChanged(mode),
                          child: Center(
                            child: Icon(
                              _modes[mode],
                              size: 17,
                              color: current == mode
                                  ? Colors.white
                                  : MizdahTokens.mutedOf(context),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        }),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────
//  Generic settings row
// ────────────────────────────────────────────────────────────────────

class _SettingRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sublabel;
  final VoidCallback onTap;
  final bool destructive;
  const _SettingRow({
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.onTap,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final accent =
        destructive ? const Color(0xFFB42318) : MizdahTokens.primary;
    final accentBg =
        destructive ? const Color(0xFFFEE4E2) : MizdahTokens.iconTileBg(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: accentBg,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, color: accent, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: destructive
                          ? const Color(0xFFB42318)
                          : MizdahTokens.inkOf(context),
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
            Icon(Icons.chevron_right_rounded,
                color: MizdahTokens.mutedOf(context), size: 20),
          ],
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Container(height: 1, color: MizdahTokens.border(context)),
      );
}
