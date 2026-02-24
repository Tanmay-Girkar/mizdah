import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/theme_provider.dart';
import '../../../core/widgets/glass_card.dart';

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
    return RadioListTile<ThemeMode>(
      title: Text(title, style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
      value: mode,
      groupValue: current,
      activeColor: MizdahTheme.primaryBlue,
      onChanged: (val) => ref.read(themeProvider.notifier).setTheme(val!),
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
          child: SwitchListTile.adaptive(
            title: Text('Push Notifications', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
            subtitle: Text('Get notified about upcoming meetings', style: TextStyle(color: isDark ? Colors.white70 : Colors.black54)),
            value: _pushEnabled,
            activeColor: MizdahTheme.primaryBlue,
            onChanged: (v) => setState(() => _pushEnabled = v),
          ),
        ),
      ],
    );
  }
}
