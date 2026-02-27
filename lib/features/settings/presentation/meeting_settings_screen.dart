import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/theme_provider.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../data/repositories/meeting_repository.dart';

class MeetingSettingsScreen extends ConsumerStatefulWidget {
  final String meetingId;
  const MeetingSettingsScreen({super.key, required this.meetingId});

  @override
  ConsumerState<MeetingSettingsScreen> createState() => _MeetingSettingsScreenState();
}

class _MeetingSettingsScreenState extends ConsumerState<MeetingSettingsScreen> {
  bool donNotShowVideoInTiles = false;
  bool liveCaptions = false;
  bool showReactionsFromOthers = true;
  bool animation = true;
  bool sound = false;
  bool isLoading = false;

  Future<void> _updateSetting(String key, dynamic value, VoidCallback updateLocalState) async {
    setState(() => isLoading = true);
    
    // Optimistic local update
    updateLocalState();
    
    try {
      final repo = ref.read(meetingRepositoryProvider);
      await repo.updateSettings(widget.meetingId, {key: value});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update setting: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    final accentColor = theme.primaryColor;
    final textColor = isDark ? Colors.white : const Color(0xFF111827);
    final subtitleColor = isDark ? Colors.white70 : Colors.black54;
    final iconColor = isDark ? Colors.white : const Color(0xFF111827);

    return Container(
      decoration: BoxDecoration(
        gradient: isDark ? MizdahTheme.darkGradient : null,
        color: isDark ? null : MizdahTheme.lightBackground,
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.close, color: textColor),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Text(
            'Settings',
            style: TextStyle(color: textColor, fontSize: 20, fontWeight: FontWeight.normal),
          ),
          centerTitle: false,
        ),
        body: ListView(
          children: [
          _buildSectionHeader('Video', accentColor),
          _buildSwitchTile(
            title: "Don't show video in tiles",
            subtitle: 'Watch only presentations',
            value: donNotShowVideoInTiles,
            onChanged: (v) => _updateSetting('dont_show_video_in_tiles', v, () => donNotShowVideoInTiles = v),
            accentColor: accentColor,
            textColor: textColor,
            subtitleColor: subtitleColor,
          ),
          const SizedBox(height: 16),
          _buildSectionHeader('General', accentColor),
          _buildActionTile(
            icon: Icons.lock_person_outlined,
            title: 'Host controls',
            iconColor: iconColor,
            textColor: textColor,
          ),
          _buildActionTile(
            icon: Icons.feedback_outlined,
            title: 'Send feedback',
            iconColor: iconColor,
            textColor: textColor,
          ),
          const SizedBox(height: 16),
          _buildSectionHeader('Captions', accentColor),
          _buildSwitchTile(
            icon: Icons.closed_caption_outlined,
            title: 'Live captions',
            subtitle: 'Show captions in this call',
            value: liveCaptions,
            onChanged: (v) => _updateSetting('live_captions', v, () => liveCaptions = v),
            accentColor: accentColor,
            textColor: textColor,
            subtitleColor: subtitleColor,
            iconColor: iconColor,
          ),
          _buildActionTile(
            icon: Icons.language_outlined,
            title: 'Language of the call',
            subtitle: 'English (India)',
            iconColor: iconColor,
            textColor: textColor,
            subtitleColor: subtitleColor,
          ),
          const SizedBox(height: 16),
          _buildSectionHeader('Reactions', accentColor),
          _buildSwitchTile(
            title: 'Show reactions from others',
            subtitle: 'When off, your own reactions still appear',
            value: showReactionsFromOthers,
            onChanged: (v) => _updateSetting('show_reactions_from_others', v, () => showReactionsFromOthers = v),
            accentColor: accentColor,
            textColor: textColor,
            subtitleColor: subtitleColor,
          ),
          _buildSwitchTile(
            title: 'Animation',
            subtitle: 'Reactions move on the screen',
            value: animation,
            onChanged: (v) => _updateSetting('animation', v, () => animation = v),
            accentColor: accentColor,
            textColor: textColor,
            subtitleColor: subtitleColor,
          ),
          _buildSwitchTile(
            title: 'Sound',
            subtitle: 'Sound can accompany reactions',
            value: sound,
            onChanged: (v) => _updateSetting('sound', v, () => sound = v),
            accentColor: accentColor,
            textColor: textColor,
            subtitleColor: subtitleColor,
          ),
          _buildActionTile(
            title: 'Skin tone',
            subtitle: 'Select the skin tone for your emoji',
            textColor: textColor,
            subtitleColor: subtitleColor,
            trailing: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: isDark ? Colors.white24 : Colors.black12),
              ),
              child: const Text('👍', style: TextStyle(fontSize: 20)),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, Color accentColor) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          color: accentColor,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildSwitchTile({
    IconData? icon,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    required Color accentColor,
    required Color textColor,
    required Color subtitleColor,
    Color? iconColor,
  }) {
    return ListTile(
      leading: icon != null ? Icon(icon, color: iconColor) : null,
      title: Text(
        title,
        style: TextStyle(color: textColor, fontSize: 16),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: TextStyle(color: subtitleColor, fontSize: 13),
            )
          : null,
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeColor: Colors.white,
        activeTrackColor: accentColor,
        inactiveThumbColor: Colors.grey[400],
        inactiveTrackColor: Colors.white10.withOpacity(0.1),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
    );
  }

  Widget _buildActionTile({
    IconData? icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    required Color textColor,
    Color? iconColor,
    Color? subtitleColor,
  }) {
    return ListTile(
      leading: icon != null ? Icon(icon, color: iconColor) : null,
      title: Text(
        title,
        style: TextStyle(color: textColor, fontSize: 16),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: TextStyle(color: subtitleColor, fontSize: 13),
            )
          : null,
      trailing: trailing,
      onTap: () {},
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
    );
  }
}
