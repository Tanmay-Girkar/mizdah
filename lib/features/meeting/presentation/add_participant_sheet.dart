// ════════════════════════════════════════════════════════════════════
//  AddParticipantSheet — pick someone to drop into a live session
// ════════════════════════════════════════════════════════════════════
//
//  Reusable bottom sheet opened from:
//    • Meeting room's More options sheet ("Add participant" row)
//    • P2P call screen's bottom control row (`+ Add` button)
//
//  Calls into InCallInviteRepository — meeting path uses
//  inviteToLiveMeeting(); P2P path uses promoteToMeeting() so both
//  existing peers transparently transition to a fresh SFU meeting.
//
//  Filter rules:
//    • Hide self (can't invite yourself)
//    • Hide users already in the current meeting (participant list
//      is passed in; P2P path filters out the peer instead)
//    • Empty query → recent chat peers (cached, no network)
//    • Non-empty query → server search via ChatRepository.searchUsers
//      (debounced 250ms)
//

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/mizdah_design.dart';
import '../../../data/repositories/in_call_invite_repository.dart';
import '../../auth/auth_provider.dart';
import '../../chats/chats_provider.dart';
import '../../chats/data/chat_models.dart';

/// What kind of session we're adding to. The picker shows the same
/// UI for both; only the on-pick callback differs.
enum AddParticipantTarget { meeting, p2pCall }

/// Identifies the active session so the repository call hits the
/// right endpoint. For meetings, [meetingId] is required. For P2P,
/// [callId] is required and [excludePeerUserId] lets the picker
/// hide the other peer from the search results.
class AddParticipantSessionContext {
  final AddParticipantTarget target;
  final String? meetingId;
  final String? callId;
  final String? excludePeerUserId;
  final List<String> excludeUserIds;

  const AddParticipantSessionContext.meeting({
    required String this.meetingId,
    this.excludeUserIds = const [],
  })  : target = AddParticipantTarget.meeting,
        callId = null,
        excludePeerUserId = null;

  const AddParticipantSessionContext.p2pCall({
    required String this.callId,
    this.excludePeerUserId,
    this.excludeUserIds = const [],
  })  : target = AddParticipantTarget.p2pCall,
        meetingId = null;
}

/// Open the picker. Returns the userId that was successfully invited
/// (so the caller can show "Inviting Farhan…" toast), or null if the
/// user dismissed the sheet without picking.
Future<String?> showAddParticipantSheet(
  BuildContext context, {
  required AddParticipantSessionContext session,
}) {
  return showModalBottomSheet<String?>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    useRootNavigator: true,
    builder: (_) => _AddParticipantSheet(session: session),
  );
}

class _AddParticipantSheet extends ConsumerStatefulWidget {
  final AddParticipantSessionContext session;
  const _AddParticipantSheet({required this.session});

  @override
  ConsumerState<_AddParticipantSheet> createState() =>
      _AddParticipantSheetState();
}

