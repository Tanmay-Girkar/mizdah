// ════════════════════════════════════════════════════════════════════
//  Mizdah Premium design system
//  ────────────────────────────────────────────────────────────────────
//  Single source of truth for the premium look established in the
//  redesigned home screen. Centralised so the four "tab" screens
//  (Home, Meetings, Call, People, Settings) share an identical
//  palette / shadow recipe / nav layout without copy-paste drift.
//
//  IF YOU CHANGE COLOURS OR THE GRADIENT, you only need to edit
//  this file — every screen reads from `MizdahTokens`.
// ════════════════════════════════════════════════════════════════════

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class MizdahTokens {
  static const primary = Color(0xFF6C63FF);
  static const secondary = Color(0xFF8B5CF6);
  static const tertiary = Color(0xFFA78BFA);
  static const lavenderBg = Color(0xFFF6F7FB);
  static const cardBorder = Color(0xFFEEF0F7);
  static const ink = Color(0xFF0F1322);
  static const muted = Color(0xFF6B7180);
  static const subtleStroke = Color(0xFFE7E9F2);

  static const heroGradient = LinearGradient(
    colors: [Color(0xFF6C63FF), Color(0xFF8B5CF6), Color(0xFFA78BFA)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const screenBgGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFF1EEFF), Color(0xFFFAFBFE)],
  );

  /// Soft, layered shadow system — never use one harsh shadow. The
  /// purple-tinted ambient shadow gives the floating-card look used
  /// across the design without going dark/heavy.
  static List<BoxShadow> softShadow({double elevation = 1}) => [
        BoxShadow(
          color: const Color(0xFF6C63FF).withValues(alpha: 0.06 * elevation),
          blurRadius: 32 * elevation,
          offset: Offset(0, 12 * elevation),
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.03 * elevation),
          blurRadius: 8 * elevation,
          offset: Offset(0, 2 * elevation),
        ),
      ];

  /// Color rotation for timeline dots / row icons — each row gets
  /// a distinct (background, foreground) pair from this palette.
  static const List<List<Color>> rowColors = [
    [Color(0xFFEDE9FE), Color(0xFF8B5CF6)], // violet
    [Color(0xFFDBEAFE), Color(0xFF3B82F6)], // blue
    [Color(0xFFD1FAE5), Color(0xFF10B981)], // emerald
    [Color(0xFFFEF3C7), Color(0xFFF59E0B)], // amber
    [Color(0xFFFCE7F3), Color(0xFFEC4899)], // pink
  ];
}

// ────────────────────────────────────────────────────────────────────
//  Animation helpers — re-export of the home_screen.dart primitives
// ────────────────────────────────────────────────────────────────────

/// Staggered fade-up entry. `controller` runs once forward; `delay`
/// is a fraction of the controller (0..1) — 0 = animates from the
/// start, 0.3 = waits until the controller is 30 % through.
class MizdahFadeUp extends StatelessWidget {
  final AnimationController controller;
  final double delay;
  final Widget child;
  const MizdahFadeUp({
    super.key,
    required this.controller,
    required this.delay,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final v = ((controller.value - delay) / (1 - delay)).clamp(0.0, 1.0);
        final eased = Curves.easeOutCubic.transform(v);
        return Opacity(
          opacity: eased,
          child: Transform.translate(
            offset: Offset(0, (1 - eased) * 14),
            child: child,
          ),
        );
      },
    );
  }
}

/// Tappable that scales down briefly on press. Used everywhere — meeting
/// rows, list cards, primary buttons.
class MizdahPressScale extends StatefulWidget {
  final Widget child;
  final double scaleTo;
  final VoidCallback? onTap;
  const MizdahPressScale({
    super.key,
    required this.child,
    this.scaleTo = 0.97,
    this.onTap,
  });

  @override
  State<MizdahPressScale> createState() => _MizdahPressScaleState();
}

