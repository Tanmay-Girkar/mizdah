import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'dart:ui';

class MeetingRoomScreen extends StatefulWidget {
  final String meetingId;
  const MeetingRoomScreen({super.key, required this.meetingId});

  @override
  State<MeetingRoomScreen> createState() => _MeetingRoomScreenState();
}

class _MeetingRoomScreenState extends State<MeetingRoomScreen> {
  bool _isMuted = false;
  bool _isCameraOff = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Video Grid (Mocked)
          GridView.count(
            crossAxisCount: 2,
            padding: const EdgeInsets.fromLTRB(8, 60, 8, 100),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            children: List.generate(4, (index) => _VideoTile(index: index)),
          ),
          // Top Bar
          Positioned(
            top: 40,
            left: 16,
            right: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Meeting ID: ${widget.meetingId}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.flip_camera_ios, color: Colors.white),
                  onPressed: () {},
                ),
              ],
            ),
          ),
          // Bottom Controls
          Positioned(
            bottom: 32,
            left: 0,
            right: 0,
            child: Center(
              child: _ControlBar(
                isMuted: _isMuted,
                isCameraOff: _isCameraOff,
                onMuteToggle: () => setState(() => _isMuted = !_isMuted),
                onCameraToggle: () =>
                    setState(() => _isCameraOff = !_isCameraOff),
                onHangup: () => context.go('/'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VideoTile extends StatelessWidget {
  final int index;
  const _VideoTile({required this.index});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Stack(
        children: [
          Center(
            child: CircleAvatar(
              radius: 30,
              backgroundColor: Colors.blueGrey,
              child: Text(
                'User ${index + 1}',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ),
          Positioned(
            bottom: 8,
            left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                index == 0 ? 'You' : 'Participant ${index + 1}',
                style: const TextStyle(color: Colors.white, fontSize: 10),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ControlBar extends StatelessWidget {
  final bool isMuted;
  final bool isCameraOff;
  final VoidCallback onMuteToggle;
  final VoidCallback onCameraToggle;
  final VoidCallback onHangup;

  const _ControlBar({
    required this.isMuted,
    required this.isCameraOff,
    required this.onMuteToggle,
    required this.onCameraToggle,
    required this.onHangup,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(32),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: Colors.white.withOpacity(0.2)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ControlIcon(
                icon: isMuted ? Icons.mic_off : Icons.mic,
                color: isMuted ? Colors.red : Colors.white,
                onTap: onMuteToggle,
              ),
              const SizedBox(width: 20),
              _ControlIcon(
                icon: isCameraOff ? Icons.videocam_off : Icons.videocam,
                color: isCameraOff ? Colors.red : Colors.white,
                onTap: onCameraToggle,
              ),
              const SizedBox(width: 20),
              _ControlIcon(
                icon: Icons.back_hand_outlined,
                color: Colors.white,
                onTap: () {},
              ),
              const SizedBox(width: 20),
              _ControlIcon(
                icon: Icons.call_end,
                color: Colors.red,
                size: 32,
                onTap: onHangup,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ControlIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final double size;

  const _ControlIcon({
    required this.icon,
    required this.color,
    required this.onTap,
    this.size = 24,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Icon(icon, color: color, size: size),
    );
  }
}