class _AddParticipantSheetState
    extends ConsumerState<_AddParticipantSheet> {
  final TextEditingController _ctrl = TextEditingController();
  String _query = '';
  Timer? _debounce;
  bool _searching = false;
  List<ChatUser> _results = const [];
  String? _inFlightUserId;
  String? _inlineError;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onQueryChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onQueryChanged() {
    final q = _ctrl.text.trim();
    setState(() => _query = q);
    _debounce?.cancel();
    if (q.isEmpty) {
      setState(() {
        _results = const [];
        _searching = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 250), () => _runSearch(q));
  }

  Future<void> _runSearch(String q) async {
    if (!mounted) return;
    setState(() => _searching = true);
    try {
      final repo = ref.read(chatRepositoryProvider);
      final hits = await repo.searchUsers(q);
      if (!mounted || _ctrl.text.trim() != q) return;
      setState(() {
        _results = hits.where(_keep).toList();
        _searching = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _results = const [];
        _searching = false;
      });
    }
  }

  bool _keep(ChatUser u) {
    final selfEmail =
        ref.read(authProvider).user?.email.toLowerCase() ?? '';
    final lc = u.email.toLowerCase();
    if (lc == selfEmail) return false;
    return true;
  }

  /// Recent chat peers (no network) — what shows when the search
  /// box is empty. Pulled from the conversations stream the user
  /// already has in memory.
  List<({String email, String? name, String? avatarUrl})>
      _recentSuggestions() {
    final convos = ref.read(conversationsProvider).maybeWhen(
          data: (list) => list,
          orElse: () => const <dynamic>[],
        );
    final selfEmail =
        ref.read(authProvider).user?.email.toLowerCase() ?? '';
    final seen = <String>{};
    final out = <({String email, String? name, String? avatarUrl})>[];
    for (final c in convos) {
      final peer = (c as dynamic).peerOf(selfEmail) as String;
      final lc = peer.toLowerCase();
      if (lc.isEmpty || lc == selfEmail) continue;
      if (!seen.add(lc)) continue;
      out.add((email: peer, name: null, avatarUrl: null));
      if (out.length >= 10) break;
    }
    return out;
  }

  Future<void> _pickByEmailKey(String email, String displayLabel) async {
    if (_inFlightUserId != null) return;
    setState(() {
      _inFlightUserId = email; // reuse as in-flight sentinel
      _inlineError = null;
    });
    try {
      final repo = ref.read(inCallInviteRepositoryProvider);
      if (widget.session.target == AddParticipantTarget.meeting) {
        await repo.inviteToLiveMeeting(
          meetingId: widget.session.meetingId!,
          inviteeEmail: email,
        );
      } else {
        await repo.promoteToMeeting(
          callId: widget.session.callId!,
          inviteeEmail: email,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(email);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Inviting $displayLabel…'),
          duration: const Duration(seconds: 2),
        ),
      );
    } on InCallInviteError catch (e) {
      if (!mounted) return;
      setState(() {
        _inFlightUserId = null;
        _inlineError = _humanise(e);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _inFlightUserId = null;
        _inlineError = 'Could not send invite. Try again.';
      });
    }
  }

  String _humanise(InCallInviteError e) {
    return switch (e) {
      InviteNotAllowedByHostError() =>
        'Host has disabled invites for participants.',
      ForbiddenNotParticipantError() =>
        "You're no longer in this meeting.",
      AlreadyInMeetingError() => "They're already in the meeting.",
      CannotInviteSelfError() => "You can't invite yourself.",
      MeetingFullError() => 'Meeting is full.',
      RateLimitedError() => 'Too many invites — slow down a bit.',
      AlreadyPromotedError() =>
        "Already added someone to this call — wait for them to join first.",
      _ => 'Could not send invite. Try again.',
    };
  }

  /// Backend resolves email → userId server-side per
  /// docs/ADD_PARTICIPANT_BACKEND.md §2. Saves the client a
  /// search-by-email round-trip that wouldn't always work
  /// anyway (ChatUser doesn't expose userId on every server
  /// build).
  Future<void> _pickByEmail(String email, String? displayLabel) async {
    return _pickByEmailKey(email, displayLabel ?? email);
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final recents = _query.isEmpty
        ? _recentSuggestions()
        : const <({String email, String? name, String? avatarUrl})>[];
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, scrollCtrl) {
        return Container(
          decoration: BoxDecoration(
            color: MizdahTokens.surface(context),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: MizdahTokens.border(context),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Row(
                  children: [
                    Icon(Icons.person_add_alt_1_rounded,
                        color: MizdahTokens.primary, size: 22),
                    const SizedBox(width: 10),
                    Text(
                      widget.session.target == AddParticipantTarget.meeting
                          ? 'Add to meeting'
                          : 'Add to call',
                      style: TextStyle(
                        color: MizdahTokens.inkOf(context),
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                child: TextField(
                  controller: _ctrl,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'Search by name or email',
                    prefixIcon: const Icon(Icons.search_rounded),
                    filled: true,
                    fillColor: MizdahTokens.bg(context),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              if (_inlineError != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFB42318).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      _inlineError!,
                      style: const TextStyle(
                          color: Color(0xFFB42318),
                          fontSize: 13,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              Expanded(
                child: _query.isEmpty
                    ? _buildRecents(context, recents, scrollCtrl)
                    : _buildResults(context, scrollCtrl),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRecents(
    BuildContext context,
    List<({String email, String? name, String? avatarUrl})> recents,
    ScrollController ctrl,
  ) {
    if (recents.isEmpty) {
      return _emptyHint(context, 'Search above to find someone to add.');
    }
    return ListView.separated(
      controller: ctrl,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
      itemCount: recents.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 4),
      itemBuilder: (ctx, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
            child: Text(
              'Recent',
              style: TextStyle(
                color: MizdahTokens.mutedOf(context),
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
              ),
            ),
          );
        }
        final r = recents[i - 1];
        final label = r.name ??
            (r.email.contains('@') ? r.email.split('@').first : r.email);
        return _PeerRow(
          name: label,
          email: r.email,
          avatarUrl: r.avatarUrl,
          isBusy: false,
          onTap: () => _pickByEmail(r.email, label),
        );
      },
    );
  }

  Widget _buildResults(BuildContext context, ScrollController ctrl) {
    if (_searching) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_results.isEmpty) {
      return _emptyHint(context, 'No Mizdah user matches "$_query".');
    }
    return ListView.separated(
      controller: ctrl,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
      itemCount: _results.length,
      separatorBuilder: (_, __) => const SizedBox(height: 4),
      itemBuilder: (ctx, i) {
        final u = _results[i];
        return _PeerRow(
          name: u.label,
          email: u.email,
          avatarUrl: u.avatarUrl,
          isBusy:
              _inFlightUserId != null && _inFlightUserId == u.email,
          onTap: () => _pickByEmail(u.email, u.label),
        );
      },
    );
  }

  Widget _emptyHint(BuildContext context, String text) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: MizdahTokens.mutedOf(context),
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _PeerRow extends StatelessWidget {
  final String name;
  final String email;
  final String? avatarUrl;
  final bool isBusy;
  final VoidCallback onTap;

  const _PeerRow({
    required this.name,
    required this.email,
    required this.avatarUrl,
    required this.isBusy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: isBusy ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              MizdahAvatar(name: name, avatarUrl: avatarUrl, size: 42),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: MizdahTokens.inkOf(context),
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: MizdahTokens.mutedOf(context),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              if (isBusy)
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(
                  Icons.add_circle_rounded,
                  color: MizdahTokens.primary,
                  size: 28,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
