import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import '../../settings/meeting_layout_provider.dart';
import 'widgets/present_source_picker.dart';
import 'widgets/remote_control_dialog.dart';
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

    // When the host hangs up the backend broadcasts end-meeting-for-all
    // to every participant; the notifier flips phase -> ended. Watch
    // for that transition and bounce back to the home screen with a
    // snackbar so the user understands why the call closed.
    ref.listen<MeetingPhase>(
      meetingProvider(widget.meetingId).select((s) => s.phase),
      (prev, next) {
        if (next == MeetingPhase.ended && prev != MeetingPhase.ended) {
          if (!context.mounted) return;
          if (!meetingState.isHost) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Meeting ended by host')),
            );
          }
          context.go('/');
        }
      },
    );

    // Inbound remote-control request — pop the grant/deny dialog
    // the moment notifier state has it, regardless of which panel
    // is currently open.
    ref.listen<Map<String, dynamic>?>(
      meetingProvider(widget.meetingId).select((s) => s.incomingControlRequest),
      (prev, next) async {
        if (next == null || prev == next) return;
        if (!context.mounted) return;
        final granted = await RemoteControlRequestDialog.show(
          context,
          requesterName: (next['name'] ?? 'A participant').toString(),
        );
        meetingNotifier.respondRemoteControl(granted: granted == true);
      },
    );

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
              // Main body — single layout, cross-faded internally so
              // we never tear down and rebuild the surrounding chrome
              // when a peer joins or their video starts arriving.
              Positioned.fill(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 280),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) =>
                      FadeTransition(opacity: animation, child: child),
                  layoutBuilder: (current, previous) => Stack(
                    alignment: Alignment.center,
                    children: <Widget>[
                      ...previous,
                      if (current != null) current,
                    ],
                  ),
                  child: (meetingState.remoteRenderers.isNotEmpty ||
                          _hasOtherParticipants(meetingState) ||
                          meetingState.mockParticipantCount > 0)
                      ? KeyedSubtree(
                          key: const ValueKey('grid'),
                          child: _VideoGrid(meetingState: meetingState),
                        )
                      : KeyedSubtree(
                          key: const ValueKey('solitary'),
                          child: _SolitaryHeroView(meetingId: widget.meetingId),
                        ),
                ),
              ),

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
              Positioned(
                bottom: 140, // above controls
                left: 16,
                right: 16,
                child: CaptionsView(meetingId: widget.meetingId),
              ),

              // PIP for Self — always visible above the controls so the
              // host can see themselves whether alone OR with remote
              // participants in the grid (matches Google Meet behaviour).
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
                    // Host hanging up = meeting ends for everyone.
                    // Non-hosts just leave their own seat in the room.
                    if (meetingState.isHost) {
                      meetingNotifier.endMeetingForAll();
                    } else {
                      meetingNotifier.leaveMeeting();
                    }
                    context.go('/');
                  },
                  onOptionsTap: () => _showOptionsBottomSheet(context),
                  onReactions: () => _showReactionsPicker(context),
                  hasWaitingParticipants: meetingState.waitingParticipants.isNotEmpty,
                ),
              ),

              // Floating reactions overlay (above grid, below controls).
              if (meetingState.reactions.isNotEmpty)
                Positioned.fill(
                  child: IgnorePointer(
                    child: _ReactionsOverlay(reactions: meetingState.reactions),
                  ),
                ),

              // "You are presenting" banner — Google-Meet style, only
              // when the local user has screen share active.
              if (meetingState.isScreenSharing)
                Positioned(
                  top: 80,
                  left: 16,
                  right: 16,
                  child: _PresentingBanner(
                    onStop: () => meetingNotifier.toggleScreenShare(),
                  ),
                ),

              // Active remote-control banner — visible when someone
              // ELSE is currently controlling our screen (we granted),
              // OR when we've been granted control of someone else.
              if (meetingState.controllingPeerSocketId != null ||
                  meetingState.controlOfPeerSocketId != null)
                Positioned(
                  top: meetingState.isScreenSharing ? 132 : 80,
                  left: 16,
                  right: 16,
                  child: _RemoteControlActiveBanner(
                    isHostBeingControlled:
                        meetingState.controllingPeerSocketId != null,
                    onRevoke: () => meetingNotifier.revokeRemoteControl(),
                  ),
                ),

              // Incoming-message toast — anchored to the TOP-RIGHT
              // corner so it doesn't sit on top of the controls and
              // is visible without overlapping the self-PIP. Slides
              // in from above and fades.
              Positioned(
                top: 70,
                right: 12,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeIn,
                    transitionBuilder: (child, anim) => SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0.4, -0.15),
                        end: Offset.zero,
                      ).animate(anim),
                      child: FadeTransition(opacity: anim, child: child),
                    ),
                    child: meetingState.incomingChatToast == null
                        ? const SizedBox.shrink(key: ValueKey('chat-toast-empty'))
                        : _ChatToast(
                            key: ValueKey(meetingState.incomingChatToast!['at']),
                            sender: (meetingState.incomingChatToast!['sender'] ?? '').toString(),
                            text: (meetingState.incomingChatToast!['text'] ?? '').toString(),
                            onTap: () => setState(() => _activePanel = 'chat'),
                          ),
                  ),
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

  String? _activePanel;

  /// True iff the participants list contains anyone other than us.
  /// Used at the body-switcher to avoid showing the grid for a
  /// list that's just `[self]` (which would empty out a moment later
  /// when join-confirmation lands and cause a flicker).
  bool _hasOtherParticipants(MeetingState s) {
    for (final p in s.participants) {
      if (p is! Map) continue;
      final pid = (p['userId'] ?? p['user_id'])?.toString();
      // Skip self by user-id. We don't compare socketId to userId
      // (those are different namespaces, the comparison is always
      // false and would mark every entry as "other").
      if (pid != null && pid == s.userId) continue;
      return true;
    }
    return false;
  }

  void _showReactionsPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _ReactionsPickerSheet(
        onPick: (emoji) {
          Navigator.pop(sheetContext);
          ref.read(meetingProvider(widget.meetingId).notifier).sendReaction(emoji);
        },
      ),
    );
  }

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
        onToggleScreenShare: () async {
          Navigator.pop(context);
          final notifier =
              ref.read(meetingProvider(widget.meetingId).notifier);
          // If we're already sharing, the same control stops sharing
          // immediately — no picker needed.
          final isSharing =
              ref.read(meetingProvider(widget.meetingId)).isScreenSharing;
          if (isSharing) {
            notifier.toggleScreenShare();
            return;
          }
          // Show the Chrome-style picker dialog. The actual capture
          // (which on mobile triggers the OS native picker) only
          // fires once the user taps Share in the dialog.
          if (!context.mounted) return;
          final source = await PresentSourcePicker.show(
            context,
            origin: 'mizdah-front.ogoul.cloud',
          );
          if (source == null) return;
          notifier.toggleScreenShare();
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
        return WhiteboardView(meetingId: widget.meetingId);
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

class _VideoGrid extends ConsumerWidget {
  final MeetingState meetingState;
  const _VideoGrid({required this.meetingState});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Build one tile per known participant. If we have a live renderer
    // for that participant's socketId we show their video, otherwise an
    // avatar tile with their name.
    final tiles = <_ParticipantTileData>[];
    for (final p in meetingState.participants) {
      if (p is! Map) continue;
      final pUserId = (p['userId'] ?? p['user_id'])?.toString();
      if (pUserId != null && pUserId == meetingState.userId) continue;
      final socketId = (p['socketId'] ?? p['userId'])?.toString();
      if (socketId != null && socketId == meetingState.userId) continue;
      final name = (p['name'] ?? p['displayName'] ?? 'Participant').toString();
      final renderer = socketId != null ? meetingState.remoteRenderers[socketId] : null;
      final videoEnabled = p['videoEnabled'] != false;
      final audioEnabled = p['audioEnabled'] != false;
      final isPresenting = p['isSharing'] == true;
      tiles.add(_ParticipantTileData(
        name: name,
        renderer: renderer,
        videoEnabled: videoEnabled,
        audioEnabled: audioEnabled,
        isPresenting: isPresenting,
        socketId: socketId,
        meetingId: meetingState.meetingCode ?? meetingState.meetingId,
      ));
    }
    for (final entry in meetingState.remoteRenderers.entries) {
      final already = tiles.any((t) => t.renderer == entry.value);
      if (!already) {
        tiles.add(_ParticipantTileData(name: 'Participant', renderer: entry.value));
      }
    }
    // While the local user is presenting, show a STATIC placeholder
    // tile — never the live screen renderer. Rendering the screen
    // capture inside the same screen creates infinite mirror
    // recursion (the screenshot the user sent shows ~20 nested
    // 'You — Presentation' tiles cascading off the edge).
    if (meetingState.isScreenSharing) {
      tiles.insert(
        0,
        const _ParticipantTileData(
          name: 'You · Presenting',
          videoEnabled: false,
          isPresentingPlaceholder: true,
        ),
      );
    }
    if (tiles.isEmpty && meetingState.mockParticipantCount > 0) {
      return GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 80, 16, 120),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 0.75,
        ),
        itemCount: meetingState.mockParticipantCount,
        itemBuilder: (context, index) => _MockParticipantTile(index: index),
      );
    }

    final layout = ref.watch(meetingLayoutProvider);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      transitionBuilder: (child, anim) =>
          FadeTransition(opacity: anim, child: child),
      child: KeyedSubtree(
        key: ValueKey(layout),
        child: switch (layout) {
          MeetingLayout.spotlight      => _SpotlightStripGrid(tiles: tiles),
          MeetingLayout.equalGrid      => _EqualGridGrid(tiles: tiles),
          MeetingLayout.speakerSidebar => _SpeakerSidebarGrid(tiles: tiles),
          MeetingLayout.premiumCards   => _PremiumCardsGrid(tiles: tiles),
        },
      ),
    );
  }
}

