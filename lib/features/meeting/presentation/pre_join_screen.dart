import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/mizdah_button.dart';
import '../../../core/widgets/control_icon_button.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/theme_provider.dart';
import '../../../data/repositories/meeting_repository.dart';
import '../../../data/models/models.dart';
import '../../auth/auth_provider.dart';
import '../../../core/widgets/mizdah_text_field.dart';
import '../../../data/repositories/mizdah_repository.dart';
import '../../../core/utils/meeting_utils.dart';
import '../../home/presentation/home_screen.dart';
import '../meeting_provider.dart';

class PreJoinScreen extends ConsumerStatefulWidget {
  final String? meetingId;
  const PreJoinScreen({super.key, this.meetingId});

  @override
  ConsumerState<PreJoinScreen> createState() => _PreJoinScreenState();
}

class _PreJoinScreenState extends ConsumerState<PreJoinScreen> {
  bool _isMicOn = true;
  bool _isCameraOn = true;
  bool _isPermissionLoading = true;
  bool _hasPermissions = true; // Default to true for UI development
  bool _isJoining = false;
  Meeting? _meeting;
  bool _isLoadingMeeting = true;
  final _nameController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    if (widget.meetingId != null) {
      _fetchMeetingInfo();
    } else {
      _isLoadingMeeting = false;
    }
    _checkPermissions();
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = ref.read(authProvider).user;
      if (user != null) {
        _nameController.text = user.name;
      }
    });
  }


  Future<void> _fetchMeetingInfo() async {
    try {
      final repo = ref.read(meetingRepositoryProvider);
      final meeting = await repo.getMeetingInfo(widget.meetingId!);
      if (mounted) {
        setState(() {
          _meeting = meeting;
          _isLoadingMeeting = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingMeeting = false);
      }
    }
  }

  Future<void> _checkPermissions() async {
    final status = await [Permission.camera, Permission.microphone].request();
    if (mounted) {
      setState(() {
        _hasPermissions = status[Permission.camera]!.isGranted && 
                         status[Permission.microphone]!.isGranted;
        _isPermissionLoading = false;
      });
      if (_hasPermissions) {
        _setupMedia();
      }
    }
  }

  Future<void> _setupMedia() async {
    // Always start the camera preview, including instant-meeting flow
    // (widget.meetingId == null). Without this the preview area renders
    // an empty black box because the renderer never gets a srcObject.
    ref.read(meetingProvider(widget.meetingId ?? '').notifier).prepareLocalPreview();
  }

  Future<void> _handleJoin() async {
    setState(() => _isJoining = true);
    
    String? finalMeetingId = widget.meetingId;

    try {
      // If we don't have a meeting ID yet, we are creating an instant meeting
      if (finalMeetingId == null) {
        final repository = ref.read(mizdahRepositoryProvider);
        final code = MeetingUtils.generateMeetingCode();
        final meeting = await repository.createMeeting(
          title: 'Instant Meeting',
          dateTime: DateTime.now(),
          code: code,
        );
        finalMeetingId = meeting.code;
        
        // Refresh data providers to show the new meeting in history
        ref.invalidate(callHistoryProvider);
        ref.invalidate(schedulesProvider);
      }

      if (!mounted) return;
      // Hand the already-running camera over to the in-meeting
      // provider via a static stage. We can't write into the new
      // provider directly — `ref.read(...notifier)` doesn't establish
      // a watcher, so its autoDispose can fire while we await and the
      // assignment then throws "Bad state: ... after dispose was called".
      final previewKey = widget.meetingId ?? '';
      final previewNotifier =
          ref.read(meetingProvider(previewKey).notifier);
      final liveStream = previewNotifier.releaseLocalStream();
      if (liveStream != null) {
        MeetingNotifier.stageLocalStream(liveStream);
      }

      context.pushReplacement(
        Uri(
          path: '/meeting/$finalMeetingId',
          queryParameters: {
            'video': _isCameraOn.toString(),
            'audio': _isMicOn.toString(),
          },
        ).toString(),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start meeting: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isJoining = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: isDark ? MizdahTheme.darkGradient : null,
          color: isDark ? null : MizdahTheme.lightBackground,
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    IconButton(icon: const Icon(Icons.close), onPressed: () => context.pop()),
                    Expanded(
                      child: Center(
                        child: Text(
                          (widget.meetingId == null || (_meeting?.hostId != null && _meeting?.hostId == ref.read(authProvider).user?.id)) 
                              ? 'Start Meeting' 
                              : 'Join Meeting',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(width: 48), // Spacer
                  ],
                ),
              ),

              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                  child: Column(
                    children: [
                      _CameraPreview(
                        renderer: ref.watch(meetingProvider(widget.meetingId ?? '')).localRenderer,
                        isCameraOn: _isCameraOn,
                        isMicOn: _isMicOn,
                        hasPermissions: _hasPermissions,
                        isLoading: _isPermissionLoading,
                        onMicToggle: () {
                          setState(() => _isMicOn = !_isMicOn);
                          if (widget.meetingId != null) {
                            ref.read(meetingProvider(widget.meetingId!).notifier).toggleMic();
                          }
                        },
                        onCameraToggle: () {
                          setState(() => _isCameraOn = !_isCameraOn);
                          if (widget.meetingId != null) {
                            ref.read(meetingProvider(widget.meetingId!).notifier).toggleCamera();
                          }
                        },
                      ),

                      const SizedBox(height: 24),

                      // Meeting Details Card
                      GlassCard(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          children: [
                            Text(
                              _meeting?.title ?? 'Mizdah Meeting',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                              textAlign: TextAlign.center,
                            ),
                            if (widget.meetingId != null) ...[
                              const SizedBox(height: 8),
                              SelectableText(
                                MeetingUtils.generateMeetingLink(widget.meetingId!),
                                style: const TextStyle(
                                  color: MizdahTheme.primaryBlue, 
                                  fontSize: 13, 
                                  fontWeight: FontWeight.w500,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                            const SizedBox(height: 16),
                            if (_isLoadingMeeting)
                              const CircularProgressIndicator()
                            else if (_meeting == null && widget.meetingId != null)
                              const Text(
                                'Meeting not found or has expired',
                                style: TextStyle(color: Colors.red),
                              )
                            else ...[
                              MizdahTextField(
                                controller: _nameController,
                                hintText: 'Your name',
                                prefixIcon: Icons.person_outline,
                                onChanged: (_) => setState(() {}),
                              ),
                            ],
                            const SizedBox(height: 12),
                            Text(
                              (widget.meetingId == null || (_meeting?.hostId != null && _meeting?.hostId == ref.read(authProvider).user?.id))
                                  ? 'Ready to start your meeting?'
                                  : 'Ready to join? Others are already here.',
                              style: const TextStyle(color: Colors.grey, fontSize: 13),
                            ),
                            const SizedBox(height: 24),
                            MizdahButton(
                              label: (widget.meetingId == null || (_meeting?.hostId != null && _meeting?.hostId == ref.read(authProvider).user?.id))
                                  ? 'Start Now'
                                  : 'Join Now',
                              onTap: (_isJoining || (widget.meetingId != null && _meeting == null) || _nameController.text.trim().isEmpty) ? null : _handleJoin,
                              isLoading: _isJoining,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
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
}

class _CameraPreview extends StatelessWidget {
  final RTCVideoRenderer renderer;
  final bool isCameraOn;
  final bool isMicOn;
  final bool hasPermissions;
  final bool isLoading;
  final VoidCallback onMicToggle;
  final VoidCallback onCameraToggle;

  const _CameraPreview({
    required this.renderer,
    required this.isCameraOn,
    required this.isMicOn,
    required this.hasPermissions,
    required this.isLoading,
    required this.onMicToggle,
    required this.onCameraToggle,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 9 / 12,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(32),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (isLoading)
                const Center(child: CircularProgressIndicator())
              else if (!hasPermissions)
                const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.no_photography_outlined, color: Colors.white24, size: 64),
                    SizedBox(height: 16),
                    Text('Permissions required', style: TextStyle(color: Colors.white54)),
                  ],
                )
              else if (!isCameraOn)
                const Center(
                  child: CircleAvatar(
                    radius: 40,
                    backgroundColor: Colors.white10,
                    child: Icon(Icons.person, color: Colors.white24, size: 40),
                  ),
                )
              else
                RTCVideoView(
                  renderer,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  mirror: true,
                ),
              
              // Media Controls (Bottom Right Overlay)
              Positioned(
                bottom: 20,
                right: 20,
                child: Row(
                  children: [
                    ControlIconButton(
                      icon: isMicOn ? Icons.mic_rounded : Icons.mic_off_rounded,
                      isActive: !isMicOn,
                      onTap: onMicToggle,
                      size: 48,
                    ),
                    const SizedBox(width: 12),
                    ControlIconButton(
                      icon: isCameraOn ? Icons.videocam_rounded : Icons.videocam_off_rounded,
                      isActive: !isCameraOn,
                      onTap: onCameraToggle,
                      size: 48,
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
}
