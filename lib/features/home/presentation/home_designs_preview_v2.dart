import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Round 2 of home-screen design concepts. Five fresh layouts that
/// go in a different direction from the V1 gallery: bento grids,
/// editorial typography, mesh-gradient glass, spatial stacks, and
/// mono-minimal. None of these share the structure of V1's six —
/// they're alternative aesthetics, not refinements.
///
/// Same contract as V1: this is preview-only. The live
/// `home_screen.dart` is unchanged. When you pick a winner, point
/// it out and the agent will port it onto production.
class HomeDesignsPreviewV2Screen extends StatefulWidget {
  const HomeDesignsPreviewV2Screen({super.key});

  @override
  State<HomeDesignsPreviewV2Screen> createState() =>
      _HomeDesignsPreviewV2ScreenState();
}

class _HomeDesignsPreviewV2ScreenState
    extends State<HomeDesignsPreviewV2Screen> {
  int _variant = 0;

  static const List<_Spec> _specs = [
    _Spec('Bento', 'Mixed-size tile grid, Apple iOS 17 bento aesthetic'),
    _Spec('Aurora Glass', 'Mesh gradient + heavy frosted glass, Vision Pro feel'),
    _Spec('Editorial', 'Big display type + full-bleed hero, magazine layout'),
    _Spec('Spatial Stack', 'Overlapping 3D cards, Apple Wallet on steroids'),
    _Spec('Mono', 'Black/white minimalism with monospace numerics'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0F1F),
      body: SafeArea(
        child: Column(
          children: [
            _buildToolbar(),
            const Divider(height: 1, color: Colors.white10),
            Expanded(child: _buildPreviewFrame()),
            const Divider(height: 1, color: Colors.white10),
            _buildVariantChips(),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbar() {
    final spec = _specs[_variant];
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => context.pop(),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  spec.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  spec.description,
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 11,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${_variant + 1} / ${_specs.length}',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVariantChips() {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: _specs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final selected = i == _variant;
          return ChoiceChip(
            label: Text(_specs[i].name),
            selected: selected,
            onSelected: (_) => setState(() => _variant = i),
            backgroundColor: Colors.white.withValues(alpha: 0.06),
            selectedColor: const Color(0xFF6366F1),
            labelStyle: TextStyle(
              color: selected ? Colors.white : Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(
                color: selected ? Colors.transparent : Colors.white12,
              ),
            ),
            showCheckmark: false,
          );
        },
      ),
    );
  }

  Widget _buildPreviewFrame() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: AspectRatio(
          aspectRatio: 9 / 18.5,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Colors.white12, width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(27),
              child: _renderVariant(_variant),
            ),
          ),
        ),
      ),
    );
  }

  Widget _renderVariant(int index) {
    switch (index) {
      case 0:
        return const _Bento();
      case 1:
        return const _AuroraGlass();
      case 2:
        return const _Editorial();
      case 3:
        return const _SpatialStack();
      case 4:
        return const _Mono();
      default:
        return const SizedBox.shrink();
    }
  }
}

class _Spec {
  final String name;
  final String description;
  const _Spec(this.name, this.description);
}

// ════════════════════════════════════════════════════════════════════
//  Shared mock data — same across all variants for fair comparison.
// ════════════════════════════════════════════════════════════════════

class _Mtg {
  final String title;
  final String when;
  final String code;
  const _Mtg(this.title, this.when, this.code);
}

const _kUpcoming = <_Mtg>[
  _Mtg('Design review', 'Today · 4:30 PM', 'jhmyqrneac'),
  _Mtg('Standup', 'Tomorrow · 10:00 AM', 'ctqrskhqxv'),
  _Mtg('1:1 with Alex', 'Fri · 2:00 PM', 'emeblvocot'),
];

const _kUserName = 'Tanmay';

// ════════════════════════════════════════════════════════════════════
//  V1 — BENTO  (Apple iOS 17+ multi-size tile grid)
// ════════════════════════════════════════════════════════════════════

