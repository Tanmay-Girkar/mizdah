import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Round 4 — "Mizdah Premium" — the reference design the user shared.
/// A single, polished iOS-style dashboard inspired by modern SaaS
/// (Linear / Notion / Apple) with glassmorphism, soft neumorphism,
/// purple gradients, and a translucent blob illustration in the hero.
///
/// One design only — the goal is faithful reproduction of the
/// reference image, not a gallery of alternatives. Same preview-only
/// contract as V1/V2/V3: production home_screen.dart is unchanged.

// ════════════════════════════════════════════════════════════════════
//  Design tokens — keep all colors / sizes here so a future port to
//  the live home_screen is a one-import affair.
// ════════════════════════════════════════════════════════════════════

class _Tokens {
  static const primary = Color(0xFF6C63FF);
  // Used inside heroGradient + spec palette; named for future ports.
  // ignore: unused_field
  static const secondary = Color(0xFF8B5CF6);
  // ignore: unused_field
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

  // Soft, layered shadow system — never use one harsh shadow.
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
}

// ════════════════════════════════════════════════════════════════════
//  Mock data
// ════════════════════════════════════════════════════════════════════

class _Meeting {
  final String month;
  final int day;
  final String weekday;
  final String title;
  final String timeRange;
  final String duration;
  final Color dotColor;
  final Color iconBg;
  final Color iconFg;
  final List<Color> avatars;
  final int extra;
  const _Meeting({
    required this.month,
    required this.day,
    required this.weekday,
    required this.title,
    required this.timeRange,
    required this.duration,
    required this.dotColor,
    required this.iconBg,
    required this.iconFg,
    required this.avatars,
    required this.extra,
  });
}

const _kMeetings = <_Meeting>[
  _Meeting(
    month: 'APR',
    day: 23,
    weekday: 'WED',
    title: 'Product Strategy Meeting',
    timeRange: '5:30 PM – 6:00 PM',
    duration: '30 min',
    dotColor: Color(0xFF8B5CF6),
    iconBg: Color(0xFFEDE9FE),
    iconFg: Color(0xFF8B5CF6),
    avatars: [Color(0xFFFDE68A), Color(0xFFFCA5A5), Color(0xFFA5B4FC)],
    extra: 3,
  ),
  _Meeting(
    month: 'APR',
    day: 23,
    weekday: 'WED',
    title: 'Design Systems Review',
    timeRange: '6:30 PM – 7:15 PM',
    duration: '45 min',
    dotColor: Color(0xFF3B82F6),
    iconBg: Color(0xFFDBEAFE),
    iconFg: Color(0xFF3B82F6),
    avatars: [Color(0xFFFCD34D), Color(0xFFA7F3D0), Color(0xFFFBCFE8)],
    extra: 2,
  ),
  _Meeting(
    month: 'APR',
    day: 24,
    weekday: 'THU',
    title: 'Client Sync – Acme Corp',
    timeRange: '10:00 AM – 11:00 AM',
    duration: '60 min',
    dotColor: Color(0xFF10B981),
    iconBg: Color(0xFFD1FAE5),
    iconFg: Color(0xFF10B981),
    avatars: [Color(0xFFFBA5A5), Color(0xFFA5F3FC), Color(0xFFFDE68A)],
    extra: 4,
  ),
  _Meeting(
    month: 'APR',
    day: 24,
    weekday: 'THU',
    title: 'Marketing Weekly Update',
    timeRange: '3:00 PM – 3:30 PM',
    duration: '30 min',
    dotColor: Color(0xFFF59E0B),
    iconBg: Color(0xFFFEF3C7),
    iconFg: Color(0xFFF59E0B),
    avatars: [Color(0xFFA7F3D0), Color(0xFFC7D2FE)],
    extra: 1,
  ),
];

// ════════════════════════════════════════════════════════════════════
//  Preview shell — phone frame around the live design
// ════════════════════════════════════════════════════════════════════

