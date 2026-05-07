import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Round 3 — proper premium aesthetics. Five designs that lean into
/// restraint, depth, and sophisticated palettes rather than gimmicks.
/// Each takes inspiration from a category of high-end apps:
///
///   1. Obsidian   — black + electric cyan, like Linear Pro / a premium watch face
///   2. Ivory      — pristine white luxury, like Apple keynote slides
///   3. Twilight   — sunset mesh gradient with cream cards, premium magazine feel
///   4. Chrome     — brushed metallic gradients with deep shadows, premium tech
///   5. Concierge  — deep navy + warm gold + serif headings, luxury hotel app
///
/// Same contract as V1/V2: production home_screen.dart is untouched.
/// Pick one and the agent ports it.
class HomeDesignsPreviewV3Screen extends StatefulWidget {
  const HomeDesignsPreviewV3Screen({super.key});

  @override
  State<HomeDesignsPreviewV3Screen> createState() =>
      _HomeDesignsPreviewV3ScreenState();
}

class _HomeDesignsPreviewV3ScreenState
    extends State<HomeDesignsPreviewV3Screen> {
  int _variant = 0;

  static const List<_Spec> _specs = [
    _Spec('Obsidian', 'Pure black + electric cyan, premium watch-face minimalism'),
    _Spec('Ivory', 'Pristine white luxury, generous whitespace, Apple keynote feel'),
    _Spec('Twilight', 'Sunset mesh gradient with cream overlays, magazine premium'),
    _Spec('Chrome', 'Brushed metallic depth with multi-layer shadows'),
    _Spec('Concierge', 'Deep navy + warm gold + serif headings, hotel luxury'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
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
                Text(spec.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    )),
                const SizedBox(height: 2),
                Text(spec.description,
                    style: const TextStyle(color: Colors.white60, fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
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
            selectedColor: const Color(0xFFC9A961),
            labelStyle: TextStyle(
              color: selected ? Colors.black : Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w700,
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
                  color: Colors.black.withValues(alpha: 0.6),
                  blurRadius: 28,
                  offset: const Offset(0, 10),
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
        return const _Obsidian();
      case 1:
        return const _Ivory();
      case 2:
        return const _Twilight();
      case 3:
        return const _Chrome();
      case 4:
        return const _Concierge();
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
//  V1 — OBSIDIAN  (Black + electric cyan, premium watch-face minimal)
// ════════════════════════════════════════════════════════════════════

class _Obsidian extends StatelessWidget {
  const _Obsidian();
  static const _accent = Color(0xFF00E6CC);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0A0A0A),
      child: Stack(
        children: [
          // Subtle accent glow at top-right
          Positioned(
            top: -80,
            right: -60,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    _accent.withValues(alpha: 0.25),
                    _accent.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
              children: [
                // Top bar — minimal
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: _accent.withValues(alpha: 0.35), width: 0.5),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.circle, color: _accent, size: 6),
                          SizedBox(width: 5),
                          Text('LIVE',
                              style: TextStyle(
                                color: _accent,
                                fontSize: 9,
                                letterSpacing: 1.5,
                                fontWeight: FontWeight.w800,
                              )),
                        ],
                      ),
                    ),
                    const Spacer(),
                    const Icon(Icons.notifications_none_rounded,
                        color: Colors.white70, size: 20),
                    const SizedBox(width: 16),
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white12, width: 0.5),
                      ),
                      child: const Center(
                        child: Text('T',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            )),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 36),

                // Hero — restrained typography
                Row(
                  children: [
                    Container(
                      width: 28,
                      height: 1,
                      color: _accent,
                    ),
                    const SizedBox(width: 10),
                    const Text('TUESDAY · 6:42 PM',
                        style: TextStyle(
                          color: Colors.white60,
                          fontSize: 10,
                          letterSpacing: 2.5,
                          fontWeight: FontWeight.w700,
                        )),
                  ],
                ),
                const SizedBox(height: 14),
                const Text(
                  'Welcome\nback,',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 38,
                    height: 1.0,
                    letterSpacing: -1.5,
                    fontWeight: FontWeight.w200,
                  ),
                ),
                const Text(
                  _kUserName,
                  style: TextStyle(
                    color: _accent,
                    fontSize: 38,
                    height: 1.0,
                    letterSpacing: -1.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 34),

                // Primary action — full-width pill with glow
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 18),
                  decoration: BoxDecoration(
                    color: _accent,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: _accent.withValues(alpha: 0.4),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.videocam_rounded,
                          color: Colors.black, size: 22),
                      SizedBox(width: 10),
                      Text('Start meeting',
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                          )),
                      Spacer(),
                      Icon(Icons.arrow_forward_rounded,
                          color: Colors.black, size: 20),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Secondary actions — outlined, dark
                Row(
                  children: [
                    Expanded(child: _OutlineAction('Join', Icons.input_rounded)),
                    const SizedBox(width: 12),
                    Expanded(
                        child: _OutlineAction('Schedule', Icons.event_rounded)),
                  ],
                ),
                const SizedBox(height: 36),

                // Upcoming — just hairline dividers, very minimal
                Row(
                  children: [
                    const Text('UPCOMING',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          letterSpacing: 3,
                          fontWeight: FontWeight.w700,
                        )),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white24, width: 0.5),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('03',
                          style: TextStyle(
                            color: Colors.white60,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            fontFeatures: [FontFeature.tabularFigures()],
                          )),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Container(height: 1, color: Colors.white12),
                for (final m in _kUpcoming)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: const BoxDecoration(
                      border: Border(
                          bottom:
                              BorderSide(color: Colors.white10, width: 0.5)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: _accent,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(m.title,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: -0.2,
                                  )),
                              const SizedBox(height: 2),
                              Text(m.when,
                                  style: const TextStyle(
                                    color: Colors.white54,
                                    fontSize: 11,
                                  )),
                            ],
                          ),
                        ),
                        const Icon(Icons.arrow_forward_rounded,
                            color: Colors.white38, size: 16),
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