class _Bento extends StatelessWidget {
  const _Bento();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF5F5F7),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 24),
        children: [
          // Greeting row
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Good evening',
                      style: TextStyle(
                        fontSize: 14,
                        color: Color(0xFF6B6B70),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _kUserName,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0A0A0F),
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Center(
                  child: Text(
                    'T',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Bento grid — top row (large + small stacked)
          SizedBox(
            height: 180,
            child: Row(
              children: [
                // Big: New meeting
                Expanded(
                  flex: 3,
                  child: _BentoBigTile(
                    label: 'Start meeting',
                    sub: 'Instant',
                    icon: Icons.videocam_rounded,
                    bg: const Color(0xFF6366F1),
                    fg: Colors.white,
                  ),
                ),
                const SizedBox(width: 10),
                // Two small stacked
                Expanded(
                  flex: 2,
                  child: Column(
                    children: [
                      Expanded(
                        child: _BentoSmallTile(
                          label: 'Join',
                          icon: Icons.input_rounded,
                          bg: Colors.white,
                          fg: Color(0xFF0A0A0F),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: _BentoSmallTile(
                          label: 'Schedule',
                          icon: Icons.event_rounded,
                          bg: Color(0xFF0A0A0F),
                          fg: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Stats banner
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFFE4E6), Color(0xFFE0E7FF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                _bentoStat('4h 12m', 'this week'),
                const _BentoVDivider(),
                _bentoStat('12', 'meetings'),
                const _BentoVDivider(),
                _bentoStat('3', 'upcoming'),
              ],
            ),
          ),
          const SizedBox(height: 18),

          const _BentoSectionHeader('Upcoming'),
          const SizedBox(height: 8),
          for (final m in _kUpcoming) ...[
            _BentoMeetingRow(m: m),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  Widget _bentoStat(String big, String small) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            big,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0A0A0F),
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            small,
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF6B6B70),
            ),
          ),
        ],
      ),
    );
  }
}

class _BentoBigTile extends StatelessWidget {
  final String label;
  final String sub;
  final IconData icon;
  final Color bg;
  final Color fg;
  const _BentoBigTile({
    required this.label,
    required this.sub,
    required this.icon,
    required this.bg,
    required this.fg,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: fg, size: 30),
          const Spacer(),
          Text(
            sub,
            style: TextStyle(
              fontSize: 12,
              color: fg.withValues(alpha: 0.7),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 18,
              color: fg,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _BentoSmallTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color bg;
  final Color fg;
  const _BentoSmallTile({
    required this.label,
    required this.icon,
    required this.bg,
    required this.fg,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E5EA), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: fg, size: 22),
          const Spacer(),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: fg,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _BentoVDivider extends StatelessWidget {
  const _BentoVDivider();
  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: 28,
        color: Colors.black.withValues(alpha: 0.08),
        margin: const EdgeInsets.symmetric(horizontal: 8),
      );
}

class _BentoSectionHeader extends StatelessWidget {
  final String label;
  const _BentoSectionHeader(this.label);
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: Color(0xFF0A0A0F),
            letterSpacing: -0.2,
          ),
        ),
        const Text(
          'See all',
          style: TextStyle(
            fontSize: 12,
            color: Color(0xFF6366F1),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _BentoMeetingRow extends StatelessWidget {
  final _Mtg m;
  const _BentoMeetingRow({required this.m});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E5EA), width: 0.5),
      ),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 32,
            decoration: BoxDecoration(
              color: const Color(0xFF6366F1),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  m.title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0A0A0F),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  m.when,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF6B6B70),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF6366F1).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'Join',
              style: TextStyle(
                fontSize: 12,
                color: Color(0xFF6366F1),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
//  V2 — AURORA GLASS  (Mesh gradient + heavy glassmorphism)
// ════════════════════════════════════════════════════════════════════

class _AuroraGlass extends StatelessWidget {
  const _AuroraGlass();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Mesh gradient backdrop
        Positioned.fill(
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF1E1B4B),
                  Color(0xFF312E81),
                  Color(0xFF7C3AED),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          top: -60,
          right: -40,
          child: _glow(180, const Color(0xFFEC4899)),
        ),
        Positioned(
          bottom: 100,
          left: -60,
          child: _glow(220, const Color(0xFF06B6D4)),
        ),
        Positioned(
          top: 200,
          right: -30,
          child: _glow(140, const Color(0xFFA78BFA)),
        ),

        // Content
        SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              // Top bar
              Row(
                children: [
                  _glassPill(
                    child: const Icon(Icons.menu_rounded,
                        color: Colors.white, size: 18),
                  ),
                  const Spacer(),
                  _glassPill(
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6),
                      child: Text(
                        'MIZDAH',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  _glassPill(
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: const Center(
                        child: Text('T',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            )),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),

              // Greeting
              const Text(
                'Hello,',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.white70,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Text(
                _kUserName,
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(height: 24),

              // Hero glass card
              _glass(
                padding: const EdgeInsets.all(18),
                radius: 24,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(Icons.videocam_rounded,
                              color: Colors.white),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Start meeting',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  )),
                              SizedBox(height: 2),
                              Text('Instant · HD · End-to-end secure',
                                  style: TextStyle(
                                    color: Colors.white60,
                                    fontSize: 11,
                                  )),
                            ],
                          ),
                        ),
                        const Icon(Icons.arrow_forward_rounded,
                            color: Colors.white, size: 18),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Two-up secondary actions
              Row(
                children: [
                  Expanded(
                    child: _glass(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 16),
                      radius: 18,
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.input_rounded,
                              color: Colors.white, size: 22),
                          SizedBox(height: 8),
                          Text('Join',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              )),
                          SizedBox(height: 1),
                          Text('Enter code',
                              style: TextStyle(
                                color: Colors.white60,
                                fontSize: 10,
                              )),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _glass(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 16),
                      radius: 18,
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.event_rounded,
                              color: Colors.white, size: 22),
                          SizedBox(height: 8),
                          Text('Schedule',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              )),
                          SizedBox(height: 1),
                          Text('Pick time',
                              style: TextStyle(
                                color: Colors.white60,
                                fontSize: 10,
                              )),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),

              // Upcoming list (glass rows)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Text('Upcoming',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                    )),
              ),
              const SizedBox(height: 8),
              for (final m in _kUpcoming) ...[
                _glass(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  radius: 16,
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.calendar_today_rounded,
                            color: Colors.white, size: 14),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(m.title,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                )),
                            const SizedBox(height: 2),
                            Text(m.when,
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 10,
                                )),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded,
                          color: Colors.white60, size: 18),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _glow(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color.withValues(alpha: 0.5), color.withValues(alpha: 0)],
        ),
      ),
    );
  }

  Widget _glass({
    required Widget child,
    required double radius,
    required EdgeInsets padding,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.10),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.18),
              width: 1,
            ),
            borderRadius: BorderRadius.circular(radius),
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _glassPill({required Widget child}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.10),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.18),
              width: 1,
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: child,
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
//  V3 — EDITORIAL  (Magazine-style, big display type, full-bleed)
// ════════════════════════════════════════════════════════════════════

