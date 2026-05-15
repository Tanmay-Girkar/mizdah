import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/repositories/notification_repository.dart';
import '../../data/models/models.dart';
import '../auth/auth_provider.dart';

/// Notifications inbox — full first page + unread count, freshly
/// fetched every time something watches the provider.
///
/// AutoDispose so the cache vacates when the user leaves the home
/// tab (the only persistent watcher today). Re-mount = re-fetch,
/// which is what we want — both for catching new pushes the user
/// missed while elsewhere AND for snapping back to a true count
/// after a mark-read / dismiss action invalidated the provider.
///
/// Returns a `NotificationsPage` (not a bare `List`) so consumers
/// get `items` AND `unreadCount` from a single round-trip.
final notificationsProvider =
    FutureProvider.autoDispose<NotificationsPage>((ref) async {
  final user = ref.watch(authProvider).user;
  if (user == null) {
    return const NotificationsPage(items: []);
  }
  final repo = ref.watch(notificationRepositoryProvider);
  return repo.getUserNotifications(user.id, limit: 50);
});
