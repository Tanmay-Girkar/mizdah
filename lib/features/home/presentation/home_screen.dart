import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/utils/meeting_utils.dart';
import '../../../core/widgets/mizdah_text_field.dart';
import 'package:intl/intl.dart';
import '../../../data/repositories/meeting_repository.dart';
import '../../../data/repositories/participant_repository.dart';
import '../../../data/repositories/scheduling_repository.dart';
import '../../../data/models/models.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/mizdah_button.dart';
import '../../../core/theme/theme_provider.dart';
import '../../auth/auth_provider.dart';
import '../notification_provider.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/services/google_calendar_service.dart';
import '../../../data/repositories/mizdah_repository.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final callHistoryAsync = ref.watch(callHistoryProvider);
    final authState = ref.watch(authProvider);


    return Scaffold(
      drawer: const MizdahDrawer(),
      endDrawer: const NotificationsDrawer(),
      body: Container(
        decoration: BoxDecoration(
          gradient: isDark ? MizdahTheme.darkGradient : null,
          color: isDark ? null : MizdahTheme.lightBackground,
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: MizdahAppBar(user: authState.user),
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async => ref.refresh(callHistoryProvider),
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // Restored Premium Action Cards
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: _ActionCard(
                                title: 'New Meeting',
                                icon: Icons.video_call_rounded,
                                color: MizdahTheme.primaryBlue,
                                onTap: () => _handleNewMeeting(context, ref),
                              ),
                            ),
                            const SizedBox(width: 16),
                            const Expanded(
                              child: JoinMeetingCard(),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      const UpcomingMeetingsSection(),
                      const SizedBox(height: 24),
                      const SizedBox(height: 32),

                      // Recent History Section
                      _SectionHeader(title: 'Recent activity'),
                      const SizedBox(height: 16),
                      callHistoryAsync.when(
                        data: (history) => history.isEmpty
                            ? const EmptyStateView()
                            : Column(
                                children: history.map((item) => HistoryTile(item: item)).toList(),
                              ),
                        loading: () => const Center(child: CircularProgressIndicator()),
                        error: (err, stack) => Center(child: Text('Failed to load history')),
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

  Future<void> _handleNewMeeting(BuildContext context, WidgetRef ref) async {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _NewMeetingOptions(ref: ref),
    );
  }

  void _showJoinCodeDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => const JoinCodeDialog(),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ActionCard({
    required this.title,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: GlassCard(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: MizdahTheme.primaryBlue, size: 28),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class UpcomingMeetingsSection extends ConsumerWidget {
  const UpcomingMeetingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schedulesAsync = ref.watch(schedulesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(title: 'Scheduled meetings'),
        const SizedBox(height: 16),
        schedulesAsync.when(
          data: (schedules) => schedules.isEmpty
              ? GlassCard(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Container(
                        height: 48,
                        width: 48,
                        decoration: BoxDecoration(
                          color: MizdahTheme.primaryBlue.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.event_available, color: MizdahTheme.primaryBlue),
                      ),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('No meetings today', style: TextStyle(fontWeight: FontWeight.bold)),
                            Text('Tap schedule to plan one', style: TextStyle(color: Colors.grey, fontSize: 12)),
                          ],
                        ),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: schedules.map((s) => _ScheduleTile(schedule: s)).toList(),
                ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, stack) => Center(child: Text('Failed to load schedules')),
        ),
      ],
    );
  }
}

class JoinMeetingCard extends ConsumerStatefulWidget {
  const JoinMeetingCard({super.key});

  @override
  ConsumerState<JoinMeetingCard> createState() => _JoinMeetingCardState();
}

class _JoinMeetingCardState extends ConsumerState<JoinMeetingCard> {
  final _controller = TextEditingController();
  bool _validating = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final code = MeetingUtils.extractCode(_controller.text);
    if (code.isEmpty) {
      _showError('Please enter a meeting code');
      return;
    }
    setState(() => _validating = true);
    final repo = ref.read(meetingRepositoryProvider);
    final meeting = await repo.getMeetingInfo(code);
    if (!mounted) return;
    setState(() => _validating = false);
    if (meeting == null) {
      _showError('Meeting code is not valid');
      return;
    }
    context.push('/pre-join/$code');
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(msg)),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFFB71C1C),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          MizdahTextField(
            controller: _controller,
            hintText: 'abc-defg-hij',
            prefixIcon: Icons.link_rounded,
            onSubmitted: (_) => _join(),
          ),
          const SizedBox(height: 12),
          MizdahButton(
            label: _validating ? 'Checking…' : 'Join',
            onTap: _validating ? null : _join,
            isFullWidth: true,
          ),
        ],
      ),
    );
  }
}