class _Editorial extends StatelessWidget {
  const _Editorial();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFFAF9F6),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          // Full-bleed hero
          Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            decoration: const BoxDecoration(
              color: Color(0xFF111111),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top row
                Row(
                  children: [
                    const Text('MIZDAH',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          letterSpacing: 4,
                          fontWeight: FontWeight.w800,
                        )),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.4)),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text('VOL · 04',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            letterSpacing: 1.5,
                            fontWeight: FontWeight.w600,
                          )),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                const Text('Tuesday',
                    style: TextStyle(
                      color: Colors.white60,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    )),
                const SizedBox(height: 4),
                const Text(
                  'A quieter\nmorning.',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 36,
                    fontWeight: FontWeight.w800,
                    height: 1.05,
                    letterSpacing: -1.5,
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Two meetings on the calendar — your '
                  'first not until 4:30.',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 20),
                // Primary CTA
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 18, vertical: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFAF9F6),
                    borderRadius: BorderRadius.circular(40),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Start a meeting',
                          style: TextStyle(
                            color: Color(0xFF111111),
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          )),
                      SizedBox(width: 8),
                      Icon(Icons.arrow_forward_rounded,
                          color: Color(0xFF111111), size: 16),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Quick join input — print-style
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 8),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 16,
                  color: const Color(0xFF111111),
                  margin: const EdgeInsets.only(right: 8),
                ),
                const Text('JOIN WITH CODE',
                    style: TextStyle(
                      color: Color(0xFF111111),
                      fontSize: 11,
                      letterSpacing: 2,
                      fontWeight: FontWeight.w800,
                    )),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF111111), width: 1.2),
              ),
              child: const Row(
                children: [
                  Expanded(
                    child: Text(
                      'abc · defg · hij',
                      style: TextStyle(
                        fontSize: 16,
                        color: Color(0xFF111111),
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  Icon(Icons.arrow_forward_rounded,
                      color: Color(0xFF111111), size: 20),
                ],
              ),
            ),
          ),

          // Today section header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 16,
                  color: const Color(0xFF111111),
                  margin: const EdgeInsets.only(right: 8),
                ),
                const Text('TODAY · 3 ITEMS',
                    style: TextStyle(
                      color: Color(0xFF111111),
                      fontSize: 11,
                      letterSpacing: 2,
                      fontWeight: FontWeight.w800,
                    )),
              ],
            ),
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < _kUpcoming.length; i++) ...[
            _editorialMtg(_kUpcoming[i], i + 1),
            if (i != _kUpcoming.length - 1)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                height: 1,
                color: const Color(0xFF111111).withValues(alpha: 0.1),
              ),
          ],
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _editorialMtg(_Mtg m, int n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28,
            child: Text(
              n.toString().padLeft(2, '0'),
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF6B6B70),
                fontFeatures: [FontFeature.tabularFigures()],
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(m.title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF111111),
                      letterSpacing: -0.4,
                    )),
                const SizedBox(height: 4),
                Text(m.when.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFF6B6B70),
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.w700,
                    )),
              ],
            ),
          ),
          const Icon(Icons.arrow_outward_rounded,
              color: Color(0xFF111111), size: 18),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
