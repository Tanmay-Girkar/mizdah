import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/widgets/control_icon_button.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/theme/theme_provider.dart';
import '../../../core/widgets/mizdah_button.dart';

class MeetingRoomScreen extends StatefulWidget {
  final String meetingId;
  const MeetingRoomScreen({super.key, required this.meetingId});

  @override
  State<MeetingRoomScreen> createState() => _MeetingRoomScreenState();
}

class _MeetingRoomScreenState extends State<MeetingRoomScreen> {
  bool _isMicOn = true;
  bool _isCameraOn = true;
  bool _isRaisingHand = false;
  bool _isRecording = false;
  String? _activePanel; // 'chat', 'participants', 'host', 'breakout'

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Video Grid (Mocked)
          const _VideoGrid(),

          // Top Bar
          _MeetingTopBar(meetingId: widget.meetingId, isRecording: _isRecording),

          // Bottom Controls
          _InCallControls(
            isMicOn: _isMicOn,
            isCameraOn: _isCameraOn,
            isRaisingHand: _isRaisingHand,
            onMicToggle: () => setState(() => _isMicOn = !_isMicOn),
            onCameraToggle: () => setState(() => _isCameraOn = !_isCameraOn),
            onHangup: () => context.go('/'),
            onRaiseHand: () => setState(() => _isRaisingHand = !_isRaisingHand),
            onChatOpen: () => setState(() => _activePanel = 'chat'),
            onParticipantsOpen: () => setState(() => _activePanel = 'participants'),
            onHostOpen: () => setState(() => _activePanel = 'host'),
            onBreakoutOpen: () => setState(() => _activePanel = 'breakout'),
          ),

          // Sliding Panels
          if (_activePanel != null)
            _SlidingPanel(
              title: _getPanelTitle(),
              onClose: () => setState(() => _activePanel = null),
              child: _getPanelChild(),
            ),
        ],
      ),
    );
  }

  String _getPanelTitle() {
    switch (_activePanel) {
      case 'chat': return 'In-call messages';
      case 'participants': return 'Participants (5)';
      case 'host': return 'Host Controls';
      case 'breakout': return 'Breakout Rooms';
      default: return '';
    }
  }

  Widget _getPanelChild() {
    switch (_activePanel) {
      case 'chat': return const _ChatView();
      case 'participants': return const _ParticipantsView();
      case 'host': return _HostControlsView(
        isRecording: _isRecording,
        onRecordingToggle: (val) => val ? _showRecordingConsent() : setState(() => _isRecording = false),
      );
      case 'breakout': return const _BreakoutRoomsView();
      default: return const SizedBox.shrink();
    }
  }

  void _showRecordingConsent() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: MizdahTheme.darkBackgroundTop,
        surfaceTintColor: Colors.transparent,
        title: const Text('Record this meeting?', style: TextStyle(color: Colors.white)),
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
  const _VideoGrid();

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      childAspectRatio: 0.8,
      padding: EdgeInsets.zero,
      children: List.generate(
        4,
        (index) => Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white10),
            color: Colors.grey[900],
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.network(
                'https://i.pravatar.cc/300?u=$index',
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => const Icon(Icons.person, size: 60, color: Colors.white24),
              ),
              Positioned(
                bottom: 8,
                left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    index == 0 ? 'You' : 'Participant $index',
                    style: const TextStyle(color: Colors.white, fontSize: 10),
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

class _MeetingTopBar extends StatelessWidget {
  final String meetingId;
  final bool isRecording;
  const _MeetingTopBar({required this.meetingId, required this.isRecording});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        height: 100,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black87, Colors.transparent],
          ),
        ),
        padding: const EdgeInsets.fromLTRB(16, 40, 16, 0),
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  meetingId,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
                if (isRecording)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(4)),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.circle, color: Colors.white, size: 8),
                        SizedBox(width: 4),
                        Text('REC', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
              ],
            ),
            const Spacer(),
            IconButton(icon: const Icon(Icons.switch_camera, color: Colors.white), onPressed: () {}),
            IconButton(icon: const Icon(Icons.volume_up, color: Colors.white), onPressed: () {}),
          ],
        ),
      ),
    );
  }
}

class _InCallControls extends StatelessWidget {
  final bool isMicOn;
  final bool isCameraOn;
  final bool isRaisingHand;
  final VoidCallback onMicToggle;
  final VoidCallback onCameraToggle;
  final VoidCallback onHangup;
  final VoidCallback onRaiseHand;
  final VoidCallback onChatOpen;
  final VoidCallback onParticipantsOpen;
  final VoidCallback onHostOpen;
  final VoidCallback onBreakoutOpen;

