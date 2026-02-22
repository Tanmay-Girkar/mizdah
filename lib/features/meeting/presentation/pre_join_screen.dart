import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/mizdah_button.dart';
import '../../../core/widgets/control_icon_button.dart';
import '../../../core/theme/theme_provider.dart';

class PreJoinScreen extends StatefulWidget {
  final String meetingId;
  const PreJoinScreen({super.key, required this.meetingId});

  @override
  State<PreJoinScreen> createState() => _PreJoinScreenState();
}

class _PreJoinScreenState extends State<PreJoinScreen> {
  bool _isMicOn = true;
  bool _isCameraOn = true;
  bool _isPermissionLoading = true;
  bool _hasPermissions = false;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    final status = await [Permission.camera, Permission.microphone].request();
    if (mounted) {
      setState(() {
        _hasPermissions = status[Permission.camera]!.isGranted && 
                         status[Permission.microphone]!.isGranted;
        _isPermissionLoading = false;
      });
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
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Camera Preview Placeholder
                      _CameraPreview(
                        isCameraOn: _isCameraOn,
                        hasPermissions: _hasPermissions,
                        isLoading: _isPermissionLoading,
                      ),
                      
                      const SizedBox(height: 32),

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
                            onTap: () => setState(() => _isCameraOn = !_isCameraOn),
                          ),
                        ],
                      ),

                      const SizedBox(height: 48),

                      // Meeting Details Card
                      GlassCard(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          children: [
                            Text(
                              'Meeting ID: ${widget.meetingId}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            const SizedBox(height: 8),
                            const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.circle, size: 8, color: Colors.green),
                                SizedBox(width: 8),
                                Text(
                                  '3 people are waiting in the lobby',
                                  style: TextStyle(color: Colors.green, fontSize: 13, fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Ready to join? Others are already here.',
                              style: TextStyle(color: Colors.grey, fontSize: 13),
                            ),
                            const SizedBox(height: 32),
                            MizdahButton(
                              label: 'Join Now',
                              onTap: _isPermissionLoading ? null : () {
                                if (_hasPermissions) {
                                  context.pushReplacement('/meeting/${widget.meetingId}');
                                } else {
                                  _checkPermissions();
                                }
                              },
                              isLoading: _isPermissionLoading,
                            ),
                          ],
                        ),
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
}

class _CameraPreview extends StatelessWidget {
  final bool isCameraOn;
  final bool hasPermissions;
  final bool isLoading;

  const _CameraPreview({
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
          border: Border.all(color: Colors.white.withOpacity(0.1)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
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
                Image.network(
                  'https://images.unsplash.com/photo-1544005313-94ddf0286df2?w=400&h=600&fit=crop',
                  fit: BoxFit.cover,
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