class _EqualGridGrid extends StatelessWidget {
  final List<_ParticipantTileData> tiles;
  const _EqualGridGrid({required this.tiles});

  @override
  Widget build(BuildContext context) {
    final n = tiles.length;
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 80, 16, 120),
      physics: const BouncingScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: n <= 1 ? 1 : 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: n <= 1 ? 0.6 : 0.8,
      ),
      itemCount: n,
      itemBuilder: (_, i) => _RemoteParticipantTile(data: tiles[i]),
    );
  }
}

class _SpotlightStripGrid extends StatelessWidget {
  final List<_ParticipantTileData> tiles;
  const _SpotlightStripGrid({required this.tiles});

  @override
  Widget build(BuildContext context) {
    final speaker = tiles.first;
    final others = tiles.skip(1).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 80, 12, 120),
      child: Column(
        children: [
          Expanded(child: _RemoteParticipantTile(data: speaker)),
          if (others.isNotEmpty) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 80,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: others.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) => SizedBox(
                  width: 110,
                  child: _RemoteParticipantTile(data: others[i]),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SpeakerSidebarGrid extends StatelessWidget {
  final List<_ParticipantTileData> tiles;
  const _SpeakerSidebarGrid({required this.tiles});

  @override
  Widget build(BuildContext context) {
    final speaker = tiles.first;
    final others = tiles.skip(1).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 80, 12, 120),
      child: Row(
        children: [
          Expanded(child: _RemoteParticipantTile(data: speaker)),
          if (others.isNotEmpty) ...[
            const SizedBox(width: 10),
            SizedBox(
              width: 110,
              child: ListView.separated(
                itemCount: others.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) => AspectRatio(
                  aspectRatio: 0.75,
                  child: _RemoteParticipantTile(data: others[i]),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PremiumCardsGrid extends StatelessWidget {
  final List<_ParticipantTileData> tiles;
  const _PremiumCardsGrid({required this.tiles});

  @override
  Widget build(BuildContext context) {
    final n = tiles.length;
    final cols = n <= 2 ? 1 : 2;
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 80, 16, 120),
      physics: const BouncingScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        childAspectRatio: cols == 1 ? 0.7 : 0.85,
      ),
      itemCount: n,
      itemBuilder: (_, i) => _PremiumParticipantTile(data: tiles[i]),
    );
  }
}

/// Premium-style tile — gradient background, soft shadow, glowing
/// border around the active speaker. Wraps the same content as the
/// regular tile so the avatar/video crossfade still applies.
class _PremiumParticipantTile extends StatelessWidget {
  final _ParticipantTileData data;
  const _PremiumParticipantTile({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF2A2D33), Color(0xFF1F232B)],
            ),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.06),
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: _RemoteParticipantTile(data: data),
        ),
      ),
    );
  }
}

