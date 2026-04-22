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
                      Row(
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
                          Expanded(
                            child: _ActionCard(
                              title: 'Join with code',
                              icon: Icons.keyboard_rounded,
                              color: Colors.white24,
                              onTap: () => _showJoinCodeDialog(context, ref),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const UpcomingMeetingsSection(),
                      const SizedBox(height: 16),
                      const JoinMeetingCard(),
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

class JoinMeetingCard extends StatelessWidget {
  const JoinMeetingCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(title: 'Join meeting'),
        const SizedBox(height: 16),
        GlassCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              MizdahTextField(
                label: 'Meeting Code or Link',
                hintText: 'e.g. abc-defg-hij',
                prefixIcon: Icons.link_rounded,
                onChanged: (val) {
                  final code = MeetingUtils.extractCode(val);
                  if (code.length >= 9) {
                    context.push('/pre-join/$code');
                  }
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ScheduleTile extends StatelessWidget {
  final dynamic schedule; // Use your model if available
  const _ScheduleTile({required this.schedule});

  @override
  Widget build(BuildContext context) {
    final startTime = DateTime.parse(schedule['startTime']);
    final title = schedule['title'] ?? 'Untitled Meeting';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05)),
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
                  style: const TextStyle(color: MizdahTheme.primaryBlue, fontWeight: FontWeight.bold, fontSize: 10),
                ),
                Text(
                  DateFormat('d').format(startTime),
                  style: const TextStyle(color: MizdahTheme.primaryBlue, fontWeight: FontWeight.w900, fontSize: 18),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                Text(
                  '${DateFormat('h:mm a').format(startTime)} • ${schedule['timezone'] ?? 'UTC'}',
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
            onPressed: () => context.push('/pre-join/${schedule['id']}'),
          ),
        ],
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
        onTap: () => context.push('/pre-join/${item.meetingCode ?? item.id}'),
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
class _NewMeetingOptions extends StatelessWidget {
  final WidgetRef ref;
  const _NewMeetingOptions({required this.ref});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      radius: 32,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),
          _OptionTile(
            icon: Icons.link_rounded,
            title: 'Create a meeting for later',
            onTap: () => _createMeeting(context, 'Share'),
          ),
          _OptionTile(
            icon: Icons.video_call_rounded,
            title: 'Start an instant meeting',
            onTap: () => _createMeeting(context, 'Join'),
          ),
          _OptionTile(
            icon: Icons.calendar_today_rounded,
            title: 'Schedule in Google Calendar',
            onTap: () => _scheduleMeeting(context),
          ),
        ],
      ),
    );
  }

  Future<void> _createMeeting(BuildContext context, String mode) async {
    final repository = ref.read(mizdahRepositoryProvider);
    final code = MeetingUtils.generateMeetingCode();
    
    Navigator.pop(context); // Close sheet

    try {
      final meeting = await repository.createMeeting(
        title: 'Meeting', 
        dateTime: DateTime.now(),
        code: code,
      );
      
      if (context.mounted) {
        if (mode == 'Share') {
          showModalBottomSheet(
            context: context,
            backgroundColor: Colors.transparent,
            builder: (context) => _ShareLinkModal(meeting: meeting),
          );
        } else {
          context.push('/pre-join/${meeting.code}');
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to create meeting')));
      }
    }
  }

  Future<void> _scheduleMeeting(BuildContext context) async {
    final repository = ref.read(mizdahRepositoryProvider);
    final code = MeetingUtils.generateMeetingCode();
    
    Navigator.pop(context); // Close sheet

    try {
      await repository.createMeeting(
        title: 'Scheduled Meeting', 
        dateTime: DateTime.now().add(const Duration(hours: 1)),
        code: code,
      );
      
      final url = MeetingUtils.generateCalendarUrl(code);
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to schedule meeting')));
      }
    }
  }
}

class _OptionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const _OptionTile({required this.icon, required this.title, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: MizdahTheme.primaryBlue),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }
}

class _ShareLinkModal extends StatelessWidget {
  final Meeting meeting;
  const _ShareLinkModal({required this.meeting});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      radius: 32,
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Meeting link ready',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Text(
            'Share this link with participants you want in the meeting.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[400], fontSize: 13),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Row(
              children: [
                Expanded(child: Text(meeting.code, style: const TextStyle(fontWeight: FontWeight.w500))),
                IconButton(
                  icon: const Icon(Icons.copy_rounded, size: 20),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: meeting.code));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Link copied!')));
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          MizdahButton(
            label: 'Share Invite',
            icon: Icons.share_rounded,
            onTap: () {},
          ),
          const SizedBox(height: 12),
          MizdahButton(
            label: 'Join Meeting',
            backgroundColor: Colors.white.withValues(alpha: 0.05),
            onTap: () {
              Navigator.pop(context);
              context.push('/pre-join/${meeting.code}');
            },
          ),
        ],
      ),
    );
  }
}