  const _InCallControls({
    required this.isMicOn,
    required this.isCameraOn,
    required this.isRaisingHand,
    required this.onMicToggle,
    required this.onCameraToggle,
    required this.onHangup,
    required this.onRaiseHand,
    required this.onChatOpen,
    required this.onParticipantsOpen,
    required this.onHostOpen,
    required this.onBreakoutOpen,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 24,
      left: 16,
      right: 16,
      child: GlassCard(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        radius: 32,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            ControlIconButton(
              icon: isMicOn ? Icons.mic : Icons.mic_off,
              isActive: !isMicOn,
              onTap: onMicToggle,
              size: 44,
            ),
            ControlIconButton(
              icon: isCameraOn ? Icons.videocam : Icons.videocam_off,
              isActive: !isCameraOn,
              onTap: onCameraToggle,
              size: 44,
            ),
            ControlIconButton(
              icon: Icons.chat_bubble_outline, 
              onTap: onChatOpen,
              size: 40,
            ),
            ControlIconButton(
              icon: Icons.people_outline, 
              onTap: onParticipantsOpen,
              size: 40,
            ),
            ControlIconButton(
              icon: Icons.call_end,
              backgroundColor: Colors.red,
              onTap: onHangup,
              size: 52,
            ),
            ControlIconButton(
              icon: isRaisingHand ? Icons.pan_tool : Icons.pan_tool_outlined,
              isActive: isRaisingHand,
              activeColor: Colors.yellow[700]!,
              onTap: onRaiseHand,
              size: 40,
            ),
            ControlIconButton(
              icon: Icons.more_vert, 
              onTap: onHostOpen,
              size: 40,
            ),
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

  const _SlidingPanel({required this.title, required this.child, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: GestureDetector(
        onTap: onClose,
        child: Container(
          color: Colors.black54,
          alignment: Alignment.bottomCenter,
          child: GestureDetector(
            onTap: () {}, // Prevent tap propagation
            child: GlassCard(
              radius: 32,
              padding: EdgeInsets.zero,
              child: Container(
                height: MediaQuery.of(context).size.height * 0.7,
                width: double.infinity,
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                          IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: onClose),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: Colors.white10),
                    Expanded(child: child),
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
  const _ChatView();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: 5,
            itemBuilder: (context, index) => Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Row(
                children: [
                  const CircleAvatar(radius: 16, child: Icon(Icons.person, size: 16)),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('User Name', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white)),
                      const SizedBox(height: 4),
                      Text('Can everyone hear me clearly?', style: TextStyle(color: Colors.grey[400])),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 40),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Send a message...',
                    hintStyle: const TextStyle(color: Colors.grey),
                    filled: true,
                    fillColor: Colors.white10,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              CircleAvatar(
                backgroundColor: MizdahTheme.primaryBlue,
                child: IconButton(icon: const Icon(Icons.send, size: 20, color: Colors.white), onPressed: () {}),
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
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      itemCount: 5,
      itemBuilder: (context, index) => ListTile(
        leading: CircleAvatar(child: Text(index == 0 ? 'Y' : 'P')),
        title: Text(index == 0 ? 'You (Host)' : 'Participant $index', style: const TextStyle(color: Colors.white)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.mic, color: Colors.grey[600], size: 20),
            const SizedBox(width: 16),
            Icon(Icons.videocam, color: Colors.grey[600], size: 20),
          ],
        ),
      ),
    );
  }
}

class _HostControlsView extends StatefulWidget {
  final bool isRecording;
  final ValueChanged<bool> onRecordingToggle;

  const _HostControlsView({required this.isRecording, required this.onRecordingToggle});

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
        const Text('Meeting Security', style: TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        _ControlToggle(
          title: 'Lock Meeting',
          subtitle: 'Prevent new participants from joining',
          value: _lockMeeting,
          onChanged: (v) => setState(() => _lockMeeting = v),
        ),
        const SizedBox(height: 24),
        const Text('Participant Permissions', style: TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        _ControlToggle(title: 'Share Microphone', value: _allowMic, onChanged: (v) => setState(() => _allowMic = v)),
        _ControlToggle(title: 'Share Video', value: _allowCam, onChanged: (v) => setState(() => _allowCam = v)),
        _ControlToggle(title: 'Send Chat Messages', value: _allowChat, onChanged: (v) => setState(() => _allowChat = v)),
        const Divider(color: Colors.white10, height: 32),
        _ControlToggle(
          title: 'Record Meeting',
          subtitle: 'Store this session in the cloud',
          value: widget.isRecording,
          onChanged: widget.onRecordingToggle,
        ),
        const SizedBox(height: 32),
        MizdahButton(label: 'Mute All', backgroundColor: Colors.white10, onTap: () {}),
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

  const _ControlToggle({required this.title, this.subtitle, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
      subtitle: subtitle != null ? Text(subtitle!, style: const TextStyle(color: Colors.grey, fontSize: 12)) : null,
      trailing: Switch.adaptive(value: value, activeColor: MizdahTheme.primaryBlue, onChanged: onChanged),
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
              const Text('Assign participants to rooms', style: TextStyle(color: Colors.grey, fontSize: 13)),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Number of rooms', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                  Container(
                    decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(12)),
                    child: Row(
                      children: [
                        IconButton(onPressed: () => setState(() => _roomCount = (_roomCount > 1 ? _roomCount - 1 : 1)), icon: const Icon(Icons.remove, color: Colors.white)),
                        Text('$_roomCount', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                        IconButton(onPressed: () => setState(() => _roomCount++), icon: const Icon(Icons.add, color: Colors.white)),
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
              Text('Room ${index + 1}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
              const Text('0 participants', style: TextStyle(color: Colors.grey, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 12),
          MizdahButton(label: 'Assign', isFullWidth: false, backgroundColor: Colors.white10, onTap: () {}),
        ],
      ),
    );
  }
}