class HomeDesignsPreviewV4Screen extends StatelessWidget {
  const HomeDesignsPreviewV4Screen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: SafeArea(
        child: Column(
          children: [
            // Toolbar
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => context.pop(),
                  ),
                  const SizedBox(width: 4),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Mizdah Premium',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Glass blobs · gradient hero · timeline list · floating nav',
                          style: TextStyle(color: Colors.white60, fontSize: 11),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6C63FF).withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: const Color(0xFF6C63FF).withValues(alpha: 0.4),
                        width: 0.5,
                      ),
                    ),
                    child: const Text(
                      'REFERENCE',
                      style: TextStyle(
                        color: Color(0xFFA78BFA),
                        fontSize: 9,
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Colors.white10),
            // Phone frame
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: AspectRatio(
                    aspectRatio: 9 / 18.5,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(28),
                        border:
                            Border.all(color: Colors.white12, width: 1),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.6),
                            blurRadius: 28,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(27),
                        child: const _MizdahPremium(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
//  THE DESIGN — full home dashboard
// ════════════════════════════════════════════════════════════════════

class _MizdahPremium extends StatefulWidget {
  const _MizdahPremium();

  @override
  State<_MizdahPremium> createState() => _MizdahPremiumState();
}

class _MizdahPremiumState extends State<_MizdahPremium>
    with TickerProviderStateMixin {
  late final AnimationController _floatCtrl;
  late final AnimationController _entryCtrl;

  @override
  void initState() {
    super.initState();
    _floatCtrl = AnimationController(
      duration: const Duration(seconds: 6),
      vsync: this,
    )..repeat(reverse: true);
    _entryCtrl = AnimationController(
      duration: const Duration(milliseconds: 700),
      vsync: this,
    )..forward();
  }

  @override
  void dispose() {
    _floatCtrl.dispose();
    _entryCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _Tokens.lavenderBg,
      child: Stack(
        children: [
          // Faint background gradient wash
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: [Color(0xFFF1EEFF), Color(0xFFFAFBFE)],
                ),
              ),
            ),
          ),

          // Scrollable content
          Positioned.fill(
            bottom: 80, // leave room for floating nav
            child: ListView(
              padding: const EdgeInsets.fromLTRB(0, 0, 0, 16),
              physics: const BouncingScrollPhysics(),
              children: [
                _Header(entryCtrl: _entryCtrl),
                _Hero(floatCtrl: _floatCtrl, entryCtrl: _entryCtrl),
                const SizedBox(height: 16),
                _ActionCardsRow(entryCtrl: _entryCtrl),
                const SizedBox(height: 24),
                _UpcomingSection(entryCtrl: _entryCtrl),
                const SizedBox(height: 14),
                const _RecentActivityCard(),
                const SizedBox(height: 16),
              ],
            ),
          ),

          // Floating bottom navigation
          const Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: _FloatingNav(),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────
//  Header
// ────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final AnimationController entryCtrl;
  const _Header({required this.entryCtrl});

  @override
  Widget build(BuildContext context) {
    return _FadeUp(
      controller: entryCtrl,
      delay: 0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 16, 8),
        child: Row(
          children: [
            // Hamburger
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.centerLeft,
              child: const Icon(
                Icons.menu_rounded,
                color: _Tokens.ink,
                size: 22,
              ),
            ),
            const Spacer(),
            // Logo + wordmark
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    gradient: _Tokens.heroGradient,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(
                    Icons.auto_awesome_rounded,
                    color: Colors.white,
                    size: 13,
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'MIZDAH',
                  style: TextStyle(
                    color: _Tokens.ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 3.5,
                  ),
                ),
              ],
            ),
            const Spacer(),
            // Bell with notification dot
            SizedBox(
              width: 36,
              height: 36,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const Icon(
                    Icons.notifications_none_rounded,
                    color: _Tokens.ink,
                    size: 22,
                  ),
                  Positioned(
                    top: 7,
                    right: 9,
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        gradient: _Tokens.heroGradient,
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: _Tokens.lavenderBg, width: 1.2),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            // Avatar
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                gradient: _Tokens.heroGradient,
                shape: BoxShape.circle,
                boxShadow: _Tokens.softShadow(elevation: 0.6),
              ),
              child: const Center(
                child: Text(
                  'A',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────
//  Hero — left text + right glass blob illustration
// ────────────────────────────────────────────────────────────────────

class _Hero extends StatelessWidget {
  final AnimationController floatCtrl;
  final AnimationController entryCtrl;
  const _Hero({required this.floatCtrl, required this.entryCtrl});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 16, 10),
      child: SizedBox(
        height: 168,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: _FadeUp(
                controller: entryCtrl,
                delay: 0.05,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    _HeroHeading(),
                    SizedBox(height: 8),
                    Text(
                      'Collaborate · Meet · Achieve',
                      style: TextStyle(
                        color: _Tokens.muted,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Glass blob illustration
            SizedBox(
              width: 130,
              height: 168,
              child: _BlobIllustration(floatCtrl: floatCtrl),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroHeading extends StatelessWidget {
  const _HeroHeading();

  @override
  Widget build(BuildContext context) {
    // "Ready to\nconnect today?" — "today" gets the gradient.
    return RichText(
      text: TextSpan(
        style: const TextStyle(
          color: _Tokens.ink,
          fontSize: 24,
          fontWeight: FontWeight.w800,
          height: 1.15,
          letterSpacing: -0.6,
        ),
        children: [
          const TextSpan(text: 'Ready to\nconnect '),
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: ShaderMask(
              shaderCallback: (rect) =>
                  _Tokens.heroGradient.createShader(rect),
              child: const Text(
                'today',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                  letterSpacing: -0.6,
                ),
              ),
            ),
          ),
          const TextSpan(text: '?'),
        ],
      ),
    );
  }
}

// Translucent blobs + orbit lines + floating icon cards.
class _BlobIllustration extends StatelessWidget {
  final AnimationController floatCtrl;
  const _BlobIllustration({required this.floatCtrl});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: floatCtrl,
      builder: (context, _) {
        // Convert 0..1..0 wave for floating motion.
        final t = math.sin(floatCtrl.value * math.pi * 2);
        return Stack(
          children: [
            // Big purple blob
            Positioned(
              top: 20 + t * 4,
              left: 10,
              child: _Blob(
                size: 90,
                colors: const [Color(0xFFB6A8FF), Color(0xFF8B5CF6)],
                opacity: 0.28,
                blur: 14,
              ),
            ),
            // Smaller indigo blob
            Positioned(
              top: 70 - t * 6,
              right: 0,
              child: _Blob(
                size: 70,
                colors: const [Color(0xFF6C63FF), Color(0xFF3B82F6)],
                opacity: 0.22,
                blur: 18,
              ),
            ),
            // Soft white wash blob
            Positioned(
              bottom: 0,
              left: 30 + t * 3,
              child: _Blob(
                size: 60,
                colors: const [Colors.white, Color(0xFFEEF2FF)],
                opacity: 0.55,
                blur: 10,
              ),
            ),
            // Orbit ring
            Positioned.fill(
              child: CustomPaint(
                painter: _OrbitPainter(progress: floatCtrl.value),
              ),
            ),
            // Floating icon — video (top right)
            Positioned(
              top: 14 + t * -3,
              right: 8,
              child: _FloatIconCard(
                icon: Icons.videocam_rounded,
                colors: const [Color(0xFF8B5CF6), Color(0xFF6C63FF)],
                size: 38,
              ),
            ),
            // Floating icon — team (right middle)
            Positioned(
              top: 70 + t * 2,
              right: 30,
              child: _FloatIconCard(
                icon: Icons.groups_rounded,
                colors: const [Color(0xFF6C63FF), Color(0xFF8B5CF6)],
                size: 32,
              ),
            ),
            // Floating icon — chat (bottom)
            Positioned(
              bottom: 24 + t * -2,
              right: 50,
              child: _FloatIconCard(
                icon: Icons.chat_bubble_rounded,
                colors: const [Color(0xFFA78BFA), Color(0xFF8B5CF6)],
                size: 26,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Blob extends StatelessWidget {
  final double size;
  final List<Color> colors;
  final double opacity;
  final double blur;
  const _Blob({
    required this.size,
    required this.colors,
    required this.opacity,
    required this.blur,
  });

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                colors[0].withValues(alpha: opacity),
                colors[1].withValues(alpha: opacity * 0.4),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OrbitPainter extends CustomPainter {
  final double progress;
  _OrbitPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2 + 6, size.height / 2 + 4);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = const Color(0xFF8B5CF6).withValues(alpha: 0.20);

    // Two soft orbit ellipses
    final r1 = math.min(size.width, size.height) * 0.55;
    final r2 = math.min(size.width, size.height) * 0.40;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(progress * math.pi * 0.1);
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset.zero, width: r1 * 2, height: r1 * 1.4),
      paint,
    );
    paint.color = const Color(0xFF6C63FF).withValues(alpha: 0.15);
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset.zero, width: r2 * 2, height: r2 * 1.6),
      paint,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_OrbitPainter old) => old.progress != progress;
}

class _FloatIconCard extends StatelessWidget {
  final IconData icon;
  final List<Color> colors;
  final double size;
  const _FloatIconCard({
    required this.icon,
    required this.colors,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(size * 0.28),
        boxShadow: [
          BoxShadow(
            color: colors[0].withValues(alpha: 0.45),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.35),
          width: 1,
        ),
      ),
      child: Icon(icon, color: Colors.white, size: size * 0.45),
    );
  }
}

// ────────────────────────────────────────────────────────────────────
//  Action cards — Start a Meeting + Join with Code
// ────────────────────────────────────────────────────────────────────

class _ActionCardsRow extends StatelessWidget {
  final AnimationController entryCtrl;
  const _ActionCardsRow({required this.entryCtrl});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _FadeUp(
              controller: entryCtrl,
              delay: 0.10,
              child: const _StartMeetingCard(),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _FadeUp(
              controller: entryCtrl,
              delay: 0.18,
              child: const _JoinCodeCard(),
            ),
          ),
        ],
      ),
    );
  }
}

class _StartMeetingCard extends StatefulWidget {
  const _StartMeetingCard();
  @override
  State<_StartMeetingCard> createState() => _StartMeetingCardState();
}

class _StartMeetingCardState extends State<_StartMeetingCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return _PressScale(
      onPressedChange: (v) => setState(() => _pressed = v),
      child: Container(
        height: 200,
        padding: const EdgeInsets.fromLTRB(18, 18, 16, 16),
        decoration: BoxDecoration(
          gradient: _Tokens.heroGradient,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6C63FF).withValues(alpha: 0.3),
              blurRadius: 24,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Curved abstract overlay shape
            Positioned(
              right: -24,
              top: -22,
              child: ClipOval(
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.10),
                  ),
                ),
              ),
            ),
            Positioned(
              right: -40,
              bottom: -30,
              child: ClipOval(
                child: Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                  ),
                ),
              ),
            ),
            // Content
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Start a',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Meeting',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Create new meeting\ninstantly',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.88),
                    fontSize: 11.5,
                    height: 1.35,
                  ),
                ),
                const Spacer(),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.22),
                          width: 0.8,
                        ),
                      ),
                      child: const Icon(Icons.videocam_rounded,
                          color: Colors.white, size: 20),
                    ),
                    const Spacer(),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(19),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.white
                                .withValues(alpha: _pressed ? 0.5 : 0.3),
                            blurRadius: _pressed ? 18 : 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.arrow_forward_rounded,
                        color: _Tokens.primary,
                        size: 20,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _JoinCodeCard extends StatelessWidget {
  const _JoinCodeCard();
  @override
  Widget build(BuildContext context) {
    return _PressScale(
      child: Container(
        height: 200,
        padding: const EdgeInsets.fromLTRB(16, 18, 14, 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: _Tokens.cardBorder, width: 1),
          boxShadow: _Tokens.softShadow(),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Join with',
              style: TextStyle(
                color: _Tokens.muted,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 2),
            const Text(
              'Meeting Code',
              style: TextStyle(
                color: _Tokens.ink,
                fontSize: 17,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Enter the code and\njoin the meeting',
              style: TextStyle(
                color: _Tokens.muted,
                fontSize: 11,
                height: 1.35,
              ),
            ),
            const Spacer(),
            // Input field
            Row(
              children: [
                Expanded(
                  child: Container(
                    height: 38,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F4F8),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.link_rounded,
                            color: _Tokens.muted, size: 14),
                        SizedBox(width: 6),
                        Text(
                          'Enter code',
                          style: TextStyle(
                            color: _Tokens.muted,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    gradient: _Tokens.heroGradient,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF6C63FF).withValues(alpha: 0.4),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.arrow_forward_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────
//  Upcoming Meetings — header + timeline list
// ────────────────────────────────────────────────────────────────────

class _UpcomingSection extends StatelessWidget {
  final AnimationController entryCtrl;
  const _UpcomingSection({required this.entryCtrl});

  @override
  Widget build(BuildContext context) {
    return _FadeUp(
      controller: entryCtrl,
      delay: 0.26,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Row(
              children: [
                const Text(
                  'Upcoming Meetings',
                  style: TextStyle(
                    color: _Tokens.ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                const Spacer(),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ShaderMask(
                      shaderCallback: (r) =>
                          _Tokens.heroGradient.createShader(r),
                      child: const Text(
                        'View all',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 2),
                    const Icon(Icons.chevron_right_rounded,
                        color: _Tokens.primary, size: 16),
                  ],
                ),
              ],
            ),
          ),
          // List card
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Container(
              padding: const EdgeInsets.fromLTRB(0, 4, 0, 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: _Tokens.cardBorder, width: 1),
                boxShadow: _Tokens.softShadow(elevation: 0.7),
              ),
              child: Column(
                children: [
                  for (var i = 0; i < _kMeetings.length; i++) ...[
                    _MeetingRow(
                      m: _kMeetings[i],
                      isFirst: i == 0,
                      isLast: i == _kMeetings.length - 1,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MeetingRow extends StatelessWidget {
  final _Meeting m;
  final bool isFirst;
  final bool isLast;
  const _MeetingRow({
    required this.m,
    required this.isFirst,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    return _PressScale(
      scaleTo: 0.98,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Date pill
            Container(
              width: 50,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: m.iconBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Text(
                    m.month,
                    style: TextStyle(
                      color: m.iconFg,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                  Text(
                    '${m.day}',
                    style: TextStyle(
                      color: m.iconFg,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.6,
                      height: 1.05,
                    ),
                  ),
                  Text(
                    m.weekday,
                    style: TextStyle(
                      color: m.iconFg.withValues(alpha: 0.75),
                      fontSize: 8,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
            // Timeline column
            SizedBox(
              width: 18,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Vertical line
                  Positioned.fill(
                    child: Padding(
                      padding: EdgeInsets.only(
                        top: isFirst ? 22 : 0,
                        bottom: isLast ? 22 : 0,
                      ),
                      child: Center(
                        child: Container(
                          width: 1.2,
                          color: _Tokens.subtleStroke,
                        ),
                      ),
                    ),
                  ),
                  // Dot
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: m.dotColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: m.dotColor.withValues(alpha: 0.4),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            // Title + time + avatars
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    m.title,
                    style: const TextStyle(
                      color: _Tokens.ink,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          m.timeRange,
                          style: const TextStyle(
                            color: _Tokens.muted,
                            fontSize: 10.5,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Text(
                        ' · ',
                        style:
                            TextStyle(color: _Tokens.muted, fontSize: 10.5),
                      ),
                      Text(
                        m.duration,
                        style: const TextStyle(
                          color: _Tokens.muted,
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  _AvatarStack(colors: m.avatars, extra: m.extra),
                ],
              ),
            ),
            const SizedBox(width: 6),
            // Action icon
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: m.iconBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.videocam_rounded,
                  color: m.iconFg, size: 16),
            ),
          ],
        ),
      ),
    );
  }
}

class _AvatarStack extends StatelessWidget {
  final List<Color> colors;
  final int extra;
  const _AvatarStack({required this.colors, required this.extra});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 18,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < colors.length; i++)
            Positioned(
              left: i * 12.0,
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: colors[i],
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
              ),
            ),
          Positioned(
            left: colors.length * 12.0 + 4,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: const Color(0xFFEEF2FF),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '+$extra',
                style: const TextStyle(
                  color: _Tokens.primary,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
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
//  Recent activity card
// ────────────────────────────────────────────────────────────────────

class _RecentActivityCard extends StatelessWidget {
  const _RecentActivityCard();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 4),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _Tokens.cardBorder, width: 1),
          boxShadow: _Tokens.softShadow(elevation: 0.5),
        ),
        child: Stack(
          children: [
            // Diagonal background pattern (very subtle)
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: CustomPaint(
                  painter: _DiagonalPattern(),
                ),
              ),
            ),
            Row(
              children: [
                // Pulse icon
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF2FF),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.show_chart_rounded,
                    color: _Tokens.primary,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'Recent Activity',
                        style: TextStyle(
                          color: _Tokens.muted,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'You created a meeting',
                        style: TextStyle(
                          color: _Tokens.ink,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 1),
                      Text(
                        'Product Strategy Meeting',
                        style: TextStyle(
                          color: _Tokens.muted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                const Text(
                  'Today, 5:30 PM',
                  style: TextStyle(
                    color: _Tokens.muted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DiagonalPattern extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF6C63FF).withValues(alpha: 0.025)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;
    const step = 12.0;
    // Diagonal lines from top-right to bottom-left
    for (double x = -size.height; x < size.width; x += step) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x + size.height, size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DiagonalPattern old) => false;
}

// ────────────────────────────────────────────────────────────────────
//  Floating bottom navigation
// ────────────────────────────────────────────────────────────────────

class _FloatingNav extends StatelessWidget {
  const _FloatingNav();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: _Tokens.cardBorder, width: 1),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF6C63FF).withValues(alpha: 0.1),
                blurRadius: 28,
                offset: const Offset(0, 12),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: const Row(
            children: [
              Expanded(
                child: _NavItem(
                  icon: Icons.home_rounded,
                  label: 'Home',
                  active: true,
                ),
              ),
              Expanded(
                child: _NavItem(
                  icon: Icons.calendar_month_rounded,
                  label: 'Meetings',
                ),
              ),
              Expanded(
                child: _NavItem(
                  icon: Icons.people_outline_rounded,
                  label: 'People',
                ),
              ),
              Expanded(
                child: _NavItem(
                  icon: Icons.settings_outlined,
                  label: 'Settings',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  const _NavItem({
    required this.icon,
    required this.label,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    if (active) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ShaderMask(
            shaderCallback: (r) => _Tokens.heroGradient.createShader(r),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
          const SizedBox(height: 3),
          ShaderMask(
            shaderCallback: (r) => _Tokens.heroGradient.createShader(r),
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          // Glow indicator
          Container(
            margin: const EdgeInsets.only(top: 3),
            width: 16,
            height: 3,
            decoration: BoxDecoration(
              gradient: _Tokens.heroGradient,
              borderRadius: BorderRadius.circular(2),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF6C63FF).withValues(alpha: 0.5),
                  blurRadius: 6,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
          ),
        ],
      );
    }
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: const Color(0xFF8A8FA0), size: 22),
        const SizedBox(height: 3),
        const Text(
          '',
          style: TextStyle(fontSize: 10),
        ),
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

// ────────────────────────────────────────────────────────────────────
//  Helpers — fade-up entry animation, press-scale gesture
// ────────────────────────────────────────────────────────────────────

class _FadeUp extends StatelessWidget {
  final AnimationController controller;
  final double delay;
  final Widget child;
  const _FadeUp({
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

class _PressScale extends StatefulWidget {
  final Widget child;
  final double scaleTo;
  final ValueChanged<bool>? onPressedChange;
  const _PressScale({
    required this.child,
    this.scaleTo = 0.97,
    this.onPressedChange,
  });
  @override
  State<_PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<_PressScale> {
  bool _pressed = false;
  void _set(bool v) {
    if (_pressed == v) return;
    setState(() => _pressed = v);
    widget.onPressedChange?.call(v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
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
