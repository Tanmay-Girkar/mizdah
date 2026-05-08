import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/services/google_calendar_service.dart';
import '../../../core/ui/mizdah_design.dart' as md;
import '../../../core/utils/meeting_utils.dart';
import '../../../core/widgets/mizdah_button.dart';
import '../../../data/models/models.dart';
import '../../../data/repositories/meeting_repository.dart';
import '../../../data/repositories/mizdah_repository.dart';
import '../../../data/repositories/participant_repository.dart';
import '../../../data/repositories/scheduling_repository.dart';
import '../../auth/auth_provider.dart';
import '../notification_provider.dart';

// ════════════════════════════════════════════════════════════════════
//  Design tokens — purple/blue gradient theme per spec.
//  Centralised so future tweaks (palette, shadow recipe, radii) are
//  one-edit affairs instead of grep-and-replace.
// ════════════════════════════════════════════════════════════════════

/// Lightweight private alias kept so any remaining references to
/// `_Tokens.primary`, `.heroGradient`, `.softShadow()` resolve without
/// touching every line. The brightness-aware palette lives in
/// `md.MizdahTokens` (see `lib/core/ui/mizdah_design.dart`); the
/// hardcoded light-mode tokens (lavenderBg / ink / muted / etc.) were
/// removed because all callers now go through the adaptive accessors
/// (`md.MizdahTokens.bg(context)`, `.inkOf(context)`, …).
class _Tokens {
  static const primary = Color(0xFF6C63FF);
  // ignore: unused_field
  static const secondary = Color(0xFF8B5CF6);
  // ignore: unused_field
  static const tertiary = Color(0xFFA78BFA);

