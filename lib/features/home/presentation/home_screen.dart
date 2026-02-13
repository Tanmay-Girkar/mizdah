import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../data/repositories/mizdah_repository.dart';
import '../../../data/models/models.dart';
import 'package:intl/intl.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final callHistoryAsync = ref.watch(callHistoryProvider);

    return Scaffold(
      drawer: const MizdahDrawer(),
      body: SafeArea(
        child: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) {
            return [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: MizdahAppBar(),
                ),
              ),
            ];
          },
          body: callHistoryAsync.when(
            data: (history) {
              if (history.isEmpty) {
                return const EmptyStateView();
              }
              return RecentCallsList(history: history);
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, stack) => Center(child: Text('Error: $err')),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/start-call'),
        label: const Text('New'),
        icon: const Icon(Icons.video_call),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
    );
  }
}

final callHistoryProvider = FutureProvider<List<CallHistory>>((ref) {
  return ref.watch(mizdahRepositoryProvider).getCallHistory();
});

class MizdahAppBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      height: 56,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
          const Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 8.0),
              child: Text('Search contacts', style: TextStyle(fontSize: 16)),
            ),
          ),
          const CircleAvatar(radius: 16, child: Icon(Icons.person, size: 20)),
        ],
      ),
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
          DrawerHeader(
            child: Text(
              'Mizdah',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Privacy in Meet'),
            onTap: () => context.push('/privacy'),
          ),
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text('Settings'),
            onTap: () => context.push('/settings'),
          ),
          ListTile(
            leading: const Icon(Icons.help_outline),
            title: const Text('Help and feedback'),
            onTap: () {
              // Open Help (To be implemented)
            },
          ),
        ],
      ),
    );
  }
}

class RecentCallsList extends StatelessWidget {
  final List<CallHistory> history;
  const RecentCallsList({super.key, required this.history});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: history.length,
      itemBuilder: (context, index) {
        final item = history[index];
        return ListTile(
          leading: CircleAvatar(child: Text(item.title[0])),
          title: Text(item.title),
          subtitle: Text(DateFormat('MMM d, h:mm a').format(item.timestamp)),
          trailing: IconButton(
            icon: const Icon(Icons.videocam_outlined),
            onPressed: () => context.push('/meeting/${item.id}'),
          ),
        );
      },
    );
  }
}

class EmptyStateView extends StatelessWidget {
  const EmptyStateView({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.history,
            size: 80,
            color: Theme.of(context).colorScheme.outline.withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'Your latest activity will appear here',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}