class _OutlineAction extends StatelessWidget {
  final String label;
  final IconData icon;
  const _OutlineAction(this.label, this.icon);
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12, width: 0.5),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white70, size: 18),
          const SizedBox(width: 8),
          Text(label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              )),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
//  V2 — IVORY  (Pristine white luxury, generous whitespace)
// ════════════════════════════════════════════════════════════════════

class _Ivory extends StatelessWidget {
  const _Ivory();
  static const _ink = Color(0xFF14181F);
  static const _muted = Color(0xFF8A8A92);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFFAFAFA),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
          children: [
            // Top bar — centered logo
            Row(
              children: [
                const Icon(Icons.menu_rounded, color: _ink, size: 22),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: _ink,
                    borderRadius: BorderRadius.circular(40),
                  ),
                  child: const Text('MIZDAH',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 3,
                      )),
                ),
                const Spacer(),
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: _ink,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Center(
                    child: Text('T',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        )),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 60),

            // Hero — generous space, classy split
            const Text('Welcome,',
                style: TextStyle(
                  color: _muted,
                  fontSize: 18,
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w400,
                )),
            const SizedBox(height: 6),
            const Text(
              _kUserName,
              style: TextStyle(
                color: _ink,
                fontSize: 44,
                fontWeight: FontWeight.w800,
                letterSpacing: -1.8,
                height: 1.0,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Your day looks light.\nThree meetings ahead.',
              style: TextStyle(
                color: _muted,
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 44),

            // One bold primary
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
              decoration: BoxDecoration(
                color: _ink,
                borderRadius: BorderRadius.circular(60),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.videocam_rounded,
                      color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Text('Start a meeting',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      )),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Two outlined secondary
            Row(
              children: [
                Expanded(child: _ivoryOutlined('Join', Icons.input_rounded)),
                const SizedBox(width: 12),
                Expanded(
                    child: _ivoryOutlined('Schedule', Icons.event_rounded)),
              ],
            ),
            const SizedBox(height: 48),

            // Upcoming — clean cards, lots of whitespace
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Today',
                    style: TextStyle(
                      color: _ink,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                    )),
                Text('${_kUpcoming.length} meetings',
                    style: const TextStyle(
                      color: _muted,
                      fontSize: 12,
                    )),
              ],
            ),
            const SizedBox(height: 18),
            for (final m in _kUpcoming) ...[
              _ivoryMtg(m),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }

  Widget _ivoryOutlined(String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(60),
        border: Border.all(color: _ink.withValues(alpha: 0.15), width: 1),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: _ink, size: 18),
          const SizedBox(width: 6),
          Text(label,
              style: const TextStyle(
                color: _ink,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              )),
        ],
      ),
    );
  }

  Widget _ivoryMtg(_Mtg m) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _ink.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(m.when,
                    style: const TextStyle(
                      color: _muted,
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                    )),
                const SizedBox(height: 6),
                Text(m.title,
                    style: const TextStyle(
                      color: _ink,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                    )),
              ],
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _ink,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Open',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    )),
                SizedBox(width: 4),
                Icon(Icons.arrow_outward_rounded,
                    color: Colors.white, size: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
//  V3 — TWILIGHT  (Sunset mesh gradient, cream cards, magazine premium)
// ════════════════════════════════════════════════════════════════════

class _Twilight extends StatelessWidget {
  const _Twilight();
  static const _cream = Color(0xFFF5EDD8);
  static const _ink = Color(0xFF1A0F2E);

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF1A0F2E),
                  Color(0xFF6B2D5C),
                  Color(0xFFD4458B),
                  Color(0xFFFF8A50),
                ],
                stops: [0.0, 0.4, 0.75, 1.0],
              ),
            ),
          ),
        ),
        // Soft glow accents
        Positioned(
          top: -50,
          right: -80,
          child: _glow(220, const Color(0xFFFFD8A8)),
        ),
        Positioned(
          bottom: 200,
          left: -100,
          child: _glow(260, const Color(0xFF8A4FFF)),
        ),

        SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
            children: [
              // Top — minimal pill
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.2),
                              width: 0.5),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.brightness_3_rounded,
                                color: Colors.white, size: 14),
                            SizedBox(width: 6),
                            Text('Twilight',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                )),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  const Icon(Icons.search_rounded,
                      color: Colors.white, size: 22),
                ],
              ),
              const SizedBox(height: 32),

              // Hero on gradient — magazine-style
              const Text('GOOD EVENING',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    letterSpacing: 3,
                    fontWeight: FontWeight.w700,
                  )),
              const SizedBox(height: 8),
              const Text(
                'Tanmay,',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 44,
                  fontWeight: FontWeight.w800,
                  height: 1.0,
                  letterSpacing: -1.8,
                ),
              ),
              const Text(
                'shall we begin?',
                style: TextStyle(
                  color: Color(0xFFFFE4B5),
                  fontSize: 24,
                  fontWeight: FontWeight.w300,
                  fontStyle: FontStyle.italic,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 28),

              // Hero cream card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: _cream,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF1A0F2E).withValues(alpha: 0.3),
                      blurRadius: 24,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: _ink,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text('NEXT UP',
                              style: TextStyle(
                                color: _cream,
                                fontSize: 9,
                                letterSpacing: 1.5,
                                fontWeight: FontWeight.w800,
                              )),
                        ),
                        const Spacer(),
                        Text(_kUpcoming[0].when,
                            style: const TextStyle(
                              color: _ink,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              fontStyle: FontStyle.italic,
                            )),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(_kUpcoming[0].title,
                        style: const TextStyle(
                          color: _ink,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        )),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 12),
                      decoration: BoxDecoration(
                        color: _ink,
                        borderRadius: BorderRadius.circular(40),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.videocam_rounded,
                              color: _cream, size: 16),
                          SizedBox(width: 6),
                          Text('Start now',
                              style: TextStyle(
                                color: _cream,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              )),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Two-up glass actions
              Row(
                children: [
                  Expanded(child: _glassAction('Join', Icons.input_rounded)),
                  const SizedBox(width: 10),
                  Expanded(
                      child: _glassAction('Schedule', Icons.event_rounded)),
                ],
              ),
              const SizedBox(height: 26),

              // Upcoming chapters
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Text('UPCOMING · LATER',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      letterSpacing: 2.5,
                      fontWeight: FontWeight.w800,
                    )),
              ),
              const SizedBox(height: 12),
              for (var i = 1; i < _kUpcoming.length; i++) ...[
                _twilightRow(_kUpcoming[i]),
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
          colors: [color.withValues(alpha: 0.4), color.withValues(alpha: 0)],
        ),
      ),
    );
  }

  Widget _glassAction(String label, IconData icon) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: Colors.white.withValues(alpha: 0.2), width: 0.5),
          ),
          child: Row(
            children: [
              Icon(icon, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Text(label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _twilightRow(_Mtg m) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.10),
            border: Border.all(
                color: Colors.white.withValues(alpha: 0.15), width: 0.5),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        )),
                    const SizedBox(height: 2),
                    Text(m.when,
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                        )),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: Colors.white60, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
//  V4 — CHROME  (Brushed metallic depth, multi-layer shadows)
// ════════════════════════════════════════════════════════════════════