  static const heroGradient = LinearGradient(
    colors: [Color(0xFF6C63FF), Color(0xFF8B5CF6), Color(0xFFA78BFA)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // softShadow() removed — every callsite now uses the adaptive
  // `md.MizdahTokens.shadow(context)` which handles light + dark.
}

// Color palette for timeline dots — rotates per row index so each
// upcoming meeting gets a distinct colour without needing per-row
// configuration on the backend side.
const List<List<Color>> _kRowColors = [
  [Color(0xFFEDE9FE), Color(0xFF8B5CF6)], // violet
  [Color(0xFFDBEAFE), Color(0xFF3B82F6)], // blue
  [Color(0xFFD1FAE5), Color(0xFF10B981)], // emerald
  [Color(0xFFFEF3C7), Color(0xFFF59E0B)], // amber
  [Color(0xFFFCE7F3), Color(0xFFEC4899)], // pink
];

// ════════════════════════════════════════════════════════════════════
//  THE LIVE HOME SCREEN — Mizdah Premium
//  Wired to real data:
//    • authProvider                  → header avatar + drawer
//    • schedulesProvider             → upcoming meetings timeline
//    • callHistoryProvider           → recent activity card
//    • notificationsProvider         → bell badge + drawer
//    • _NewMeetingOptions sheet      → "Start a Meeting" tap
//    • meetingRepositoryProvider     → "Join with Code" validate/push
// ════════════════════════════════════════════════════════════════════

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with TickerProviderStateMixin {
  late final AnimationController _floatCtrl;
  late final AnimationController _entryCtrl;

  @override
  void initState() {
    super.initState();
    // 6s sin-wave loop drives the slow floating motion of the blob
    // illustration's icon cards. Auto-reverses so the wave stays
    // continuous instead of snapping back to 0.
    _floatCtrl = AnimationController(
      duration: const Duration(seconds: 6),
      vsync: this,
    )..repeat(reverse: true);
    // Single 700ms forward run drives the staggered fade-up entry
    // animation on each section.
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
    return Scaffold(
      drawer: const MizdahDrawer(),
      endDrawer: const NotificationsDrawer(),
      backgroundColor: md.MizdahTokens.bg(context),
      body: Stack(
        children: [
          // Faint background gradient wash — adaptive: lavender →
          // off-white in light mode, deep navy in dark mode.
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: md.MizdahTokens.pageGradient(context),
              ),
            ),
          ),

          // Scrollable content
          SafeArea(
            bottom: false,
            child: RefreshIndicator(
              color: _Tokens.primary,
              onRefresh: () async {
                ref.invalidate(callHistoryProvider);
                ref.invalidate(schedulesProvider);
              },
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                    0, 0, 0, md.MizdahTokens.navBarBottomInset(context)),
                physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics()),
                children: [
                  _Header(entryCtrl: _entryCtrl),
                  _Hero(floatCtrl: _floatCtrl, entryCtrl: _entryCtrl),
                  const SizedBox(height: 8),
                  _ActionCardsRow(entryCtrl: _entryCtrl),
                  const SizedBox(height: 24),
                  _UpcomingSection(entryCtrl: _entryCtrl),
                  const SizedBox(height: 14),
                  _RecentActivityCard(entryCtrl: _entryCtrl),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),

          // Floating bottom navigation — shared 5-tab nav (Home /
          // Meetings / Call / People / Settings) so every tab page
          // looks identical. activeIndex=0 because this IS the home.
          Positioned(
            left: 12,
            right: 12,
            bottom: MediaQuery.of(context).padding.bottom + 10,
            child: const md.MizdahFloatingNav(activeIndex: 0),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────
//  Header — hamburger / wordmark / bell+badge / gradient avatar
// ────────────────────────────────────────────────────────────────────

class _Header extends ConsumerWidget {
  final AnimationController entryCtrl;
  const _Header({required this.entryCtrl});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;
    final notificationsAsync = ref.watch(notificationsProvider);
    // Show the small purple dot only when there's at least one
    // unread / unseen notification. We don't have a "read" concept on
    // the model yet, so any non-empty list lights the dot.
    final hasNotifications = notificationsAsync.maybeWhen(
      data: (list) => list.isNotEmpty,
      orElse: () => false,
    );
    final initial = (user?.name.isNotEmpty == true)
        ? user!.name[0].toUpperCase()
        : 'A';

    return _FadeUp(
      controller: entryCtrl,
      delay: 0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 16, 4),
        child: Row(
          children: [
            // Hamburger
            _IconTap(
              onTap: () => Scaffold.of(context).openDrawer(),
              tooltip: 'Menu',
              child: Icon(
                Icons.menu_rounded,
                color: md.MizdahTokens.inkOf(context),
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
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF6C63FF).withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.auto_awesome_rounded,
                    color: Colors.white,
                    size: 13,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'MIZDAH',
                  style: TextStyle(
                    color: md.MizdahTokens.inkOf(context),
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 3.5,
                  ),
                ),
              ],
            ),
            const Spacer(),
            // Bell with notification dot
            _IconTap(
              onTap: () => Scaffold.of(context).openEndDrawer(),
              tooltip: 'Notifications',
              child: SizedBox(
                width: 24,
                height: 24,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(
                      Icons.notifications_none_rounded,
                      color: md.MizdahTokens.inkOf(context),
                      size: 22,
                    ),
                    if (hasNotifications)
                      Positioned(
                        top: 2,
                        right: 4,
                        child: Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            gradient: _Tokens.heroGradient,
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: md.MizdahTokens.bg(context), width: 1.2),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
            // Avatar — first letter of user name, gradient bg
            GestureDetector(
              onTap: () => Scaffold.of(context).openDrawer(),
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  gradient: _Tokens.heroGradient,
                  shape: BoxShape.circle,
                  boxShadow: md.MizdahTokens.shadow(context, elevation: 0.6),
                ),
                child: Center(
                  child: Text(
                    initial,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
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

/// Tap target for header icons that gives a 36x36 hit area without
/// taking up visual space (matches Apple HIG minimum without
/// making the icon look chunky).
class _IconTap extends StatelessWidget {
  final VoidCallback onTap;
  final String tooltip;
  final Widget child;
  const _IconTap({
    required this.onTap,
    required this.tooltip,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Center(child: child),
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
      padding: const EdgeInsets.fromLTRB(20, 4, 0, 4),
      child: SizedBox(
        height: 210,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Hero illustration positioned on the right, allowed to
            // be wider than a Row's Expanded sibling would allow. The
            // illustration is mostly translucent at the edges so any
            // overlap with the text column reads as soft layering
            // rather than a collision.
            Positioned(
              right: -25,
              top: 0,
              bottom: 0,
              width: 230,
              child: _BlobIllustration(floatCtrl: floatCtrl),
            ),
            // Text column on the left — fixed-width SizedBox so the
            // heading wraps the same way regardless of screen width,
            // and the illustration can take the remainder.
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: _FadeUp(
                controller: entryCtrl,
                delay: 0.05,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const _HeroHeading(),
                    const SizedBox(height: 14),
                    Text(
                      'Collaborate · Meet · Achieve',
                      style: TextStyle(
                        color: md.MizdahTokens.mutedOf(context),
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroHeading extends StatelessWidget {
  const _HeroHeading();

  // "Ready to\nconnect today?" — "today" gets the purple gradient via
  // ShaderMask. WidgetSpan keeps it on the same baseline as the rest
  // of the heading instead of dropping below.
  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: TextStyle(
          color: md.MizdahTokens.inkOf(context),
          fontSize: 30,
          fontWeight: FontWeight.w800,
          height: 1.15,
          letterSpacing: -0.8,
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
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                  letterSpacing: -0.8,
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

/// Hero illustration — uses the user-supplied `bg_image.png` from
/// `assets/images/`. Subtle vertical bob driven by the float
/// controller's sin-wave so the image feels alive without
/// distracting motion.
///
/// If the asset is missing the errorBuilder shows a soft lavender
/// blob fallback so a missing-file deploy doesn't crash the
/// home screen.
class _BlobIllustration extends StatelessWidget {
  final AnimationController floatCtrl;
  const _BlobIllustration({required this.floatCtrl});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: floatCtrl,
      builder: (context, _) {
        final t = math.sin(floatCtrl.value * math.pi * 2);
        return Transform.translate(
          offset: Offset(0, t * 4),
          child: Image.asset(
            'assets/images/bg_image.png',
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              return Container(
                decoration: BoxDecoration(
                  gradient: const RadialGradient(
                    colors: [Color(0xFFE0DDFF), Color(0xFFF5F3FF)],
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Center(
                  child: Icon(
                    Icons.image_outlined,
                    color: Color(0xFFA78BFA),
                    size: 32,
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

// ────────────────────────────────────────────────────────────────────
//  Action cards row
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

class _StartMeetingCard extends ConsumerStatefulWidget {
  const _StartMeetingCard();
  @override
  ConsumerState<_StartMeetingCard> createState() => _StartMeetingCardState();
}

class _StartMeetingCardState extends ConsumerState<_StartMeetingCard> {
  bool _pressed = false;

  void _open() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _NewMeetingOptions(ref: ref),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _PressScale(
      onPressedChange: (v) => setState(() => _pressed = v),
      onTap: _open,
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
            // Curved abstract overlay shapes
            Positioned(
              right: -24,
              top: -22,
              child: ClipOval(
                child: Container(
                  width: 100,
                  height: 100,
                  color: Colors.white.withValues(alpha: 0.10),
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
                  color: Colors.white.withValues(alpha: 0.06),
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

class _JoinCodeCard extends ConsumerStatefulWidget {
  const _JoinCodeCard();
  @override
  ConsumerState<_JoinCodeCard> createState() => _JoinCodeCardState();
}

class _JoinCodeCardState extends ConsumerState<_JoinCodeCard> {
  final _controller = TextEditingController();
  bool _validating = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final raw = _controller.text;
    if (raw.trim().isEmpty) {
      _snack('Please enter a meeting code', error: true);
      return;
    }
    final code = MeetingUtils.extractCode(raw);
    if (code.isEmpty) {
      _snack('Invalid meeting code', error: true);
      return;
    }
    setState(() => _validating = true);
    final repo = ref.read(meetingRepositoryProvider);
    final meeting = await repo.getMeetingInfo(code);
    if (!mounted) return;
    setState(() => _validating = false);
    if (meeting == null) {
      _snack('Meeting code is not valid', error: true);
      return;
    }
    final identifier = meeting.code.isNotEmpty ? meeting.code : meeting.id;
    context.push('/pre-join/$identifier');
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? const Color(0xFFB42318) : _Tokens.primary,
        content: Text(msg),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 200,
      padding: const EdgeInsets.fromLTRB(16, 18, 14, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: md.MizdahTokens.border(context), width: 1),
        boxShadow: md.MizdahTokens.shadow(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Join with',
            style: TextStyle(
              color: md.MizdahTokens.mutedOf(context),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Meeting Code',
            style: TextStyle(
              color: md.MizdahTokens.inkOf(context),
              fontSize: 17,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Enter the code and\njoin the meeting',
            style: TextStyle(
              color: md.MizdahTokens.mutedOf(context),
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
                  child: Row(
                    children: [
                      Icon(Icons.link_rounded,
                          color: md.MizdahTokens.mutedOf(context), size: 14),
                      const SizedBox(width: 6),
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          textInputAction: TextInputAction.go,
                          onSubmitted: (_) => _join(),
                          style: TextStyle(
                            color: md.MizdahTokens.inkOf(context),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.2,
                          ),
                          decoration: InputDecoration(
                            isCollapsed: true,
                            border: InputBorder.none,
                            hintText: 'Enter code',
                            hintStyle: TextStyle(
                              color: md.MizdahTokens.mutedOf(context),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: _validating ? null : _join,
                child: Container(
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
                  child: _validating
                      ? const Padding(
                          padding: EdgeInsets.all(10),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(Colors.white),
                          ),
                        )
                      : const Icon(
                          Icons.arrow_forward_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────
//  Upcoming Meetings — header + timeline list (real schedules data)
// ────────────────────────────────────────────────────────────────────

class _UpcomingSection extends ConsumerWidget {
  final AnimationController entryCtrl;
  const _UpcomingSection({required this.entryCtrl});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schedulesAsync = ref.watch(schedulesProvider);

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
                Text(
                  'Upcoming Meetings',
                  style: TextStyle(
                    color: md.MizdahTokens.inkOf(context),
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                const Spacer(),
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () {}, // future: dedicated meetings list page
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 4),
                    child: Row(
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
                  ),
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
                border: Border.all(color: md.MizdahTokens.border(context), width: 1),
                boxShadow: md.MizdahTokens.shadow(context, elevation: 0.7),
              ),
              child: schedulesAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(28),
                  child: Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation(_Tokens.primary),
                      ),
                    ),
                  ),
                ),
                error: (_, __) => const Padding(
                  padding: EdgeInsets.all(20),
                  child: _UpcomingEmpty(
                    icon: Icons.cloud_off_rounded,
                    title: 'Could not load schedules',
                    subtitle: 'Pull down to retry',
                  ),
                ),
                data: (schedules) => schedules.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(20),
                        child: _UpcomingEmpty(
                          icon: Icons.event_available_rounded,
                          title: 'No meetings scheduled',
                          subtitle: 'Tap “Start a Meeting” to plan one',
                        ),
                      )
                    : Column(
                        children: [
                          for (var i = 0; i < schedules.length; i++)
                            _MeetingRow(
                              schedule: schedules[i],
                              colorIndex: i,
                              isFirst: i == 0,
                              isLast: i == schedules.length - 1,
                            ),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UpcomingEmpty extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _UpcomingEmpty({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFFEEF2FF),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: _Tokens.primary, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: md.MizdahTokens.inkOf(context),
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  color: md.MizdahTokens.mutedOf(context),
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MeetingRow extends StatelessWidget {
  final dynamic schedule;
  final int colorIndex;
  final bool isFirst;
  final bool isLast;
  const _MeetingRow({
    required this.schedule,
    required this.colorIndex,
    required this.isFirst,
    required this.isLast,
  });

  /// Recovers the meeting code from a schedule row using the same
  /// priority chain the legacy `_ScheduleTile` used: explicit
  /// `meetingCode` → `meetingId` → `[code]` suffix in the title →
  /// null. See docs/SCHEDULING_BACKEND.md.
  static String? _extractMeetingCode(dynamic s) {
    final code = s['meetingCode']?.toString();
    if (code != null && code.isNotEmpty) return code;
    final mid = s['meetingId']?.toString();
    if (mid != null && mid.isNotEmpty) return mid;
    final title = s['title']?.toString() ?? '';
    final m = RegExp(r'\[([a-z0-9-]{6,})\]').firstMatch(title);
    return m?.group(1);
  }

  /// Strips the `[code]` suffix from titles for display.
  static String _displayTitle(String raw) {
    final stripped =
        raw.replaceAll(RegExp(r'\s*\[[a-z0-9-]{6,}\]\s*$'), '').trim();
    return stripped.isEmpty ? raw : stripped;
  }

  @override
  Widget build(BuildContext context) {
    final start = DateTime.tryParse(schedule['startTime']?.toString() ?? '') ??
        DateTime.now();
    final end = DateTime.tryParse(schedule['endTime']?.toString() ?? '');
    final rawTitle = schedule['title']?.toString() ?? 'Meeting';
    final title = _displayTitle(rawTitle);
    final code = _extractMeetingCode(schedule);
    final palette = _kRowColors[colorIndex % _kRowColors.length];
    final iconBg = palette[0];
    final iconFg = palette[1];

    final timeRange = end != null
        ? '${DateFormat('h:mm a').format(start)} – ${DateFormat('h:mm a').format(end)}'
        : DateFormat('h:mm a').format(start);
    final duration = end != null
        ? _formatDuration(end.difference(start))
        : (schedule['timezone']?.toString() ?? 'IST');

    void onTap() {
      if (code == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(
                'No meeting code on this schedule yet — open it from the calendar invite.'),
          ),
        );
        return;
      }
      context.push('/pre-join/$code');
    }

    return _PressScale(
      scaleTo: 0.98,
      onTap: onTap,
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
                color: iconBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Text(
                    DateFormat('MMM').format(start).toUpperCase(),
                    style: TextStyle(
                      color: iconFg,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                  Text(
                    DateFormat('d').format(start),
                    style: TextStyle(
                      color: iconFg,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.6,
                      height: 1.05,
                    ),
                  ),
                  Text(
                    DateFormat('EEE').format(start).toUpperCase(),
                    style: TextStyle(
                      color: iconFg.withValues(alpha: 0.75),
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
                  Positioned.fill(
                    child: Padding(
                      padding: EdgeInsets.only(
                        top: isFirst ? 22 : 0,
                        bottom: isLast ? 22 : 0,
                      ),
                      child: Center(
                        child: Container(
                          width: 1.2,
                          color: md.MizdahTokens.subtle(context),
                        ),
                      ),
                    ),
                  ),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: iconFg,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: iconFg.withValues(alpha: 0.4),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            // Title + time + code chip
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: md.MizdahTokens.inkOf(context),
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
                          timeRange,
                          style: TextStyle(
                            color: md.MizdahTokens.mutedOf(context),
                            fontSize: 10.5,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        ' · ',
                        style: TextStyle(
                            color: md.MizdahTokens.mutedOf(context), fontSize: 10.5),
                      ),
                      Text(
                        duration,
                        style: TextStyle(
                          color: md.MizdahTokens.mutedOf(context),
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ),
                  if (code != null) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEEF2FF),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        code,
                        style: const TextStyle(
                          color: _Tokens.primary,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 6),
            // Action icon
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.videocam_rounded, color: iconFg, size: 16),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatDuration(Duration d) {
    if (d.inMinutes < 60) return '${d.inMinutes} min';
    final h = d.inHours;
    final m = d.inMinutes % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }
}

// ────────────────────────────────────────────────────────────────────
//  Recent activity card — uses the most recent CallHistory item
// ────────────────────────────────────────────────────────────────────

class _RecentActivityCard extends ConsumerWidget {
  final AnimationController entryCtrl;
  const _RecentActivityCard({required this.entryCtrl});

  /// How many recent meetings to show inline on home. The full list
  /// lives behind the "View all" link on the Meetings tab.
  static const int _maxRows = 4;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(callHistoryProvider);
    final user = ref.watch(authProvider).user;

    return _FadeUp(
      controller: entryCtrl,
      delay: 0.34,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header row: title + "View all" → Meetings tab ──────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Row(
              children: [
                Text(
                  'Recent Activity',
                  style: TextStyle(
                    color: md.MizdahTokens.inkOf(context),
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                const Spacer(),
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => context.go('/meetings?tab=recent'),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 4),
                    child: Row(
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
                  ),
                ),
              ],
            ),
          ),
          // ── Body card: 4-row list of host/joined entries ───────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                color: md.MizdahTokens.surface(context),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                    color: md.MizdahTokens.border(context), width: 1),
                boxShadow: md.MizdahTokens.shadow(context, elevation: 0.5),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Stack(
                  children: [
                    // Soft diagonal pattern, only behind data state.
                    Positioned.fill(
                      child: CustomPaint(painter: _DiagonalPattern()),
                    ),
                    historyAsync.when(
                      loading: () => const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(
                                  _Tokens.primary),
                            ),
                          ),
                        ),
                      ),
                      error: (_, __) => _emptyRow(
                        context: context,
                        icon: Icons.cloud_off_rounded,
                        title: 'Could not load',
                        subtitle: 'Pull down to retry',
                      ),
                      data: (items) {
                        if (items.isEmpty) {
                          return _emptyRow(
                            context: context,
                            icon: Icons.history_rounded,
                            title: 'No recent activity',
                            subtitle:
                                'Your past meetings will show here',
                          );
                        }
                        final shown = items.length > _maxRows
                            ? items.sublist(0, _maxRows)
                            : items;
                        return Column(
                          children: [
                            for (var i = 0; i < shown.length; i++) ...[
                              _RecentActivityRow(
                                item: shown[i],
                                isHost: shown[i].hostId != null &&
                                    user != null &&
                                    shown[i].hostId == user.id,
                              ),
                              if (i < shown.length - 1)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14),
                                  child: Divider(
                                    height: 1,
                                    thickness: 1,
                                    color: md.MizdahTokens.subtle(context),
                                  ),
                                ),
                            ],
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyRow({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: md.MizdahTokens.iconTileBg(context),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: _Tokens.primary, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: md.MizdahTokens.inkOf(context),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: md.MizdahTokens.mutedOf(context),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
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

/// One row in the Recent Activity list. Visually distinguishes
/// hosted (purple gradient) vs joined (emerald gradient) so the
/// user can scan their history at a glance.
class _RecentActivityRow extends ConsumerWidget {
  final CallHistory item;
  final bool isHost;
  const _RecentActivityRow({required this.item, required this.isHost});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.read(authProvider).user;
    final palette = _palette(isHost);
    final displayTitle = (item.title.contains('http') ||
            item.title.length > 24)
        ? (item.meetingCode ?? 'Meeting')
        : item.title;

    return InkWell(
      onTap: () {
        showModalBottomSheet(
          context: context,
          backgroundColor: Colors.transparent,
          isScrollControlled: true,
          builder: (_) => _HistoryDetailModal(
            item: item,
            isHost: item.hostId != null &&
                user != null &&
                item.hostId == user.id,
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            // Gradient pill icon — distinct per role.
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: palette.iconGradient,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: palette.glow.withValues(alpha: 0.30),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(
                isHost
                    ? Icons.video_call_rounded
                    : Icons.call_received_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // Role pill — "HOSTED" / "JOINED"
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: palette.chipBg,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          isHost ? 'HOSTED' : 'JOINED',
                          style: TextStyle(
                            color: palette.chipFg,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          displayTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: md.MizdahTokens.inkOf(context),
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    DateFormat('MMM d, h:mm a').format(item.timestamp),
                    style: TextStyle(
                      color: md.MizdahTokens.mutedOf(context),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: md.MizdahTokens.mutedOf(context), size: 18),
          ],
        ),
      ),
    );
  }

  _RolePalette _palette(bool isHost) {
    return isHost
        ? const _RolePalette(
            iconGradient: LinearGradient(
              colors: [Color(0xFF6C63FF), Color(0xFF8B5CF6)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            glow: Color(0xFF6C63FF),
            chipBg: Color(0xFFEDE9FE),
            chipFg: Color(0xFF6C63FF),
          )
        : const _RolePalette(
            iconGradient: LinearGradient(
              colors: [Color(0xFF10B981), Color(0xFF059669)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            glow: Color(0xFF10B981),
            chipBg: Color(0xFFD1FAE5),
            chipFg: Color(0xFF047857),
          );
  }
}

class _RolePalette {
  final LinearGradient iconGradient;
  final Color glow;
  final Color chipBg;
  final Color chipFg;
  const _RolePalette({
    required this.iconGradient,
    required this.glow,
    required this.chipBg,
    required this.chipFg,
  });
}

class _DiagonalPattern extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF6C63FF).withValues(alpha: 0.025)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;
    const step = 12.0;
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

class _FloatingNav extends StatefulWidget {
  const _FloatingNav();

  @override
  State<_FloatingNav> createState() => _FloatingNavState();
}

class _FloatingNavState extends State<_FloatingNav>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  // Currently-active tab index. Home is the only one that "stays"
  // active (this IS the home screen); Meetings/People/Settings are
  // momentary highlights that bounce back to Home after their action
  // fires, so the pill indicator does a satisfying slide animation
  // even when the route doesn't actually change.
  int _activeIndex = 0;

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

  void _activate(int index) {
    if (_activeIndex == index) return;
    setState(() => _activeIndex = index);
    // Briefly highlight the tapped tab, then snap back to Home —
    // since none of the secondary tabs actually change the screen
    // permanently, having Home "win" again after ~280ms keeps the
    // visual state honest with where the user actually is.
    if (index != 0) {
      Future.delayed(const Duration(milliseconds: 280), () {
        if (!mounted) return;
        setState(() => _activeIndex = 0);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        // Stronger blur (30 from 22) for a more pronounced frosted-
        // glass read on busy backgrounds, especially when scrolling
        // colourful card content underneath.
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            // Vertical white→translucent gradient adds depth that a
            // flat fill can't — the top of the bar reads brighter
            // (specular highlight) and the bottom reads softer.
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
              // Stronger purple-tinted ambient glow for the
              // floating-glass effect.
              BoxShadow(
                color: const Color(0xFF6C63FF).withValues(alpha: 0.16),
                blurRadius: 36,
                offset: const Offset(0, 18),
              ),
              // Mid-distance neutral shadow so the bar doesn't look
              // weightless on light backgrounds.
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
              // Tiny inner-edge highlight (mimics an inset 1px white
              // line) — sits at the top of the bar.
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
                  activeIndex: _activeIndex,
                  pulseCtrl: _pulseCtrl,
                  icon: Icons.home_rounded,
                  label: 'Home',
                  onTap: () => _activate(0),
                ),
              ),
              Expanded(
                child: _NavItem(
                  index: 1,
                  activeIndex: _activeIndex,
                  pulseCtrl: _pulseCtrl,
                  icon: Icons.calendar_month_rounded,
                  label: 'Meetings',
                  onTap: () {
                    _activate(1);
                    // No dedicated meetings page yet — fall back to
                    // the schedule-creation sheet which is the natural
                    // next-step from "look at my calendar" intent.
                    final ctx = context;
                    final ref = ProviderScope.containerOf(ctx);
                    showModalBottomSheet(
                      context: ctx,
                      backgroundColor: Colors.transparent,
                      isScrollControlled: true,
                      builder: (sheetCtx) => _NewMeetingOptions(
                        ref: _ContainerWidgetRefShim(ref),
                      ),
                    );
                  },
                ),
              ),
              Expanded(
                child: _NavItem(
                  index: 2,
                  activeIndex: _activeIndex,
                  pulseCtrl: _pulseCtrl,
                  icon: Icons.people_outline_rounded,
                  label: 'People',
                  onTap: () {
                    _activate(2);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        behavior: SnackBarBehavior.floating,
                        content: Text('People directory coming soon'),
                      ),
                    );
                  },
                ),
              ),
              Expanded(
                child: _NavItem(
                  index: 3,
                  activeIndex: _activeIndex,
                  pulseCtrl: _pulseCtrl,
                  icon: Icons.settings_outlined,
                  label: 'Settings',
                  onTap: () {
                    _activate(3);
                    context.push('/settings');
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lets us call sheet builders that expect `WidgetRef` from places we
/// only have a `ProviderContainer`. Wraps just the `read` API since
/// that's all `_NewMeetingOptions` uses.
class _ContainerWidgetRefShim implements WidgetRef {
  final ProviderContainer _container;
  _ContainerWidgetRefShim(this._container);

  @override
  T read<T>(ProviderListenable<T> provider) => _container.read(provider);

  @override
  void invalidate(ProviderOrFamily provider) =>
      _container.invalidate(provider);

  // Noop for unused members — _NewMeetingOptions only calls `read`
  // and `invalidate` so the rest can throw if anyone wires it
  // somewhere richer later.
  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnsupportedError('Only read() / invalidate() are supported');
}

/// One tab in the floating bottom nav. Animates between the
/// inactive grey state and the active gradient state via a 240ms
/// AnimatedSwitcher, plus a subtle press-scale on tap. The active
/// pill indicator pulses softly via the shared pulseCtrl.
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
    // No Expanded here — `Expanded` must be a direct child of the
    // parent Row, not nested inside _NavItem. The parent _FloatingNav
    // wraps each _NavItem with Expanded itself.
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
        // Pulsing pill indicator — the pulseCtrl is shared across
        // every nav item so they all breathe in sync (only the
        // active one is visible at any time).
        AnimatedBuilder(
          animation: pulseCtrl,
          builder: (context, _) {
            // pulseCtrl reverses, so .value is naturally a 0→1→0
            // wave we can drive opacity + glow radius off.
            final t = pulseCtrl.value;
            return Container(
              margin: const EdgeInsets.only(top: 3),
              width: 16 + t * 2, // 16 → 18 → 16
              height: 3,
              decoration: BoxDecoration(
                gradient: _Tokens.heroGradient,
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
  final VoidCallback? onTap;
  const _PressScale({
    required this.child,
    this.scaleTo = 0.97,
    this.onPressedChange,
    this.onTap,
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

// ════════════════════════════════════════════════════════════════════
//  PRESERVED FROM LEGACY HOME SCREEN
//  Drawers, dialogs, sheets, history modal — referenced by the new
//  home screen + by pre_join_screen (callHistoryProvider /
//  schedulesProvider invalidation). Code is unchanged from the
//  pre-redesign version so behaviour stays identical.
// ════════════════════════════════════════════════════════════════════

class JoinCodeDialog extends ConsumerStatefulWidget {
  const JoinCodeDialog({super.key});

  @override
  ConsumerState<JoinCodeDialog> createState() => _JoinCodeDialogState();
}

class _JoinCodeDialogState extends ConsumerState<JoinCodeDialog> {
  final _controller = TextEditingController();
  bool _isLoading = false;

  Future<void> _onJoin() async {
    if (_controller.text.isEmpty) return;
    setState(() => _isLoading = true);
    final repo = ref.read(meetingRepositoryProvider);
    final meeting = await repo.getMeetingInfo(_controller.text);
    if (mounted) {
      setState(() => _isLoading = false);
      if (meeting != null) {
        Navigator.pop(context);
        final identifier =
            meeting.code.isNotEmpty ? meeting.code : meeting.id;
        context.push('/pre-join/$identifier');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid meeting code')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Join with code'),
      content: TextField(
        controller: _controller,
        decoration: const InputDecoration(
          hintText: 'Example: abc-defg-hij',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        _isLoading
            ? const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : ElevatedButton(
                onPressed: _onJoin,
                child: const Text('Join'),
              ),
      ],
    );
  }
}

class NotificationsDrawer extends ConsumerWidget {
  const NotificationsDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notificationsAsync = ref.watch(notificationsProvider);

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Notifications',
                      style: TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  )
                ],
              ),
            ),
            const Divider(),
            Expanded(
              child: notificationsAsync.when(
                data: (notifications) {
                  if (notifications.isEmpty) {
                    return const Center(
                        child: Text('No new notifications',
                            style: TextStyle(color: Colors.grey)));
                  }
                  return ListView.builder(
                    itemCount: notifications.length,
                    itemBuilder: (ctx, i) {
                      final n = notifications[i];
                      return ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: Color(0xFFEEF2FF),
                          child: Icon(Icons.notifications,
                              color: _Tokens.primary, size: 18),
                        ),
                        title: Text(n.title,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600)),
                        subtitle: Text(n.body,
                            style: const TextStyle(fontSize: 12)),
                        trailing: Text(
                          DateFormat('h:mm a').format(n.createdAt),
                          style: const TextStyle(
                              fontSize: 11, color: Colors.grey),
                        ),
                      );
                    },
                  );
                },
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (_, __) =>
                    const Center(child: Text('Failed to load')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MizdahDrawer extends ConsumerWidget {
  const MizdahDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;

    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(
              gradient: _Tokens.heroGradient,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      (user?.name.isNotEmpty == true)
                          ? user!.name[0].toUpperCase()
                          : 'A',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(user?.name ?? 'Guest User',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold)),
                Text(user?.email ?? '',
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.dashboard_customize_outlined),
            title: const Text('Meeting layout designs'),
            onTap: () => context.push('/meeting-designs'),
          ),
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text('Settings'),
            onTap: () => context.push('/settings'),
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Privacy'),
            onTap: () => context.push('/privacy'),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Logout',
                style: TextStyle(color: Colors.red)),
            onTap: () {
              ref.read(authProvider.notifier).logout();
              context.go('/login');
            },
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
//  Providers — exported (pre_join_screen invalidates these)
// ════════════════════════════════════════════════════════════════════

final callHistoryProvider = FutureProvider<List<CallHistory>>((ref) async {
  final authState = ref.watch(authProvider);
  if (authState.user == null) return [];
  final repo = ref.watch(participantRepositoryProvider);
  return repo.getUserHistory(authState.user!.id);
});

final schedulesProvider = FutureProvider<List<dynamic>>((ref) async {
  final authState = ref.watch(authProvider);
  if (authState.user == null) return [];
  final repo = ref.watch(schedulingRepositoryProvider);
  return repo.getUserSchedules(authState.user!.id);
});

final googleCalendarServiceProvider =
    Provider((ref) => GoogleCalendarService());

// ════════════════════════════════════════════════════════════════════
//  Bottom-sheet for "Start a Meeting" — preserved from legacy
// ════════════════════════════════════════════════════════════════════

class _NewMeetingOptions extends StatelessWidget {
  final WidgetRef ref;
  const _NewMeetingOptions({required this.ref});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1F2E) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 20,
            spreadRadius: 5,
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Create Meeting',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 24),
              _OptionTile(
                icon: Icons.link_rounded,
                title: 'Create a meeting for later',
                subtitle: 'Get a link you can share with others',
                color: Colors.blue,
                onTap: () => _createMeeting(context, 'Share'),
              ),
              const SizedBox(height: 12),
              _OptionTile(
                icon: Icons.video_call_rounded,
                title: 'Start an instant meeting',
                subtitle: 'Join and invite people right now',
                color: Colors.green,
                onTap: () {
                  Navigator.pop(context);
                  context.push('/pre-join');
                },
              ),
              const SizedBox(height: 12),
              _OptionTile(
                icon: Icons.calendar_today_rounded,
                title: 'Schedule in Google Calendar',
                subtitle: 'Plan a meeting in your calendar',
                color: Colors.orange,
                onTap: () => _scheduleMeeting(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _createMeeting(BuildContext context, String mode) async {
    final repository = ref.read(mizdahRepositoryProvider);
    final code = MeetingUtils.generateMeetingCode();

    try {
      final meeting = await repository.createMeeting(
        title: 'Meeting',
        dateTime: DateTime.now(),
        code: code,
      );

      if (context.mounted) {
        Navigator.pop(context);
        ref.invalidate(callHistoryProvider);
        ref.invalidate(schedulesProvider);

        if (mode == 'Join') {
          if (context.mounted) {
            context.push('/pre-join/${meeting.code}');
          }
        } else if (mode == 'Share') {
          if (context.mounted) {
            showModalBottomSheet(
              context: context,
              backgroundColor: Colors.transparent,
              builder: (context) => _ShareLinkModal(meeting: meeting),
            );
          }
        }
      }
    } catch (_) {
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to create meeting')),
        );
      }
    }
  }

  Future<void> _scheduleMeeting(BuildContext context) async {
    final scheduleRepo = ref.read(schedulingRepositoryProvider);
    final meetingRepo = ref.read(mizdahRepositoryProvider);
    final calendarService = ref.read(googleCalendarServiceProvider);
    final user = ref.read(authProvider).user;

    if (user == null) return;
    Navigator.pop(context);

    try {
      final startTime = DateTime.now().add(const Duration(hours: 1));
      final endTime = startTime.add(const Duration(hours: 1));
      final timezone = DateTime.now().timeZoneName;

      // Create the actual meeting room first so we have a real
      // join code; the schedule row references it. Backend currently
      // drops dedicated meetingId/meetingCode fields so we also embed
      // the code in the title — see docs/SCHEDULING_BACKEND.md.
      final code = MeetingUtils.generateMeetingCode();
      final meeting = await meetingRepo.createMeeting(
        title: 'Mizdah Meeting',
        dateTime: startTime,
        code: code,
      );
      final realCode = meeting.code;

      await scheduleRepo.scheduleMeeting(
        hostId: user.id,
        title: 'Mizdah Meeting [$realCode]',
        startTime: startTime,
        endTime: endTime,
        recurrence: 'none',
        timezone: timezone,
        meetingId: meeting.id,
        meetingCode: realCode,
      );

      final link = MeetingUtils.generateMeetingLink(realCode);
      await calendarService.openGoogleCalendarTemplate(
        title: 'Mizdah Meeting',
        description: 'Join with Mizdah: $link\nMeeting Code: $realCode',
        location: link,
        startTime: startTime,
      );

      ref.invalidate(schedulesProvider);
      ref.invalidate(callHistoryProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to schedule meeting: $e')),
        );
      }
    }
  }
}

class _OptionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  const _OptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.black.withValues(alpha: 0.02),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.black.withValues(alpha: 0.05),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: isDark ? Colors.white70 : Colors.black54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: isDark ? Colors.white24 : Colors.black26,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShareLinkModal extends StatelessWidget {
  final Meeting meeting;
  const _ShareLinkModal({required this.meeting});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1F2E) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const SizedBox(width: 60),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.black12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'Done',
                    style: TextStyle(
                      color: _Tokens.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _Tokens.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.link_rounded,
                  color: _Tokens.primary, size: 36),
            ),
            const SizedBox(height: 20),
            const Text(
              'Meeting link ready',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              'Share this link with participants you want in the meeting.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isDark ? Colors.white70 : Colors.black54,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.black.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.1)
                      : Colors.black.withValues(alpha: 0.1),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      MeetingUtils.generateMeetingLink(meeting.code),
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        letterSpacing: 0.5,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        Clipboard.setData(ClipboardData(
                            text: MeetingUtils.generateMeetingLink(
                                meeting.code)));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Link copied to clipboard')),
                        );
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: _Tokens.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.copy_rounded,
                            size: 18, color: _Tokens.primary),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            MizdahButton(
              label: 'Share Invite',
              icon: Icons.share_rounded,
              onTap: () {
                final link =
                    MeetingUtils.generateMeetingLink(meeting.code);
                SharePlus.instance.share(
                  ShareParams(
                    text: 'Join my Mizdah meeting: $link',
                    subject: 'Mizdah Meeting Invite',
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryDetailModal extends StatelessWidget {
  final CallHistory item;
  final bool isHost;
  const _HistoryDetailModal({required this.item, required this.isHost});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final displayTitle = (item.title.contains('http') || item.title.length > 20)
        ? (item.meetingCode ?? 'Meeting')
        : item.title;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1F2E) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: isDark ? Colors.white24 : Colors.black12,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),
          CircleAvatar(
            radius: 32,
            backgroundColor: isHost
                ? Colors.green.withValues(alpha: 0.1)
                : _Tokens.primary.withValues(alpha: 0.1),
            child: Icon(
              isHost ? Icons.outbound_rounded : Icons.call_received_rounded,
              color: isHost ? Colors.green : _Tokens.primary,
              size: 32,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            displayTitle,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            isHost ? 'Meeting you hosted' : 'Meeting you joined',
            style: TextStyle(
              color: isHost ? Colors.green : _Tokens.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 24),
          if (item.meetingCode != null)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : const Color(0xFFF6F7FB),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  const Icon(Icons.link_rounded, color: _Tokens.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Meeting Code',
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey)),
                        const SizedBox(height: 2),
                        Text(
                          item.meetingCode!,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy_rounded,
                        color: _Tokens.primary),
                    onPressed: () {
                      Clipboard.setData(
                          ClipboardData(text: item.meetingCode!));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Code copied')),
                      );
                    },
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          Text(
            DateFormat('EEE, MMM d · h:mm a').format(item.timestamp),
            style: const TextStyle(color: Colors.grey, fontSize: 13),
          ),
          const SizedBox(height: 20),
          if (item.meetingCode != null)
            MizdahButton(
              label: 'Rejoin meeting',
              icon: Icons.video_call_rounded,
              onTap: () {
                Navigator.pop(context);
                context.push('/pre-join/${item.meetingCode}');
              },
            ),
        ],
      ),
    );
  }
}