class _MizdahPressScaleState extends State<MizdahPressScale> {
  bool _pressed = false;
  void _set(bool v) {
    if (_pressed == v) return;
    setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapUp: (_) {
        _set(false);
        widget.onTap?.call();
      },
      onTapCancel: () => _set(false),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        scale: _pressed ? widget.scaleTo : 1.0,
        child: widget.child,
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────
//  Gradient-shaded text — reusable for screen titles + accent words
// ────────────────────────────────────────────────────────────────────

class MizdahGradientText extends StatelessWidget {
  final String text;
  final TextStyle style;
  const MizdahGradientText(this.text, {super.key, required this.style});

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (r) => MizdahTokens.heroGradient.createShader(r),
      child: Text(text, style: style.copyWith(color: Colors.white)),
    );
  }
}

// ────────────────────────────────────────────────────────────────────
//  Premium tab scaffold — every tab page wraps its body in this so
//  the background gradient + floating bottom nav stay consistent.
// ────────────────────────────────────────────────────────────────────

class MizdahTabScaffold extends StatelessWidget {
  /// Index of the active tab (0 = Home, 1 = Meetings, 2 = Call,
  /// 3 = People, 4 = Settings). Drives the floating-nav highlight.
  final int activeIndex;
  final Widget body;

  /// When true, no SafeArea is applied to the body — let the screen
  /// own its own scroll padding (so the lavender gradient extends
  /// edge-to-edge while content respects insets).
  final bool extendBodyBehindNav;
  const MizdahTabScaffold({
    super.key,
    required this.activeIndex,
    required this.body,
    this.extendBodyBehindNav = true,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MizdahTokens.lavenderBg,
      extendBody: extendBodyBehindNav,
      body: Stack(
        children: [
          // Diagonal gradient backdrop — same as home screen so all
          // tabs feel like one continuous canvas.
          Positioned.fill(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: MizdahTokens.screenBgGradient,
              ),
            ),
          ),
          // Subtle radial highlight at top-left for depth.
          Positioned(
            top: -120,
            left: -80,
            child: IgnorePointer(
              child: Container(
                width: 320,
                height: 320,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      MizdahTokens.primary.withValues(alpha: 0.10),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          body,
          // Floating bottom nav — pinned with safe-area inset.
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: MizdahFloatingNav(activeIndex: activeIndex),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────
//  Floating bottom nav — 5 tabs, with Call as the prominent center
// ────────────────────────────────────────────────────────────────────

class MizdahFloatingNav extends StatefulWidget {
  /// 0 = Home, 1 = Meetings, 2 = Call, 3 = People, 4 = Settings.
  final int activeIndex;
  const MizdahFloatingNav({super.key, required this.activeIndex});

  @override
  State<MizdahFloatingNav> createState() => _MizdahFloatingNavState();
}

class _MizdahFloatingNavState extends State<MizdahFloatingNav>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    // Subtle 1.6s breathe loop on the active pill indicator. Auto-
    // reverses so it fades up/down without snapping.
    _pulseCtrl = AnimationController(
      duration: const Duration(milliseconds: 1600),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  void _go(int index) {
    if (index == widget.activeIndex) return;
    final routes = ['/', '/meetings', '/call-hub', '/people', '/settings'];
    GoRouter.of(context).go(routes[index]);
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Container(
          height: 68,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.white.withValues(alpha: 0.92),
                Colors.white.withValues(alpha: 0.70),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.6),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF6C63FF).withValues(alpha: 0.16),
                blurRadius: 36,
                offset: const Offset(0, 18),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.6),
                blurRadius: 0,
                offset: const Offset(0, 1),
                spreadRadius: -0.5,
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: _NavItem(
                  index: 0,
                  activeIndex: widget.activeIndex,
                  pulseCtrl: _pulseCtrl,
                  icon: Icons.home_rounded,
                  label: 'Home',
                  onTap: () => _go(0),
                ),
              ),
              Expanded(
                child: _NavItem(
                  index: 1,
                  activeIndex: widget.activeIndex,
                  pulseCtrl: _pulseCtrl,
                  icon: Icons.calendar_month_rounded,
                  label: 'Meetings',
                  onTap: () => _go(1),
                ),
              ),
              // Center "Call" item — slightly raised with a stronger
              // gradient pill so it reads as the primary CTA in the
              // bar. Tap takes you to the call hub.
              Expanded(
                child: _CallNavItem(
                  active: widget.activeIndex == 2,
                  pulseCtrl: _pulseCtrl,
                  onTap: () => _go(2),
                ),
              ),
              Expanded(
                child: _NavItem(
                  index: 3,
                  activeIndex: widget.activeIndex,
                  pulseCtrl: _pulseCtrl,
                  icon: Icons.people_outline_rounded,
                  label: 'People',
                  onTap: () => _go(3),
                ),
              ),
              Expanded(
                child: _NavItem(
                  index: 4,
                  activeIndex: widget.activeIndex,
                  pulseCtrl: _pulseCtrl,
                  icon: Icons.settings_outlined,
                  label: 'Settings',
                  onTap: () => _go(4),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatefulWidget {
  final int index;
  final int activeIndex;
  final AnimationController pulseCtrl;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _NavItem({
    required this.index,
    required this.activeIndex,
    required this.pulseCtrl,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.index == widget.activeIndex;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        scale: _pressed ? 0.92 : 1.0,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 240),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.85, end: 1.0).animate(anim),
                child: child,
              ),
            ),
            child: active
                ? _ActiveContent(
                    key: const ValueKey('active'),
                    icon: widget.icon,
                    label: widget.label,
                    pulseCtrl: widget.pulseCtrl,
                  )
                : _InactiveContent(
                    key: const ValueKey('inactive'),
                    icon: widget.icon,
                    label: widget.label,
                  ),
          ),
        ),
      ),
    );
  }
}

