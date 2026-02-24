import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../meeting_provider.dart';
import '../../auth/auth_provider.dart';
import '../../../core/widgets/control_icon_button.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/theme/theme_provider.dart';
import '../../../core/widgets/mizdah_button.dart';
import 'package:intl/intl.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class MeetingRoomScreen extends ConsumerStatefulWidget {
  final String meetingId;
  const MeetingRoomScreen({super.key, required this.meetingId});

  @override
  ConsumerState<MeetingRoomScreen> createState() => _MeetingRoomScreenState();
}

class _MeetingRoomScreenState extends ConsumerState<MeetingRoomScreen> {
  bool _isChatOpen = false;
  bool _isParticipantsOpen = false;
  bool _isHostControlsOpen = false;
  bool _isBreakoutOpen = false;
  bool _isRaisingHand = false;
  bool _isRecording = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = ref.read(authProvider).user;
      ref.read(meetingProvider(widget.meetingId).notifier).joinMeeting(
        widget.meetingId,
        user?.id ?? 'guest',
        user?.name ?? 'Guest',
      );
    });
  }

  @override
  void dispose() {
    // Note: Provider might handle this, but explicit leave is safer
    ref.read(meetingProvider(widget.meetingId).notifier).leaveMeeting();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final meetingState = ref.watch(meetingProvider(widget.meetingId));
    final meetingNotifier = ref.watch(meetingProvider(widget.meetingId).notifier);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: isDark ? MizdahTheme.darkGradient : null,
          color: isDark ? null : MizdahTheme.lightBackground,
        ),
        child: SafeArea(
          child: Stack(
            children: [
              // Main Content
              _participantCount(meetingState) > 0 
                ? _VideoGrid(meetingState: meetingState)
                : _SolitaryHeroView(meetingId: widget.meetingId),

              // Top Bar
              _MeetingTopBar(
                meetingId: widget.meetingId,
                isRecording: meetingState.isRecording,
              ),

              // PIP for Self if solitary
              if (_participantCount(meetingState) == 0)
                Positioned(
                  bottom: 100,
                  right: 16,
                  child: _SelfViewCard(
                    isMicOn: meetingState.isMicOn,
                    isCameraOn: meetingState.isCameraOn,
                    renderer: meetingState.localRenderer,
                  ),
                ),
              // Bottom Controls
              Align(
                alignment: Alignment.bottomCenter,
                child: _InCallControls(
                  isMicOn: meetingState.isMicOn,
                  isCameraOn: meetingState.isCameraOn,
                  onMicToggle: meetingNotifier.toggleMic,
                  onCameraToggle: meetingNotifier.toggleCamera,
                  onHangup: () => context.go('/'),
                  onOptionsTap: () => _showOptionsBottomSheet(context),
                ),
              ),

              // Panels
              if (_activePanel != null)
                _SlidingPanel(
                  title: _getPanelTitle(),
                  onClose: () => setState(() => _activePanel = null),
                  child: _getPanelChild(),
                ),
            ],
          ),
        ),
      ),
    );
  }

  int _participantCount(MeetingState state) => 
      state.remoteRenderers.isNotEmpty ? state.remoteRenderers.length : state.mockParticipantCount;
  String? _activePanel; 

  void _showOptionsBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _MoreOptionsSheet(
        isRaisingHand: _isRaisingHand,
        onRaiseHandToggle: () {
          setState(() => _isRaisingHand = !_isRaisingHand);
          Navigator.pop(context);
        },
        onOpenChat: () {
          Navigator.pop(context);
          setState(() => _activePanel = 'chat');
        },
      ),
    );
  }

  String _getPanelTitle() {
    switch (_activePanel) {
      case 'chat':
        return 'In-call messages';
      case 'participants':
        return 'Participants (5)';
      case 'host':
        return 'Host Controls';
      case 'breakout':
        return 'Breakout Rooms';
      default:
        return '';
    }
  }

  Widget _getPanelChild() {
    switch (_activePanel) {
      case 'chat':
        final meetingState = ref.watch(meetingProvider(widget.meetingId));
        return _ChatView(
          messages: meetingState.chatMessages,
          onSend: (text) {
            final user = ref.read(authProvider).user;
            ref.read(meetingProvider(widget.meetingId).notifier).sendMessage(text, user?.name ?? 'Guest');
          },
        );
      case 'participants':
        return const _ParticipantsView();
      case 'host':
        return _HostControlsView(
          isRecording: _isRecording,
          onRecordingToggle: (val) => val
              ? _showRecordingConsent()
              : setState(() => _isRecording = false),
        );
      case 'breakout':
        return const _BreakoutRoomsView();
      default:
        return const SizedBox.shrink();
    }
  }

  void _showRecordingConsent() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: MizdahTheme.darkBackgroundTop,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Record this meeting?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'By starting the recording, you confirm that you have obtained consent from all participants to be recorded.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          MizdahButton(
            label: 'Start Recording',
            isFullWidth: false,
            onTap: () {
              Navigator.pop(context);
              setState(() => _isRecording = true);
            },
          ),
        ],
      ),
    );
  }
}