class _ParticipantTileData {
  final String name;
  final RTCVideoRenderer? renderer;
  final bool videoEnabled;
  final bool audioEnabled;
  /// Tells the tile to render the "you are presenting" badge
  /// instead of an avatar — used for the local screen-share slot
  /// (we never render the live screen renderer locally to avoid
  /// the infinite-mirror recursion).
  final bool isPresentingPlaceholder;
  /// True if this participant is currently presenting their screen
  /// (their `isSharing` flag from media-toggle is true). Used by
  /// the tile to surface a "Request control" button overlay.
  final bool isPresenting;
  /// SocketId of the participant — passed to the requestRemoteControl
  /// callback so we know who to send the request to.
  final String? socketId;
  /// Routing key for the meetingProvider so the tile can fire
  /// notifier methods (e.g. requestRemoteControl).
  final String? meetingId;
  const _ParticipantTileData({
    required this.name,
    this.renderer,
    this.videoEnabled = true,
    this.audioEnabled = true,
    this.isPresentingPlaceholder = false,
    this.isPresenting = false,
    this.socketId,
    this.meetingId,
  });
}

class _RemoteParticipantTile extends ConsumerWidget {
  final _ParticipantTileData data;
  const _RemoteParticipantTile({required this.data});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final renderer = data.renderer;
    // Show video only if the peer has video enabled AND we have a
    // renderer with a stream attached. Otherwise fall back to avatar
    // (prevents the "frozen last frame" the user reported when a peer
    // turns off their camera mid-call).
    final hasVideo = data.videoEnabled &&
        renderer != null &&
        (renderer.srcObject?.getVideoTracks().isNotEmpty ?? false);