class _ActiveContent extends StatelessWidget {
  final IconData icon;
  final String label;
  final AnimationController pulseCtrl;
  const _ActiveContent({
    super.key,
    required this.icon,
    required this.label,
    required this.pulseCtrl,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ShaderMask(
          shaderCallback: (r) => MizdahTokens.heroGradient.createShader(r),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
        const SizedBox(height: 3),
        ShaderMask(
          shaderCallback: (r) => MizdahTokens.heroGradient.createShader(r),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        AnimatedBuilder(
          animation: pulseCtrl,
          builder: (context, _) {
            final t = pulseCtrl.value;
            return Container(
              margin: const EdgeInsets.only(top: 3),
              width: 16 + t * 2,
              height: 3,
              decoration: BoxDecoration(
                gradient: MizdahTokens.heroGradient,
                borderRadius: BorderRadius.circular(2),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF6C63FF)
                        .withValues(alpha: 0.4 + t * 0.3),
                    blurRadius: 6 + t * 6,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _InactiveContent extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InactiveContent({
    super.key,
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: const Color(0xFF8A8FA0), size: 22),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF8A8FA0),
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// The center "Call" tab — visually distinct from the four neutral
/// tabs. When inactive, shows a small gradient pill behind a white
/// phone icon (high contrast). When active, the pill grows + adds a
/// glow halo + the label fades to a gradient text below. Doesn't need
/// the rotating active/inactive AnimatedSwitcher — a single
/// AnimatedContainer drives the size delta.
class _CallNavItem extends StatefulWidget {
  final bool active;
  final AnimationController pulseCtrl;
  final VoidCallback onTap;
  const _CallNavItem({
    required this.active,
    required this.pulseCtrl,
    required this.onTap,
  });

  @override
  State<_CallNavItem> createState() => _CallNavItemState();
}

class _CallNavItemState extends State<_CallNavItem> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        scale: _pressed ? 0.90 : 1.0,
        child: Center(
          child: AnimatedBuilder(
            animation: widget.pulseCtrl,
            builder: (context, _) {
              final t = widget.active ? widget.pulseCtrl.value : 0.0;
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    width: widget.active ? 46 : 40,
                    height: widget.active ? 46 : 40,
                    decoration: BoxDecoration(
                      gradient: MizdahTokens.heroGradient,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: MizdahTokens.primary
                              .withValues(alpha: widget.active ? 0.45 + t * 0.2 : 0.30),
                          blurRadius: widget.active ? 16 + t * 8 : 12,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.videocam_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (widget.active)
                    ShaderMask(
                      shaderCallback: (r) =>
                          MizdahTokens.heroGradient.createShader(r),
                      child: const Text(
                        'Call',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    )
                  else
                    const Text(
                      'Call',
                      style: TextStyle(
                        color: Color(0xFF8A8FA0),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────
//  Section header — used at the top of every tab page
// ────────────────────────────────────────────────────────────────────

class MizdahPageHeader extends StatelessWidget {
  /// Plain text drawn before the optional gradient accent word.
  final String leading;
  /// Optional accent word — rendered with the hero gradient.
  final String? accent;
  /// Optional subtitle below the title.
  final String? subtitle;
  /// Optional trailing widget (e.g. a profile avatar).
  final Widget? trailing;
  /// Optional leading widget (e.g. a back button or menu icon).
  final Widget? icon;
  const MizdahPageHeader({
    super.key,
    required this.leading,
    this.accent,
    this.subtitle,
    this.trailing,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                icon!,
                const SizedBox(width: 12),
              ],
              Expanded(
                child: RichText(
                  maxLines: 2,
                  text: TextSpan(
                    style: const TextStyle(
                      color: MizdahTokens.ink,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.6,
                      height: 1.1,
                    ),
                    children: [
                      TextSpan(text: leading),
                      if (accent != null) ...[
                        const TextSpan(text: ' '),
                        WidgetSpan(
                          alignment: PlaceholderAlignment.baseline,
                          baseline: TextBaseline.alphabetic,
                          child: ShaderMask(
                            shaderCallback: (r) =>
                                MizdahTokens.heroGradient.createShader(r),
                            child: Text(
                              accent!,
                              style: const TextStyle(
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
                    ],
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              subtitle!,
              style: const TextStyle(
                color: MizdahTokens.muted,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────
//  Premium card — used as the building block for sections
// ────────────────────────────────────────────────────────────────────

class MizdahCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final double borderRadius;
  final VoidCallback? onTap;
  const MizdahCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.margin = EdgeInsets.zero,
    this.borderRadius = 22,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final box = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: MizdahTokens.cardBorder, width: 1),
        boxShadow: MizdahTokens.softShadow(elevation: 0.7),
      ),
      child: child,
    );
    return Padding(
      padding: margin,
      child: onTap != null
          ? MizdahPressScale(
              scaleTo: 0.985,
              onTap: onTap,
              child: box,
            )
          : box,
    );
  }
}

// ────────────────────────────────────────────────────────────────────
//  Empty-state placeholder — soft icon + title + subtitle
// ────────────────────────────────────────────────────────────────────

class MizdahEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const MizdahEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFEDE9FE), Color(0xFFF5F3FF)],
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(icon, color: MizdahTokens.tertiary, size: 28),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(
              color: MizdahTokens.ink,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: MizdahTokens.muted,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────
//  Avatar that derives its initials + colour from a name string
// ────────────────────────────────────────────────────────────────────

class MizdahAvatar extends StatelessWidget {
  final String name;
  final double size;
  const MizdahAvatar({super.key, required this.name, this.size = 44});

  String get _initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  List<Color> get _palette {
    // Hash name to a stable rowColors slot — same name always gets
    // the same colour pair across the app.
    final seed = name.codeUnits.fold<int>(0, (a, b) => a + b);
    return MizdahTokens.rowColors[seed % MizdahTokens.rowColors.length];
  }

  @override
  Widget build(BuildContext context) {
    final p = _palette;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [p[0], p[1].withValues(alpha: 0.85)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: p[1].withValues(alpha: 0.25),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Text(
        _initials,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.38,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
