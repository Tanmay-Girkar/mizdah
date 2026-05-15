import 'dart:async';
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
import '../../../core/services/push_notification_service.dart';
import '../../scheduling/calendar_event_sync.dart';
import '../../scheduling/data/calendar_payload.dart';
import '../../scheduling/data/scheduled_meeting.dart';
import '../../scheduling/scheduled_meetings_provider.dart';
import '../../scheduling/scheduling_provider.dart';
import '../../chats/chats_provider.dart';
import '../../meeting/recent_meetings_provider.dart';
import '../../meetings/presentation/rejoin_sheet.dart';
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
    // Pre-warm the chats stream the moment the home screen mounts so
    // that by the time the user taps the Chats tab the conversation
    // list is already loaded. `StatefulShellRoute.indexedStack`
    // lazy-mounts branches by default, so without this the first
    // chat-tab open eats a fresh REST round-trip.
    //
    // `ref.read` on a StreamProvider initialises it; the underlying
    // RealChatRepository starts its REST refresh + spins up the
    // /chats socket. The provider stays alive (no .autoDispose) so
    // the result is cached for the rest of the session.
    Future.microtask(() {
      if (!mounted) return;
      // ignore: unused_local_variable
      final _ = ref.read(conversationsProvider);
    });
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
    final navInset = md.MizdahTokens.navBarBottomInset(context);
    return Scaffold(
      backgroundColor: md.MizdahTokens.bg(context),
      // Don't let the keyboard push the whole layout up — only the
      // active scroll region inside `Expanded` should compress.
      // Matches WhatsApp's behaviour where the header stays put
      // even when an input field at the bottom is focused.
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // Faint background gradient wash — adaptive: lavender →
          // off-white in light mode, deep navy in dark mode.
          // Spans the FULL window (under the floating nav too) so the
          // BackdropFilter has something to frost.
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: md.MizdahTokens.pageGradient(context),
              ),
            ),
          ),

          // Body — bounded ABOVE the floating nav (`bottom: navInset`)
          // so scroll content can never render under the nav. Inside,
          // the layout splits into a PINNED header + a scrollable
          // body so dragging only moves the list. Header, logo,
          // hamburger and bell stay locked in place — no parent
          // bounce, no parallax, just the list responding.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            bottom: navInset,
            child: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  // ── Pinned header — stays put during scroll ─────
                  _Header(entryCtrl: _entryCtrl),
                  // ── Scrollable content area ─────────────────────
                  Expanded(
                    child: RefreshIndicator(
                      color: _Tokens.primary,
                      // Spinner appears 32 px below the top of the
                      // scroll region so it lives in the body, not
                      // over the header — keeps the gesture subtle.
                      displacement: 32,
                      edgeOffset: 0,
                      onRefresh: () async {
                        ref.invalidate(callHistoryProvider);
                        ref.invalidate(schedulesProvider);
                      },
                      child: ListView(
                        padding: const EdgeInsets.only(bottom: 8),
                        // Rigid Telegram / WhatsApp-style scroll —
                        // ClampingScrollPhysics removes the iOS
                        // bounce entirely; AlwaysScrollableScrollPhysics
                        // wrapper keeps RefreshIndicator working on
                        // short content. App-wide MizdahScrollBehavior
                        // additionally suppresses Android's stretch
                        // overscroll glow.
                        physics: const ClampingScrollPhysics(
                          parent: AlwaysScrollableScrollPhysics(),
                        ),
                        children: [
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
                ],
              ),
            ),
          ),

          // The floating nav is rendered by the shell route
          // (`MizdahTabsShell`) so it never rebuilds on tab change.
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
        // Stack lays the wordmark exactly on the screen-horizontal
        // centre instead of "the middle of the leftover row space".
        // Two Spacers can't do that here — the right side has the
        // bell + avatar (~62 px) while the left has nothing, so the
        // wordmark drifts a couple of points to the left under the
        // old Row layout. With Stack + Align.center the icons can
        // still grow on the right without nudging the logo.
        child: SizedBox(
          height: 36,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Logo + wordmark — anchored to the visual centre.
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
                          color:
                              const Color(0xFF6C63FF).withValues(alpha: 0.3),
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
              // Action icons — flush right, never pushes the logo.
              Align(
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Bell with notification dot. Tapping pushes the
                    // dedicated /notifications screen — the right-side
                    // drawer was removed, since a full page is what
                    // most apps use here.
                    _IconTap(
                      onTap: () => context.push('/notifications'),
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
                                      color: md.MizdahTokens.bg(context),
                                      width: 1.2,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // Avatar — tap opens the small profile card with
                    // DP + name + Logout. Wrapped in a `Builder` so the
                    // `BuildContext` we pass to `_showProfileCard` is
                    // anchored to the avatar's position (used to draw
                    // the popover under it).
                    Builder(
                      builder: (avatarContext) => GestureDetector(
                        onTap: () => _showProfileCard(
                          avatarContext,
                          ref,
                          user: user,
                          initial: initial,
                        ),
                        child: _HeaderAvatar(
                          avatarUrl: user?.avatarUrl,
                          initial: initial,
                        ),
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

  /// Small floating card anchored under the header avatar. Replaces
  /// the previous full-height left drawer — most apps reserve the
  /// avatar tap for a compact identity card with a Logout shortcut,
  /// and the menu items the old drawer carried (Settings, Privacy,
  /// Meeting layout designs) are reachable from the Settings tab.
  ///
  /// Uses `showGeneralDialog` rather than `showMenu` because
  /// `PopupMenuItem` enforces ListTile-ish sizing that fights the
  /// avatar-row layout we want.
  Future<void> _showProfileCard(
    BuildContext context,
    WidgetRef ref, {
    required User? user,
    required String initial,
  }) async {
    // Snapshot the router context BEFORE the dialog opens. The
    // dialog's own `BuildContext` is detached the instant we pop it,
    // so using it to `context.go('/login')` after pop would crash.
    final router = GoRouter.of(context);
    final mq = MediaQuery.of(context);
    // Top inset (status bar) + header padding (16) + avatar height
    // (32) puts the card cleanly under the avatar.
    final topOffset = mq.padding.top + 16 + 32 + 8;

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'profile-card',
      barrierColor: Colors.black.withValues(alpha: 0.18),
      transitionDuration: const Duration(milliseconds: 140),
      pageBuilder: (dialogCtx, anim, secAnim) {
        return SafeArea(
          child: Stack(
            children: [
              Positioned(
                top: topOffset,
                right: 16,
                child: FadeTransition(
                  opacity: anim,
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 0.96, end: 1).animate(
                      CurvedAnimation(
                        parent: anim,
                        curve: Curves.easeOutCubic,
                      ),
                    ),
                    alignment: Alignment.topRight,
                    child: Material(
                      color: Colors.transparent,
                      child: _ProfileCard(
                        user: user,
                        initial: initial,
                        onLogout: () {
                          Navigator.of(dialogCtx).pop();
                          ref.read(authProvider.notifier).logout();
                          router.go('/login');
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Small dropdown card body: DP + name + email + Logout. Sits inside
/// the `showGeneralDialog` page builder.
class _ProfileCard extends StatelessWidget {
  final User? user;
  final String initial;
  final VoidCallback onLogout;

  const _ProfileCard({
    required this.user,
    required this.initial,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    final ink = md.MizdahTokens.inkOf(context);
    return Container(
      width: 260,
      decoration: BoxDecoration(
        color: md.MizdahTokens.surface(context),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _HeaderAvatar(
                avatarUrl: user?.avatarUrl,
                initial: initial,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user?.name.isNotEmpty == true
                          ? user!.name
                          : 'Guest user',
                      style: TextStyle(
                        color: ink,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (user?.email.isNotEmpty == true) ...[
                      const SizedBox(height: 2),
                      Text(
                        user!.email,
                        style: TextStyle(
                          color: ink.withValues(alpha: 0.6),
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Divider(
            height: 1,
            color: ink.withValues(alpha: 0.08),
          ),
          const SizedBox(height: 4),
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onLogout,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              child: Row(
                children: const [
                  Icon(Icons.logout_rounded,
                      color: Color(0xFFB42318), size: 18),
                  SizedBox(width: 10),
                  Text(
                    'Logout',
                    style: TextStyle(
                      color: Color(0xFFB42318),
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
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

/// Header avatar — renders the network photo when the user has set
/// one, falling back to a gradient circle with their initial. Sized
/// 32×32 to fit alongside the wordmark.
class _HeaderAvatar extends StatelessWidget {
  final String? avatarUrl;
  final String initial;
  const _HeaderAvatar({required this.avatarUrl, required this.initial});

  bool get _hasUrl => avatarUrl != null && avatarUrl!.trim().isNotEmpty;

  Widget _fallback(BuildContext context) => Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          gradient: _Tokens.heroGradient,
          shape: BoxShape.circle,
        ),
        child: Text(
          initial,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final shadow = md.MizdahTokens.shadow(context, elevation: 0.6);
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: shadow,
      ),
      child: ClipOval(
        child: _hasUrl
            ? Image.network(
                avatarUrl!,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                loadingBuilder: (ctx, child, progress) =>
                    progress == null ? child : _fallback(context),
                errorBuilder: (_, __, ___) => _fallback(context),
              )
            : _fallback(context),
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
    // useRootNavigator so the sheet renders above the floating nav
    // (which lives in the shell route). Without it, the third tile —
    // "Schedule in Google Calendar" — gets hidden under the nav.
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useRootNavigator: true,
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
    // `.toLocal()` is what flips the UTC wire-format back to the
    // device's wall clock. Without it, a meeting scheduled for 4PM
    // local arrives back as `2026-05-11T10:30:00Z`, parses as a
    // UTC DateTime, and `DateFormat('h:mm a')` renders "10:30 AM"
    // instead of "4:00 PM" because DateFormat is timezone-agnostic.
    final start =
        DateTime.tryParse(schedule['startTime']?.toString() ?? '')?.toLocal() ??
            DateTime.now();
    final end =
        DateTime.tryParse(schedule['endTime']?.toString() ?? '')?.toLocal();
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
    // Use the MERGED provider — REST snapshot overlaid with live
    // socket presence. The home recent-activity card and the
    // Meetings → Recent list now read from the same source, so a
    // meeting that ends in real-time updates both screens together.
    final historyAsync = ref.watch(recentMeetingsProvider);
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
    // `ref` is intentionally unread here — the parent already
    // computed `isHost` against the current user. We still keep it
    // a `ConsumerWidget` build signature so future presence-aware
    // additions to this row (LIVE pill etc.) can read providers
    // without changing the class shape.
    final palette = _palette(isHost);
    final displayTitle = (item.title.contains('http') ||
            item.title.length > 24)
        ? (item.meetingCode ?? 'Meeting')
        : item.title;

    return InkWell(
      onTap: () {
        // Route through the unified presence-aware sheet defined in
        // `lib/features/meetings/presentation/rejoin_sheet.dart`. It
        // handles BOTH active and ended states — shows the rejoin
        // button (live count, etc.) when the meeting is live, or the
        // "Meeting ended" state when it's not. Clears the floating
        // bottom nav via navBarBottomInset, so the action row never
        // hides behind the tab bar — that was the previous bug where
        // _HistoryDetailModal's Rejoin button rendered under the nav.
        showRejoinSheet(context, meeting: item);
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
                      useRootNavigator: true,
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
                  icon: Icons.chat_bubble_outline_rounded,
                  label: 'Chats',
                  onTap: () {
                    _activate(2);
                    context.go('/chats');
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

// ════════════════════════════════════════════════════════════════════
//  Providers — exported (pre_join_screen invalidates these)
// ════════════════════════════════════════════════════════════════════

final callHistoryProvider = FutureProvider<List<CallHistory>>((ref) async {
  final authState = ref.watch(authProvider);
  if (authState.user == null) return [];
  final repo = ref.watch(participantRepositoryProvider);
  return repo.getUserHistory(authState.user!.id);
});

/// Schedules visible in "Upcoming Meetings" — merges three sources
/// in this priority order:
///
///   1. **Local sheet-scheduled meetings** (`scheduledMeetingsProvider`)
///      — the user just tapped Save in the in-app schedule sheet.
///      Local-first so the row appears INSTANTLY, no network wait.
///   2. **Backend schedules** (`schedulingRepositoryProvider.getUserSchedules`)
///      — meetings the user (or invitee) made through some other
///      surface (web, another device).
///
/// On top of the merge we apply two transforms:
///
///   • **Drop already-ended meetings.** Without this filter, a
///     meeting that ended an hour ago still shows in "Upcoming
///     Meetings" until the user logs out — the row is technically
///     still in the database, the backend doesn't auto-archive past
///     schedules. We hide anything whose end time (or `start + 1h`
///     fallback) is older than 10 minutes ago so a meeting that
///     just started doesn't vanish out from under joiners.
///   • **Sort by start time ascending.** Older meetings near the top
///     ("starting next") makes "Upcoming" scannable.
///
/// **Dedupe rule:** if a local row and a backend row have the same
/// `meetingCode`, the local row wins (we just typed it; it has the
/// most up-to-date title / description). This handles the case where
/// the user's own `scheduleMeeting` POST round-trips back via the
/// backend list.
final schedulesProvider = FutureProvider<List<dynamic>>((ref) async {
  // 1. Local rows — `.watch` so a new schedule re-fires this future.
  final local = ref.watch(scheduledMeetingsProvider);

  // 2. Backend rows — best-effort. Repo already returns [] on failure.
  final authState = ref.watch(authProvider);
  List<dynamic> remote = const [];
  if (authState.user != null) {
    final repo = ref.read(schedulingRepositoryProvider);
    remote = await repo.getUserSchedules(authState.user!.id);
  }

  // 3. Merge with dedupe — local takes precedence on meetingCode match.
  final localCodes = {for (final m in local) m.meetingCode};
  final merged = <dynamic>[
    for (final m in local) m.toScheduleMap(),
    for (final r in remote)
      if (r is Map &&
          !localCodes.contains(r['meetingCode']?.toString()))
        r,
  ];

  // 4. Filter past + sort.
  final cutoff = DateTime.now().subtract(const Duration(minutes: 10));
  final out = <dynamic>[];
  for (final s in merged) {
    if (s is! Map) continue;
    final start =
        DateTime.tryParse(s['startTime']?.toString() ?? '')?.toLocal();
    if (start == null) continue;
    final end = DateTime.tryParse(s['endTime']?.toString() ?? '')?.toLocal() ??
        start.add(const Duration(hours: 1));
    if (end.isBefore(cutoff)) continue;
    out.add(s);
  }
  out.sort((a, b) {
    final ay = DateTime.tryParse(a['startTime']?.toString() ?? '')?.toLocal() ??
        DateTime.now();
    final by = DateTime.tryParse(b['startTime']?.toString() ?? '')?.toLocal() ??
        DateTime.now();
    return ay.compareTo(by);
  });
  return out;
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
    return Container(
      decoration: BoxDecoration(
        color: md.MizdahTokens.surface(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: md.MizdahTokens.isDark(context) ? 0.45 : 0.10,
            ),
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle — matches the report-screen / language-
              // picker bottom-sheet pattern used elsewhere.
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: md.MizdahTokens.border(context),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              // Title with gradient accent — matches MizdahPageHeader
              // style across the rest of the app (Settings, Meeting
              // preferences, Report, Edit profile).
              RichText(
                text: TextSpan(
                  style: TextStyle(
                    color: md.MizdahTokens.inkOf(context),
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                    height: 1.1,
                  ),
                  children: [
                    const TextSpan(text: 'Create a '),
                    WidgetSpan(
                      alignment: PlaceholderAlignment.baseline,
                      baseline: TextBaseline.alphabetic,
                      child: ShaderMask(
                        shaderCallback: (r) =>
                            _Tokens.heroGradient.createShader(r),
                        child: const Text(
                          'meeting',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.4,
                            height: 1.1,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Pick how you want to start',
                style: TextStyle(
                  color: md.MizdahTokens.mutedOf(context),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 18),
              _OptionTile(
                icon: Icons.link_rounded,
                title: 'Create a meeting for later',
                subtitle: 'Get a link you can share with others',
                gradient: const LinearGradient(
                  colors: [Color(0xFF3B82F6), Color(0xFF1D4ED8)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                glow: const Color(0xFF3B82F6),
                onTap: () => _createMeeting(context, 'Share'),
              ),
              const SizedBox(height: 10),
              _OptionTile(
                icon: Icons.videocam_rounded,
                title: 'Start an instant meeting',
                subtitle: 'Join and invite people right now',
                gradient: _Tokens.heroGradient,
                glow: _Tokens.primary,
                primary: true,
                onTap: () {
                  Navigator.pop(context);
                  context.push('/pre-join');
                },
              ),
              const SizedBox(height: 10),
              _OptionTile(
                icon: Icons.event_note_rounded,
                title: 'Schedule in Google Calendar',
                subtitle: 'Plan a meeting in your calendar',
                gradient: const LinearGradient(
                  colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                glow: const Color(0xFFF59E0B),
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

  /// Open Google Calendar with a prefilled "Mizdah Meeting" event,
  /// then persist a row in our own scheduling backend so the meeting
  /// shows up in Upcoming Meetings on home + the Meetings tab.
  ///
  /// Calendar launch is the user-facing critical path — it's
  /// awaited. Backend persistence is fire-and-forget (kicked off in
  /// parallel) so a slow / down server never blocks Google Calendar
  /// from opening. The schedule row uses `meetingId: null` —
  /// the meeting-service migration is currently broken on the dev
  /// gateway, but `/api/scheduling/schedule` is independent and was
  /// confirmed live with curl on 2026-05-09.
  /// **Direct Google Calendar launch — no intermediate UI, save-detected.**
  ///
  /// 1. Generate placeholder times (now + 10 min) + unique tag
  ///    `#mizdah:<code>` embedded in the description.
  /// 2. Launch Google Calendar with all fields prefilled. User edits
  ///    time/date as desired inside Calendar.
  /// 3. **Nothing is saved locally yet.** No row in Upcoming
  ///    Meetings, no snackbar, no reminders scheduled — because we
  ///    don't yet know if the user will save or cancel.
  /// 4. Once the user returns to our app, `CalendarEventSync` polls
  ///    the device's native calendar for any event carrying the tag.
  ///    • Match → user saved. Read the REAL start/end times from the
  ///      calendar event (which the user may have edited), persist
  ///      locally, schedule reminders, show "Meeting added" snackbar.
  ///    • No match within 60s → user cancelled. Do nothing.
  ///
  /// This is why we needed READ_CALENDAR permission + the
  /// `device_calendar` package; URL launch alone can't tell us
  /// whether Save was tapped, and what the saved time was.
  Future<void> _scheduleMeeting(BuildContext context) async {
    Navigator.pop(context); // dismiss the Start-a-Meeting sheet

    final user = ref.read(authProvider).user;
    final scheduling = ref.read(calendarSchedulingServiceProvider);
    final meetingRepo = ref.read(mizdahRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    final sync = CalendarEventSync();

    // Ensure we can read the calendar BEFORE launching Calendar UI —
    // otherwise we'd open Calendar, the user would save, and then we
    // couldn't fulfill our "show in Upcoming Meetings" promise. If
    // they decline, fall back to a one-off "we'll launch Calendar
    // but can't auto-add it to Upcoming" message so behaviour is
    // honest.
    final hasPerm = await sync.ensurePermissions();
    if (!context.mounted) return;

    // Generate identifying details up-front so we can embed the tag
    // in Calendar's description for the post-launch read-back.
    final meetingCode = MeetingUtils.generateMeetingCode();
    final tag = '#mizdah:$meetingCode';
    final joinLink = MeetingUtils.generateMeetingLink(meetingCode);
    final placeholderStart =
        DateTime.now().add(const Duration(minutes: 10));
    final placeholderEnd =
        placeholderStart.add(const Duration(hours: 1));

    debugPrint('[schedule] launching Calendar with tag=$tag '
        'placeholderStart=${placeholderStart.toIso8601String()} '
        'placeholderEnd=${placeholderEnd.toIso8601String()}');

    final calendarPayload = CalendarPayload(
      title: 'Mizdah Meeting',
      meetingLink: joinLink,
      meetingId: meetingCode,
      hostName: user?.name,
      // Embed the tag at the top of the description so our post-
      // launch poll can identify "this is the event the user just
      // saved". The format helper renders the tag, link, and code
      // as a clean description block.
      agenda: tag,
      startTime: placeholderStart,
      endTime: placeholderEnd,
      timezone: DateTime.now().timeZoneName,
    );

    final launched = await scheduling.schedule(calendarPayload);
    if (!context.mounted) return;

    if (!launched) {
      final fallbackUrl = scheduling.resolveUrl(calendarPayload);
      messenger.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: md.MizdahTokens.surface(context),
          duration: const Duration(seconds: 5),
          content: Row(
            children: [
              const Icon(Icons.error_outline_rounded,
                  color: Color(0xFFB42318), size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Unable to open calendar',
                    style: TextStyle(
                      color: md.MizdahTokens.inkOf(context),
                      fontWeight: FontWeight.w700,
                    )),
              ),
              if (fallbackUrl.isNotEmpty)
                TextButton(
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: fallbackUrl)),
                  child: const Text('Copy link'),
                ),
            ],
          ),
        ),
      );
      return;
    }

    if (!hasPerm) {
      // Calendar opened, but we can't read it back. Be honest with
      // the user instead of guessing a time and lying.
      messenger.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: md.MizdahTokens.surface(context),
          duration: const Duration(seconds: 5),
          content: Text(
            'Calendar access denied — the meeting won\'t auto-appear in Upcoming Meetings.',
            style: TextStyle(
              color: md.MizdahTokens.inkOf(context),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
      return;
    }

    // Snapshot the theme tokens we'll need for the eventual
    // success-snackbar BEFORE the long async wait — the sheet's
    // BuildContext is gone after Navigator.pop, so we can't read
    // theme off it later.
    final surfaceColor = md.MizdahTokens.surface(context);
    final inkColor = md.MizdahTokens.inkOf(context);

    // Kick the poll. Fire-and-forget at the call-site so we don't
    // block the UI — the helper schedules its own snackbar /
    // persistence when the event surfaces.
    // ignore: discarded_futures
    _waitForAndPersistCalendarEvent(
      sync: sync,
      tag: tag,
      meetingCode: meetingCode,
      joinLink: joinLink,
      hostName: user?.name,
      meetingRepo: meetingRepo,
      messenger: messenger,
      surfaceColor: surfaceColor,
      inkColor: inkColor,
    );
  }

  /// Polls the device calendar (via `CalendarEventSync`) for an
  /// event carrying [tag]. On match, persists locally + schedules
  /// reminders + shows snackbar. On timeout (user cancelled), no-op.
  Future<void> _waitForAndPersistCalendarEvent({
    required CalendarEventSync sync,
    required String tag,
    required String meetingCode,
    required String joinLink,
    required String? hostName,
    required MizdahRepository meetingRepo,
    required ScaffoldMessengerState messenger,
    required Color surfaceColor,
    required Color inkColor,
  }) async {
    final found = await sync.waitForEventByTag(tag);
    if (found == null) {
      debugPrint('[schedule] no calendar event with tag=$tag — '
          'user cancelled or save timed out');
      return;
    }

    debugPrint('[schedule] calendar event found: '
        'eventId=${found.eventId} '
        'realStart=${found.startTime.toIso8601String()} '
        'realEnd=${found.endTime.toIso8601String()}');

    // Build the local ScheduledMeeting from the REAL times the
    // calendar gave us — not the placeholders we sent. This is the
    // fix for "5:30 PM picked in Calendar but 5:35 PM in Upcoming".
    final meeting = ScheduledMeeting(
      id: '${DateTime.now().millisecondsSinceEpoch}_$meetingCode',
      title: found.title,
      description: found.description ?? '',
      meetingCode: meetingCode,
      startTime: found.startTime.toUtc(),
      endTime: found.endTime.toUtc(),
      participants: const [],
      meetingType: MeetingType.video,
      createdBy: hostName,
      createdAt: DateTime.now().toUtc(),
      calendarEventId: found.eventId,
    );

    final notifier = ref.read(scheduledMeetingsProvider.notifier);
    await notifier.add(meeting);

    // Best-effort backend create — uses the REAL start time so any
    // /pre-join lookups round-trip the same instant.
    // ignore: discarded_futures
    meetingRepo
        .createMeeting(
      title: meeting.title,
      dateTime: meeting.startTime.toLocal(),
      code: meeting.meetingCode,
    )
        .catchError((Object e) {
      debugPrint('[schedule] createMeeting failed: $e');
      return null as dynamic;
    });

    // Schedule the two reminder notifications against the REAL
    // start (not the placeholder).
    final push = PushNotificationService.instance;
    final localStart = meeting.startTime.toLocal();
    final payload = <String, dynamic>{
      'type': 'meeting',
      'meeting_code': meeting.meetingCode,
      'meeting_id': meeting.id,
    };
    final baseId = meeting.id.hashCode & 0x7fffffff;
    // ignore: discarded_futures
    push.scheduleLocalNotification(
      id: baseId,
      when: localStart.subtract(const Duration(minutes: 10)),
      title: meeting.title,
      body: 'Starts in 10 min — ${_fmtTime(localStart)}',
      payload: payload,
    );
    // ignore: discarded_futures
    push.scheduleLocalNotification(
      id: baseId + 1,
      when: localStart,
      title: '${meeting.title} is starting',
      body: 'Tap to join now',
      payload: payload,
    );

    // Snackbar fires regardless of where the user navigated after
    // launching Calendar — `messenger` was captured before the
    // calendar launch and survives screen changes within the shell.
    // We use `messenger.mounted` (no original BuildContext is
    // available — the sheet that called us was popped).
    if (!messenger.mounted) return;
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: surfaceColor,
        elevation: 6,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 110),
        duration: const Duration(seconds: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded,
                color: Color(0xFF10B981), size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Meeting added — ${_fmtTime(localStart)}',
                style: TextStyle(
                  color: inkColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Tiny helper — same `h:mm a` format the home meeting rows use,
  /// inlined so we don't lug `package:intl` into this file just for
  /// the reminder body.
  String _fmtTime(DateTime dt) {
    final h = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour < 12 ? 'AM' : 'PM';
    return '$h:$m $ampm';
  }
}

class _OptionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  /// Pill icon background gradient — distinct per option so the
  /// sheet reads visually like the Recent-Activity rows on home.
  final LinearGradient gradient;
  /// Accent colour used for the icon-pill drop shadow. Usually the
  /// brightest stop of `gradient`.
  final Color glow;
  /// When true the row gets a slightly larger shadow + tinted border
  /// so it reads as the primary CTA (used for "Start an instant
  /// meeting").
  final bool primary;
  final VoidCallback onTap;
  const _OptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.gradient,
    required this.glow,
    required this.onTap,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) {
    return md.MizdahPressScale(
      scaleTo: 0.97,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: md.MizdahTokens.surface(context),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: primary
                ? glow.withValues(alpha: 0.30)
                : md.MizdahTokens.border(context),
            width: primary ? 1.4 : 1,
          ),
          boxShadow: md.MizdahTokens.shadow(
            context,
            elevation: primary ? 0.8 : 0.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: gradient,
                borderRadius: BorderRadius.circular(13),
                boxShadow: [
                  BoxShadow(
                    color: glow.withValues(alpha: 0.32),
                    blurRadius: 12,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Icon(icon, color: Colors.white, size: 22),
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
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: md.MizdahTokens.mutedOf(context),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: md.MizdahTokens.mutedOf(context),
            ),
          ],
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

// _HistoryDetailModal was removed when the home screen migrated to
// the unified presence-aware rejoin sheet
// (`lib/features/meetings/presentation/rejoin_sheet.dart`). The old
// modal rendered without accounting for the floating bottom nav and
// hid its own Rejoin button under the tab bar — the new sheet uses
// `MizdahTokens.navBarBottomInset` to clear it.
