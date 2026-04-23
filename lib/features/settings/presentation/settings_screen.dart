import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/theme_provider.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/mizdah_button.dart';
import '../../auth/auth_provider.dart';
import '../../../data/repositories/settings_repository.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(text: 'General'),
            Tab(text: 'Audio'),
            Tab(text: 'Video'),
            Tab(text: 'Notifications'),
          ],
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: isDark ? MizdahTheme.darkGradient : null,
          color: isDark ? null : MizdahTheme.lightBackground,
        ),
        child: TabBarView(
          controller: _tabController,
          children: [
            _GeneralSettings(),
            _AudioSettings(),
            _VideoSettings(),
            _NotificationSettings(),
          ],
        ),
      ),
    );
  }
}

class _GeneralSettings extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _ProfileSection(),
        const SizedBox(height: 32),
        Text(
          'Appearance', 
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isDark ? Colors.white : Colors.black87)
        ),
        const SizedBox(height: 16),
        GlassCard(
          child: Column(
            children: [
              _ThemeTile(title: 'Light', mode: ThemeMode.light, current: themeMode, ref: ref, isDark: isDark),
              Divider(height: 1, color: isDark ? Colors.white10 : Colors.black12),
              _ThemeTile(title: 'Dark', mode: ThemeMode.dark, current: themeMode, ref: ref, isDark: isDark),
              Divider(height: 1, color: isDark ? Colors.white10 : Colors.black12),
              _ThemeTile(title: 'System Default', mode: ThemeMode.system, current: themeMode, ref: ref, isDark: isDark),
            ],
          ),
        ),
        const SizedBox(height: 32),
        _SupportSection(),
      ],
    );
  }
}

class _ProfileSection extends ConsumerStatefulWidget {
  @override
  ConsumerState<_ProfileSection> createState() => _ProfileSectionState();
}

class _ProfileSectionState extends ConsumerState<_ProfileSection> {
  final _nameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authProvider).user;
    if (user != null) {
      _nameController.text = user.name;
    }
  }

  Future<void> _saveProfile() async {
    setState(() => _isSaving = true);
    try {
      final newName = _nameController.text.trim();
      final newPass = _passwordController.text.trim();
      await ref.read(authProvider.notifier).updateProfile(
        name: newName.isNotEmpty ? newName : null,
        password: newPass.isNotEmpty ? newPass : null,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile updated system-wide!')));
        _passwordController.clear();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Profile', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isDark ? Colors.white : Colors.black87)),
        const SizedBox(height: 16),
        GlassCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: 'Display Name',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'New Password (Optional)',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 16),
              _isSaving
                ? const Center(child: CircularProgressIndicator())
                : MizdahButton(
                    label: 'Save Profile',
                    isFullWidth: true,
                    onTap: _saveProfile,
                  ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SupportSection extends ConsumerWidget {
  Future<void> _sendFeedback(BuildContext context, WidgetRef ref) async {
    // Basic mockup logic for the modal
    showDialog(
      context: context,
      builder: (ctx) {
        final feedbackController = TextEditingController();
        return AlertDialog(
          title: const Text('Send Feedback'),
          content: TextField(
            controller: feedbackController,
            maxLines: 4,
            decoration: const InputDecoration(hintText: 'What can we improve?'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                final text = feedbackController.text.trim();
                if (text.isEmpty) return;
                Navigator.pop(ctx);
                try {
                  final user = ref.read(authProvider).user;
                  await ref.read(settingsRepositoryProvider).sendFeedback(
                    category: 'General',
                    description: text,
                    userEmail: user?.email ?? 'anonymous',
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Feedback sent!')));
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                  }
                }
              },
              child: const Text('Send'),
            )
          ],
        );
      }
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Help & Support', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isDark ? Colors.white : Colors.black87)),
        const SizedBox(height: 16),
        GlassCard(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.feedback_outlined, color: MizdahTheme.primaryBlue),
                title: Text('Send Feedback', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
                onTap: () => _sendFeedback(context, ref),
              ),
              Divider(height: 1, color: isDark ? Colors.white10 : Colors.black12),
              ListTile(
                leading: const Icon(Icons.support_agent_outlined, color: MizdahTheme.primaryBlue),
                title: Text('Contact Support', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Support contact API triggered. (UI coming soon)')));
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ThemeTile extends StatelessWidget {
  final String title;
  final ThemeMode mode;
  final ThemeMode current;
  final WidgetRef ref;
  final bool isDark;

  const _ThemeTile({required this.title, required this.mode, required this.current, required this.ref, this.isDark = true});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(title, style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
      leading: Radio<ThemeMode>(
        value: mode,
        groupValue: current,
        activeColor: MizdahTheme.primaryBlue,
        onChanged: (val) => ref.read(themeProvider.notifier).setTheme(val!),
      ),
      onTap: () => ref.read(themeProvider.notifier).setTheme(mode),
    );
  }
}

class _AudioSettings extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Microphone', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isDark ? Colors.white : Colors.black87)),
        const SizedBox(height: 16),
        GlassCard(
          child: ListTile(
            title: Text('Built-in Microphone', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
            trailing: const Icon(Icons.check, color: MizdahTheme.primaryBlue),
            onTap: () {},
          ),
        ),
        const SizedBox(height: 24),
        Text('Speakers', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isDark ? Colors.white : Colors.black87)),
        const SizedBox(height: 16),
        GlassCard(
          child: ListTile(
            title: Text('Built-in Output', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
            trailing: const Icon(Icons.volume_up, color: MizdahTheme.primaryBlue),
            onTap: () {},
          ),
        ),
      ],
    );
  }
}

class _VideoSettings extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Camera', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isDark ? Colors.white : Colors.black87)),
        const SizedBox(height: 16),
        AspectRatio(
          aspectRatio: 16 / 9,
          child: GlassCard(
            padding: EdgeInsets.zero,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    'https://images.unsplash.com/photo-1544005313-94ddf0286df2?w=400&h=225&fit=crop',
                    fit: BoxFit.cover,
                  ),
                  const Center(child: Icon(Icons.videocam_rounded, color: Colors.white, size: 48)),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        GlassCard(
          child: ListTile(
            title: Text('FaceTime HD Camera', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
            trailing: const Icon(Icons.check, color: MizdahTheme.primaryBlue),
            onTap: () {},
          ),
        ),
      ],
    );
  }
}

class _NotificationSettings extends StatefulWidget {
  @override
  State<_NotificationSettings> createState() => _NotificationSettingsState();
}

class _NotificationSettingsState extends State<_NotificationSettings> {
  bool _pushEnabled = true;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Notifications', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isDark ? Colors.white : Colors.black87)),
        const SizedBox(height: 16),
        GlassCard(
          child: ListTile(
            title: Text('Push Notifications', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
            subtitle: Text('Get notified about upcoming meetings', style: TextStyle(color: isDark ? Colors.white70 : Colors.black54)),
            trailing: Switch.adaptive(
              value: _pushEnabled,
              activeThumbColor: Colors.white,
              activeTrackColor: MizdahTheme.primaryBlue,
              onChanged: (v) => setState(() => _pushEnabled = v),
            ),
          ),
        ),
      ],
    );
  }
}
