import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../meeting_provider.dart';
import '../../auth/auth_provider.dart';
import '../../../core/widgets/control_icon_button.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/theme/theme_provider.dart';
import '../../../core/widgets/mizdah_button.dart';
import 'package:intl/intl.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'widgets/captions_view.dart';
import 'widgets/whiteboard_view.dart';
import '../providers/meeting_services_provider.dart';
import '../../../../core/services/recording_service.dart';
import '../../../core/utils/meeting_utils.dart';

class MeetingRoomScreen extends ConsumerStatefulWidget {
  final String meetingId;
  final bool initialVideo;
  final bool initialAudio;

  const MeetingRoomScreen({
    super.key, 
    required this.meetingId,
    this.initialVideo = true,
    this.initialAudio = true,
  });

  @override
  ConsumerState<MeetingRoomScreen> createState() => _MeetingRoomScreenState();
}

class _MeetingRoomScreenState extends ConsumerState<MeetingRoomScreen> {
  bool _isRaisingHand = false;
  bool _isRecording = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authState = ref.read(authProvider);
      final user = authState.user;
      final jwtToken = authState.token ?? '';
      ref.read(meetingProvider(widget.meetingId).notifier).joinMeeting(
        widget.meetingId,
        user?.id ?? 'guest',
        user?.name ?? 'Guest',
        jwtToken,
        video: widget.initialVideo,
        audio: widget.initialAudio,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final meetingState = ref.watch(meetingProvider(widget.meetingId));
    final meetingNotifier = ref.watch(meetingProvider(widget.meetingId).notifier);

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF020617) : MizdahTheme.lightBackground,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: isDark ? const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0F172A), 
              Color(0xFF020617),
            ],
          ),
        ) : null,
        child: SafeArea(
          bottom: false,
          child: Stack(
            children: [
              // Main Video Grid
              (meetingState.participants.isNotEmpty || meetingState.mockParticipantCount > 0)
                ? _VideoGrid(meetingState: meetingState)
                : _SolitaryHeroView(meetingId: widget.meetingId),

              // Floating Top Bar
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: _MeetingTopBar(
                  meetingId: widget.meetingId,
                  isRecording: meetingState.isRecording,
                  isSpeakerphoneOn: meetingState.isSpeakerphoneOn,
                  onToggleSpeakerphone: meetingNotifier.toggleSpeakerphone,
                  onSwitchCamera: meetingNotifier.switchCamera,
                ),
              ),

              // Captions Overlay
              const Positioned(
                bottom: 140, // above controls
                left: 16,
                right: 16,
                child: CaptionsView(),
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
                  onHangup: () {
                    meetingNotifier.leaveMeeting();
                    context.go('/');
                  },
                  onOptionsTap: () => _showOptionsBottomSheet(context),
                  hasWaitingParticipants: meetingState.waitingParticipants.isNotEmpty,
                ),
              ),

              // Join Requests Notification
              if (meetingState.isHost && meetingState.waitingParticipants.isNotEmpty)
                Positioned(
                  top: 80,
                  left: 16,
                  right: 16,
                  child: _JoinRequestBanner(
                    count: meetingState.waitingParticipants.length,
                    firstName: meetingState.waitingParticipants.first['name'] ?? 'Guest',
                    onView: () => setState(() => _activePanel = 'participants'),
                    onAdmit: () => meetingNotifier.admitParticipant(meetingState.waitingParticipants.first['socketId']),
                    onDeny: () => meetingNotifier.denyParticipant(meetingState.waitingParticipants.first['socketId']),
                  ),
                ),

              // Panels
              if (_activePanel != null)
                _SlidingPanel(
                  title: _getPanelTitle(),
                  onClose: () => setState(() => _activePanel = null),
                  child: _getPanelChild(),
                ),

              // Waiting Room Overlay
              if (meetingState.isInWaitingRoom)
                Container(
                  color: isDark ? const Color(0xFF0F172A) : MizdahTheme.lightBackground,
                  width: double.infinity,
                  height: double.infinity,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.hourglass_empty_rounded, size: 64, color: MizdahTheme.primaryBlue),
                      const SizedBox(height: 24),
                      Text(
                        'Wait for the host to let you in',
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87, 
                          fontSize: 18, 
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'The meeting host will let you in soon...',
                        style: TextStyle(
                          color: isDark ? Colors.white70 : Colors.black54, 
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 48),
                      MizdahButton(
                        label: 'Leave Meeting',
                        onTap: () {
                          meetingNotifier.leaveMeeting();
                          context.go('/');
                        },
                        isFullWidth: false,
                        backgroundColor: Colors.white10,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  int _participantCount(MeetingState state) => state.participants.length;
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
        onOpenParticipants: () {
          Navigator.pop(context);
          setState(() => _activePanel = 'participants');
        },
        onOpenHostControls: () {
          Navigator.pop(context);
          setState(() => _activePanel = 'host');
        },
        onOpenWhiteboard: () {
          Navigator.pop(context);
          setState(() => _activePanel = 'whiteboard');
        },
        onToggleScreenShare: () {
          Navigator.pop(context);
          ref.read(meetingProvider(widget.meetingId).notifier).toggleScreenShare();
        },
        onToggleCaptions: () {
          Navigator.pop(context);
          ref.read(captionServiceProvider(widget.meetingId).notifier).toggleCaptions();
        },
        isScreenSharing: ref.watch(meetingProvider(widget.meetingId)).isScreenSharing,
        isCaptionsEnabled: ref.watch(captionServiceProvider(widget.meetingId)).isEnabled,
      ),
    );
  }

  String _getPanelTitle() {
    switch (_activePanel) {
      case 'chat':
        return 'In-call messages';
      case 'participants':
        final meetingState = ref.read(meetingProvider(widget.meetingId));
        return 'Participants (${meetingState.participants.length + 1})';
      case 'host':
        return 'Host Controls';
      case 'breakout':
        return 'Breakout Rooms';
      case 'whiteboard':
        return 'Whiteboard';
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
            final sent = ref.read(meetingProvider(widget.meetingId).notifier).sendMessage(
              text, 
              user?.name ?? 'Guest',
            );
            if (!sent) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Chat is disabled by the host.')));
            }
          },
        );
      case 'participants':
        return _ParticipantsView(meetingId: widget.meetingId);
      case 'host':
        final recState = ref.watch(recordingServiceProvider(widget.meetingId));
        return _HostControlsView(
          meetingId: widget.meetingId,
          isRecording: recState.status == RecordingStatus.recording || _isRecording,
          onRecordingToggle: (val) {
            if (val) {
              _showRecordingConsent();
            } else {
              ref.read(recordingServiceProvider(widget.meetingId).notifier).stopRecording();
              setState(() => _isRecording = false);
            }
          },
        );
      case 'breakout':
        return const _BreakoutRoomsView();
      case 'whiteboard':
        return const WhiteboardView();
      default:
        return const SizedBox.shrink();
    }
  }

  void _showRecordingConsent() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? MizdahTheme.darkBackgroundTop : Colors.white,
        surfaceTintColor: Colors.transparent,
        title: Text(
          'Record this meeting?',
          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
        ),
        content: Text(
          'By starting the recording, you confirm that you have obtained consent from all participants to be recorded.',
          style: TextStyle(color: isDark ? Colors.white70 : Colors.black54),
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
              ref.read(recordingServiceProvider(widget.meetingId).notifier).requestRecording();
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
      padding: const EdgeInsets.fromLTRB(16, 80, 16, 120),
      physics: const BouncingScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 0.75, // Taller cards for mobile
      ),
      itemCount: count,
      itemBuilder: (context, index) {
        if (meetingState.remoteRenderers.isNotEmpty) {
          final entry = meetingState.remoteRenderers.entries.elementAt(index);
          final hasVideo = entry.value.srcObject?.getVideoTracks().where((t) => t.enabled).isNotEmpty ?? false;
          
          return ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              color: const Color(0xFF3C4043), // Google Meet dark grey
              child: hasVideo 
                ? RTCVideoView(entry.value, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
                : const _AvatarPlaceholder(name: 'Participant', size: 64),
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
      'https://images.unsplash.com/photo-1472099645785-5658abf4ff4e?w=400&h=400&fit=crop', // Business man
      'https://images.unsplash.com/photo-1573496359142-b8d87734a5a2?w=400&h=400&fit=crop', // Business woman
      'https://images.unsplash.com/photo-1519085360753-af0119f7cbe7?w=400&h=400&fit=crop', // Professional
      'https://images.unsplash.com/photo-1580489944761-15a19d654956?w=400&h=400&fit=crop', // Professional
    ];

    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              images[index % images.length], 
              fit: BoxFit.cover,
            ),
            // Name Tag Layer
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 32, 12, 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.7),
                    ],
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Participant ${index + 1}',
                        style: const TextStyle(
                          color: Colors.white, 
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const Icon(Icons.mic_off, color: Colors.white, size: 14),
                  ],
                ),
              ),
            ),
          ],
        ),
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
              color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    MeetingUtils.generateMeetingLink(meetingId),
                    style: TextStyle(
                      color: Theme.of(context).textTheme.bodyMedium?.color,
                      fontSize: 13,
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
              SharePlus.instance.share(
                ShareParams(
                  text: 'Join my Mizdah meeting using this link: ${MeetingUtils.generateMeetingLink(meetingId)}',
                ),
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
          ? RTCVideoView(renderer, mirror: true, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
          : const _AvatarPlaceholder(name: 'You', size: 56),
      ),
    );
  }
}

