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
        child: ListView(
          physics: const BouncingScrollPhysics(),
          // Bottom space for the floating nav is reserved by
            // MizdahTabScaffold so the ListView clip ends above it.
            padding: const EdgeInsets.only(bottom: 8),
          children: [
            MizdahFadeUp(
              controller: _entryCtrl,
              delay: 0.0,
              child: const MizdahPageHeader(
                leading: 'Your',
                accent: 'settings',
                subtitle: 'Profile · Theme · Privacy',
              ),
            ),
            const SizedBox(height: 14),

            // Profile card
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

            // Quick stats
            MizdahFadeUp(
              controller: _entryCtrl,
              delay: 0.16,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 18),
                child: _StatsRow(),
              ),
            ),
            const SizedBox(height: 22),

            // Appearance
            MizdahFadeUp(
              controller: _entryCtrl,
              delay: 0.22,
              child: _Section(
                title: 'Appearance',
                child: _ThemeCard(
                  current: themeMode,
                  onChanged: (m) =>
                      ref.read(themeProvider.notifier).setTheme(m),
                ),
              ),
            ),
            const SizedBox(height: 18),

            // Account
            MizdahFadeUp(
              controller: _entryCtrl,
              delay: 0.28,
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
                            'Default mic / camera, layout, max tiles',
                        onTap: () => _comingSoon(
                            context, 'Meeting preferences'),
                      ),
                      const _Divider(),
                      _SettingRow(
                        icon: Icons.logout_rounded,
                        label: 'Sign out',
                        sublabel: 'End your current session',
                        destructive: true,
                        onTap: () => _confirmSignOut(context, ref),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),

            // Privacy & Security
            MizdahFadeUp(
              controller: _entryCtrl,
              delay: 0.34,
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

            // About
            MizdahFadeUp(
              controller: _entryCtrl,
              delay: 0.40,
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

class _StatsRow extends ConsumerWidget {
  const _StatsRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(callHistoryProvider);
    final stats = async.when(
      loading: () => null,
      error: (_, __) => null,
      data: (h) {
        final total = h.length;
        final mins = h.fold<int>(
          0,
          (acc, c) => acc + c.duration.inMinutes,
        );
        return (total, mins);
      },
    );

    return Row(
      children: [
        Expanded(
          child: _StatCard(
            label: 'Meetings',
            value: stats == null ? '—' : '${stats.$1}',
            accent: const Color(0xFF8B5CF6),
            icon: Icons.video_call_rounded,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            label: 'Total minutes',
            value: stats == null ? '—' : '${stats.$2}',
            accent: const Color(0xFF3B82F6),
            icon: Icons.timer_outlined,
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
    return MizdahCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: accent, size: 18),
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
//  Theme card — uses RadioGroup (no deprecated API)
// ────────────────────────────────────────────────────────────────────

class _ThemeCard extends StatelessWidget {
  final ThemeMode current;
  final ValueChanged<ThemeMode> onChanged;
  const _ThemeCard({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return MizdahCard(
      padding: EdgeInsets.zero,
      child: RadioGroup<ThemeMode>(
        groupValue: current,
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
        child: Column(
          children: const [
            _ThemeRow(
              mode: ThemeMode.light,
              icon: Icons.light_mode_rounded,
              label: 'Light',
              sublabel: 'Bright canvas, vivid colours',
            ),
            _Divider(),
            _ThemeRow(
              mode: ThemeMode.dark,
              icon: Icons.dark_mode_rounded,
              label: 'Dark',
              sublabel: 'Easy on the eyes after hours',
            ),
            _Divider(),
            _ThemeRow(
              mode: ThemeMode.system,
              icon: Icons.brightness_auto_rounded,
              label: 'System',
              sublabel: 'Follow your device setting',
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemeRow extends StatelessWidget {
  final ThemeMode mode;
  final IconData icon;
  final String label;
  final String sublabel;
  const _ThemeRow({
    required this.mode,
    required this.icon,
    required this.label,
    required this.sublabel,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
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
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    label,
                    style: TextStyle(
                      color: MizdahTokens.inkOf(context),
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    sublabel,
                    style: TextStyle(
                      color: MizdahTokens.mutedOf(context),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Radio<ThemeMode>(
            value: mode,
            activeColor: MizdahTokens.primary,
          ),
        ],
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