class _Chrome extends StatelessWidget {
  const _Chrome();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A1A1F), Color(0xFF2A2A33), Color(0xFF1A1A1F)],
        ),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
          children: [
            // Top bar — chrome aesthetic
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withValues(alpha: 0.06),
                    Colors.white.withValues(alpha: 0.02),
                  ],
                ),
                borderRadius: BorderRadius.circular(40),
                border: Border.all(color: Colors.white12, width: 0.5),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFE5E7EB), Color(0xFF9CA3AF)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Center(
                      child: Text('M',
                          style: TextStyle(
                            color: Color(0xFF1A1A1F),
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          )),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text('Mizdah',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                      )),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.white.withValues(alpha: 0.10),
                          Colors.white.withValues(alpha: 0.04),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white12, width: 0.5),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.workspace_premium_rounded,
                            color: Color(0xFFE5C07B), size: 14),
                        SizedBox(width: 4),
                        Text('PRO',
                            style: TextStyle(
                              color: Color(0xFFE5C07B),
                              fontSize: 10,
                              letterSpacing: 1.2,
                              fontWeight: FontWeight.w800,
                            )),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // Hero card — multi-layer chrome
            Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF373741), Color(0xFF1F1F26)],
                ),
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 32,
                    offset: const Offset(0, 16),
                  ),
                  BoxShadow(
                    color: Colors.white.withValues(alpha: 0.04),
                    blurRadius: 1,
                    offset: const Offset(0, 1),
                  ),
                ],
                border: Border.all(color: Colors.white12, width: 0.5),
              ),
              child: Stack(
                children: [
                  // Subtle top highlight
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      height: 1,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.transparent,
                            Colors.white.withValues(alpha: 0.3),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color:
                                    const Color(0xFFE5C07B).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color: const Color(0xFFE5C07B)
                                        .withValues(alpha: 0.4),
                                    width: 0.5),
                              ),
                              child: const Text('INSTANT',
                                  style: TextStyle(
                                    color: Color(0xFFE5C07B),
                                    fontSize: 9,
                                    letterSpacing: 1.5,
                                    fontWeight: FontWeight.w800,
                                  )),
                            ),
                            const Spacer(),
                            const Icon(Icons.bolt_rounded,
                                color: Color(0xFFE5C07B), size: 16),
                          ],
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'Start',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 36,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -1.5,
                            height: 1.0,
                          ),
                        ),
                        const Text(
                          'a meeting.',
                          style: TextStyle(
                            color: Color(0xFF9CA3AF),
                            fontSize: 28,
                            fontWeight: FontWeight.w300,
                            letterSpacing: -1,
                            height: 1.0,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 12),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [
                                Color(0xFFFAFAFA),
                                Color(0xFFD4D4D8)
                              ],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                            borderRadius: BorderRadius.circular(40),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.white.withValues(alpha: 0.1),
                                blurRadius: 20,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.videocam_rounded,
                                  color: Color(0xFF1A1A1F), size: 18),
                              SizedBox(width: 8),
                              Text('Begin',
                                  style: TextStyle(
                                    color: Color(0xFF1A1A1F),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.2,
                                  )),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Two-up secondary metallic
            Row(
              children: [
                Expanded(child: _chromeAction('Join', Icons.input_rounded)),
                const SizedBox(width: 10),
                Expanded(
                    child: _chromeAction('Schedule', Icons.event_rounded)),
              ],
            ),
            const SizedBox(height: 28),

            // Upcoming
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Text('UPCOMING',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    letterSpacing: 3,
                    fontWeight: FontWeight.w800,
                  )),
            ),
            const SizedBox(height: 12),
            for (final m in _kUpcoming) ...[
              _chromeRow(m),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }

  Widget _chromeAction(String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0.08),
            Colors.white.withValues(alpha: 0.02),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white12, width: 0.5),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white70, size: 18),
          const SizedBox(width: 8),
          Text(label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              )),
        ],
      ),
    );
  }

  Widget _chromeRow(_Mtg m) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0.05),
            Colors.white.withValues(alpha: 0.01),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white12, width: 0.5),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFE5C07B), Color(0xFFB89968)],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.event_rounded,
                color: Color(0xFF1A1A1F), size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(m.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    )),
                const SizedBox(height: 2),
                Text(m.when,
                    style: const TextStyle(
                      color: Color(0xFF9CA3AF),
                      fontSize: 11,
                    )),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded,
              color: Colors.white38, size: 18),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