//  V4 — SPATIAL STACK  (Overlapping 3D cards, Wallet-on-steroids)
// ════════════════════════════════════════════════════════════════════

class _SpatialStack extends StatelessWidget {
  const _SpatialStack();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top bar
              Row(
                children: [
                  const Text('Mizdah',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        letterSpacing: -0.3,
                      )),
                  const Spacer(),
                  _topIcon(Icons.search_rounded),
                  const SizedBox(width: 8),
                  _topIcon(Icons.notifications_outlined),
                ],
              ),
              const SizedBox(height: 22),

              // Greeting
              const Text('Welcome back,',
                  style: TextStyle(color: Colors.white60, fontSize: 13)),
              const SizedBox(height: 2),
              const Text(_kUserName,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  )),
              const SizedBox(height: 18),

              // Spatial card stack
              Expanded(
                child: _SpatialCardDeck(meetings: _kUpcoming),
              ),

              const SizedBox(height: 14),

              // Bottom action bar — pill of three
              Container(
                height: 64,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(40),
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08), width: 1),
                ),
                child: Row(
                  children: [
                    Expanded(child: _bottomAction(Icons.input_rounded, 'Join')),
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6366F1),
                          borderRadius: BorderRadius.circular(40),
                        ),
                        child: const Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.videocam_rounded,
                                  color: Colors.white, size: 18),
                              SizedBox(width: 6),
                              Text('Start',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  )),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: _bottomAction(Icons.event_rounded, 'Plan'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topIcon(IconData icon) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: Colors.white, size: 18),
    );
  }

  Widget _bottomAction(IconData icon, String label) {
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white70, size: 18),
          const SizedBox(width: 6),
          Text(label,
              style: const TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              )),
        ],
      ),
    );
  }
}

class _SpatialCardDeck extends StatelessWidget {
  final List<_Mtg> meetings;
  const _SpatialCardDeck({required this.meetings});