class _VideoGrid extends StatelessWidget {
  final MeetingState meetingState;
  const _VideoGrid({required this.meetingState});

  @override
  Widget build(BuildContext context) {
    final count = meetingState.remoteRenderers.isNotEmpty 
        ? meetingState.remoteRenderers.length 
        : meetingState.mockParticipantCount;

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 80, 16, 100),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.8,
      ),
      itemCount: count,
      itemBuilder: (context, index) {
        if (meetingState.remoteRenderers.isNotEmpty) {
          final entry = meetingState.remoteRenderers.entries.elementAt(index);
          return ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              color: Colors.black,
              child: RTCVideoView(entry.value),
            ),
          );
        } else {
          // Mock tiles for UI development
          return _MockParticipantTile(index: index);
        }
      },
    );
  }
}

class _MockParticipantTile extends StatelessWidget {
  final int index;
  const _MockParticipantTile({required this.index});

  @override
  Widget build(BuildContext context) {
    const images = [
      'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=400&h=400&fit=crop',
      'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=400&h=400&fit=crop',
      'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=400&h=400&fit=crop',
      'https://images.unsplash.com/photo-1438761681033-6461ffad8d80?w=400&h=400&fit=crop',
    ];

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.network(images[index % images.length], fit: BoxFit.cover),
          Positioned(
            bottom: 8,
            left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Participant ${index + 1}',
                style: const TextStyle(color: Colors.white, fontSize: 10),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SolitaryHeroView extends StatelessWidget {
  final String meetingId;
  const _SolitaryHeroView({required this.meetingId});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "You're the only one here",
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.normal,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            "Share this meeting link with others that you want in the meeting",
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.grey[300] : Colors.grey[600],
            ),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface.withOpacity(0.5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'meet.google.com/$meetingId',
                    style: TextStyle(
                      color: Theme.of(context).textTheme.bodyMedium?.color,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Meeting link copied')),
                    );
                  },
                  child: Icon(
                    Icons.copy_outlined,
                    color: Theme.of(context).iconTheme.color,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          MizdahButton(
            label: 'Share invite',
            icon: Icons.share_outlined,
            isFullWidth: false,
            onTap: () {
              Share.share(
                'Join my Mizdah meeting using this link: https://meet.google.com/$meetingId',
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SelfViewCard extends StatelessWidget {
  final bool isMicOn;
  final bool isCameraOn;
  final RTCVideoRenderer renderer;

  const _SelfViewCard({
    required this.isMicOn,
    required this.isCameraOn,
    required this.renderer,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 120,
      height: 180,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: isCameraOn 
          ? RTCVideoView(renderer, mirror: true)
          : const Center(child: Icon(Icons.person, color: Colors.white24, size: 48)),
      ),
    );
  }
}

class _MeetingTopBar extends StatelessWidget {
  final String meetingId;
  final bool isRecording;
  const _MeetingTopBar({required this.meetingId, required this.isRecording});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconColor = isDark ? Colors.white : Colors.black87;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 12.0),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back, color: iconColor),
            onPressed: () => context.pop(),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.black.withValues(alpha: 0.3)
                  : Colors.black.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.calendar_today_outlined, color: iconColor, size: 16),
                const SizedBox(width: 8),
                Text(
                  meetingId,
                  style: TextStyle(
                    color: iconColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          if (isRecording) ...[
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 4),
                  const Text('REC', style: TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
          const Spacer(),
          Container(
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.1)
                  : Colors.transparent,
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: Icon(Icons.volume_up_outlined, color: iconColor),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Audio output switched')),
                );
              },
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}

class _InCallControls extends StatelessWidget {
  final bool isMicOn;
  final bool isCameraOn;
  final VoidCallback onMicToggle;
  final VoidCallback onCameraToggle;
  final VoidCallback onHangup;
  final VoidCallback onOptionsTap;

  const _InCallControls({
    required this.isMicOn,
    required this.isCameraOn,
    required this.onMicToggle,
    required this.onCameraToggle,
    required this.onHangup,
    required this.onOptionsTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        radius: 32,
        opacity: isDark ? 0.05 : 0.08,
        child: Row(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            ControlIconButton(
              icon: isCameraOn ? Icons.videocam : Icons.videocam_off,
              isActive: !isCameraOn,
              activeColor: Colors.red,
              onTap: onCameraToggle,
              size: 48,
            ),
            ControlIconButton(
              icon: isMicOn ? Icons.mic : Icons.mic_off,
              isActive: !isMicOn,
              activeColor: Colors.red,
              onTap: onMicToggle,
              size: 48,
            ),
            ControlIconButton(
              icon: Icons.sentiment_satisfied_alt_outlined,
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Reactions coming soon')),
                );
              },
              size: 48,
            ),
            ControlIconButton(
              icon: Icons.more_vert,
              onTap: onOptionsTap,
              size: 48,
            ),
            ControlIconButton(
              icon: Icons.call_end,
              backgroundColor: Colors.red,
              activeColor: Colors.white,
              inactiveColor: Colors.white,
              onTap: onHangup,
              size: 64,
            ),
          ],
        ),
      ),
    );
  }
}

