// ════════════════════════════════════════════════════════════════════
//  Mizdah Premium design system
//  ────────────────────────────────────────────────────────────────────
//  Single source of truth for the premium look established in the
//  redesigned home screen. Centralised so the four "tab" screens
//  (Home, Meetings, Call, Chats, Settings) share an identical
//  palette / shadow recipe / nav layout without copy-paste drift.
//
//  IF YOU CHANGE COLOURS OR THE GRADIENT, you only need to edit
//  this file — every screen reads from `MizdahTokens`.
// ════════════════════════════════════════════════════════════════════

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class MizdahTokens {
  // ── Brand accents — identical in both modes ─────────────────────
  static const primary = Color(0xFF6C63FF);
  static const secondary = Color(0xFF8B5CF6);
  static const tertiary = Color(0xFFA78BFA);
  static const heroGradient = LinearGradient(
    colors: [Color(0xFF6C63FF), Color(0xFF8B5CF6), Color(0xFFA78BFA)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Color rotation for timeline dots / row icons — each row gets
  /// a distinct (background, foreground) pair from this palette.
  /// Same in both modes — the tints are bright enough to read on
  /// dark backgrounds too.
  static const List<List<Color>> rowColors = [
    [Color(0xFFEDE9FE), Color(0xFF8B5CF6)], // violet
    [Color(0xFFDBEAFE), Color(0xFF3B82F6)], // blue
    [Color(0xFFD1FAE5), Color(0xFF10B981)], // emerald
    [Color(0xFFFEF3C7), Color(0xFFF59E0B)], // amber
    [Color(0xFFFCE7F3), Color(0xFFEC4899)], // pink
  ];

  // ── Light-mode raw values (legacy const tokens kept so existing
  //    callers still resolve) ────────────────────────────────────
  static const lavenderBg = Color(0xFFF6F7FB);
  static const cardBorder = Color(0xFFEEF0F7);
  static const ink = Color(0xFF0F1322);
  static const muted = Color(0xFF6B7180);
  static const subtleStroke = Color(0xFFE7E9F2);
  static const screenBgGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFF1EEFF), Color(0xFFFAFBFE)],
  );

  // ── Dark-mode raw values ──────────────────────────────────────
  static const darkBg = Color(0xFF0B0F1A);
  static const darkSurface = Color(0xFF161B2A);
  static const darkInk = Color(0xFFF1F5FF);
  static const darkMuted = Color(0xFF8893A8);
  static const darkCardBorder = Color(0xFF252B3D);
  static const darkSubtleStroke = Color(0xFF1F2535);
  static const darkScreenBgGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF131A2E), Color(0xFF0B0F1A)],
  );

  // ── Adaptive accessors — read the active brightness off context
  //    and return the right value. Use these in widgets instead of
  //    the raw consts so the screen flips automatically when the
  //    user toggles theme. ────────────────────────────────────────

  static bool isDark(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark;

  /// Page-level background. Lavender wash in light mode, deep navy
  /// in dark mode.
  static Color bg(BuildContext c) => isDark(c) ? darkBg : lavenderBg;

  /// Card / sheet surface fill. White in light mode, raised navy
  /// surface in dark mode.
  static Color surface(BuildContext c) =>
      isDark(c) ? darkSurface : Colors.white;

  /// Primary text colour — high contrast against `bg`.
  static Color inkOf(BuildContext c) => isDark(c) ? darkInk : ink;

  /// Secondary / muted text colour.
  static Color mutedOf(BuildContext c) => isDark(c) ? darkMuted : muted;

  /// 1px stroke around cards.
  static Color border(BuildContext c) =>
      isDark(c) ? darkCardBorder : cardBorder;

  /// Even fainter divider used between rows.
  static Color subtle(BuildContext c) =>
      isDark(c) ? darkSubtleStroke : subtleStroke;

  /// Page background gradient — light lavender or dark navy.
  static LinearGradient pageGradient(BuildContext c) =>
      isDark(c) ? darkScreenBgGradient : screenBgGradient;

  /// Subtle inset pill — used for text inputs and similar inner
  /// surfaces sitting INSIDE a card. Lighter grey in light mode,
  /// raised navy in dark mode.
  static Color softPillBg(BuildContext c) =>
      isDark(c) ? const Color(0xFF1E2438) : const Color(0xFFF3F4F8);

  /// Tinted icon-tile background — the square fill behind setting-row
  /// icons / feature icons. Light lavender in light mode, dim violet
  /// in dark mode.
  static Color iconTileBg(BuildContext c) =>
      isDark(c) ? const Color(0xFF2A2342) : const Color(0xFFEEF2FF);

  /// Bottom padding every tab screen's scroll area should reserve so
  /// content stops cleanly above the floating nav without leaving a
  /// big empty band between them.
  ///
  /// Recipe (matches WhatsApp / Telegram / iOS bottom-nav spacing):
  ///   12 px  — nav outer margin from the screen edge
  /// + 72 px  — nav pill height
  /// +  6 px  — minimal visual gap between content and nav top
  /// + system safe-area inset (iOS home indicator / Android
  ///            gesture pill)
  ///
  /// The 6 px gap is intentionally tight — the nav's drop shadow
  /// (blur 44) extends well above its visible edge, so the last
  /// item naturally sits under the nav's halo. Anything more turns
  /// into wasted empty space.
  static double navBarBottomInset(BuildContext c) =>
      12 + 72 + 6 + MediaQuery.of(c).padding.bottom;

  /// Soft, layered shadow system — never use one harsh shadow. The
  /// purple-tinted ambient shadow gives the floating-card look used
  /// across the design without going dark/heavy. In dark mode we
  /// drop the elevation impact and switch to a deep-black ambient
  /// shadow for separation against the dark surface.
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

  /// Adaptive shadow — same recipe as `softShadow` in light mode,
  /// deeper black halos in dark mode so cards still read as elevated
  /// on the dark backdrop.
  static List<BoxShadow> shadow(BuildContext c, {double elevation = 1}) {
    if (isDark(c)) {
      return [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.50 * elevation),
          blurRadius: 24 * elevation,
          offset: Offset(0, 10 * elevation),
        ),
        BoxShadow(
          color: const Color(0xFF6C63FF).withValues(alpha: 0.08 * elevation),
          blurRadius: 18 * elevation,
          offset: Offset(0, 6 * elevation),
        ),
      ];
    }
    return softShadow(elevation: elevation);
  }
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
  /// `activeIndex` is now a no-op — kept on the API only so older
  /// call-sites compile while the shell route is being rolled out.
  /// The floating nav itself lives in `MizdahTabsShell`.
  final int activeIndex;
  final Widget body;
  const MizdahTabScaffold({
    super.key,
    required this.activeIndex,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    final navInset = MizdahTokens.navBarBottomInset(context);
    return Scaffold(
      backgroundColor: MizdahTokens.bg(context),
      body: Stack(
        children: [
          // 1. Full-screen background gradient — flows underneath
          //    the (shell-level) floating nav too so its
          //    BackdropFilter has something to frost.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: MizdahTokens.pageGradient(context),
              ),
            ),
          ),
          // 2. Subtle radial highlight at top-left for depth.
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
                      MizdahTokens.primary.withValues(
                        alpha: MizdahTokens.isDark(context) ? 0.18 : 0.10,
                      ),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          // 3. Body — constrained ABOVE the floating nav. The shell
          //    paints the nav over THIS scaffold, so the content
          //    must clip above where the nav floats. Any ListView
          //    inside `body` therefore physically cannot render
          //    in the nav zone.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            bottom: navInset,
            child: body,
          ),
          // The floating nav is no longer rendered here — the
          // shell route owns a single shared instance so it never
          // rebuilds on tab change.
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────
//  App-wide scroll behaviour
//  ────────────────────────────────────────────────────────────────────
//  Locks every scrollable in the app to "rigid" Telegram / WhatsApp-
//  Web-style scrolling:
//
//    • ClampingScrollPhysics on every platform — no iOS rubber-band
//      bounce, no scrolling past the content extent, no white gap
//      revealed at the top when the user pulls down.
//    • Stripped overscroll indicator — Android 12+ ships a stretch
//      effect by default; we suppress it so the page never visibly
//      deforms during a drag.
//    • Drag accepted from any pointer device (touch / mouse /
//      trackpad), which Material's default already does, but we
//      reaffirm it here for explicitness.
//
//  Apply via `MaterialApp.scrollBehavior: const MizdahScrollBehavior()`
//  Individual lists can still override `physics:` if they need
//  scroll-on-short-content (e.g. RefreshIndicator wrappers wrap the
//  same physics with `AlwaysScrollableScrollPhysics`).
// ────────────────────────────────────────────────────────────────────

class MizdahScrollBehavior extends MaterialScrollBehavior {
  const MizdahScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };

  /// Disable both overscroll affordances — iOS bounce is killed by
  /// the physics override below; Android's stretch glow is killed by
  /// returning the child unchanged here (instead of wrapping it in a
  /// `StretchingOverscrollIndicator` / `GlowingOverscrollIndicator`).
  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const ClampingScrollPhysics();
}

