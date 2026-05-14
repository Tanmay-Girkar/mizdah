// ════════════════════════════════════════════════════════════════════
//  push_reply_handler — inline-reply / mark-read action callback
//                       executed in a BACKGROUND ISOLATE
// ════════════════════════════════════════════════════════════════════
//
//  When a chat notification carries the actions we attach in
//  `PushNotificationService`, the OS shows two buttons under the
//  banner:
//
//    [ REPLY ]       ← text-input action
//    [ MARK AS READ ] ← plain action
//
//  Tapping either fires `notificationTapBackground` on Flutter's
//  side. The catch: this fires in a **separate Dart isolate** that
//  shares NOTHING with the running app — not Firebase, not the
//  Riverpod providers, not the Dio client, not the HttpOverrides
//  installed in main().
//
//  So everything we need (binding, auth token, base URL, HTTP
//  client, dev-cert allowlist) is reconstructed inside the
//  callback from primitives. The callback MUST be a top-level
//  function annotated with `@pragma('vm:entry-point')` — Dart's
//  tree-shaker would otherwise drop it from release builds, and
//  the OS's binder couldn't find it to invoke.
//
//  iOS gives this isolate ~30 seconds before it's killed. Android
//  is more lenient. The implementation favours getting the message
//  delivered quickly over rich feedback — a "Reply sent" toast
//  notification only fires if the API call succeeds promptly.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config/api_config.dart';

// ── Action / category identifiers ──────────────────────────────
// Shared between the foreground service (which attaches them to
// outgoing notifications) and this handler (which inspects them on
// the way back). Keep these names stable — changing them after a
// release strands existing notifications in users' trays.
const String kChatReplyActionId = 'mizdah_chat_reply';
const String kChatMarkReadActionId = 'mizdah_chat_mark_read';
const String kChatCategoryId = 'mizdah_chat';

/// Top-level callback invoked by `flutter_local_notifications` when
/// a notification action is triggered (Android) or a notification
/// is tapped while the app is killed (iOS). Lives in a separate
/// Dart isolate — see file-level doc.
@pragma('vm:entry-point')
Future<void> notificationTapBackground(NotificationResponse resp) async {
  // Boot the Flutter binding for this isolate. Platform channels
  // (secure storage, local notifications) need the binding even
  // when there's no UI. Idempotent.
  WidgetsFlutterBinding.ensureInitialized();

  debugPrint('[push-bg] fired: actionId=${resp.actionId} '
      'payload=${resp.payload?.length} bytes '
      'input=${(resp.input ?? '').length} chars');

  final raw = resp.payload;
  if (raw == null || raw.isEmpty) {
    debugPrint('[push-bg] no payload — nothing to act on');
    return;
  }

  Map<String, dynamic> data;
  try {
    data = Map<String, dynamic>.from(jsonDecode(raw) as Map);
  } catch (e) {
    debugPrint('[push-bg] payload decode failed: $e');
    return;
  }

  final conversationId = data['conversation_id']?.toString();
  final originalNotifId = data['__notif_id'] is int
      ? data['__notif_id'] as int
      : int.tryParse('${data['__notif_id']}');

  switch (resp.actionId) {
    case kChatReplyActionId:
      final reply = (resp.input ?? '').trim();
      if (reply.isEmpty) {
        debugPrint('[push-bg] empty reply — skipping');
        return;
      }
      await _sendChatReply(
        conversationId: conversationId,
        replyText: reply,
        originalNotifId: originalNotifId,
      );
      break;

    case kChatMarkReadActionId:
      await _markChatRead(
        conversationId: conversationId,
        originalNotifId: originalNotifId,
      );
      break;

    default:
      // Plain tap on the notification body — the main isolate
      // routes once the app boots (via `getInitialMessage` /
      // `onMessageOpenedApp`). Nothing to do from here.
      debugPrint('[push-bg] non-action tap — main isolate will route');
  }
}

// ── Reply action ──────────────────────────────────────────────

