import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Standalone preview screen for alternate home-screen + drawer
/// designs. Does NOT touch the live home_screen.dart, the auth
/// drawer, or any provider — six candidate UIs are rendered in a
/// phone-shaped frame side-by-side, switched via a chip selector.
///
/// Pick the design you want and tell the agent — they'll port it
/// into the live home screen replacing the current layout. The
/// existing production UI is unchanged until you say so.
///
/// All variants share the same data:
///   • user "Tanmay" / tanmay@gmail.com
///   • two recent meetings (jhmyqrneac, ctqrskhqxv)
///   • the same primary actions (New Meeting, Join, Schedule)
/// so the only thing that varies between variants is the LAYOUT,
/// not the content. This makes side-by-side comparison fair.
class HomeDesignsPreviewScreen extends StatefulWidget {
  const HomeDesignsPreviewScreen({super.key});

  @override
  State<HomeDesignsPreviewScreen> createState() =>
      _HomeDesignsPreviewScreenState();
}

class _HomeDesignsPreviewScreenState extends State<HomeDesignsPreviewScreen> {
  int _variant = 0;

  static const List<_VariantSpec> _variants = [
    _VariantSpec('Hero Action', 'Big primary CTA card stacked above quick join'),
    _VariantSpec('Dashboard',
        'Stat tiles + primary action grid, Linear/Notion vibe'),
    _VariantSpec('Compact List', 'Search-first, dense, Slack/Discord feel'),
    _VariantSpec('Card Stack',
        'Stacked rounded cards, Apple-Wallet style, calm'),
    _VariantSpec('Bottom Tabs',
        'Persistent bottom nav, Zoom-style, fewer hidden actions'),
    _VariantSpec('Glass Premium',
        'Frosted glass + gradient hero, premium SaaS look'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1120),
      body: SafeArea(
        child: Column(
          children: [
            _buildToolbar(),
            const Divider(height: 1, color: Colors.white12),
            Expanded(child: _buildPreviewFrame()),
            const Divider(height: 1, color: Colors.white12),
            _buildVariantChips(),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ─── Toolbar ─────────────────────────────────────────────────────

  Widget _buildToolbar() {
    final spec = _variants[_variant];
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
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${_variant + 1} / ${_variants.length}',
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

  // ─── Variant chip selector ──────────────────────────────────────

  Widget _buildVariantChips() {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: _variants.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final selected = i == _variant;
          return ChoiceChip(
            label: Text(_variants[i].name),
            selected: selected,
            onSelected: (_) => setState(() => _variant = i),
            backgroundColor: Colors.white.withValues(alpha: 0.06),
            selectedColor: const Color(0xFF2563EB),
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

  // ─── Phone frame around the variant ─────────────────────────────

  Widget _buildPreviewFrame() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: AspectRatio(
          aspectRatio: 9 / 18.5, // typical modern phone
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
        return const _V1HeroAction();
      case 1:
        return const _V2Dashboard();
      case 2:
        return const _V3CompactList();
      case 3:
        return const _V4CardStack();
      case 4:
        return const _V5BottomTabs();
      case 5:
        return const _V6GlassPremium();
      default:
        return const SizedBox.shrink();
    }
  }
}

class _VariantSpec {
  final String name;
  final String description;
  const _VariantSpec(this.name, this.description);
}

// ════════════════════════════════════════════════════════════════════
//  Shared mock data
// ════════════════════════════════════════════════════════════════════

class _MockMeeting {
  final String code;
  final String when;
  final IconData icon;
  const _MockMeeting(this.code, this.when, this.icon);
}

const _kRecent = <_MockMeeting>[
  _MockMeeting('jhmyqrneac', 'May 3 · 6:12 PM', Icons.call_received_rounded),
  _MockMeeting('ctqrskhqxv', 'May 3 · 6:04 PM', Icons.call_received_rounded),
  _MockMeeting('emeblvocot', 'May 3 · 5:49 PM', Icons.call_received_rounded),
];

const _kUserName = 'Tanmay';
const _kUserEmail = 'tanmay@gmail.com';
const _kPrimary = Color(0xFF2563EB);

// ════════════════════════════════════════════════════════════════════
//  Variant 1 — Hero Action
//  Big primary "Start meeting" card front-and-center, secondary
//  "Join with code" sits underneath. Best for users who almost
//  always start meetings rather than join. Reads like Calendly/Cal.
// ════════════════════════════════════════════════════════════════════

class _V1HeroAction extends StatelessWidget {
  const _V1HeroAction();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0B1120),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _MiniTopBar(showSearch: false),
              const SizedBox(height: 24),
              const Text(
                'Good evening,',
                style: TextStyle(color: Colors.white60, fontSize: 14),
              ),
              const Text(
                _kUserName,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 24),
              // Hero CTA
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF3B82F6), Color(0xFF2563EB)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: _kPrimary.withValues(alpha: 0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.videocam_rounded,
                          color: Colors.white, size: 22),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Start an instant meeting',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Camera & mic checks before you go live.',
                      style: TextStyle(
                          color: Colors.white70, fontSize: 12, height: 1.4),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'Start  →',
                            style: TextStyle(
                              color: _kPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Secondary join row
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.link_rounded,
                        color: Colors.white70, size: 18),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Paste a meeting code…',
                        style: TextStyle(color: Colors.white38, fontSize: 13),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'Join',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const _SectionLabel('Up next'),
              const SizedBox(height: 8),
              _EmptyHint(
                icon: Icons.calendar_today_rounded,
                title: 'No meetings today',
                hint: 'Tap schedule to plan one',
              ),
              const SizedBox(height: 20),
              const _SectionLabel('Recent'),
              const SizedBox(height: 8),
              for (final m in _kRecent.take(2))
                _RecentRow(meeting: m, dense: false),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
//  Variant 2 — Dashboard
//  Stat tiles up top (e.g. Today / This week / Hours) then a 2-up
//  primary action grid. Linear-style: information-dense without
//  feeling crowded. Good if you want users to glance at their
//  meeting load before deciding to join/start.
// ════════════════════════════════════════════════════════════════════

class _V2Dashboard extends StatelessWidget {
  const _V2Dashboard();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0E1525),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    'Mizdah',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const Spacer(),
                  _CircleIconButton(icon: Icons.search_rounded),
                  const SizedBox(width: 8),
                  _AvatarChip(),
                ],
              ),
              const SizedBox(height: 20),
              // Stat tiles row
              Row(
                children: [
                  Expanded(
                      child: _StatTile(
                          label: 'Today', value: '0', accent: Colors.white70)),
                  const SizedBox(width: 8),
                  Expanded(
                      child: _StatTile(
                          label: 'This week', value: '4', accent: _kPrimary)),
                  const SizedBox(width: 8),
                  Expanded(
                      child: _StatTile(
                          label: 'Hours',
                          value: '2.1',
                          accent: const Color(0xFF22C55E))),
                ],
              ),
              const SizedBox(height: 20),
              const _SectionLabel('Quick actions'),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _ActionCard(
                      title: 'New meeting',
                      subtitle: 'Instant',
                      icon: Icons.videocam_rounded,
                      gradient: const [Color(0xFF3B82F6), Color(0xFF2563EB)],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ActionCard(
                      title: 'Schedule',
                      subtitle: 'Plan ahead',
                      icon: Icons.calendar_month_rounded,
                      gradient: const [Color(0xFF8B5CF6), Color(0xFF6D28D9)],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _ActionCard(
                      title: 'Join',
                      subtitle: 'With code',
                      icon: Icons.qr_code_2_rounded,
                      gradient: const [Color(0xFF14B8A6), Color(0xFF0D9488)],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ActionCard(
                      title: 'Whiteboard',
                      subtitle: 'Solo',
                      icon: Icons.draw_rounded,
                      gradient: const [Color(0xFFF59E0B), Color(0xFFD97706)],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const _SectionLabel('Recent activity'),
              const SizedBox(height: 8),
              for (final m in _kRecent.take(2))
                _RecentRow(meeting: m, dense: true),
            ],
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
//  Variant 3 — Compact List
//  Search-first, like Slack/Discord. Recent meetings dominate the
//  view. Primary actions live in a sticky toolbar at the bottom.
//  Best when users have a high volume of meetings and re-join more
//  often than they create new ones.
// ════════════════════════════════════════════════════════════════════

class _V3CompactList extends StatelessWidget {
  const _V3CompactList();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0F172A),
      child: SafeArea(
        child: Column(
          children: [
            // Search bar header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  _AvatarChip(size: 32),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Container(
                      height: 38,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Row(
                        children: const [
                          Icon(Icons.search_rounded,
                              size: 18, color: Colors.white54),
                          SizedBox(width: 6),
                          Text(
                            'Search meetings, codes…',
                            style: TextStyle(
                                color: Colors.white38, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _CircleIconButton(icon: Icons.notifications_outlined),
                ],
              ),
            ),
            // Filter chips
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _FilterChip(label: 'All', selected: true),
                  const SizedBox(width: 6),
                  _FilterChip(label: 'Hosted', selected: false),
                  const SizedBox(width: 6),
                  _FilterChip(label: 'Joined', selected: false),
                  const SizedBox(width: 6),
                  _FilterChip(label: 'Scheduled', selected: false),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final m in _kRecent) _RecentRow(meeting: m, dense: true),
                ],
              ),
            ),
            // Sticky bottom toolbar
            Container(
              margin:
                  const EdgeInsets.fromLTRB(12, 4, 12, 12),
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _ToolbarBtn(
                      icon: Icons.add_rounded,
                      label: 'New',
                      filled: true,
                    ),
                  ),
                  Expanded(
                    child: _ToolbarBtn(
                      icon: Icons.link_rounded,
                      label: 'Join',
                    ),
                  ),
                  Expanded(
                    child: _ToolbarBtn(
                      icon: Icons.calendar_month_rounded,
                      label: 'Plan',
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
}

// ════════════════════════════════════════════════════════════════════
//  Variant 4 — Card Stack
//  Layered rounded cards that reveal one another, Apple Wallet
//  style. Calm, lots of whitespace. Each card is a section
//  (Today / Quick start / Recent). Best for premium-feeling apps
//  that don't want a wall of UI.
// ════════════════════════════════════════════════════════════════════

class _V4CardStack extends StatelessWidget {
  const _V4CardStack();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF111827), Color(0xFF1F2937)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _MiniTopBar(showSearch: false),
              const SizedBox(height: 18),
              // Card 1 — Today / hero
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: Colors.white10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: const [
                        Text('Today',
                            style: TextStyle(
                                color: Colors.white60,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.4)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text('No meetings yet',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    const Text(
                      'Start one when you’re ready.',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: -8 + 0).heightOrZero, // spacer with overlap feel
              // Card 2 — Quick start, slightly overlapped via negative margin
              Transform.translate(
                offset: const Offset(0, -8),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF273449),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Row(
                    children: [
                      _PillButton(
                        label: 'New meeting',
                        icon: Icons.videocam_rounded,
                        primary: true,
                      ),
                      const SizedBox(width: 8),
                      _PillButton(
                        label: 'Join',
                        icon: Icons.link_rounded,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Card 3 — Recent activity, the bottom of the stack
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF334155),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _SectionLabel('Recent', muted: false),
                      const SizedBox(height: 8),
                      for (final m in _kRecent)
                        _RecentRow(
                          meeting: m,
                          dense: true,
                          onDarker: true,
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Tiny extension so the `SizedBox` overlap idiom in V4 doesn't break
// when height is negative-or-zero. Keeps the transform-only path.
extension _SizedBoxFallback on SizedBox {
  Widget get heightOrZero =>
      (height ?? 0) <= 0 ? const SizedBox.shrink() : this;
}

// ════════════════════════════════════════════════════════════════════
//  Variant 5 — Bottom Tabs
//  Persistent 4-tab bottom nav (Home / Meetings / Schedule / Me).
//  Zoom / Google Meet style. Discoverability over density. Each
//  primary action gets its own tab so nothing is hidden behind a
//  drawer.
// ════════════════════════════════════════════════════════════════════

class _V5BottomTabs extends StatelessWidget {
  const _V5BottomTabs();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0B1120),
      child: SafeArea(
        child: Column(
          children: [
            // Top header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                children: [
                  const Text(
                    'Home',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  _CircleIconButton(icon: Icons.notifications_outlined),
                  const SizedBox(width: 8),
                  _AvatarChip(),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                children: [
                  // Two big square tiles
                  Row(
                    children: [
                      Expanded(
                        child: _BigTile(
                          icon: Icons.videocam_rounded,
                          title: 'New meeting',
                          color: _kPrimary,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _BigTile(
                          icon: Icons.link_rounded,
                          title: 'Join',
                          color: const Color(0xFF14B8A6),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const _SectionLabel('Recent'),
                  const SizedBox(height: 8),
                  for (final m in _kRecent.take(2))
                    _RecentRow(meeting: m, dense: false),
                ],
              ),
            ),
            // Bottom nav
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF111827),
                border: Border(
                    top: BorderSide(color: Colors.white12, width: 0.5)),
              ),
              child: Row(
                children: [
                  Expanded(
                      child: _BottomTab(
                          icon: Icons.home_filled,
                          label: 'Home',
                          selected: true)),
                  Expanded(
                      child: _BottomTab(
                          icon: Icons.video_call_outlined, label: 'Meetings')),
                  Expanded(
                      child: _BottomTab(
                          icon: Icons.calendar_today_outlined,
                          label: 'Schedule')),
                  Expanded(
                      child: _BottomTab(
                          icon: Icons.person_outline, label: 'Me')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
//  Variant 6 — Glass Premium
//  Frosted glass cards on a colourful gradient. Drawer is
//  reimagined as a slide-up profile sheet. Premium SaaS / fintech
//  aesthetic. Heaviest visual look — best as an option for users
//  who want a "wow" first impression.
// ════════════════════════════════════════════════════════════════════

class _V6GlassPremium extends StatelessWidget {
  const _V6GlassPremium();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFF312E81),
            Color(0xFF1E1B4B),
            Color(0xFF0B1120),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          // Decorative blurred orb
          Positioned(
            top: -40,
            right: -40,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF8B5CF6).withValues(alpha: 0.45),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF8B5CF6).withValues(alpha: 0.35),
                    blurRadius: 80,
                    spreadRadius: 30,
                  ),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _MiniTopBar(showSearch: false, brand: 'M'),
                  const SizedBox(height: 24),
                  const Text(
                    'Hi, Tanmay',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Ready when you are.',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 24),
                  // Glass hero
                  _GlassPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: const [
                            Icon(Icons.bolt_rounded,
                                color: Color(0xFFFBBF24), size: 18),
                            SizedBox(width: 6),
                            Text('Instant',
                                style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Start a meeting',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            _PillButton(
                              label: 'New',
                              icon: Icons.videocam_rounded,
                              primary: true,
                            ),
                            const SizedBox(width: 8),
                            _PillButton(
                              label: 'Join',
                              icon: Icons.link_rounded,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _GlassPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _SectionLabel('Recent', muted: false),
                        const SizedBox(height: 8),
                        for (final m in _kRecent.take(2))
                          _RecentRow(
                              meeting: m, dense: true, onDarker: true),
                      ],
                    ),
                  ),
                  const Spacer(),
                  // Slide-up profile chip
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Row(
                      children: [
                        _AvatarChip(size: 28),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_kUserName,
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600)),
                              Text(_kUserEmail,
                                  style: TextStyle(
                                      color: Colors.white60, fontSize: 11)),
                            ],
                          ),
                        ),
                        const Icon(Icons.tune_rounded,
                            color: Colors.white70, size: 18),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
//  Shared building blocks
// ════════════════════════════════════════════════════════════════════

class _MiniTopBar extends StatelessWidget {
  final bool showSearch;
  final String brand;
  const _MiniTopBar({this.showSearch = true, this.brand = 'MIZDAH'});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.menu_rounded,
              color: Colors.white, size: 18),
        ),
        const SizedBox(width: 12),
        Text(
          brand,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
          ),
        ),
        const Spacer(),
        if (showSearch) _CircleIconButton(icon: Icons.search_rounded),
        if (showSearch) const SizedBox(width: 8),
        _CircleIconButton(icon: Icons.notifications_outlined),
        const SizedBox(width: 8),
        _AvatarChip(),
      ],
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  const _CircleIconButton({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Icon(icon, color: Colors.white70, size: 16),
    );
  }
}

class _AvatarChip extends StatelessWidget {
  final double size;
  const _AvatarChip({this.size = 34});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [Color(0xFF60A5FA), Color(0xFF2563EB)],
        ),
      ),
      child: Text(
        _kUserName[0],
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.42,
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  final bool muted;
  const _SectionLabel(this.text, {this.muted = true});

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        color: muted ? Colors.white54 : Colors.white,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final Color accent;
  const _StatTile(
      {required this.label, required this.value, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white60, fontSize: 11),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: accent,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> gradient;
  const _ActionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: Colors.white, size: 18),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            subtitle,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _BigTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;
  const _BigTile(
      {required this.icon, required this.title, required this.color});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: Colors.white, size: 20),
            ),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentRow extends StatelessWidget {
  final _MockMeeting meeting;
  final bool dense;
  final bool onDarker;
  const _RecentRow(
      {required this.meeting, this.dense = false, this.onDarker = false});

  @override
  Widget build(BuildContext context) {
    final pad = dense ? 8.0 : 12.0;
    return Container(
      margin: EdgeInsets.symmetric(vertical: dense ? 3 : 5),
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: pad),
      decoration: BoxDecoration(
        color:
            (onDarker ? Colors.white : Colors.white).withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          Container(
            width: dense ? 30 : 36,
            height: dense ? 30 : 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF22C55E).withValues(alpha: 0.18),
            ),
            child: Icon(meeting.icon,
                color: const Color(0xFF22C55E), size: dense ? 14 : 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  meeting.code,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: dense ? 13 : 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (!dense) const SizedBox(height: 1),
                const Text(
                  'Hosted',
                  style: TextStyle(
                      color: Color(0xFF22C55E),
                      fontSize: 11,
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          Text(
            meeting.when,
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final IconData icon;
  final String title;
  final String hint;
  const _EmptyHint(
      {required this.icon, required this.title, required this.hint});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _kPrimary.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: _kPrimary, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
                Text(hint,
                    style: const TextStyle(
                        color: Colors.white54, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  const _FilterChip({required this.label, required this.selected});

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: selected
            ? _kPrimary
            : Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: selected ? Colors.transparent : Colors.white12),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: selected ? Colors.white : Colors.white70,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ToolbarBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool filled;
  const _ToolbarBtn(
      {required this.icon, required this.label, this.filled = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(2),
      padding: const EdgeInsets.symmetric(vertical: 10),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: filled ? _kPrimary : Colors.transparent,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: filled ? FontWeight.w700 : FontWeight.w500)),
        ],
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool primary;
  const _PillButton({
    required this.label,
    required this.icon,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: primary ? _kPrimary : Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
          border: primary
              ? null
              : Border.all(color: Colors.white24),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 16),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: primary ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomTab extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  const _BottomTab(
      {required this.icon, required this.label, this.selected = false});

  @override
  Widget build(BuildContext context) {
    final color = selected ? _kPrimary : Colors.white60;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 4),
        Text(label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            )),
      ],
    );
  }
}

class _GlassPanel extends StatelessWidget {
  final Widget child;
  const _GlassPanel({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white24),
      ),
      child: child,
    );
  }
}