// ────────────────────────────────────────────────────────────────────
//  Tabs shell — host for go_router's StatefulShellRoute.indexedStack
//  ────────────────────────────────────────────────────────────────────
//  Premium tab pattern: all five tabs stay mounted, switching is an
//  instant IndexedStack toggle (no fade / no rebuild / no flicker).
//  The floating nav lives here at the shell level so it never
//  rebuilds on tab change — only its `activeIndex` updates.
//
//  Each tab's own scaffold (Home or `MizdahTabScaffold`) keeps
//  rendering its gradient + content; IndexedStack stores them once
//  and re-shows them without rebuilding. Scroll position, in-flight
//  search query, animation controllers — all preserved between tabs.
// ────────────────────────────────────────────────────────────────────

class MizdahTabsShell extends StatelessWidget {
  /// The shell-route's navigation handle. Tells us which branch is
  /// active and how to switch to another (`goBranch(index)`).
  final StatefulNavigationShell navigationShell;

  const MizdahTabsShell({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Background lives at the tab level (each tab paints its own
      // gradient via MizdahTabScaffold or HomeScreen's own scaffold);
      // we just need the shell to be transparent so the tab body
      // shows through.
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // 1. The IndexedStack of branches. Mounted once, never
          //    rebuilt on tab change. Each branch keeps its own
          //    Navigator and state.
          navigationShell,
          // 2. Floating nav — single instance for the whole app.
          //    Tapping a tab calls `goBranch` which flips the
          //    visible child of the IndexedStack instantly.
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: MizdahFloatingNav(
                  activeIndex: navigationShell.currentIndex,
                  onTabTap: (i) {
                    navigationShell.goBranch(
                      i,
                      // Re-tapping the active tab → reset to its
                      // initial location (mirrors iOS / WhatsApp
                      // behaviour where the active tab "scrolls to
                      // top" on re-tap if it has nested routes).
                      initialLocation: i == navigationShell.currentIndex,
                    );
                  },
                ),
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
  /// 0 = Call, 1 = Meetings, 2 = Home (centre), 3 = Chats, 4 = Settings.
  final int activeIndex;

  /// Optional tap handler. When supplied, this is called instead of
  /// `GoRouter.of(context).go(...)`. The shell route uses this to
  /// switch branches via `navigationShell.goBranch(index)`, which
  /// preserves each tab's scroll + state (no flicker on switch).
  final void Function(int index)? onTabTap;

  /// Tab → route map, exposed so the shell route can keep the same
  /// list as the in-widget fallback.
  // Tab order: 0 = Call (flat, left edge) · 1 = Meetings · 2 = Home
  // (prominent gradient centre) · 3 = Chats · 4 = Settings.
  static const tabRoutes = ['/call-hub', '/meetings', '/', '/chats', '/settings'];

  const MizdahFloatingNav({
    super.key,
    required this.activeIndex,
    this.onTabTap,
  });

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
    // Hand off to the shell when present (preserves tab state via
    // navigationShell.goBranch). Otherwise fall back to a plain
    // route push so the nav still works in any non-shell context
    // (legacy callers, previews, etc.).
    if (widget.onTabTap != null) {
      widget.onTabTap!(index);
      return;
    }
    if (index == widget.activeIndex) return;
    GoRouter.of(context).go(MizdahFloatingNav.tabRoutes[index]);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = MizdahTokens.isDark(context);
    // ── Glassmorphism panel ──────────────────────────────────────
    // The bar reads as frosted glass: lower fill alpha so the
    // background gradient blurs through, a strong specular sheen
    // along the top edge, and a thin inner stroke that catches the
    // light. Layering recipe (back-to-front):
    //   1) BackdropFilter blur (sigma 36)
    //   2) Translucent fill gradient — lighter at top, darker at
    //      bottom, like a tilted glass plate.
    //   3) Diagonal sheen overlay — fades from a brighter highlight
    //      in the top-left corner to nothing.
    //   4) Hairline outer border (≈40 % white)
    //   5) Soft purple-tinted ambient shadow
    //   6) Inner 1-px highlight on the top edge

    // Fill — much more transparent than before so the underlying
    // gradient bleeds through the blur.
    final panelTop = (isDark ? const Color(0xFF1B2236) : Colors.white)
        .withValues(alpha: isDark ? 0.55 : 0.55);
    final panelBot = (isDark ? const Color(0xFF131929) : Colors.white)
        .withValues(alpha: isDark ? 0.30 : 0.28);

    // Border — bright enough to catch light without looking solid.
    final panelBorder =
        Colors.white.withValues(alpha: isDark ? 0.14 : 0.55);

    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        // Stronger blur than the old 30 — pushes the underlying
        // background into a softer, more "glass" wash.
        filter: ImageFilter.blur(sigmaX: 36, sigmaY: 36),
        child: Container(
          height: 72,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [panelTop, panelBot],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: panelBorder, width: 1.0),
            boxShadow: [
              // Outer purple ambient halo so the glass appears to
              // float above the page.
              BoxShadow(
                color: const Color(0xFF6C63FF)
                    .withValues(alpha: isDark ? 0.26 : 0.20),
                blurRadius: 44,
                offset: const Offset(0, 22),
              ),
              // Mid-distance neutral shadow for grounding.
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.06),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
              // 1-px specular highlight at the very top of the panel.
              BoxShadow(
                color: Colors.white
                    .withValues(alpha: isDark ? 0.10 : 0.85),
                blurRadius: 0,
                offset: const Offset(0, 1),
                spreadRadius: -0.5,
              ),
            ],
          ),
          // Diagonal sheen overlay — paints OVER the children too,
          // so the alpha at the brightest point is kept low (≤ 15 %)
          // so nav icons stay legible. Gives the glass a "catching
          // light from above-left" highlight without hazing the row.
          foregroundDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: isDark ? 0.07 : 0.14),
                Colors.white.withValues(alpha: 0.0),
                Colors.white.withValues(alpha: 0.0),
              ],
              stops: const [0.0, 0.40, 1.0],
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: _NavItem(
                  index: 0,
                  activeIndex: widget.activeIndex,
                  pulseCtrl: _pulseCtrl,
                  icon: Icons.videocam_rounded,
                  label: 'Call',
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
              // Centre "Home" item — slightly raised with a stronger
              // gradient pill so it reads as the primary anchor in
              // the bar. Tap takes you to the home dashboard.
              Expanded(
                child: _CenterNavItem(
                  active: widget.activeIndex == 2,
                  pulseCtrl: _pulseCtrl,
                  icon: Icons.home_rounded,
                  label: 'Home',
                  onTap: () => _go(2),
                ),
              ),
              Expanded(
                child: _NavItem(
                  index: 3,
                  activeIndex: widget.activeIndex,
                  pulseCtrl: _pulseCtrl,
                  icon: Icons.chat_bubble_outline_rounded,
                  label: 'Chats',
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
    // Slightly brighter grey in dark mode so the inactive icons
    // still read as tappable affordances.
    final c = MizdahTokens.isDark(context)
        ? const Color(0xFFA0A8BD)
        : const Color(0xFF8A8FA0);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: c, size: 22),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            color: c,
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
/// Prominent center nav item — bigger gradient circle, raised shadow,
/// pulse animation on activation. Reused for whichever tab the design
/// wants to read as the primary action at the centre of the bar.
class _CenterNavItem extends StatefulWidget {
  final bool active;
  final AnimationController pulseCtrl;
  final VoidCallback onTap;
  final IconData icon;
  final String label;
  const _CenterNavItem({
    required this.active,
    required this.pulseCtrl,
    required this.onTap,
    required this.icon,
    required this.label,
  });

  @override
  State<_CenterNavItem> createState() => _CenterNavItemState();
}

class _CenterNavItemState extends State<_CenterNavItem> {
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
                    child: Icon(
                      widget.icon,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (widget.active)
                    ShaderMask(
                      shaderCallback: (r) =>
                          MizdahTokens.heroGradient.createShader(r),
                      child: Text(
                        widget.label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    )
                  else
                    Text(
                      widget.label,
                      style: TextStyle(
                        color: MizdahTokens.isDark(context)
                            ? const Color(0xFFA0A8BD)
                            : const Color(0xFF8A8FA0),
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
                    style: TextStyle(
                      color: MizdahTokens.inkOf(context),
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
              style: TextStyle(
                color: MizdahTokens.mutedOf(context),
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
        color: MizdahTokens.surface(context),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: MizdahTokens.border(context), width: 1),
        boxShadow: MizdahTokens.shadow(context, elevation: 0.7),
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
    final isDark = MizdahTokens.isDark(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                // Lighter pastel pair in light mode; dimmed
                // translucent purple in dark mode so the icon halo
                // doesn't glow too brightly against the navy bg.
                colors: isDark
                    ? [
                        const Color(0xFF2D2547).withValues(alpha: 0.85),
                        const Color(0xFF1F1A33).withValues(alpha: 0.85),
                      ]
                    : const [Color(0xFFEDE9FE), Color(0xFFF5F3FF)],
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(icon, color: MizdahTokens.tertiary, size: 28),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: TextStyle(
              color: MizdahTokens.inkOf(context),
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: MizdahTokens.mutedOf(context),
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
  /// HTTPS URL to the user's profile photo. When null/empty, the
  /// widget falls back to coloured initials.
  final String? avatarUrl;
  const MizdahAvatar({
    super.key,
    required this.name,
    this.size = 44,
    this.avatarUrl,
  });

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

  bool get _hasUrl => avatarUrl != null && avatarUrl!.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final p = _palette;
    final fallback = Container(
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

    if (!_hasUrl) return fallback;
    // Render the network avatar; `errorBuilder` ensures the initials
    // still appear if the image 404s or the network is offline.
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: Image.network(
          avatarUrl!,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          loadingBuilder: (ctx, child, progress) {
            if (progress == null) return child;
            return fallback;
          },
          errorBuilder: (ctx, error, stack) => fallback,
        ),
      ),
    );
  }
}