//  V5 — CONCIERGE  (Deep navy + warm gold + serif, hotel luxury)
// ════════════════════════════════════════════════════════════════════

class _Concierge extends StatelessWidget {
  const _Concierge();
  static const _navy = Color(0xFF0F1F2E);
  static const _navyLight = Color(0xFF1A2C3E);
  static const _gold = Color(0xFFC9A961);
  static const _cream = Color(0xFFE8DCC4);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _navy,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            // Top — wordmark
            Center(
              child: Column(
                children: [
                  Container(
                    width: 36,
                    height: 1,
                    color: _gold,
                  ),
                  const SizedBox(height: 8),
                  const Text('MIZDAH',
                      style: TextStyle(
                        color: _cream,
                        fontSize: 13,
                        letterSpacing: 6,
                        fontWeight: FontWeight.w800,
                      )),
                  const SizedBox(height: 4),
                  const Text('— RESERVE —',
                      style: TextStyle(
                        color: _gold,
                        fontSize: 9,
                        letterSpacing: 4,
                        fontWeight: FontWeight.w700,
                        fontStyle: FontStyle.italic,
                      )),
                  const SizedBox(height: 8),
                  Container(
                    width: 36,
                    height: 1,
                    color: _gold,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 36),

            // Greeting — italic serif feel
            const Text('Good evening,',
                style: TextStyle(
                  color: _cream,
                  fontSize: 16,
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w400,
                )),
            const SizedBox(height: 6),
            RichText(
              text: const TextSpan(
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 36,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.2,
                  height: 1.0,
                ),
                children: [
                  TextSpan(text: 'Mr. '),
                  TextSpan(
                      text: _kUserName,
                      style: TextStyle(
                        color: _gold,
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w300,
                      )),
                  TextSpan(text: '.'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Three engagements await your presence today.',
              style: TextStyle(
                color: Color(0xFFB8C4D2),
                fontSize: 13,
                height: 1.5,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 30),

            // Hero gold-bordered card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _navyLight,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _gold.withValues(alpha: 0.4), width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _gold,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text('PRIORITY',
                            style: TextStyle(
                              color: _navy,
                              fontSize: 9,
                              letterSpacing: 1.8,
                              fontWeight: FontWeight.w800,
                            )),
                      ),
                      const Spacer(),
                      const Icon(Icons.star_rounded, color: _gold, size: 16),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Begin a new\nsession',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.6,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 12),
                    decoration: BoxDecoration(
                      color: _gold,
                      borderRadius: BorderRadius.circular(40),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Proceed',
                            style: TextStyle(
                              color: _navy,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            )),
                        SizedBox(width: 6),
                        Icon(Icons.arrow_forward_rounded,
                            color: _navy, size: 16),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Two-up secondary
            Row(
              children: [
                Expanded(
                    child: _conciergeAction('Join', Icons.input_rounded)),
                const SizedBox(width: 10),
                Expanded(
                    child:
                        _conciergeAction('Schedule', Icons.event_rounded)),
              ],
            ),
            const SizedBox(height: 30),

            // Upcoming — luxury list with gold separator
            Row(
              children: [
                Container(width: 8, height: 1, color: _gold),
                const SizedBox(width: 8),
                const Text('YOUR ITINERARY',
                    style: TextStyle(
                      color: _gold,
                      fontSize: 10,
                      letterSpacing: 3,
                      fontWeight: FontWeight.w800,
                    )),
                const SizedBox(width: 8),
                Expanded(child: Container(height: 1, color: _gold)),
              ],
            ),
            const SizedBox(height: 14),
            for (var i = 0; i < _kUpcoming.length; i++) ...[
              _conciergeRow(_kUpcoming[i], i + 1),
              if (i != _kUpcoming.length - 1)
                Container(
                  height: 0.5,
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  color: _gold.withValues(alpha: 0.15),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _conciergeAction(String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: _navyLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _gold.withValues(alpha: 0.2), width: 0.5),
      ),
      child: Row(
        children: [
          Icon(icon, color: _gold, size: 18),
          const SizedBox(width: 8),
          Text(label,
              style: const TextStyle(
                color: _cream,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              )),
        ],
      ),
    );
  }

  Widget _conciergeRow(_Mtg m, int n) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 26,
            child: Text(
              n.toString().padLeft(2, '0'),
              style: const TextStyle(
                color: _gold,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                fontStyle: FontStyle.italic,
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
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                    )),
                const SizedBox(height: 3),
                Text(m.when,
                    style: const TextStyle(
                      color: Color(0xFFB8C4D2),
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                    )),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(Icons.arrow_outward_rounded,
                color: _gold, size: 16),
          ),
        ],
      ),
    );
  }
}
