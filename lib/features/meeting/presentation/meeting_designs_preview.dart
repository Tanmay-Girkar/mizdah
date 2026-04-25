import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/theme_provider.dart';

/// Standalone preview / spike screen — does NOT touch the live
/// MeetingRoomScreen or any provider. Lets the user see five
/// candidate Google-Meet-style layouts side-by-side, with a
/// participant-count slider so each layout is rendered at 2/3/4/5/6
/// participants.
///
/// Pick the design you want and tell the agent — they'll port it
/// into MeetingRoomScreen replacing the current `_VideoGrid`.
class MeetingDesignsPreviewScreen extends StatefulWidget {
  const MeetingDesignsPreviewScreen({super.key});

  @override
  State<MeetingDesignsPreviewScreen> createState() =>
      _MeetingDesignsPreviewScreenState();
}

class _MeetingDesignsPreviewScreenState
    extends State<MeetingDesignsPreviewScreen> {
  int _variant = 0;
  int _count = 4;

  static const _variants = [
    'Spotlight + Strip',
    'Equal Grid',
    'Speaker + Sidebar',
    'Floating PIP',
    'Premium Cards',
  ];

  @override
  Widget build(BuildContext context) {
    final mock = _mockParticipants(_count);
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: Column(
          children: [
            _buildToolbar(),
            const Divider(height: 1, color: Colors.white12),
            Expanded(child: _buildPreview(mock)),
            const Divider(height: 1, color: Colors.white12),
            _buildCountSelector(),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => context.pop(),
          ),
          const SizedBox(width: 4),
          const Text(
            'Layout',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          // Quick link to the screen-share UX preview.
          TextButton.icon(
            onPressed: () => context.push('/screen-share-designs'),
            icon: const Icon(Icons.present_to_all_rounded,
                color: Colors.white70, size: 16),
            label: const Text(
              'Share UX',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              backgroundColor: Colors.white.withValues(alpha: 0.06),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _variants.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final selected = i == _variant;
                  return ChoiceChip(
                    label: Text(_variants[i]),
                    selected: selected,
                    onSelected: (_) => setState(() => _variant = i),
                    backgroundColor: Colors.white10,
                    selectedColor: MizdahTheme.primaryBlue,
                    labelStyle: TextStyle(
                      color: selected ? Colors.white : Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: BorderSide.none,
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCountSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const Text(
            'Participants',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(width: 16),
          for (final n in const [2, 3, 4, 5, 6]) ...[
            GestureDetector(
              onTap: () => setState(() => _count = n),
              child: Container(
                width: 40,
                height: 40,
                margin: const EdgeInsets.only(right: 8),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _count == n
                      ? MizdahTheme.primaryBlue
                      : Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _count == n
                        ? MizdahTheme.primaryBlue
                        : Colors.white12,
                  ),
                ),
                child: Text(
                  '$n',
                  style: TextStyle(
                    color: _count == n ? Colors.white : Colors.white70,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPreview(List<_MockParticipant> mock) {
    switch (_variant) {
      case 0:
        return _SpotlightLayout(participants: mock);
      case 1:
        return _EqualGridLayout(participants: mock);
      case 2:
        return _SidebarLayout(participants: mock);
      case 3:
        return _FloatingPipLayout(participants: mock);
      case 4:
      default:
        return _PremiumCardsLayout(participants: mock);
    }
  }
}

// ---------------------------------------------------------------------------
// Mock data
// ---------------------------------------------------------------------------

class _MockParticipant {
  final String name;
  final Color color;
  final bool muted;
  final bool isSpeaking;
  const _MockParticipant({
    required this.name,
    required this.color,
    this.muted = false,
    this.isSpeaking = false,
  });
}

List<_MockParticipant> _mockParticipants(int n) {
  const names = ['Alex', 'Beth', 'Charlie', 'Dana', 'Eli', 'Farah'];
  const colors = [
    Color(0xFFE53935),
    Color(0xFF1E88E5),
    Color(0xFF43A047),
    Color(0xFFFB8C00),
    Color(0xFF8E24AA),
    Color(0xFF00ACC1),
  ];
  return List.generate(
    n,
    (i) => _MockParticipant(
      name: names[i],
      color: colors[i],
      muted: i % 3 == 0,
      isSpeaking: i == 1,
    ),
  );
}

// ---------------------------------------------------------------------------
// Shared building blocks
// ---------------------------------------------------------------------------

class _Tile extends StatelessWidget {
  final _MockParticipant p;
  final double avatarSize;
  final double radius;
  const _Tile({
    required this.p,
    this.avatarSize = 48,
    this.radius = 16,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Container(
        color: const Color(0xFF1F232B),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // "Camera" placeholder — colored avatar.
            Center(
              child: Container(
                width: avatarSize,
                height: avatarSize,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: p.color.withValues(alpha: 0.85),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  p.name[0],
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: avatarSize * 0.4,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            if (p.isSpeaking)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(radius),
                      border: Border.all(color: const Color(0xFF1A73E8), width: 2),
                    ),
                  ),
                ),
              ),
            Positioned(
                left: 8,
                bottom: 8,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        p.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (p.muted) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.85),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.mic_off, color: Colors.white, size: 10),
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

Widget _stubTopBar(String code) {
  return Padding(
    padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
    child: Row(
      children: [
        Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.arrow_back, color: Colors.white, size: 18),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              const Icon(Icons.lock, color: Color(0xFF1A73E8), size: 12),
              const SizedBox(width: 6),
              Text(code,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  )),
              const SizedBox(width: 4),
              const Icon(Icons.keyboard_arrow_down,
                  color: Colors.white54, size: 16),
            ],
          ),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.fiber_manual_record, color: Colors.red, size: 8),
              SizedBox(width: 4),
              Text('REC',
                  style: TextStyle(
                    color: Colors.red,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  )),
            ],
          ),
        ),
      ],
    ),
  );
}

Widget _stubControls() {
  return Padding(
    padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(40),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: const [
          _CtlBtn(icon: Icons.videocam_rounded),
          _CtlBtn(icon: Icons.mic_rounded),
          _CtlBtn(icon: Icons.sentiment_satisfied_rounded),
          _CtlBtn(icon: Icons.more_vert_rounded),
          _CtlBtn(icon: Icons.call_end_rounded, bg: Color(0xFFE53935)),
        ],
      ),
    ),
  );
}

class _CtlBtn extends StatelessWidget {
  final IconData icon;
  final Color? bg;
  const _CtlBtn({required this.icon, this.bg});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg ?? Colors.white.withValues(alpha: 0.10),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: Colors.white, size: 20),
    );
  }
}