class _AvatarPlaceholder extends StatelessWidget {
  final String name;
  final double size;

  const _AvatarPlaceholder({
    required this.name,
    this.size = 64,
  });

  @override
  Widget build(BuildContext context) {
    // Generate a consistent color based on the name
    final colorVal = name.isNotEmpty ? name.codeUnitAt(0) : 0;
    final colors = [
      Colors.blue, Colors.red, Colors.green, Colors.orange,
      Colors.purple, Colors.teal, Colors.pink, Colors.indigo
    ];
    final bgColor = colors[colorVal % colors.length].shade400;
    final initial = name.isNotEmpty ? name.substring(0, 1).toUpperCase() : '?';

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: bgColor,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              initial,
              style: TextStyle(
                color: Colors.white,
                fontSize: size * 0.45,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            name,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _MeetingTopBar extends StatelessWidget {
  final String meetingId;
  final bool isRecording;
  final bool isSpeakerphoneOn;
  final VoidCallback onToggleSpeakerphone;
  final VoidCallback onSwitchCamera;

  const _MeetingTopBar({
    required this.meetingId, 
    required this.isRecording,
    required this.isSpeakerphoneOn,
    required this.onToggleSpeakerphone,
    required this.onSwitchCamera,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconColor = isDark ? Colors.white : Colors.black87;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Row(
        children: [
          _TopBarIconButton(
            icon: Icons.arrow_back,
            onTap: () => context.pop(),
          ),
          const SizedBox(width: 8),
          GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            radius: 20,
            opacity: isDark ? 0.1 : 0.05,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_rounded, color: isDark ? MizdahTheme.primaryBlue : Colors.black54, size: 14),
                const SizedBox(width: 8),
                Text(
                  meetingId,
                  style: TextStyle(
                    color: iconColor,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                Icon(Icons.keyboard_arrow_down, color: iconColor.withValues(alpha: 0.5), size: 18),
              ],
            ),
          ),
          if (isRecording) ...[
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.circle, color: Colors.red, size: 8),
                  const SizedBox(width: 6),
                  const Text(
                    'REC',
                    style: TextStyle(
                      color: Colors.red,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const Spacer(),
          _TopBarIconButton(
            icon: isSpeakerphoneOn ? Icons.volume_up_rounded : Icons.volume_off_rounded,
            onTap: onToggleSpeakerphone,
          ),
          const SizedBox(width: 8),
          _TopBarIconButton(
            icon: Icons.cameraswitch_outlined,
            onTap: onSwitchCamera,
          ),
        ],
      ),
    );
  }
}

class _TopBarIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _TopBarIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GlassCard(
      padding: EdgeInsets.zero,
      radius: 100,
      opacity: isDark ? 0.1 : 0.05,
      child: IconButton(
        icon: Icon(icon, color: isDark ? Colors.white : Colors.black87, size: 20),
        onPressed: onTap,
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
  final bool hasWaitingParticipants;

  const _InCallControls({
    required this.isMicOn,
    required this.isCameraOn,
    required this.onMicToggle,
    required this.onCameraToggle,
    required this.onHangup,
    required this.onOptionsTap,
    this.hasWaitingParticipants = false,
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
            Stack(
              clipBehavior: Clip.none,
              children: [
                ControlIconButton(
                  icon: Icons.more_vert,
                  onTap: onOptionsTap,
                  size: 48,
                ),
                if (hasWaitingParticipants)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 12,
                        minHeight: 12,
                      ),
                    ),
                  ),
              ],
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
  final VoidCallback onOpenParticipants;
  final VoidCallback onOpenHostControls;
  final VoidCallback onOpenWhiteboard;
  final VoidCallback onToggleScreenShare;
  final VoidCallback onToggleCaptions;
  final bool isScreenSharing;
  final bool isCaptionsEnabled;

  const _MoreOptionsSheet({
    required this.isRaisingHand,
    required this.onRaiseHandToggle,
    required this.onOpenChat,
    required this.onOpenParticipants,
    required this.onOpenHostControls,
    required this.onOpenWhiteboard,
    required this.onToggleScreenShare,
    required this.onToggleCaptions,
    required this.isScreenSharing,
    required this.isCaptionsEnabled,
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
                      onTap: onToggleScreenShare,
                      isActive: isScreenSharing,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _SheetButton(
                      icon: Icons.closed_caption_outlined,
                      label: '',
                      onTap: onToggleCaptions,
                      isActive: isCaptionsEnabled,
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

              // Messages & Participants
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
                      icon: Icons.people_outline,
                      label: 'Participants',
                      onTap: onOpenParticipants,
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
                      icon: Icons.security,
                      label: 'Host Controls',
                      onTap: onOpenHostControls,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _SheetButton(
                      icon: Icons.brush_outlined,
                      label: 'Whiteboard',
                      onTap: onOpenWhiteboard,
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
          color: Colors.black.withValues(alpha: 0.4),
          alignment: Alignment.bottomCenter,
          child: GestureDetector(
            onTap: () {}, // Prevent tap propagation
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
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
                        color: isDark ? Colors.white24 : Colors.black.withValues(alpha: 0.1),
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
                      color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
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

class _ChatView extends ConsumerStatefulWidget {
  final List<Map<String, dynamic>> messages;
  final Function(String) onSend;

  const _ChatView({required this.messages, required this.onSend});

  @override
  ConsumerState<_ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends ConsumerState<_ChatView> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void didUpdateWidget(_ChatView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.messages.length > oldWidget.messages.length) {
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentUser = ref.watch(authProvider).user;

    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(20),
            itemCount: widget.messages.length,
            itemBuilder: (context, index) {
              final msg = widget.messages[index];
              final isMe = msg['sender'] == 'You' || 
                           msg['sender'] == 'Mustafa Omen' || 
                           msg['sender'] == currentUser?.name;
              
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
                            backgroundColor: MizdahTheme.primaryBlue.withValues(alpha: 0.1),
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
                                      : (isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFEFEFEF)),
                                  borderRadius: BorderRadius.only(
                                    topLeft: const Radius.circular(16),
                                    topRight: const Radius.circular(16),
                                    bottomLeft: Radius.circular(isMe ? 16 : 4),
                                    bottomRight: Radius.circular(isMe ? 4 : 16),
                                  ),
                                  boxShadow: isMe ? [
                                    BoxShadow(
                                      color: MizdahTheme.primaryBlue.withValues(alpha: 0.3),
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
                                    if (msg['attachmentUrl'] != null)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 8.0),
                                        child: GestureDetector(
                                          onTap: () => launchUrl(Uri.parse(msg['attachmentUrl'])),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                            decoration: BoxDecoration(
                                              color: isMe ? Colors.white.withValues(alpha: 0.2) : Colors.black.withValues(alpha: 0.05),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(Icons.attach_file, size: 16, color: isMe ? Colors.white : MizdahTheme.primaryBlue),
                                                const SizedBox(width: 4),
                                                Flexible(
                                                  child: Text(
                                                    'Attachment',
                                                    style: TextStyle(
                                                      color: isMe ? Colors.white : MizdahTheme.primaryBlue,
                                                      fontSize: 12,
                                                      decoration: TextDecoration.underline,
                                                    ),
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
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
                                  color: Colors.grey.withValues(alpha: 0.6),
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
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withValues(alpha: 0.02) : Colors.white,
            border: Border(top: BorderSide(color: isDark ? Colors.white10 : Colors.black12)),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _textController,
                  style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                  decoration: InputDecoration(
                    hintText: 'Send a message...',
                    hintStyle: TextStyle(color: Colors.grey.withValues(alpha: 0.6)),
                    filled: true,
                    fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF0F2f5),
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
                  if (_textController.text.isNotEmpty) {
                    widget.onSend(_textController.text);
                    _textController.clear();
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
                        color: MizdahTheme.primaryBlue.withValues(alpha: 0.3),
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

class _ParticipantsView extends ConsumerWidget {
  final String meetingId;
  const _ParticipantsView({required this.meetingId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final meetingState = ref.watch(meetingProvider(meetingId));
    final participants = meetingState.participants;
    final waitingParticipants = meetingState.waitingParticipants;
    final isHost = meetingState.hostId == meetingState.userId;

    return CustomScrollView(
      slivers: [
        if (waitingParticipants.isNotEmpty && isHost) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                'Waiting Room (${waitingParticipants.length})',
                style: const TextStyle(
                  color: MizdahTheme.primaryBlue,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final p = waitingParticipants[index];
                final name = p['name'] ?? 'Guest';
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                  leading: CircleAvatar(
                    backgroundColor: MizdahTheme.primaryBlue.withValues(alpha: 0.1),
                    child: Text(name[0].toUpperCase(), style: const TextStyle(color: MizdahTheme.primaryBlue)),
                  ),
                  title: Text(name, style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: () => ref.read(meetingProvider(meetingId).notifier).denyParticipant(p['socketId']),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.redAccent,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                        child: const Text('Deny', style: TextStyle(fontSize: 12)),
                      ),
                      const SizedBox(width: 4),
                      TextButton(
                        onPressed: () => ref.read(meetingProvider(meetingId).notifier).admitParticipant(p['socketId']),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: MizdahTheme.primaryBlue,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        ),
                        child: const Text('Admit', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                );
              },
              childCount: waitingParticipants.length,
            ),
          ),
          const SliverToBoxAdapter(child: Divider(indent: 20, endIndent: 20, height: 32)),
        ],
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            child: Text(
              'In the meeting (${participants.length + 1})',
              style: TextStyle(
                color: isDark ? Colors.white70 : Colors.black54,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
        ),
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              // Include self
              if (index == 0) {
                 final user = ref.read(authProvider).user;
                 return _ParticipantTile(
                   name: '${user?.name ?? 'You'} (Me)',
                   isHost: meetingState.hostId == meetingState.userId,
                   isMicOn: meetingState.isMicOn,
                   isCameraOn: meetingState.isCameraOn,
                   isMe: true,
                 );
              }
              final p = participants[index - 1];
              return _ParticipantTile(
                name: p['name'] ?? 'Unknown',
                isHost: p['userId'] == meetingState.hostId || p['isHost'] == true,
                isMicOn: p['isMicOn'] ?? false,
                isCameraOn: p['isCameraOn'] ?? false,
                isMe: false,
              );
            },
            childCount: participants.length + 1,
          ),
        ),
      ],
    );
  }
}

class _ParticipantTile extends StatelessWidget {
  final String name;
  final bool isHost;
  final bool isMicOn;
  final bool isCameraOn;
  final bool isMe;

  const _ParticipantTile({
    required this.name,
    this.isHost = false,
    this.isMicOn = true,
    this.isCameraOn = true,
    this.isMe = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: isHost ? MizdahTheme.primaryBlue.withValues(alpha: 0.1) : (isDark ? Colors.white10 : Colors.black12),
        child: Text(
          name[0].toUpperCase(),
          style: TextStyle(
            color: isHost ? MizdahTheme.primaryBlue : (isDark ? Colors.white70 : Colors.black54),
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      title: Text(
        name,
        style: TextStyle(
          color: isDark ? Colors.white : Colors.black87,
          fontSize: 15,
          fontWeight: isMe ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      subtitle: isHost ? const Text('Meeting Host', style: TextStyle(color: MizdahTheme.primaryBlue, fontSize: 11)) : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isMicOn ? Icons.mic_none_rounded : Icons.mic_off_rounded,
            size: 20,
            color: isMicOn ? (isDark ? Colors.white38 : Colors.black38) : Colors.redAccent,
          ),
          const SizedBox(width: 12),
          Icon(
            isCameraOn ? Icons.videocam_outlined : Icons.videocam_off_outlined,
            size: 20,
            color: isCameraOn ? (isDark ? Colors.white38 : Colors.black38) : Colors.redAccent,
          ),
        ],
      ),
    );
  }
}

class _HostControlsView extends ConsumerStatefulWidget {
  final String meetingId;
  final bool isRecording;
  final ValueChanged<bool> onRecordingToggle;

  const _HostControlsView({
    required this.meetingId,
    required this.isRecording,
    required this.onRecordingToggle,
  });

  @override
  ConsumerState<_HostControlsView> createState() => _HostControlsViewState();
}

class _HostControlsViewState extends ConsumerState<_HostControlsView> {
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
          onChanged: (v) {
            setState(() => _lockMeeting = v);
            ref.read(meetingProvider(widget.meetingId).notifier).toggleLockMeeting(v);
          },
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
          onChanged: (v) {
            setState(() => _allowMic = v);
            ref.read(meetingProvider(widget.meetingId).notifier).updateParticipantPermissions('allowMic', v);
          }
        ),
        _ControlToggle(
          title: 'Share Video',
          value: _allowCam,
          onChanged: (v) {
            setState(() => _allowCam = v);
            ref.read(meetingProvider(widget.meetingId).notifier).updateParticipantPermissions('allowCam', v);
          }
        ),
        _ControlToggle(
          title: 'Send Chat Messages',
          value: _allowChat,
          onChanged: (v) {
            setState(() => _allowChat = v);
            ref.read(meetingProvider(widget.meetingId).notifier).updateParticipantPermissions('allowChat', v);
          }
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
          onTap: () {
            ref.read(meetingProvider(widget.meetingId).notifier).muteAll();
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('All participants muted')));
          },
        ),
        const SizedBox(height: 12),
        MizdahButton(
          label: 'End Meeting for All',
          backgroundColor: Colors.red.withValues(alpha: 0.1),
          onTap: () {
            ref.read(meetingProvider(widget.meetingId).notifier).endMeetingForAll();
            context.go('/');
          },
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
        activeThumbColor: Colors.white,
        activeTrackColor: MizdahTheme.primaryBlue,
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
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
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

class _JoinRequestBanner extends StatelessWidget {
  final int count;
  final String firstName;
  final VoidCallback onView;
  final VoidCallback onAdmit;
  final VoidCallback onDeny;

  const _JoinRequestBanner({
    required this.count,
    required this.firstName,
    required this.onView,
    required this.onAdmit,
    required this.onDeny,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      radius: 16,
      opacity: 0.95,
      child: Row(
        children: [
          const Icon(Icons.person_add_rounded, color: MizdahTheme.primaryBlue),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              count > 1 
                ? '$firstName and ${count - 1} others want to join'
                : '$firstName wants to join',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
          TextButton(
            onPressed: onView,
            child: const Text('View', style: TextStyle(color: MizdahTheme.primaryBlue)),
          ),
          const SizedBox(width: 4),
          TextButton(
            onPressed: onDeny,
            child: const Text('Deny', style: TextStyle(color: Colors.redAccent)),
          ),
          const SizedBox(width: 4),
          MizdahButton(
            label: 'Admit',
            isFullWidth: false,
            onTap: onAdmit,
          ),
        ],
      ),
    );
  }
}