class _ScheduleTile extends StatelessWidget {
  final dynamic schedule; // Use your model if available
  const _ScheduleTile({required this.schedule});

  /// Recovers the actual meeting code from a schedule row.
  ///
  /// Priority order:
  ///   1. `meetingCode` field (when backend ships fix — preferred)
  ///   2. `meetingId` field (also backend-fix path; could be either
  ///      a UUID linking to the Meeting row, or the code itself)
  ///   3. Title suffix `[xxxxxx]` — the legacy escape hatch the
  ///      Flutter client currently embeds during schedule creation
  ///      so the code survives the round-trip even though the
  ///      backend ignores the dedicated fields. See
  ///      docs/SCHEDULING_BACKEND.md.
  ///   4. null — no code is recoverable; tap should explain.
  static String? _extractMeetingCode(dynamic schedule) {
    final code = schedule['meetingCode']?.toString();
    if (code != null && code.isNotEmpty) return code;
    final mid = schedule['meetingId']?.toString();
    if (mid != null && mid.isNotEmpty) return mid;
    final title = schedule['title']?.toString() ?? '';
    final m = RegExp(r'\[([a-z0-9-]{6,})\]').firstMatch(title);
    return m?.group(1);
  }

  /// Removes the legacy `[code]` suffix from titles for display so
  /// the user-visible title is just `Mizdah Meeting` instead of
  /// `Mizdah Meeting [docscht3xy]`. If the strip leaves an empty
  /// string (paranoid guard for titles that were ONLY a code), the
  /// raw title is shown verbatim.
  static String _displayTitle(String raw) {
    final stripped =
        raw.replaceAll(RegExp(r'\s*\[[a-z0-9-]{6,}\]\s*$'), '').trim();
    return stripped.isEmpty ? raw : stripped;
  }

  @override
  Widget build(BuildContext context) {
    final startTime = DateTime.parse(schedule['startTime']);
    final rawTitle = schedule['title']?.toString() ?? 'Untitled Meeting';
    final title = _displayTitle(rawTitle);
    final code = _extractMeetingCode(schedule);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    void onTap() {
      if (code == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'This schedule has no meeting code yet — open it from your calendar invite.',
            ),
          ),
        );
        return;
      }
      context.push('/pre-join/$code');
    }

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.black.withValues(alpha: 0.05)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: MizdahTheme.primaryBlue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Text(
                    DateFormat('MMM').format(startTime).toUpperCase(),
                    style: const TextStyle(
                        color: MizdahTheme.primaryBlue,
                        fontWeight: FontWeight.bold,
                        fontSize: 10),
                  ),
                  Text(
                    DateFormat('d').format(startTime),
                    style: const TextStyle(
                        color: MizdahTheme.primaryBlue,
                        fontWeight: FontWeight.w900,
                        fontSize: 18),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(
                    '${DateFormat('h:mm a').format(startTime)} • ${schedule['timezone'] ?? 'UTC'}',
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  if (code != null) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: MizdahTheme.primaryBlue.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        code,
                        style: const TextStyle(
                          color: MizdahTheme.primaryBlue,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}


class HistoryTile extends ConsumerWidget {
  final CallHistory item;
  const HistoryTile({super.key, required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final isHost = item.hostId != null && authState.user != null && item.hostId == authState.user!.id;
    final displayTitle = (item.title.contains('http') || item.title.length > 20) 
        ? (item.meetingCode ?? item.title) 
        : item.title;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: CircleAvatar(
          backgroundColor: isHost 
              ? Colors.green.withValues(alpha: 0.1) 
              : MizdahTheme.primaryBlue.withValues(alpha: 0.1),
          child: Icon(
            isHost ? Icons.outbound_rounded : Icons.call_received_rounded,
            color: isHost ? Colors.green : MizdahTheme.primaryBlue,
            size: 20,
          ),
        ),
        title: Text(
          displayTitle, 
          style: const TextStyle(fontWeight: FontWeight.bold),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          isHost ? 'Hosted' : 'Joined',
          style: TextStyle(
            fontSize: 12, 
            color: isHost ? Colors.green : Colors.grey,
            fontWeight: isHost ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        trailing: Text(
          DateFormat('MMM d, h:mm a').format(item.timestamp),
          style: const TextStyle(fontSize: 11, color: Colors.grey),
        ),
        onTap: () {
          showModalBottomSheet(
            context: context,
            backgroundColor: Colors.transparent,
            isScrollControlled: true,
            builder: (context) => _HistoryDetailModal(item: item, isHost: isHost),
          );
        },
      ),
    );
  }
}

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
        final identifier = meeting.code.isNotEmpty ? meeting.code : meeting.id;
        context.push('/pre-join/$identifier');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid meeting code')));
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
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        _isLoading
          ? const Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
          : ElevatedButton(
              onPressed: _onJoin,
              child: const Text('Join'),
            ),
      ],
    );
  }
}