Widget _stubSelfPip({double size = 92}) {
  return Container(
    width: size,
    height: size * 1.4,
    decoration: BoxDecoration(
      color: const Color(0xFF1F232B),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.4),
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
      ],
    ),
    child: Stack(
      fit: StackFit.expand,
      children: [
        Center(
          child: Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: Color(0xFF455A64),
              shape: BoxShape.circle,
            ),
            child: const Text('Y',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600)),
          ),
        ),
        Positioned(
          left: 6,
          bottom: 6,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text('You',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// Variant 1 — Spotlight + bottom strip (Google Meet mobile default)
// ---------------------------------------------------------------------------

class _SpotlightLayout extends StatelessWidget {
  final List<_MockParticipant> participants;
  const _SpotlightLayout({required this.participants});

  @override
  Widget build(BuildContext context) {
    final speaker = participants.firstWhere((p) => p.isSpeaking,
        orElse: () => participants.first);
    final others = participants.where((p) => p != speaker).toList();
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 64, 12, 96),
          child: Column(
            children: [
              Expanded(
                  child: _Tile(p: speaker, avatarSize: 80, radius: 20)),
              const SizedBox(height: 10),
              SizedBox(
                height: 76,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: others.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) => SizedBox(
                    width: 100,
                    child: _Tile(p: others[i], avatarSize: 28, radius: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
        Positioned(top: 0, left: 0, right: 0, child: _stubTopBar('fojndzaphd')),
        Positioned(
            bottom: 88,
            right: 16,
            child: _stubSelfPip(size: 76)),
        Positioned(left: 0, right: 0, bottom: 0, child: _stubControls()),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Variant 2 — Equal grid (Google Meet "Tile view")
// ---------------------------------------------------------------------------

class _EqualGridLayout extends StatelessWidget {
  final List<_MockParticipant> participants;
  const _EqualGridLayout({required this.participants});

  @override
  Widget build(BuildContext context) {
    final n = participants.length;
    final cols = n <= 1 ? 1 : (n <= 4 ? 2 : 2);
    final rows = (n / cols).ceil();
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 64, 12, 96),
          child: GridView.count(
            crossAxisCount: cols,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio:
                rows == 1 ? 0.7 : (rows == 2 ? 0.8 : 0.9),
            children: [
              for (final p in participants) _Tile(p: p),
            ],
          ),
        ),
        Positioned(top: 0, left: 0, right: 0, child: _stubTopBar('fojndzaphd')),
        Positioned(
            bottom: 88,
            right: 16,
            child: _stubSelfPip(size: 76)),
        Positioned(left: 0, right: 0, bottom: 0, child: _stubControls()),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Variant 3 — Speaker + right sidebar (Zoom-style on mobile)
// ---------------------------------------------------------------------------

class _SidebarLayout extends StatelessWidget {
  final List<_MockParticipant> participants;
  const _SidebarLayout({required this.participants});

  @override
  Widget build(BuildContext context) {
    final speaker = participants.firstWhere((p) => p.isSpeaking,
        orElse: () => participants.first);
    final others = participants.where((p) => p != speaker).toList();
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 64, 12, 96),
          child: Row(
            children: [
              Expanded(
                child: _Tile(p: speaker, avatarSize: 80, radius: 20),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 100,
                child: ListView.separated(
                  itemCount: others.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => AspectRatio(
                    aspectRatio: 0.75,
                    child: _Tile(p: others[i], avatarSize: 32, radius: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
        Positioned(top: 0, left: 0, right: 0, child: _stubTopBar('fojndzaphd')),
        Positioned(
          bottom: 88,
          right: 16,
          child: _stubSelfPip(size: 70),
        ),
        Positioned(left: 0, right: 0, bottom: 0, child: _stubControls()),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Variant 4 — Floating PIP (one-on-one casual call)
// ---------------------------------------------------------------------------

class _FloatingPipLayout extends StatelessWidget {
  final List<_MockParticipant> participants;
  const _FloatingPipLayout({required this.participants});

  @override
  Widget build(BuildContext context) {
    final speaker = participants.firstWhere((p) => p.isSpeaking,
        orElse: () => participants.first);
    final others = participants.where((p) => p != speaker).toList();
    return Stack(
      children: [
        Positioned.fill(
          child: _Tile(p: speaker, avatarSize: 96, radius: 0),
        ),
        Positioned(top: 0, left: 0, right: 0, child: _stubTopBar('fojndzaphd')),
        Positioned(
          top: 70,
          right: 12,
          child: SizedBox(
            width: 110,
            child: Column(
              children: [
                for (final p in others.take(4)) ...[
                  AspectRatio(
                    aspectRatio: 0.8,
                    child: _Tile(p: p, avatarSize: 26, radius: 14),
                  ),
                  const SizedBox(height: 8),
                ],
                if (others.length > 4)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '+${others.length - 4}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Positioned(
          bottom: 88,
          right: 12,
          child: _stubSelfPip(size: 80),
        ),
        Positioned(left: 0, right: 0, bottom: 0, child: _stubControls()),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Variant 5 — Premium cards (rich shadows, glass-morphism feel)
// ---------------------------------------------------------------------------

class _PremiumCardsLayout extends StatelessWidget {
  final List<_MockParticipant> participants;
  const _PremiumCardsLayout({required this.participants});

  @override
  Widget build(BuildContext context) {
    final n = participants.length;
    final cols = n <= 2 ? 1 : 2;
    return Stack(
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0F172A), Color(0xFF020617)],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 64, 16, 96),
          child: GridView.count(
            crossAxisCount: cols,
            mainAxisSpacing: 14,
            crossAxisSpacing: 14,
            childAspectRatio: cols == 1 ? 0.7 : 0.85,
            children: [
              for (final p in participants) _PremiumTile(p: p),
            ],
          ),
        ),
        Positioned(top: 0, left: 0, right: 0, child: _stubTopBar('fojndzaphd')),
        Positioned(
          bottom: 88,
          right: 16,
          child: _stubSelfPip(size: 76),
        ),
        Positioned(left: 0, right: 0, bottom: 0, child: _stubControls()),
      ],
    );
  }
}

class _PremiumTile extends StatelessWidget {
  final _MockParticipant p;
  const _PremiumTile({required this.p});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                p.color.withValues(alpha: 0.30),
                const Color(0xFF1F232B),
              ],
            ),
            border: Border.all(
              color: p.isSpeaking
                  ? const Color(0xFF1A73E8)
                  : Colors.white.withValues(alpha: 0.06),
              width: p.isSpeaking ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Center(
                child: Container(
                  width: 60,
                  height: 60,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: p.color,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: p.color.withValues(alpha: 0.45),
                        blurRadius: 18,
                      ),
                    ],
                  ),
                  child: Text(
                    p.name[0],
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 10,
                top: 10,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: p.isSpeaking
                        ? const Color(0xFF34D399)
                        : Colors.white24,
                    shape: BoxShape.circle,
                    boxShadow: p.isSpeaking
                        ? [
                            const BoxShadow(
                              color: Color(0xFF34D399),
                              blurRadius: 8,
                            ),
                          ]
                        : null,
                  ),
                ),
              ),
              Positioned(
                left: 10,
                bottom: 10,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        p.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: p.muted
                            ? Colors.red.withValues(alpha: 0.85)
                            : Colors.white.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        p.muted ? Icons.mic_off : Icons.mic,
                        color: Colors.white,
                        size: 11,
                      ),
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
}
