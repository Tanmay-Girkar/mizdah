import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../data/repositories/mizdah_repository.dart';
import '../../../data/models/models.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/mizdah_button.dart';
import '../../../core/theme/theme_provider.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final callHistoryAsync = ref.watch(callHistoryProvider);

    return Scaffold(
      drawer: const MizdahDrawer(),
      body: Container(
        decoration: BoxDecoration(
          gradient: isDark ? MizdahTheme.darkGradient : null,
          color: isDark ? null : MizdahTheme.lightBackground,
        ),
        child: SafeArea(
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: MizdahAppBar(),
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
                              onTap: () => context.push('/start-call'),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _ActionCard(
                              title: 'Join with code',
                              icon: Icons.keyboard_rounded,
                              color: Colors.white24,
                              onTap: () => _showJoinCodeDialog(context),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const UpcomingMeetingsSection(),
                      const SizedBox(height: 32),

                      // Recent History Section
                      const _SectionHeader(title: 'Recent activity'),
                      const SizedBox(height: 16),
                      callHistoryAsync.when(
                        data: (history) => history.isEmpty
                            ? const EmptyStateView()
                            : Column(
                                children: history.map((item) => HistoryTile(item: item)).toList(),
                              ),
                        loading: () => const Center(child: CircularProgressIndicator()),
                        error: (err, stack) => Text('Error: $err'),
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

  void _showJoinCodeDialog(BuildContext context) {
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
                color: color.withOpacity(0.1),
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
    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                height: 48,
                width: 48,
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.event, color: MizdahTheme.primaryBlue),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Plan ahead',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Schedule next meeting',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
              MizdahButton(
                label: 'Schedule',
                isFullWidth: false,
                onTap: () => context.push('/schedule'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}


class HistoryTile extends StatelessWidget {
  final CallHistory item;
  const HistoryTile({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withOpacity(0.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: CircleAvatar(
          backgroundColor: Colors.blue.withOpacity(0.1),
          child: Text(item.title[0], style: const TextStyle(color: Colors.blue)),
        ),
        title: Text(item.title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(
          DateFormat('MMM d, h:mm a').format(item.timestamp),
          style: const TextStyle(fontSize: 12),
        ),
        trailing: Icon(Icons.chevron_right, color: Colors.grey.withOpacity(0.5)),
        onTap: () => context.push('/meeting/${item.id}'),
      ),
    );
  }
}

class JoinCodeDialog extends StatefulWidget {
  const JoinCodeDialog({super.key});

  @override
  State<JoinCodeDialog> createState() => _JoinCodeDialogState();
}

class _JoinCodeDialogState extends State<JoinCodeDialog> {
  final _controller = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Join with code'),
      content: TextField(
        controller: _controller,
        decoration: const InputDecoration(
          hintText: 'Example: vpm-mwrh-fjc',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () {
            if (_controller.text.isNotEmpty) {
              Navigator.pop(context);
              context.push('/meeting/${_controller.text}');
            }
          },
          child: const Text('Join'),
        ),
      ],
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
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 0.5),
    );
  }
}

final callHistoryProvider = FutureProvider<List<CallHistory>>((ref) {
  return ref.watch(mizdahRepositoryProvider).getCallHistory();
});

class MizdahAppBar extends StatelessWidget {
  const MizdahAppBar({super.key});

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
        const CircleAvatar(
          radius: 18,
          backgroundColor: Colors.blue,
          child: Icon(Icons.person, color: Colors.white, size: 20),
        ),
      ],
    );
  }
}

class MizdahDrawer extends StatelessWidget {
  const MizdahDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          const DrawerHeader(
            decoration: BoxDecoration(color: MizdahTheme.darkBackgroundTop),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(radius: 30, child: Icon(Icons.person)),
                SizedBox(height: 12),
                Text('User Name', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                Text('user@example.com', style: TextStyle(color: Colors.white70, fontSize: 12)),
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
          Icon(Icons.history, size: 64, color: Colors.grey.withOpacity(0.3)),
          const SizedBox(height: 16),
          const Text('No recent activity', style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}