  @override
  Widget build(BuildContext context) {
    final colors = const [
      [Color(0xFF6366F1), Color(0xFF8B5CF6)],
      [Color(0xFFEC4899), Color(0xFFF59E0B)],
      [Color(0xFF10B981), Color(0xFF06B6D4)],
    ];

    return LayoutBuilder(
      builder: (context, c) {
        final h = c.maxHeight;
        final cardH = h * 0.62;
        final stagger = (h - cardH) / (meetings.length - 1).clamp(1, 99);

        return Stack(
          children: [
            for (var i = meetings.length - 1; i >= 0; i--)
              Positioned(
                left: 0,
                right: 0,
                top: i * stagger,
                child: Transform.scale(
                  scale: 1.0 - (i * 0.04),
                  child: Container(
                    height: cardH,
                    margin: EdgeInsets.symmetric(horizontal: i * 6.0),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: colors[i % colors.length],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: [
                        BoxShadow(
                          color:
                              colors[i % colors.length][0].withValues(alpha: 0.4),
                          blurRadius: 32,
                          offset: const Offset(0, 16),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(20),
                    child: i == 0
                        ? _topCard(meetings[i])
                        : _shadowCard(meetings[i]),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _topCard(_Mtg m) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text('NEXT UP',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.w700,
                  )),
            ),
            const Spacer(),
            const Icon(Icons.more_horiz_rounded, color: Colors.white),
          ],
        ),
        const Spacer(),
        Text(m.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
              height: 1.1,
            )),
        const SizedBox(height: 6),
        Text(m.when,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 13,
            )),
        const SizedBox(height: 14),
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(30),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.videocam_rounded,
                  size: 16, color: Color(0xFF111111)),
              SizedBox(width: 6),
              Text('Join now',
                  style: TextStyle(
                    color: Color(0xFF111111),
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  )),
            ],
          ),
        ),
      ],
    );
  }

  Widget _shadowCard(_Mtg m) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(m.when,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 11,
                  )),
              const SizedBox(height: 2),
              Text(m.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  )),
            ],
          ),
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════
//  V5 — MONO  (Black/white minimalism, monospace numerics)
// ════════════════════════════════════════════════════════════════════

class _Mono extends StatelessWidget {
  const _Mono();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            // Top
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: const Center(
                    child: Text('M',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                        )),
                  ),
                ),
                const SizedBox(width: 10),
                const Text('Mizdah',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                    )),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    border:
                        Border.all(color: Colors.black.withValues(alpha: 0.15)),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('⌘ K',
                      style: TextStyle(
                        color: Colors.black54,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      )),
                ),
              ],
            ),
            const SizedBox(height: 32),

            const Text('Today',
                style: TextStyle(
                  color: Colors.black54,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                )),
            const SizedBox(height: 4),
            const Text(
              'Three meetings.',
              style: TextStyle(
                color: Colors.black,
                fontSize: 28,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.8,
              ),
            ),
            const SizedBox(height: 24),

            // Action row — flat outlined
            _MonoAction(
              label: 'Start a meeting',
              detail: 'Instant · No code',
              icon: Icons.videocam_outlined,
              filled: true,
            ),
            const SizedBox(height: 8),
            _MonoAction(
              label: 'Join with a code',
              detail: 'abc · defg · hij',
              icon: Icons.input_rounded,
              filled: false,
            ),
            const SizedBox(height: 8),
            _MonoAction(
              label: 'Schedule',
              detail: 'Pick a day & time',
              icon: Icons.event_outlined,
              filled: false,
            ),
            const SizedBox(height: 28),

            // Hairline divider with label
            Row(
              children: [
                const Text('UPCOMING',
                    style: TextStyle(
                      color: Colors.black54,
                      fontSize: 10,
                      letterSpacing: 2,
                      fontWeight: FontWeight.w700,
                    )),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    height: 1,
                    color: Colors.black.withValues(alpha: 0.12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            for (final m in _kUpcoming) _monoMtgRow(m),
          ],
        ),
      ),
    );
  }

  Widget _monoMtgRow(_Mtg m) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 76,
            child: Text(
              m.when.split(' · ').last,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(m.title,
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    )),
                const SizedBox(height: 3),
                Text(
                  m.code,
                  style: const TextStyle(
                    color: Colors.black54,
                    fontSize: 11,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(Icons.arrow_forward_rounded,
                color: Colors.black, size: 16),
          ),
        ],
      ),
    );
  }
}

class _MonoAction extends StatelessWidget {
  final String label;
  final String detail;
  final IconData icon;
  final bool filled;
  const _MonoAction({
    required this.label,
    required this.detail,
    required this.icon,
    required this.filled,
  });
  @override
  Widget build(BuildContext context) {
    final fg = filled ? Colors.white : Colors.black;
    final bg = filled ? Colors.black : Colors.white;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: filled
            ? null
            : Border.all(color: Colors.black.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          Icon(icon, color: fg, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                      color: fg,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    )),
                const SizedBox(height: 2),
                Text(detail,
                    style: TextStyle(
                      color: fg.withValues(alpha: 0.65),
                      fontSize: 11,
                    )),
              ],
            ),
          ),
          Icon(Icons.arrow_forward_rounded, color: fg, size: 16),
        ],
      ),
    );
  }
}
