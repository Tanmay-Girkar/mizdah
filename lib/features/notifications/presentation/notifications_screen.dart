import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/ui/mizdah_design.dart';
import '../../../data/models/models.dart';
import '../../home/notification_provider.dart';

/// Notification types we surface on this screen. Chat / DM
/// notifications are deliberately excluded — those have their own
/// unread surface inside the Chats tab and would otherwise double-up.
///
/// Backend `type` strings the app recognises (defaults to "info"
/// rendering when an unknown string lands):
///
///   meeting_invite      — someone invited you to a meeting
///   meeting_reminder    — your scheduled meeting starts soon
///   meeting_started     — host opened a meeting you're on the
///                          invite list for, join now
///   meeting_cancelled   — host cancelled an upcoming meeting
///   meeting_rescheduled — host moved an upcoming meeting
///   recording_ready     — a recording you started is now available
///   missed_call         — P2P voice/video call you didn't answer
///   contact_joined      — a phone-contact just signed up for Mizdah
///   security            — password changed / new-device sign-in
///   info                — fallback bucket
///
/// Everything else (chat:message, chat:mention, chat:reply, …) is
/// filtered out by `_isChatType`.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(notificationsProvider);

    return Scaffold(
      backgroundColor: MizdahTokens.bg(context),
      appBar: AppBar(
        backgroundColor: MizdahTokens.bg(context),
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          color: MizdahTokens.inkOf(context),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Notifications',
          style: TextStyle(
            color: MizdahTokens.inkOf(context),
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: false,
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.refresh(notificationsProvider.future),
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => ListView(
            children: const [
              SizedBox(height: 120),
              Center(
                child: Text(
                  'Could not load notifications.\nPull to retry.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ],
          ),
          data: (all) {
            final list = all.where((n) => !_isChatType(n.type)).toList();
            if (list.isEmpty) return const _EmptyState();
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (ctx, i) => _NotificationTile(item: list[i]),
            );
          },
        ),
      ),
    );
  }

  /// Anything chat-shaped is the Chats tab's job, not this screen.
  bool _isChatType(String type) {
    final t = type.toLowerCase();
    return t == 'chat' ||
        t == 'message' ||
        t == 'dm' ||
        t.startsWith('chat:') ||
        t.startsWith('message:');
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 120),
        Icon(
          Icons.notifications_none_rounded,
          size: 56,
          color: MizdahTokens.inkOf(context).withValues(alpha: 0.35),
        ),
        const SizedBox(height: 12),
        Center(
          child: Text(
            'No notifications yet',
            style: TextStyle(
              color: MizdahTokens.inkOf(context),
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Center(
          child: Text(
            "Meeting invites, reminders, missed\ncalls and account alerts show up here.",
            textAlign: TextAlign.center,
            style: TextStyle(
              color: MizdahTokens.inkOf(context).withValues(alpha: 0.55),
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final NotificationModel item;
  const _NotificationTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final meta = _meta(item.type);
    return Container(
      decoration: BoxDecoration(
        color: MizdahTokens.surface(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: MizdahTokens.inkOf(context).withValues(alpha: 0.05),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: meta.tint.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(meta.icon, color: meta.tint, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.title,
                        style: TextStyle(
                          color: MizdahTokens.inkOf(context),
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      _timeLabel(item.createdAt),
                      style: TextStyle(
                        color:
                            MizdahTokens.inkOf(context).withValues(alpha: 0.5),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                if (item.body.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    item.body,
                    style: TextStyle(
                      color:
                          MizdahTokens.inkOf(context).withValues(alpha: 0.65),
                      fontSize: 12.5,
                      height: 1.35,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// "Today" → time, this week → "Mon 9:14 AM", older → date.
  String _timeLabel(DateTime ts) {
    final now = DateTime.now();
    final diff = now.difference(ts);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inHours < 24 && ts.day == now.day) {
      return DateFormat('h:mm a').format(ts);
    }
    if (diff.inDays < 7) return DateFormat('E h:mm a').format(ts);
    return DateFormat('MMM d').format(ts);
  }

  _TypeMeta _meta(String type) {
    switch (type.toLowerCase()) {
      case 'meeting_invite':
        return const _TypeMeta(Icons.event_available_rounded, Color(0xFF6C63FF));
      case 'meeting_reminder':
      case 'meeting_started':
        return const _TypeMeta(Icons.videocam_rounded, Color(0xFF8B5CF6));
      case 'meeting_cancelled':
        return const _TypeMeta(Icons.event_busy_rounded, Color(0xFFB42318));
      case 'meeting_rescheduled':
        return const _TypeMeta(Icons.update_rounded, Color(0xFFB45309));
      case 'recording_ready':
        return const _TypeMeta(Icons.fiber_smart_record_rounded,
            Color(0xFF10B981));
      case 'missed_call':
        return const _TypeMeta(Icons.call_missed_rounded, Color(0xFFB42318));
      case 'contact_joined':
        return const _TypeMeta(Icons.person_add_alt_1_rounded,
            Color(0xFF10B981));
      case 'security':
        return const _TypeMeta(Icons.shield_outlined, Color(0xFFB45309));
      default:
        return const _TypeMeta(Icons.notifications_rounded, Color(0xFF6C63FF));
    }
  }
}

class _TypeMeta {
  final IconData icon;
  final Color tint;
  const _TypeMeta(this.icon, this.tint);
}
