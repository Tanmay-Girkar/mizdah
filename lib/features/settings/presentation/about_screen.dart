// ════════════════════════════════════════════════════════════════════
//  About Mizdah — credits, version, legal links
//  ────────────────────────────────────────────────────────────────────
//  Reachable from Settings → About → About Mizdah. All static — no
//  backend calls, no providers. Premium presentation befitting an
//  app's signature "About" page.
// ════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ui/mizdah_design.dart';

class AboutScreen extends ConsumerStatefulWidget {
  const AboutScreen({super.key});

  @override
  ConsumerState<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends ConsumerState<AboutScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entryCtrl;
  // Subtle floating loop on the brand mark.
  late final AnimationController _floatCtrl;

  @override
  void initState() {
    super.initState();
    _entryCtrl = AnimationController(
      duration: const Duration(milliseconds: 700),
      vsync: this,
    )..forward();
    _floatCtrl = AnimationController(
      duration: const Duration(seconds: 5),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    _floatCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MizdahTokens.bg(context),
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: MizdahTokens.pageGradient(context),
              ),
            ),
          ),
          // Decorative radial highlights for depth — these are the
          // same colours as the home screen's hero illustration so
          // the page feels like part of the brand.
          Positioned(
            top: -160,
            right: -120,
            child: IgnorePointer(
              child: Container(
                width: 360,
                height: 360,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      MizdahTokens.primary.withValues(alpha: 0.18),
                      Colors.transparent,
                    ],
                  ),
                ),
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
                Expanded(
                  child: ListView(
                    physics: const ClampingScrollPhysics(
                      parent: AlwaysScrollableScrollPhysics(),
                    ),
                    padding: const EdgeInsets.only(top: 6, bottom: 36),
                    children: [
                      // ── Hero brand mark + name ─────────────────
                      MizdahFadeUp(
                        controller: _entryCtrl,
                        delay: 0.05,
                        child: _Hero(floatCtrl: _floatCtrl),
                      ),
                      const SizedBox(height: 28),
                      // ── Tagline ────────────────────────────────
                      MizdahFadeUp(
                        controller: _entryCtrl,
                        delay: 0.14,
                        child: const _Tagline(),
                      ),
                      const SizedBox(height: 28),
                      // ── Legal section ──────────────────────────
                      MizdahFadeUp(
                        controller: _entryCtrl,
                        delay: 0.20,
                        child: _Section(
                          title: 'Legal',
                          rows: [
                            _LinkRow(
                              icon: Icons.shield_outlined,
                              label: 'Privacy policy',
                              sublabel: 'How we handle your data',
                              onTap: () => context.push('/privacy'),
                            ),
                            _LinkRow(
                              icon: Icons.description_outlined,
                              label: 'Terms of service',
                              sublabel: 'The rules you agreed to',
                              onTap: () => _comingSoon(context,
                                  'Terms of service'),
                            ),
                            _LinkRow(
                              icon: Icons.verified_user_outlined,
                              label: 'Open-source licenses',
                              sublabel:
                                  'Credits for the libraries we use',
                              onTap: () => _comingSoon(context,
                                  'Open-source licenses'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      // ── Connect section ────────────────────────
                      MizdahFadeUp(
                        controller: _entryCtrl,
                        delay: 0.26,
                        child: _Section(
                          title: 'Connect',
                          rows: [
                            _LinkRow(
                              icon: Icons.public_rounded,
                              label: 'Website',
                              sublabel: 'mizdah.com',
                              onTap: () =>
                                  _comingSoon(context, 'Website'),
                            ),
                            _LinkRow(
                              icon: Icons.support_agent_rounded,
                              label: 'Contact support',
                              sublabel: 'We usually reply within a day',
                              onTap: () => context.push('/report'),
                            ),
                            _LinkRow(
                              icon: Icons.star_rate_rounded,
                              label: 'Rate Mizdah',
                              sublabel: 'Tell us what you think',
                              onTap: () =>
                                  _comingSoon(context, 'Rate Mizdah'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 30),
                      // ── Footer signature ───────────────────────
                      MizdahFadeUp(
                        controller: _entryCtrl,
                        delay: 0.32,
                        child: const _Footer(),
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

  static void _comingSoon(BuildContext context, String label) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('$label · coming soon'),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────

class _Hero extends StatelessWidget {
  final AnimationController floatCtrl;
  const _Hero({required this.floatCtrl});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        children: [
          // Floating brand mark with concentric halos.
          AnimatedBuilder(
            animation: floatCtrl,
            builder: (context, _) {
              final t = floatCtrl.value;
              return Transform.translate(
                offset: Offset(0, -4 + t * 8),
                child: SizedBox(
                  width: 200,
                  height: 200,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Outer halo
                      Container(
                        width: 200,
                        height: 200,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              MizdahTokens.primary.withValues(alpha: 0.16),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                      // Mid halo
                      Container(
                        width: 144,
                        height: 144,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: MizdahTokens.primary.withValues(alpha: 0.10),
                        ),
                      ),
                      // Brand pill
                      Container(
                        width: 96,
                        height: 96,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          gradient: MizdahTokens.heroGradient,
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: [
                            BoxShadow(
                              color: MizdahTokens.primary
                                  .withValues(alpha: 0.45),
                              blurRadius: 30,
                              offset: const Offset(0, 14),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.auto_awesome_rounded,
                          color: Colors.white,
                          size: 42,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          // Wordmark
          ShaderMask(
            shaderCallback: (r) =>
                MizdahTokens.heroGradient.createShader(r),
            child: const Text(
              'MIZDAH',
              style: TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w800,
                letterSpacing: 6,
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Version chip
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: MizdahTokens.surface(context),
              borderRadius: BorderRadius.circular(99),
              border: Border.all(
                color: MizdahTokens.border(context),
              ),
              boxShadow: MizdahTokens.shadow(context, elevation: 0.4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: Color(0xFF10B981),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'Version 1.0  ·  Build 2026.05',
                  style: TextStyle(
                    color: MizdahTokens.mutedOf(context),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
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

class _Tagline extends StatelessWidget {
  const _Tagline();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          Text(
            'Premium meetings, made simple.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: MizdahTokens.inkOf(context),
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Built for teams and friends who care about how their calls feel — fast joins, crisp audio, calm interface.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: MizdahTokens.mutedOf(context),
              fontSize: 13.5,
              fontWeight: FontWeight.w500,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> rows;
  const _Section({required this.title, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              title,
              style: TextStyle(
                color: MizdahTokens.inkOf(context),
                fontSize: 14,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
              ),
            ),
          ),
          MizdahCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < rows.length; i++) ...[
                  rows[i],
                  if (i < rows.length - 1) _RowDivider(),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sublabel;
  final VoidCallback onTap;
  const _LinkRow({
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
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
            Icon(Icons.arrow_outward_rounded,
                color: MizdahTokens.mutedOf(context), size: 18),
          ],
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Column(
        children: [
          Text(
            'Made with care · Mizdah',
            style: TextStyle(
              color: MizdahTokens.mutedOf(context),
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '© ${DateTime.now().year}',
            style: TextStyle(
              color: MizdahTokens.mutedOf(context).withValues(alpha: 0.7),
              fontSize: 11,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.3,
            ),
          ),
        ],
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
