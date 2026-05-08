// ════════════════════════════════════════════════════════════════════
//  Call hub — premium "what kind of call?" landing page
//  ────────────────────────────────────────────────────────────────────
//  Reachable from the floating bottom-nav center "Call" tab. Three
//  primary actions:
//    • Start instant meeting (gradient hero card)
//    • Join with code         (input card)
//    • Schedule for later     (secondary card)
//  Plus a "Recent" preview row below — same data as home_screen's
//  callHistoryProvider — so the hub doubles as a quick redial.
// ════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ui/mizdah_design.dart';
import '../../../core/utils/meeting_utils.dart';
import '../../../data/repositories/meeting_repository.dart';
import '../../auth/auth_provider.dart';
import '../../home/presentation/home_screen.dart' show callHistoryProvider;

class CallHubScreen extends ConsumerStatefulWidget {
  const CallHubScreen({super.key});

  @override
  ConsumerState<CallHubScreen> createState() => _CallHubScreenState();
}

class _CallHubScreenState extends ConsumerState<CallHubScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entryCtrl;
  final TextEditingController _codeCtrl = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _entryCtrl = AnimationController(
      duration: const Duration(milliseconds: 700),
      vsync: this,
    )..forward();
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _startInstantMeeting() async {
    if (_busy) return;
    final auth = ref.read(authProvider);
    if (auth.user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Sign in first to start a meeting.'),
        ),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final repo = ref.read(meetingRepositoryProvider);
      final meeting = await repo.createMeeting(hostId: auth.user!.id);
      if (!mounted) return;
      context.push('/pre-join/${meeting.code}?host=true');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Could not start meeting: $e'),
          backgroundColor: const Color(0xFFB42318),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _joinWithCode() {
    final raw = _codeCtrl.text.trim();
    if (raw.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Enter a meeting code to continue.'),
        ),
      );
      return;
    }
    final code = MeetingUtils.extractCode(raw);
    context.push('/pre-join/$code');
  }

  @override
  Widget build(BuildContext context) {
    return MizdahTabScaffold(
      activeIndex: 2,
      body: SafeArea(
        bottom: false,
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 110),
          children: [
            MizdahFadeUp(
              controller: _entryCtrl,
              delay: 0.0,
              child: const MizdahPageHeader(
                leading: 'Start a',
                accent: 'call',
                subtitle: 'Instant · Scheduled · Join with code',
              ),
            ),
            const SizedBox(height: 18),

            // Hero gradient — instant meeting CTA
            MizdahFadeUp(
              controller: _entryCtrl,
              delay: 0.10,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: _InstantMeetingHero(
                  busy: _busy,
                  onTap: _startInstantMeeting,
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Join with code card
            MizdahFadeUp(
              controller: _entryCtrl,
              delay: 0.18,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: _JoinCodeCard(
                  controller: _codeCtrl,
                  onSubmit: _joinWithCode,
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Schedule + Add People (compact 2-column row)
            MizdahFadeUp(
              controller: _entryCtrl,
              delay: 0.24,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Row(
                  children: [
                    Expanded(
                      child: _ActionTile(
                        icon: Icons.event_note_rounded,
                        label: 'Schedule',
                        sublabel: 'For later',
                        onTap: () => context.push('/schedule'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ActionTile(
                        icon: Icons.group_add_rounded,
                        label: 'Add people',
                        sublabel: 'From contacts',
                        onTap: () => context.go('/people'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 26),

            // Recent calls — quick redial
            MizdahFadeUp(
              controller: _entryCtrl,
              delay: 0.30,
              child: const _RecentCallsStrip(),
            ),
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────
//  Hero CTA — full-width gradient card with a phone-call icon
// ────────────────────────────────────────────────────────────────────

class _InstantMeetingHero extends StatelessWidget {
  final bool busy;
  final VoidCallback onTap;
  const _InstantMeetingHero({required this.busy, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return MizdahPressScale(
      scaleTo: 0.985,
      onTap: busy ? () {} : onTap,
      child: Container(
        height: 200,
        decoration: BoxDecoration(
          gradient: MizdahTokens.heroGradient,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: MizdahTokens.primary.withValues(alpha: 0.35),
              blurRadius: 24,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Decorative curved overlays
            Positioned(
              right: -60,
              top: -40,
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.10),
                ),
              ),
            ),
            Positioned(
              right: 30,
              bottom: -40,
              child: Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.06),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.20),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.30)),
                    ),
                    child: const Text(
                      'INSTANT',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        letterSpacing: 1.4,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const Spacer(),
                  const Text(
                    'Start a meeting',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Spin up a room and share the link',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.30)),
                        ),
                        child: const Icon(Icons.videocam_rounded,
                            color: Colors.white, size: 20),
                      ),
                      const Spacer(),
                      Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.10),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation(
                                      MizdahTokens.primary),
                                ),
                              )
                            : const Icon(
                                Icons.arrow_forward_rounded,
                                color: MizdahTokens.primary,
                                size: 20,
                              ),
                      ),
                    ],
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

// ────────────────────────────────────────────────────────────────────
//  Join with code
// ────────────────────────────────────────────────────────────────────

class _JoinCodeCard extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSubmit;
  const _JoinCodeCard({required this.controller, required this.onSubmit});

  @override
  Widget build(BuildContext context) {
    return MizdahCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Join with',
            style: TextStyle(
              color: MizdahTokens.muted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'Meeting code',
            style: TextStyle(
              color: MizdahTokens.ink,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 46,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F8),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.link_rounded,
                          color: MizdahTokens.muted, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: controller,
                          textCapitalization: TextCapitalization.none,
                          style: const TextStyle(
                            color: MizdahTokens.ink,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.3,
                          ),
                          decoration: const InputDecoration(
                            isCollapsed: true,
                            border: InputBorder.none,
                            hintText: 'Enter code or link',
                            hintStyle: TextStyle(
                              color: MizdahTokens.muted,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          onSubmitted: (_) => onSubmit(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              MizdahPressScale(
                scaleTo: 0.92,
                onTap: onSubmit,
                child: Container(
                  width: 46,
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: MizdahTokens.heroGradient,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color:
                            MizdahTokens.primary.withValues(alpha: 0.40),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.arrow_forward_rounded,
                      color: Colors.white, size: 20),
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
//  Compact action tile — used for Schedule + Add People
// ────────────────────────────────────────────────────────────────────

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sublabel;
  final VoidCallback onTap;
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MizdahCard(
      padding: const EdgeInsets.all(14),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFEEF2FF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: MizdahTokens.primary, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: MizdahTokens.ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.1,
                  ),
                ),
                Text(
                  sublabel,
                  style: const TextStyle(
                    color: MizdahTokens.muted,
                    fontSize: 11,
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

// ────────────────────────────────────────────────────────────────────
//  Recent calls — horizontal strip below the actions
// ────────────────────────────────────────────────────────────────────

class _RecentCallsStrip extends ConsumerWidget {
  const _RecentCallsStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(callHistoryProvider);
    return async.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (history) {
        if (history.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Text(
                'Recent',
                style: TextStyle(
                  color: MizdahTokens.ink,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
            ),
            SizedBox(
              height: 116,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                itemCount: history.length.clamp(0, 8),
                itemBuilder: (ctx, i) {
                  final c = history[i];
                  final code = c.meetingCode?.isNotEmpty == true
                      ? MeetingUtils.extractCode(c.meetingCode!)
                      : null;
                  return Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: MizdahPressScale(
                      scaleTo: 0.95,
                      onTap: code == null
                          ? null
                          : () => context.push('/pre-join/$code'),
                      child: Container(
                        width: 102,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                              color: MizdahTokens.cardBorder, width: 1),
                          boxShadow:
                              MizdahTokens.softShadow(elevation: 0.5),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            MizdahAvatar(name: c.title, size: 36),
                            const Spacer(),
                            Text(
                              c.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: MizdahTokens.ink,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              code ?? 'No code',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: MizdahTokens.muted,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
