import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../data/repositories/mizdah_repository.dart';
import '../../../data/models/models.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/mizdah_button.dart';
import '../../../core/theme/theme_provider.dart';
import '../../../core/utils/meeting_utils.dart';
import 'package:url_launcher/url_launcher.dart';

class StartCallScreen extends ConsumerWidget {
  const StartCallScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contactsAsync = ref.watch(contactsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: isDark ? MizdahTheme.darkGradient : null,
          color: isDark ? null : MizdahTheme.lightBackground,
        ),
        child: SafeArea(
          child: Column(
            children: [
              _CustomAppBar(),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: GlassCard(
                  child: Column(
                    children: [
                      _QuickActionTile(
                        icon: Icons.link,
                        title: 'Create a meeting for later',
                        onTap: () => _createMeeting(context, ref, 'Share'),
                      ),
                      const Divider(height: 1),
                      _QuickActionTile(
                        icon: Icons.video_call_rounded,
                        title: 'Start an instant meeting',
                        onTap: () => _createMeeting(context, ref, 'Join'),
                      ),
                      const Divider(height: 1),
                      _QuickActionTile(
                        icon: Icons.calendar_today_rounded,
                        title: 'Schedule in Google Calendar',
                        onTap: () => _scheduleMeeting(context, ref),
                      ),
                    ],
                  ),
                ),
              ),
              const _SectionHeader(title: 'Suggestions'),
              Expanded(
                child: contactsAsync.when(
                  data: (contacts) => ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: contacts.length,
                    itemBuilder: (context, index) {
                      final contact = contacts[index];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                             backgroundColor: MizdahTheme.primaryBlue.withValues(alpha: 0.1),
                            child: Text(contact.name[0], style: const TextStyle(color: MizdahTheme.primaryBlue)),
                          ),
                          title: Text(contact.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(contact.email, style: const TextStyle(fontSize: 12)),
                          onTap: () => context.push('/meeting/direct-${contact.id}'),
                        ),
                      );
                    },
                  ),
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (err, stack) => Center(child: Text('Error: $err')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _createMeeting(BuildContext context, WidgetRef ref, String mode) async {
    final repository = ref.read(mizdahRepositoryProvider);
    final code = MeetingUtils.generateMeetingCode();
    
    final meeting = await repository.createMeeting(
      title: 'Instant Meeting', 
      dateTime: DateTime.now(),
      code: code,
    );
    
    if (!context.mounted) return;
    
    if (mode == 'Share') {
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (context) => ShareLinkModal(meeting: meeting),
      );
    } else {
      context.push('/meeting/${meeting.code}');
    }
  }

  void _scheduleMeeting(BuildContext context, WidgetRef ref) async {
    final repository = ref.read(mizdahRepositoryProvider);
    final code = MeetingUtils.generateMeetingCode();
    
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
  }
}

class _CustomAppBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        children: [
          IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
          const Expanded(
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search people or dial',
                border: InputBorder.none,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const _QuickActionTile({required this.icon, required this.title, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: MizdahTheme.primaryBlue),
      title: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
      onTap: onTap,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey),
        ),
      ),
    );
  }
}

final contactsProvider = FutureProvider<List<Contact>>((ref) {
  return ref.watch(mizdahRepositoryProvider).getContacts();
});

class ShareLinkModal extends StatelessWidget {
  final Meeting meeting;
  const ShareLinkModal({super.key, required this.meeting});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      radius: 32,
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Meeting Link Ready',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Text(
            'Share this link with participants you want in the meeting.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[400]),
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
                Expanded(child: Text(meeting.code, style: const TextStyle(fontFamily: 'monospace'))),
                IconButton(
                  icon: const Icon(Icons.copy),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: meeting.code));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied!')));
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
            backgroundColor: Colors.white10,
            onTap: () {
              Navigator.pop(context);
              context.push('/meeting/${meeting.id}');
            },
          ),
        ],
      ),
    );
  }
}