Future<void> _sendChatReply({
  required String? conversationId,
  required String replyText,
  required int? originalNotifId,
}) async {
  if (conversationId == null || conversationId.isEmpty) {
    debugPrint('[push-bg] reply: missing conversation_id');
    return;
  }

  final jwt = await _readAuthToken();
  if (jwt == null || jwt.isEmpty) {
    debugPrint('[push-bg] reply: no auth token, user signed out');
    await _showStatusNotification(
      'Sign in to reply',
      'Open Mizdah to continue this conversation',
    );
    return;
  }

  try {
    _installDevCertOverride();
    final dio = _buildDio(jwt);
    final clientId = 'tmp_bg_${DateTime.now().microsecondsSinceEpoch}';
    debugPrint('[push-bg] POST /api/chats/.../$conversationId/messages');
    final response = await dio.post(
      '${ApiConfig.baseUrl}/api/chats/conversations/$conversationId/messages',
      data: {
        'client_id': clientId,
        'body': replyText,
      },
    );
    debugPrint('[push-bg] reply sent, status=${response.statusCode}');

    // Dismiss the original notification + show a tiny "Sent"
    // confirmation. The user knows the message left the device
    // without having to open the app to verify.
    if (originalNotifId != null) {
      await FlutterLocalNotificationsPlugin().cancel(originalNotifId);
    }
    await _showStatusNotification(
      'Reply sent',
      replyText.length > 60 ? '${replyText.substring(0, 57)}…' : replyText,
    );
  } catch (e) {
    debugPrint('[push-bg] reply send failed: $e');
    await _showStatusNotification(
      'Reply failed to send',
      'Open Mizdah to retry',
    );
  }
}

// ── Mark-as-read action ───────────────────────────────────────

Future<void> _markChatRead({
  required String? conversationId,
  required int? originalNotifId,
}) async {
  if (conversationId == null || conversationId.isEmpty) {
    debugPrint('[push-bg] mark-read: missing conversation_id');
    return;
  }
  final jwt = await _readAuthToken();
  if (jwt == null || jwt.isEmpty) return;

  try {
    _installDevCertOverride();
    final dio = _buildDio(jwt);
    debugPrint(
        '[push-bg] POST /api/chats/conversations/$conversationId/read');
    await dio.post(
      '${ApiConfig.baseUrl}/api/chats/conversations/$conversationId/read',
      data: const <String, dynamic>{},
    );
    if (originalNotifId != null) {
      await FlutterLocalNotificationsPlugin().cancel(originalNotifId);
    }
  } catch (e) {
    debugPrint('[push-bg] mark-read failed: $e');
  }
}

// ── Helpers ───────────────────────────────────────────────────

/// Reads the JWT from secure storage. Uses the same key + iOS
/// accessibility settings as `StorageService` so the value resolves
/// correctly after the device's first unlock since boot.
Future<String?> _readAuthToken() async {
  try {
    const storage = FlutterSecureStorage(
      iOptions: IOSOptions(
        accessibility: KeychainAccessibility.first_unlock,
      ),
    );
    return storage.read(key: 'auth_token');
  } catch (e) {
    debugPrint('[push-bg] secure storage read failed: $e');
    return null;
  }
}

/// Background isolates don't see the `HttpOverrides.global` set in
/// `main()`. Without re-installing it, Dio fails on the self-signed
/// dev cert with CERTIFICATE_VERIFY_FAILED. Mirrors the allowlist
/// in `main.dart`'s `_DevHttpOverrides`. No-op in release builds.
void _installDevCertOverride() {
  if (!kDebugMode) return;
  if (HttpOverrides.current is _BgDevHttpOverrides) return;
  HttpOverrides.global = _BgDevHttpOverrides();
}

class _BgDevHttpOverrides extends HttpOverrides {
  // Same set as main.dart's allowlist — must stay in sync. A future
  // refactor could share this list; not worth the indirection today.
  static const _trustedDevHosts = <String>{
    '192.168.1.18',
    '192.168.1.20',
    '192.168.1.100',
    '192.168.1.48',
    '192.168.1.117',
    'localhost',
    '127.0.0.1',
    '10.0.2.2',
  };

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback =
          (cert, host, port) => _trustedDevHosts.contains(host);
  }
}

Dio _buildDio(String jwt) {
  return Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 6),
    sendTimeout: const Duration(seconds: 6),
    receiveTimeout: const Duration(seconds: 8),
    headers: {
      'Authorization': 'Bearer $jwt',
      'Content-Type': 'application/json',
    },
  ));
}

/// Show a small confirmation/failure notification from the background
/// isolate. Uses the same channel as the main app so no extra channel
/// registration is required.
Future<void> _showStatusNotification(String title, String body) async {
  try {
    final plugin = FlutterLocalNotificationsPlugin();
    // The plugin must be initialized before show() works. Calling
    // initialize from a background isolate is supported and is a
    // no-op for already-registered channels.
    await plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    await plugin.show(
      DateTime.now().millisecondsSinceEpoch.remainder(0x7fffffff),
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'mizdah_general_v1',
          'General notifications',
          channelDescription: 'Chats, calls, meetings, and scheduling alerts.',
          icon: '@mipmap/ic_launcher',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
    );
  } catch (e) {
    debugPrint('[push-bg] status notif failed: $e');
  }
}
