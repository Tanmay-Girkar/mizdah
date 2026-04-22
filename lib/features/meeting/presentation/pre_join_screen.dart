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

class PreJoinScreen extends ConsumerStatefulWidget {
  final String meetingId;
  const PreJoinScreen({super.key, required this.meetingId});

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
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  MediaStream? _localStream;

  @override
  void dispose() {
    _localRenderer.dispose();
    _localStream?.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _fetchMeetingInfo();
    _checkPermissions();
    _initRenderer();
  }

  Future<void> _initRenderer() async {
    await _localRenderer.initialize();
  }

  Future<void> _fetchMeetingInfo() async {
    try {
      final repo = ref.read(meetingRepositoryProvider);
      final meeting = await repo.getMeetingInfo(widget.meetingId);
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
    try {
      final stream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': {
          'facingMode': 'user',
          'width': 1280,
          'height': 720,
        },
      });
      _localStream = stream;
      if (mounted) {
        setState(() {
          _localRenderer.srcObject = _localStream;
        });
      }
    } catch (e) {
      debugPrint("Error setting up media: $e");
    }
  }

  Future<void> _handleJoin() async {
    setState(() => _isJoining = true);
    // Simulating delay
    await Future.delayed(const Duration(milliseconds: 500));
    
    if (mounted) {
      context.pushReplacement(
        Uri(
          path: '/meeting/${widget.meetingId}',
          queryParameters: {
            'video': _isCameraOn.toString(),
            'audio': _isMicOn.toString(),
          },
        ).toString(),
      );
      setState(() => _isJoining = false);
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
                    const Expanded(
                      child: Center(
                        child: Text(
                          'Join Meeting',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
                      // Camera Preview Placeholder
                      _CameraPreview(
                        renderer: _localRenderer,
                        isCameraOn: _isCameraOn,
                        hasPermissions: _hasPermissions,
                        isLoading: _isPermissionLoading,
                      ),
                      
                      const SizedBox(height: 24),

                      // Media Controls
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ControlIconButton(
                            icon: _isMicOn ? Icons.mic_rounded : Icons.mic_off_rounded,
                            isActive: !_isMicOn,
                            onTap: () => setState(() => _isMicOn = !_isMicOn),
                          ),
                          const SizedBox(width: 24),
                          ControlIconButton(
                            icon: _isCameraOn ? Icons.videocam_rounded : Icons.videocam_off_rounded,
                            isActive: !_isCameraOn,
                            onTap: () {
                              setState(() => _isCameraOn = !_isCameraOn);
                              _localStream?.getVideoTracks().forEach((track) {
                                track.enabled = _isCameraOn;
                              });
                            },
                          ),
                        ],
                      ),

                      const SizedBox(height: 24),

                      // Meeting Details Card
                      GlassCard(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          children: [
                            Text(
                              _meeting?.title ?? 'Meeting ID: ${widget.meetingId.replaceAll('-', '')}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                              textAlign: TextAlign.center,
                            ),
                            if (_meeting?.code != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                _meeting!.code,
                                style: const TextStyle(color: Colors.grey, fontSize: 14),
                              ),
                            ],
                            const SizedBox(height: 16),
                            if (_isLoadingMeeting)
                              const CircularProgressIndicator()
                            else if (_meeting == null)
                              const Text(
                                'Meeting not found or has expired',
                                style: TextStyle(color: Colors.red),
                              )
                            else ...[
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.circle, size: 8, color: Colors.green),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${_meeting?.participants.length ?? 0} people in this meeting',
                                    style: const TextStyle(color: Colors.green, fontSize: 13, fontWeight: FontWeight.w500),
                                  ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 12),
                            const Text(
                              'Ready to join? Others are already here.',
                              style: TextStyle(color: Colors.grey, fontSize: 13),
                            ),
                            const SizedBox(height: 24),
                            MizdahButton(
                              label: 'Join Now',
                              onTap: (_isJoining || _meeting == null) ? null : _handleJoin,
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
  final bool hasPermissions;
  final bool isLoading;

  const _CameraPreview({
    required this.renderer,
    required this.isCameraOn,
    required this.hasPermissions,
    required this.isLoading,
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
              
              // Bottom Indicator
              Positioned(
                bottom: 20,
                left: 20,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.mic_rounded, color: Colors.white, size: 14),
                      SizedBox(width: 8),
                      Text('Your Mic is ON', style: TextStyle(color: Colors.white, fontSize: 10)),
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