class _MoreOptionsSheet extends StatelessWidget {
  final bool isRaisingHand;
  final VoidCallback onRaiseHandToggle;
  final VoidCallback onOpenChat;

  const _MoreOptionsSheet({
    required this.isRaisingHand,
    required this.onRaiseHandToggle,
    required this.onOpenChat,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF201A18)
            : Colors.white, // Opaque container for light mode
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.1),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Grabber
              Container(
                width: 32,
                height: 4,
                margin: const EdgeInsets.only(bottom: 24, top: 8),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black26,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Raise Hand
              _SheetButton(
                icon: Icons.pan_tool_outlined,
                label: '',
                isWideRow: true,
                onTap: onRaiseHandToggle,
                isActive: isRaisingHand,
              ),

              const SizedBox(height: 8),

              // Mid Row: Share, CC, Volume
              Row(
                children: [
                  Expanded(
                    child: _SheetButton(
                      icon: Icons.present_to_all_outlined,
                      label: '',
                      onTap: () {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Sharing screen...')),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _SheetButton(
                      icon: Icons.closed_caption_outlined,
                      label: '',
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Captions enabled')),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _SheetButton(
                      icon: Icons.volume_up_outlined,
                      label: '',
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Volume adjusted')),
                        );
                      },
                      isActive: true,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // On the go
              _SheetButton(
                icon: Icons.directions_walk,
                label: 'On the go',
                isWideRow: true,
                onTap: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('On the go mode activated')),
                  );
                },
              ),

              const SizedBox(height: 8),

              // Messages & Add others
              Row(
                children: [
                  Expanded(
                    child: _SheetButton(
                      icon: Icons.chat_bubble_outline,
                      label: 'In-call messages',
                      onTap: onOpenChat,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _SheetButton(
                      icon: Icons.person_add_outlined,
                      label: 'Add others',
                      onTap: () {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Invite link copied')),
                        );
                      },
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // Bottom row: Settings, Tools, Report
              Row(
                children: [
                  Expanded(
                    child: _SheetButton(
                      icon: Icons.settings_outlined,
                      label: 'Settings',
                      onTap: () {
                        Navigator.pop(context);
                        context.push('/meeting-settings');
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _SheetButton(
                      icon: Icons.apps,
                      label: 'Tools',
                      onTap: () {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Opening tools')),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _SheetButton(
                      icon: Icons.info_outline,
                      label: 'Report abuse',
                      onTap: () {
                        Navigator.pop(context);
                        context.push('/report');
                      },
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _SheetButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isWideRow;
  final bool isActive;

  const _SheetButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isWideRow = false,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 64,
        width: double.infinity,
        decoration: BoxDecoration(
          color: isActive
              ? Theme.of(context).primaryColor.withValues(alpha: 0.2)
              : (isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.black.withValues(alpha: 0.02)),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive
                ? Theme.of(context).primaryColor.withValues(alpha: 0.5)
                : (isDark
                      ? Colors.white.withValues(alpha: 0.1)
                      : Colors.black.withValues(alpha: 0.05)),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isActive
                  ? Theme.of(context).primaryColor
                  : (isDark ? Colors.white : Colors.black87),
              size: 24,
            ),
            if (label.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: isActive
                      ? Theme.of(context).primaryColor
                      : (isDark ? Colors.white : Colors.black87),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SlidingPanel extends StatelessWidget {
  final String title;
  final Widget child;
  final VoidCallback onClose;

  const _SlidingPanel({
    required this.title,
    required this.child,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Positioned.fill(
      child: GestureDetector(
        onTap: onClose,
        child: Container(
          color: Colors.black.withOpacity(0.4),
          alignment: Alignment.bottomCenter,
          child: GestureDetector(
            onTap: () {}, // Prevent tap propagation
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 30,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.8,
                width: double.infinity,
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white24 : Colors.black.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : Colors.black,
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              Icons.close_rounded,
                              color: isDark ? Colors.white60 : Colors.black54,
                            ),
                            onPressed: onClose,
                          ),
                        ],
                      ),
                    ),
                    Divider(
                      height: 1,
                      color: isDark ? Colors.white10 : Colors.black.withOpacity(0.05),
                    ),
                    Expanded(
                      child: Container(
                        color: isDark ? Colors.transparent : Colors.white,
                        child: child,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChatView extends StatelessWidget {
  final List<Map<String, dynamic>> messages;
  final Function(String) onSend;

  const _ChatView({required this.messages, required this.onSend});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textController = TextEditingController();

    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: messages.length,
            itemBuilder: (context, index) {
              final msg = messages[index];
              final isMe = msg['sender'] == 'You' || msg['sender'] == 'Mustafa Omen';
              final timeStr = msg['time'] != null 
                  ? DateFormat('h:mm a').format(DateTime.parse(msg['time']))
                  : DateFormat('h:mm a').format(DateTime.now());
              
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (!isMe) ...[
                          CircleAvatar(
                            radius: 14,
                            backgroundColor: MizdahTheme.primaryBlue.withOpacity(0.1),
                            child: Text(msg['sender'][0], style: const TextStyle(fontSize: 10, color: MizdahTheme.primaryBlue, fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Flexible(
                          child: Column(
                            crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                decoration: BoxDecoration(
                                  color: isMe 
                                      ? MizdahTheme.primaryBlue 
                                      : (isDark ? Colors.white.withOpacity(0.08) : const Color(0xFFEFEFEF)),
                                  borderRadius: BorderRadius.only(
                                    topLeft: const Radius.circular(16),
                                    topRight: const Radius.circular(16),
                                    bottomLeft: Radius.circular(isMe ? 16 : 4),
                                    bottomRight: Radius.circular(isMe ? 4 : 16),
                                  ),
                                  boxShadow: isMe ? [
                                    BoxShadow(
                                      color: MizdahTheme.primaryBlue.withOpacity(0.3),
                                      blurRadius: 8,
                                      offset: const Offset(0, 4),
                                    )
                                  ] : null,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (!isMe)
                                      Padding(
                                        padding: const EdgeInsets.only(bottom: 4),
                                        child: Text(
                                          msg['sender'],
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 11,
                                            color: isDark ? Colors.white70 : Colors.black54,
                                          ),
                                        ),
                                      ),
                                    Text(
                                      msg['text'],
                                      style: TextStyle(
                                        color: isMe ? Colors.white : (isDark ? Colors.white : Colors.black87),
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                timeStr,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey.withOpacity(0.6),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (isMe) const SizedBox(width: 8),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 40),
          decoration: BoxDecoration(
            color: isDark ? Colors.transparent : Colors.white,
            border: Border(top: BorderSide(color: isDark ? Colors.white10 : Colors.black.withOpacity(0.05))),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: textController,
                  style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                  decoration: InputDecoration(
                    hintText: 'Send a message...',
                    hintStyle: TextStyle(color: Colors.grey.withOpacity(0.6)),
                    filled: true,
                    fillColor: isDark ? Colors.white.withOpacity(0.05) : const Color(0xFFF0F2f5),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: () {
                  if (textController.text.isNotEmpty) {
                    onSend(textController.text);
                    textController.clear();
                  }
                },
                child: Container(
                  height: 48,
                  width: 48,
                  decoration: BoxDecoration(
                    color: MizdahTheme.primaryBlue,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: MizdahTheme.primaryBlue.withOpacity(0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.send_rounded, size: 20, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ParticipantsView extends StatelessWidget {
  const _ParticipantsView();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      itemCount: 5,
      itemBuilder: (context, index) => ListTile(
        leading: CircleAvatar(
          backgroundColor: isDark ? Colors.white10 : Colors.black12,
          child: Text(
            index == 0 ? 'Y' : 'P',
            style: TextStyle(color: isDark ? Colors.white : Colors.black),
          ),
        ),
        title: Text(
          index == 0 ? 'You (Host)' : 'Participant $index',
          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.mic,
              color: isDark ? Colors.grey[600] : Colors.grey[400],
              size: 20,
            ),
            const SizedBox(width: 16),
            Icon(
              Icons.videocam,
              color: isDark ? Colors.grey[600] : Colors.grey[400],
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

class _HostControlsView extends StatefulWidget {
  final bool isRecording;
  final ValueChanged<bool> onRecordingToggle;

  const _HostControlsView({
    required this.isRecording,
    required this.onRecordingToggle,
  });

  @override
  State<_HostControlsView> createState() => _HostControlsViewState();
}

class _HostControlsViewState extends State<_HostControlsView> {
  bool _lockMeeting = false;
  bool _allowMic = true;
  bool _allowCam = true;
  bool _allowChat = true;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      children: [
        const Text(
          'Meeting Security',
          style: TextStyle(
            color: Colors.grey,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        _ControlToggle(
          title: 'Lock Meeting',
          subtitle: 'Prevent new participants from joining',
          value: _lockMeeting,
          onChanged: (v) => setState(() => _lockMeeting = v),
        ),
        const SizedBox(height: 24),
        const Text(
          'Participant Permissions',
          style: TextStyle(
            color: Colors.grey,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        _ControlToggle(
          title: 'Share Microphone',
          value: _allowMic,
          onChanged: (v) => setState(() => _allowMic = v),
        ),
        _ControlToggle(
          title: 'Share Video',
          value: _allowCam,
          onChanged: (v) => setState(() => _allowCam = v),
        ),
        _ControlToggle(
          title: 'Send Chat Messages',
          value: _allowChat,
          onChanged: (v) => setState(() => _allowChat = v),
        ),
        const Divider(color: Colors.white10, height: 32),
        _ControlToggle(
          title: 'Record Meeting',
          subtitle: 'Store this session in the cloud',
          value: widget.isRecording,
          onChanged: widget.onRecordingToggle,
        ),
        const SizedBox(height: 32),
        MizdahButton(
          label: 'Mute All',
          backgroundColor: Colors.white10,
          onTap: () {},
        ),
        const SizedBox(height: 12),
        MizdahButton(
          label: 'End Meeting for All',
          backgroundColor: Colors.red.withOpacity(0.1),
          onTap: () => context.go('/'),
        ),
        const SizedBox(height: 40),
      ],
    );
  }
}

class _ControlToggle extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ControlToggle({
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        title,
        style: TextStyle(
          color: isDark ? Colors.white : Colors.black87,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle!,
              style: TextStyle(
                color: isDark ? Colors.grey : Colors.grey[600],
                fontSize: 12,
              ),
            )
          : null,
      trailing: Switch.adaptive(
        value: value,
        activeColor: MizdahTheme.primaryBlue,
        onChanged: onChanged,
      ),
    );
  }
}

class _BreakoutRoomsView extends StatefulWidget {
  const _BreakoutRoomsView();

  @override
  State<_BreakoutRoomsView> createState() => _BreakoutRoomsViewState();
}

class _BreakoutRoomsViewState extends State<_BreakoutRoomsView> {
  int _roomCount = 2;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Text(
                'Assign participants to rooms',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Number of rooms',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () => setState(
                            () => _roomCount = (_roomCount > 1
                                ? _roomCount - 1
                                : 1),
                          ),
                          icon: const Icon(Icons.remove, color: Colors.white),
                        ),
                        Text(
                          '$_roomCount',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        IconButton(
                          onPressed: () => setState(() => _roomCount++),
                          icon: const Icon(Icons.add, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              ...List.generate(_roomCount, (index) => _RoomItem(index: index)),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
          child: MizdahButton(label: 'Create Rooms', onTap: () {}),
        ),
      ],
    );
  }
}

class _RoomItem extends StatelessWidget {
  final int index;
  const _RoomItem({required this.index});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Room ${index + 1}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const Text(
                '0 participants',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 12),
          MizdahButton(
            label: 'Assign',
            isFullWidth: false,
            backgroundColor: Colors.white10,
            onTap: () {},
          ),
        ],
      ),
    );
  }
}
