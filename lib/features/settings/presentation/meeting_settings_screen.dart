import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/theme_provider.dart';
import '../../../core/widgets/glass_card.dart';

class MeetingSettingsScreen extends ConsumerStatefulWidget {
  const MeetingSettingsScreen({super.key});

  @override
  ConsumerState<MeetingSettingsScreen> createState() => _MeetingSettingsScreenState();
}

class _MeetingSettingsScreenState extends ConsumerState<MeetingSettingsScreen> {
  bool donNotShowVideoInTiles = false;
  bool liveCaptions = false;
  bool showReactionsFromOthers = true;
  bool animation = true;
  bool sound = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    // In-meeting specific theme (Dark brown/black for dark mode, default for light)
    final accentColor = isDark ? const Color(0xFFE38E6E) : theme.primaryColor;
    final backgroundColor = isDark ? const Color(0xFF1D1B16) : theme.scaffoldBackgroundColor;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subtitleColor = isDark ? Colors.white70 : Colors.black54;
    final iconColor = isDark ? Colors.white : theme.primaryColor;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: backgroundColor,
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
            onChanged: (v) => setState(() => donNotShowVideoInTiles = v),
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
            onChanged: (v) => setState(() => liveCaptions = v),
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
            onChanged: (v) => setState(() => showReactionsFromOthers = v),
            accentColor: accentColor,
            textColor: textColor,
            subtitleColor: subtitleColor,
          ),
          _buildSwitchTile(
            title: 'Animation',
            subtitle: 'Reactions move on the screen',
            value: animation,
            onChanged: (v) => setState(() => animation = v),
            accentColor: accentColor,
            textColor: textColor,
            subtitleColor: subtitleColor,
          ),
          _buildSwitchTile(
            title: 'Sound',
            subtitle: 'Sound can accompany reactions',
            value: sound,
            onChanged: (v) => setState(() => sound = v),
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
