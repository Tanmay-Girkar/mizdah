import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/repositories/notification_repository.dart';
import '../../data/models/models.dart';
import '../auth/auth_provider.dart';

final notificationsProvider = FutureProvider.autoDispose<List<NotificationModel>>((ref) async {
  final user = ref.watch(authProvider).user;
  if (user == null) {
    return [];
  }
  final repo = ref.watch(notificationRepositoryProvider);
  final rawData = await repo.getUserNotifications(user.id);
  
  if (rawData is List) {
    return rawData.map((e) => NotificationModel.fromJson(e)).toList();
  }
  return [];
});