    // Single Stack layout for the tile — the avatar/video crossfade
    // happens inside an AnimatedSwitcher. The label / mute badge are
    // kept in the same Positioned slot regardless of state, so they
    // never re-layout when the swap happens.
    final Widget inner;
    if (data.isPresentingPlaceholder) {
      inner = const KeyedSubtree(
        key: ValueKey('presenting-placeholder'),
        child: _PresentingPlaceholder(),
      );
    } else if (hasVideo) {
      inner = RepaintBoundary(
        key: ValueKey('video-${identityHashCode(renderer)}'),
        child: RTCVideoView(
          renderer,
          objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
        ),
      );
    } else {
      inner = KeyedSubtree(
        key: ValueKey('avatar-${data.name}'),
        child: _AvatarPlaceholder(name: data.name, size: 72),
      );
    }

    // If this remote participant is currently presenting their
    // screen, surface a "Request control" button in the corner.
    // Tapping it asks them via socket; their client pops the
    // grant/deny dialog. Hide it for the local presenting placeholder
    // (you don't request control of your own screen).
    final canRequestControl = data.isPresenting &&
        !data.isPresentingPlaceholder &&
        data.socketId != null &&
        data.meetingId != null;

    String? alreadyControllingId;
    if (canRequestControl) {
      // Cheap watch — only touches state.controlOfPeerSocketId so
      // re-runs only when control state changes.
      alreadyControllingId = ref.watch(
        meetingProvider(data.meetingId!)
            .select((s) => s.controlOfPeerSocketId),
      );
    }
    final iAmControlling = alreadyControllingId == data.socketId;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        color: const Color(0xFF3C4043),
        child: Stack(
          fit: StackFit.expand,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) =>
                  FadeTransition(opacity: animation, child: child),
              child: inner,
            ),
            // Bottom-left name + mute badge
            Positioned(
              left: 8,
              bottom: 8,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      data.name,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                  if (!data.audioEnabled) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.85),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.mic_off,
                          color: Colors.white, size: 12),
                    ),
                  ],
                ],
              ),
            ),
            // Top-right Request-control / Stop-controlling pill —
            // only visible while the participant is presenting.
            if (canRequestControl)
              Positioned(
                right: 8,
                top: 8,
                child: _RequestControlPill(
                  active: iAmControlling,
                  onTap: () {
                    final notifier = ref.read(
                      meetingProvider(data.meetingId!).notifier,
                    );
                    if (iAmControlling) {
                      notifier.revokeRemoteControl();
                    } else {
                      notifier.requestRemoteControl(data.socketId!);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Control request sent to ${data.name}'),
                          behavior: SnackBarBehavior.floating,
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RequestControlPill extends StatelessWidget {
  final bool active;
  final VoidCallback onTap;
  const _RequestControlPill({required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = active ? Colors.red : const Color(0xFF1A73E8);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                active
                    ? Icons.stop_circle_outlined
                    : Icons.near_me_rounded,
                color: Colors.white,
                size: 14,
              ),
              const SizedBox(width: 4),
              Text(
                active ? 'Stop control' : 'Request control',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
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
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          transitionBuilder: (child, animation) =>
              FadeTransition(opacity: animation, child: child),
          child: isCameraOn
              ? RepaintBoundary(
                  key: const ValueKey('self-video'),
                  child: RTCVideoView(
                    renderer,
                    mirror: true,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  ),
                )
              : const KeyedSubtree(
                  key: ValueKey('self-avatar'),
                  child: _AvatarPlaceholder(name: 'You', size: 56),
                ),
        ),
      ),
    );
  }
}

/// Static "you are presenting" tile shown to the host while they
/// share their screen. We deliberately do NOT render the live
/// screen renderer here — displaying a live screen-capture stream
/// inside the same screen creates infinite recursive nesting (the
/// camera captures the display capturing the display capturing…).
class _PresentingPlaceholder extends StatelessWidget {
  const _PresentingPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A73E8), Color(0xFF0B47A1)],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60,
              height: 60,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.cast_connected_rounded,
                color: Colors.white,
                size: 28,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              "You're presenting",
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Others can see your screen',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.75),
                fontSize: 11,
              ),
            ),
          ],
        ),
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
          // Layout switcher — opens a small popup menu listing the
          // 4 layouts. Selecting one persists via meetingLayoutProvider
          // so the choice is remembered for next time too.
          const _LayoutSwitcherButton(),
          const SizedBox(width: 8),
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
  final VoidCallback onReactions;
  final bool hasWaitingParticipants;

  const _InCallControls({
    required this.isMicOn,
    required this.isCameraOn,
    required this.onMicToggle,
    required this.onCameraToggle,
    required this.onHangup,
    required this.onOptionsTap,
    required this.onReactions,
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
              onTap: onReactions,
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
  final FocusNode _inputFocus = FocusNode();
  bool _emojiPanelOpen = false;

  void _toggleEmojiPanel() {
    setState(() => _emojiPanelOpen = !_emojiPanelOpen);
    if (_emojiPanelOpen) {
      _inputFocus.unfocus();
    } else {
      _inputFocus.requestFocus();
    }
  }

  void _onEmojiSelected(Category? _, Emoji emoji) {
    final ctrl = _textController;
    final selection = ctrl.selection;
    final text = ctrl.text;
    final start = selection.start < 0 ? text.length : selection.start;
    final end = selection.end < 0 ? text.length : selection.end;
    final newText = text.replaceRange(start, end, emoji.emoji);
    ctrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + emoji.emoji.length),
    );
  }

  void _onBackspace() {
    final ctrl = _textController;
    final text = ctrl.text;
    if (text.isEmpty) return;
    final selection = ctrl.selection;
    if (selection.start <= 0 || selection.start != selection.end) {
      // Use default delete behavior for ranges.
      return;
    }
    // Delete one user-perceived character (handles surrogate pairs).
    final runes = text.runes.toList();
    int byteIdx = 0;
    int runeIdx = 0;
    while (runeIdx < runes.length) {
      final char = String.fromCharCode(runes[runeIdx]);
      if (byteIdx + char.length >= selection.start) break;
      byteIdx += char.length;
      runeIdx++;
    }
    if (runeIdx >= runes.length) return;
    final removed = String.fromCharCode(runes[runeIdx]);
    final newText = text.replaceRange(byteIdx, byteIdx + removed.length, '');
    ctrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: byteIdx),
    );
  }

  void _send() {
    if (_textController.text.trim().isEmpty) return;
    widget.onSend(_textController.text);
    _textController.clear();
  }

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
    _inputFocus.dispose();
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
              final senderRaw = (msg['sender'] ?? '').toString();
              final isMe = senderRaw == 'You' ||
                  (currentUser?.name != null &&
                      senderRaw.trim().toLowerCase() ==
                          currentUser!.name.trim().toLowerCase());

              DateTime parsedTime;
              try {
                parsedTime = msg['time'] != null
                    ? DateTime.parse(msg['time'].toString())
                    : DateTime.now();
              } catch (_) {
                parsedTime = DateTime.now();
              }
              final timeStr = DateFormat('h:mm a').format(parsedTime);
              
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
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withValues(alpha: 0.02) : Colors.white,
            border: Border(top: BorderSide(color: isDark ? Colors.white10 : Colors.black12)),
          ),
          child: Row(
            children: [
              // Left-side emoji toggle.
              IconButton(
                onPressed: _toggleEmojiPanel,
                splashRadius: 22,
                tooltip: _emojiPanelOpen ? 'Show keyboard' : 'Insert emoji',
                icon: Icon(
                  _emojiPanelOpen
                      ? Icons.keyboard_alt_outlined
                      : Icons.emoji_emotions_outlined,
                  color: _emojiPanelOpen
                      ? MizdahTheme.primaryBlue
                      : (isDark ? Colors.white70 : Colors.black54),
                  size: 24,
                ),
              ),
              Expanded(
                child: TextField(
                  controller: _textController,
                  focusNode: _inputFocus,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  onTap: () {
                    if (_emojiPanelOpen) {
                      setState(() => _emojiPanelOpen = false);
                    }
                  },
                  style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                  decoration: InputDecoration(
                    hintText: 'Send a message...',
                    hintStyle: TextStyle(color: Colors.grey.withValues(alpha: 0.6)),
                    filled: true,
                    fillColor: isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : const Color(0xFFF0F2F5),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _send,
                child: Container(
                  height: 44,
                  width: 44,
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

        // Slide-up emoji picker panel. Shown only when toggled so it
        // doesn't steal screen real estate by default.
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          child: SizedBox(
            height: _emojiPanelOpen ? 300 : 0,
            child: _emojiPanelOpen
                ? EmojiPicker(
                    textEditingController: _textController,
                    onEmojiSelected: _onEmojiSelected,
                    onBackspacePressed: _onBackspace,
                    config: Config(
                      height: 300,
                      checkPlatformCompatibility: true,
                      emojiViewConfig: EmojiViewConfig(
                        backgroundColor: isDark
                            ? const Color(0xFF1A1A1A)
                            : const Color(0xFFF7F8FA),
                        columns: 8,
                        emojiSizeMax: 26,
                      ),
                      categoryViewConfig: CategoryViewConfig(
                        backgroundColor: isDark
                            ? const Color(0xFF1A1A1A)
                            : const Color(0xFFF7F8FA),
                        iconColor: isDark ? Colors.white38 : Colors.black38,
                        iconColorSelected: MizdahTheme.primaryBlue,
                        indicatorColor: MizdahTheme.primaryBlue,
                      ),
                      bottomActionBarConfig: BottomActionBarConfig(
                        backgroundColor: isDark
                            ? const Color(0xFF1A1A1A)
                            : const Color(0xFFF7F8FA),
                        buttonColor: MizdahTheme.primaryBlue,
                        buttonIconColor: Colors.white,
                      ),
                      searchViewConfig: SearchViewConfig(
                        backgroundColor: isDark
                            ? const Color(0xFF1A1A1A)
                            : const Color(0xFFF7F8FA),
                      ),
                    ),
                  )
                : null,
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

// ---------------------------------------------------------------------------
// Remote-control active banner — visible while a control session is open
// ---------------------------------------------------------------------------

class _RemoteControlActiveBanner extends StatelessWidget {
  final bool isHostBeingControlled;
  final VoidCallback onRevoke;
  const _RemoteControlActiveBanner({
    required this.isHostBeingControlled,
    required this.onRevoke,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF8E24AA).withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.near_me_rounded,
                color: Colors.white, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isHostBeingControlled
                  ? 'Someone is controlling your screen'
                  : 'You are controlling a remote screen',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: onRevoke,
            style: TextButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF8E24AA),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              isHostBeingControlled ? 'Revoke' : 'Stop',
              style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Presenting banner — appears when local user is sharing their screen
// ---------------------------------------------------------------------------

class _PresentingBanner extends StatelessWidget {
  final VoidCallback onStop;
  const _PresentingBanner({required this.onStop});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1A73E8).withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.present_to_all_rounded,
                color: Colors.white, size: 16),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'You are presenting',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: onStop,
            style: TextButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF1A73E8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              minimumSize: Size.zero,
            ),
            child: const Text(
              'Stop',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Chat toast — surfaces the latest incoming message over the video grid
// ---------------------------------------------------------------------------

class _ChatToast extends StatelessWidget {
  final String sender;
  final String text;
  final VoidCallback onTap;
  const _ChatToast({
    super.key,
    required this.sender,
    required this.text,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.78),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: MizdahTheme.primaryBlue.withValues(alpha: 0.18),
                child: Text(
                  sender.isNotEmpty ? sender[0].toUpperCase() : '?',
                  style: const TextStyle(
                    color: MizdahTheme.primaryBlue,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      sender,
                      style: const TextStyle(
                        color: MizdahTheme.primaryBlue,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.chat_bubble_outline_rounded,
                  color: Colors.white54, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Reactions UI
// ---------------------------------------------------------------------------

/// Bottom sheet with a row of common emojis. Tapping one fires the
/// `onPick` callback (which sends the reaction and dismisses the sheet).
class _ReactionsPickerSheet extends StatelessWidget {
  final ValueChanged<String> onPick;
  const _ReactionsPickerSheet({required this.onPick});

  static const List<String> _emojis = [
    '👍', '❤️', '😂', '😮', '🎉', '👏', '🙌', '🔥',
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1A1F26) : Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          children: _emojis.map((e) {
            return InkResponse(
              onTap: () => onPick(e),
              radius: 28,
              child: Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                child: Text(e, style: const TextStyle(fontSize: 28)),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

/// Floats every reaction up from the bottom for a few seconds. Each
/// reaction has its own animated entry — they never block taps and
/// stop receiving rebuilds once the notifier removes them from state.
class _ReactionsOverlay extends StatelessWidget {
  final List<ReactionEvent> reactions;
  const _ReactionsOverlay({required this.reactions});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        for (final r in reactions)
          _FloatingReaction(key: ValueKey(r), reaction: r),
      ],
    );
  }
}

class _FloatingReaction extends StatefulWidget {
  final ReactionEvent reaction;
  const _FloatingReaction({super.key, required this.reaction});

  @override
  State<_FloatingReaction> createState() => _FloatingReactionState();
}

class _FloatingReactionState extends State<_FloatingReaction>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final double _xOffset;

  @override
  void initState() {
    super.initState();
    // Random horizontal jitter so multiple reactions don't stack.
    _xOffset = (widget.reaction.hashCode % 60) - 30.0;
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 3200),
      vsync: this,
    )..forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final t = Curves.easeOut.transform(_ctrl.value);
        final size = MediaQuery.of(context).size;
        // Travel from ~60% of height up to 15% of height.
        final dy = size.height * (0.60 - t * 0.45);
        final dx = (size.width / 2) - 28 + _xOffset;
        // Fade in fast, out slow.
        final opacity = t < 0.1 ? t * 10 : (1.0 - ((t - 0.1) / 0.9) * 0.85);
        return Positioned(
          left: dx,
          top: dy,
          child: Opacity(
            opacity: opacity.clamp(0.0, 1.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(widget.reaction.emoji, style: const TextStyle(fontSize: 48)),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    widget.reaction.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Layout switcher in the top bar
// ---------------------------------------------------------------------------

class _LayoutSwitcherButton extends ConsumerWidget {
  const _LayoutSwitcherButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final current = ref.watch(meetingLayoutProvider);
    return GlassCard(
      padding: EdgeInsets.zero,
      radius: 100,
      opacity: isDark ? 0.1 : 0.05,
      child: PopupMenuButton<MeetingLayout>(
        icon: Icon(
          current.icon,
          color: isDark ? Colors.white : Colors.black87,
          size: 20,
        ),
        tooltip: 'Change layout',
        position: PopupMenuPosition.under,
        color: isDark ? const Color(0xFF1A1F26) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        onSelected: (layout) =>
            ref.read(meetingLayoutProvider.notifier).set(layout),
        itemBuilder: (context) => [
          for (final l in MeetingLayout.values)
            PopupMenuItem<MeetingLayout>(
              value: l,
              child: Row(
                children: [
                  Icon(
                    l.icon,
                    color: l == current
                        ? const Color(0xFF1A73E8)
                        : (isDark ? Colors.white70 : Colors.black54),
                    size: 18,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    l.label,
                    style: TextStyle(
                      color: l == current
                          ? const Color(0xFF1A73E8)
                          : (isDark ? Colors.white : Colors.black87),
                      fontWeight:
                          l == current ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