class MizdahAppBar extends StatelessWidget {
  final User? user;
  const MizdahAppBar({super.key, this.user});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => Scaffold.of(context).openDrawer(),
        ),
        const Expanded(
          child: Center(
            child: Text(
              'MIZDAH',
              style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2, fontSize: 18),
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.dashboard_customize_outlined),
          tooltip: 'Meeting layout designs',
          onPressed: () => context.push('/meeting-designs'),
        ),
        IconButton(
          icon: const Icon(Icons.notifications_outlined),
          onPressed: () => Scaffold.of(context).openEndDrawer(),
        ),
        const SizedBox(width: 8),
        CircleAvatar(
          radius: 18,
          backgroundColor: MizdahTheme.primaryBlue,
          child: user != null 
            ? Text(user!.name[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
            : const Icon(Icons.person, color: Colors.white, size: 20),
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
                  const Text('Notifications', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
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
                    return const Center(child: Text('No new notifications', style: TextStyle(color: Colors.grey)));
                  }
                  return ListView.builder(
                    itemCount: notifications.length,
                    itemBuilder: (context, index) {
                      final notif = notifications[index];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: notif.isRead ? Colors.grey.withValues(alpha: 0.2) : MizdahTheme.primaryBlue.withValues(alpha: 0.2),
                          child: Icon(Icons.notifications, color: notif.isRead ? Colors.grey : MizdahTheme.primaryBlue),
                        ),
                        title: Text(notif.title, style: TextStyle(fontWeight: notif.isRead ? FontWeight.normal : FontWeight.bold)),
                        subtitle: Text(notif.body),
                        trailing: Text(
                          DateFormat('MMM d').format(notif.createdAt),
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        onTap: () {
                          // Could mark as read here using the repo
                        },
                      );
                    },
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, stack) => Center(child: Text('Error: $err')),
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
    final authState = ref.watch(authProvider);
    final user = authState.user;

    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(color: MizdahTheme.darkBackgroundTop),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CircleAvatar(radius: 30, child: Icon(Icons.person)),
                const SizedBox(height: 12),
                Text(user?.name ?? 'Guest User', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                Text(user?.email ?? '', style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
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
            title: const Text('Logout', style: TextStyle(color: Colors.red)),
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

class EmptyStateView extends StatelessWidget {
  const EmptyStateView({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        children: [
          const SizedBox(height: 48),
          Icon(Icons.history, size: 64, color: Colors.grey.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          const Text('No recent activity', style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}
class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
      ),
    );
  }
}

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

final googleCalendarServiceProvider = Provider((ref) => GoogleCalendarService());
class _NewMeetingOptions extends StatelessWidget {
  final WidgetRef ref;
  const _NewMeetingOptions({required this.ref});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      decoration: BoxDecoration(
        color: isDark ? MizdahTheme.darkSurface : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 20,
            spreadRadius: 5,
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag Handle
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
        Navigator.pop(context); // Close sheet
        
        // Refresh data providers to show the latest meeting
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
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context); // Close sheet on error too
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to create meeting')));
      }
    }
  }

  Future<void> _scheduleMeeting(BuildContext context) async {
    final scheduleRepo = ref.read(schedulingRepositoryProvider);
    final meetingRepo = ref.read(mizdahRepositoryProvider);
    final calendarService = ref.read(googleCalendarServiceProvider);
    final authState = ref.read(authProvider);
    final user = authState.user;

    if (user == null) return;

    Navigator.pop(context); // Close sheet

    try {
      final startTime = DateTime.now().add(const Duration(hours: 1));
      final endTime = startTime.add(const Duration(hours: 1));
      final timezone = DateTime.now().timeZoneName;

      // 1. Create the actual meeting room FIRST so we have a real
      //    join code (e.g. `xfm9kpqlnt`). The previous code only
      //    created a `schedule` row, whose UUID is NOT a valid
      //    meeting code — the calendar link it sent users pointed
      //    to a meeting that never existed (404 on /api/meeting/<id>).
      final code = MeetingUtils.generateMeetingCode();
      print('📅 1. Creating meeting room (code=$code)…');
      final meeting = await meetingRepo.createMeeting(
        title: 'Mizdah Meeting',
        dateTime: startTime,
        code: code,
      );
      final realCode = meeting.code; // authoritative

      // 2. Create the schedule row pointing at that meeting. The
      //    backend currently drops `meetingId`/`meetingCode`
      //    (see docs/SCHEDULING_BACKEND.md), so as a stop-gap we
      //    also append the code in square brackets to the title —
      //    that's the only field guaranteed to round-trip on GET.
      //    `_ScheduleTile` parses it back out. Once the backend
      //    persists the dedicated fields this title-tagging can
      //    be dropped.
      print('📅 2. Creating schedule row referencing $realCode…');
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

      // 3. Open Google Calendar with the real (working) code.
      print('📅 3. Opening Google Calendar…');
      final link = MeetingUtils.generateMeetingLink(realCode);
      await calendarService.openGoogleCalendarTemplate(
        title: 'Mizdah Meeting',
        description: 'Join with Mizdah: $link\nMeeting Code: $realCode',
        location: link,
        startTime: startTime,
      );

      // Refresh data providers so the new schedule appears.
      ref.invalidate(schedulesProvider);
      ref.invalidate(callHistoryProvider);
    } catch (e) {
      print('📅 ERROR during scheduling: $e');
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
            color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.02),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05),
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
        color: isDark ? MizdahTheme.darkSurface : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Top Bar with Drag Handle and Done button
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const SizedBox(width: 60), // Spacer to center the handle
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
                      color: MizdahTheme.primaryBlue,
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
                color: MizdahTheme.primaryBlue.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.link_rounded, color: MizdahTheme.primaryBlue, size: 36),
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
            
            // Link Display Box
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.1),
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
                        Clipboard.setData(ClipboardData(text: MeetingUtils.generateMeetingLink(meeting.code)));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Link copied to clipboard')),
                        );
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: MizdahTheme.primaryBlue.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.copy_rounded, size: 18, color: MizdahTheme.primaryBlue),
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
                final link = MeetingUtils.generateMeetingLink(meeting.code);
                Share.share(
                  'Join my Mizdah meeting: $link',
                  subject: 'Mizdah Meeting Invite',
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
        color: isDark ? MizdahTheme.darkSurface : Colors.white,
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
                : MizdahTheme.primaryBlue.withValues(alpha: 0.1),
            child: Icon(
              isHost ? Icons.outbound_rounded : Icons.call_received_rounded,
              color: isHost ? Colors.green : MizdahTheme.primaryBlue,
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
              color: isHost ? Colors.green : Colors.grey,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 24),
          
          _DetailRow(
            icon: Icons.calendar_today_rounded,
            label: 'Date & Time',
            value: DateFormat('EEEE, MMM d • h:mm a').format(item.timestamp),
          ),
          const SizedBox(height: 16),
          _DetailRow(
            icon: Icons.timer_outlined,
            label: 'Duration',
            value: item.duration.inMinutes > 0 
                ? '${item.duration.inMinutes} minutes'
                : 'Under a minute',
          ),
          const SizedBox(height: 16),
          _DetailRow(
            icon: Icons.tag_rounded,
            label: 'Meeting Code',
            value: item.meetingCode ?? 'N/A',
          ),
          
          const SizedBox(height: 32),
          
          Row(
            children: [
              Expanded(
                child: MizdahButton(
                  label: 'Rejoin',
                  icon: Icons.videocam_rounded,
                  onTap: () {
                    Navigator.pop(context);
                    context.push('/pre-join/${item.meetingCode ?? item.id}');
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: MizdahButton(
                  label: 'Share Link',
                  backgroundColor: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05),
                  icon: Icons.share_rounded,
                  onTap: () {
                    final link = MeetingUtils.generateMeetingLink(item.meetingCode ?? item.id);
                    Share.share('Join my Mizdah meeting: $link');
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: Colors.grey),
        ),
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          ],
        ),
      ],
    );
  }
}
