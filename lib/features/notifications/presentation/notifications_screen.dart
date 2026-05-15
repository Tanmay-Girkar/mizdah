import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/ui/mizdah_design.dart';
import '../../../data/models/models.dart';
import '../../../data/repositories/notification_repository.dart';
import '../../home/notification_provider.dart';

/// Notification types we surface on this screen. Chat / DM
/// notifications are deliberately excluded — those have their own
/// unread surface inside the Chats tab and would otherwise double-up.
///
/// Per-type metadata (icon, colour, deep-link route) lives in
/// `_NotificationTile._meta()` below. See docs/NOTIFICATIONS_BACKEND.md
/// §3 for the full per-type contract — title / body / data shape.
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
        actions: [
          async.maybeWhen(
            data: (page) => page.unreadCount > 0
                ? IconButton(
                    tooltip: 'Mark all as read',
                    icon: const Icon(Icons.done_all_rounded),
                    color: MizdahTokens.inkOf(context),
                    onPressed: () => _markAllRead(context, ref),
                  )
                : const SizedBox.shrink(),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
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
          data: (page) {
            final list =
                page.items.where((n) => !_isChatType(n.type)).toList();
            if (list.isEmpty) return const _EmptyState();
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (ctx, i) => _NotificationTile(
                item: list[i],
                onTap: () => _onTileTap(ctx, ref, list[i]),
                onDismiss: () => _onDismiss(ctx, ref, list[i]),
              ),
            );
          },
        ),
      ),
    );
  }

  /// Anything chat-shaped is the Chats tab's job, not this screen.
  /// Server-side §3 says these types shouldn't be inserted into the
  /// table at all, but we filter defensively in case a regression
  /// slips them through.
  bool _isChatType(String type) {
    final t = type.toLowerCase();
    return t == 'chat' ||
        t == 'message' ||
        t == 'dm' ||
        t.startsWith('chat:') ||
        t.startsWith('message:');
  }

  Future<void> _markAllRead(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(notificationRepositoryProvider).markAllAsRead();
      ref.invalidate(notificationsProvider);
    } catch (e) {
      messenger.showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Color(0xFFB42318),
          content: Text(
            "Couldn't mark all as read.",
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    }
  }

  /// Tap = mark read on the server (idempotent, harmless for already-
  /// read rows) AND deep-link based on the row's `type` + `data`
  /// payload. The mark-read fires-and-forgets so the navigation
  /// isn't blocked on network.
  void _onTileTap(BuildContext context, WidgetRef ref, NotificationModel n) {
    if (!n.isRead) {
      _markOneReadInBackground(ref, n.id);
    }
    final href = _deepLinkFor(n);
    if (href != null) context.push(href);
  }

  void _markOneReadInBackground(WidgetRef ref, String id) {
    // No await, no catch — the next provider refetch will reconcile
    // the read flag. Worst case the row stays "unread" until next
    // mark/refresh, which is annoying but not broken.
    ref.read(notificationRepositoryProvider).markAsRead(id).then((_) {
      ref.invalidate(notificationsProvider);
    }).catchError((_) {});
  }

  Future<void> _onDismiss(
      BuildContext context, WidgetRef ref, NotificationModel n) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(notificationRepositoryProvider).dismiss(n.id);
      ref.invalidate(notificationsProvider);
    } catch (e) {
      messenger.showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Color(0xFFB42318),
          content: Text(
            "Couldn't dismiss notification.",
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    }
  }

  /// Picks a deep-link target for the given notification, falling
  /// back to no-op (returns null) when there's no useful place to
  /// send the user. Pulls keys from `data` per the type contract in
  /// docs/NOTIFICATIONS_BACKEND.md §3.
  String? _deepLinkFor(NotificationModel n) {
    final data = n.data;
    String? str(String key) {
      final v = data[key];
      return v is String && v.isNotEmpty ? v : null;
    }

    switch (n.type.toLowerCase()) {
      case 'meeting_invite':
      case 'meeting_reminder':
      case 'meeting_started':
      case 'meeting_rescheduled':
        final id = str('meetingId') ?? str('meeting_id');
        return id != null ? '/pre-join/$id' : '/meetings';
      case 'meeting_cancelled':
        return '/meetings';
      case 'recording_ready':
        final code = str('meetingCode') ?? str('meeting_code');
        return code != null ? '/recordings/$code' : null;
      case 'missed_call':
        return '/call-history';
      case 'contact_joined':
        return '/call-hub';
      case 'security':
        return '/settings';
      default:
        return null;
    }
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
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  const _NotificationTile({
    required this.item,
    required this.onTap,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final meta = _meta(item.type);
    final ink = MizdahTokens.inkOf(context);
    // Unread rows get a subtle accent stripe + slightly stronger
    // background so the user's eye lands there first.
    final unreadAccent = !item.isRead;

    return Dismissible(
      key: ValueKey('notif-${item.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: const Color(0xFFB42318),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
      ),
      onDismissed: (_) => onDismiss(),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              color: MizdahTokens.surface(context),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: unreadAccent
                    ? meta.tint.withValues(alpha: 0.35)
                    : ink.withValues(alpha: 0.05),
                width: unreadAccent ? 1.2 : 1,
              ),
            ),
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                                color: ink,
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (unreadAccent) ...[
                            const SizedBox(width: 6),
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: meta.tint,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Text(
                            _timeLabel(item.createdAt),
                            style: TextStyle(
                              color: ink.withValues(alpha: 0.5),
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
                            color: ink.withValues(alpha: 0.65),
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
          ),
        ),
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
