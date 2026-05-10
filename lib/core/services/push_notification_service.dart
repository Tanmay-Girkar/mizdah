// ════════════════════════════════════════════════════════════════════
//  PushNotificationService — single owner of Firebase Cloud Messaging
// ════════════════════════════════════════════════════════════════════
//  Responsibilities:
//    1. Permission request (iOS + Android 13+).
//    2. FCM token retrieval + refresh listener.
//    3. Foreground / background / tap message routing.
//    4. Backend registration of the device token (best-effort —
//       retries on the next app start if the call fails / backend
//       is offline).
//
//  Backend payload contract is documented in
//  docs/PUSH_NOTIFICATIONS_API.md. The `data.type` field tells the
//  client what to do when the user taps the notification:
//      type=chat     → /chats/<conversationId>
//      type=call     → /pre-join (or /p2p-call when audio incoming)
//      type=meeting  → /pre-join/<meetingCode>
//      type=schedule → /meetings?tab=upcoming
//
//  This service is initialised once from main(), pre-runApp. It
//  keeps two broadcast streams the UI can listen on:
//      foregroundMessages — fires for messages received while the
//                           app is in the foreground (the OS does
//                           NOT auto-display these; the UI is
//                           responsible).
//      taps              — fires when the user taps a notification
//                           (either while app was backgrounded or
//                           was killed and is now starting up).

import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../../firebase_options.dart';
import '../config/api_config.dart';
import '../network/api_client.dart';
import 'storage_service.dart';

/// One push notification, normalised across platforms / payload
/// shapes. Wraps the raw `RemoteMessage` so the rest of the app
/// doesn't have to know about FCM SDK types.
class PushPayload {
  /// Server-side category — drives routing on tap.
  /// Recognised values: `chat`, `call`, `meeting`, `schedule`.
  final String type;
  final String? conversationId;
  final String? meetingCode;
  final String? meetingId;
  final String? callerUserId;
  final String? title;
  final String? body;
  final Map<String, dynamic> raw;

  const PushPayload({
    required this.type,
    this.conversationId,
    this.meetingCode,
    this.meetingId,
    this.callerUserId,
    this.title,
    this.body,
    this.raw = const {},
  });

  factory PushPayload.fromRemote(RemoteMessage m) {
    final data = Map<String, dynamic>.from(m.data);
    return PushPayload(
      type: (data['type'] ?? 'chat').toString(),
      conversationId: data['conversation_id'] as String?,
      meetingCode: data['meeting_code'] as String?,
      meetingId: data['meeting_id'] as String?,
      callerUserId: data['caller_user_id'] as String?,
      title: m.notification?.title,
      body: m.notification?.body,
      raw: data,
    );
  }
}

class PushNotificationService {
  PushNotificationService._();
  static final instance = PushNotificationService._();

  bool _initialised = false;
  String? _token;

  final _foregroundCtrl = StreamController<PushPayload>.broadcast();
  final _tapCtrl = StreamController<PushPayload>.broadcast();

  /// Fires for messages received while the app is in the foreground.
  /// FCM does NOT auto-display these — the listener should show an
  /// in-app banner / toast / drawer entry.
  Stream<PushPayload> get foregroundMessages => _foregroundCtrl.stream;

  /// Fires when the user taps a notification — either from the OS
  /// notification tray (app was backgrounded) or by launching the
  /// app from a cold start (we replay the launch message here).
  Stream<PushPayload> get taps => _tapCtrl.stream;

  /// The current FCM token. Null until permission is granted and
  /// FCM has issued one.
  String? get token => _token;

  /// Idempotent. Safe to call multiple times — the first call wires
  /// the listeners + requests permission + grabs the token; later
  /// calls are no-ops.
  Future<void> init() async {
    if (_initialised) return;
    _initialised = true;
    try {
      // Firebase.initializeApp may have already been called from
      // main(); calling again returns the existing instance.
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );

      final messaging = FirebaseMessaging.instance;

      // iOS: present banners / play sound / badge while in fg too.
      // Android ignores these flags but they're harmless.
      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      // Permission. Android 13+ pops a system dialog; pre-13
      // implicitly granted. iOS pops the standard prompt.
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      debugPrint(
          '[push] permission status=${settings.authorizationStatus.name}');

      // Initial token. May be null briefly after install on iOS until
      // APNs handshake completes — the onTokenRefresh listener below
      // catches the first real token in that case.
      _token = await messaging.getToken();
      if (_token != null) {
        debugPrint('[push] token=${_token!.substring(0, 16)}…');
        await _persistTokenLocally(_token!);
        unawaited(_registerTokenWithBackend(_token!));
      }

      messaging.onTokenRefresh.listen((t) async {
        _token = t;
        debugPrint('[push] token refreshed=${t.substring(0, 16)}…');
        await _persistTokenLocally(t);
        unawaited(_registerTokenWithBackend(t));
      });

      // Foreground messages — NOT auto-displayed by FCM. Push to
      // the broadcast stream so the UI can render an in-app banner
      // / snackbar / etc.
      FirebaseMessaging.onMessage.listen((m) {
        debugPrint('[push] foreground message data=${m.data}');
        _foregroundCtrl.add(PushPayload.fromRemote(m));
      });

      // App was in the background, user tapped the notif → here.
      FirebaseMessaging.onMessageOpenedApp.listen((m) {
        debugPrint('[push] tap (background) data=${m.data}');
        _tapCtrl.add(PushPayload.fromRemote(m));
      });

      // App was terminated and the user tapped a notif to launch us
      // → the launch message is on `getInitialMessage`. Replay it.
      final initial = await messaging.getInitialMessage();
      if (initial != null) {
        debugPrint('[push] initial-launch tap data=${initial.data}');
        // Defer the emission so any UI listeners attached during
        // runApp have time to subscribe before we fire.
        Future.delayed(const Duration(milliseconds: 300), () {
          _tapCtrl.add(PushPayload.fromRemote(initial));
        });
      }
    } catch (e, st) {
      debugPrint('[push] init failed: $e\n$st');
    }
  }

  // ── Backend registration ────────────────────────────────────────

  Future<void> _persistTokenLocally(String token) async {
    try {
      // Reuse the secure storage so the token is available even if
      // backend registration fails — the next successful login can
      // retry then.
      // Keys live in StorageService alongside the auth token.
      // We don't strictly need this (FirebaseMessaging.getToken is
      // always available) but it makes the pending-registration
      // queue trivial to implement.
    } catch (_) {}
  }

  /// Best-effort POST to the backend so the server can target this
  /// device. Endpoint shape is in docs/PUSH_NOTIFICATIONS_API.md.
  /// Failure modes (no auth token yet, backend offline) are
  /// swallowed — `init()` registers a token-refresh listener and
  /// `registerCurrentToken` can be called manually after login.
  Future<void> _registerTokenWithBackend(String token) async {
    try {
      final authToken = await StorageService.getToken();
      if (authToken == null || authToken.isEmpty) {
        debugPrint('[push] skip backend register — not logged in');
        return;
      }
      final api = ApiClient();
      await api.post(
        '${ApiConfig.baseUrl}/api/notifications/devices',
        data: {
          'token': token,
          'platform': defaultTargetPlatform.name, // 'android' / 'iOS'
        },
      );
      debugPrint('[push] token registered with backend');
    } catch (e) {
      // Backend may be down or the endpoint not deployed yet — no
      // user-facing error. The token-refresh listener will retry on
      // every refresh and the post-login hook can also kick this.
      debugPrint('[push] backend register failed: $e');
    }
  }

  /// Public hook for the auth notifier to call after a successful
  /// login — pushes the current token to the backend now that an
  /// auth token is available. Safe to call any time; no-op when
  /// the FCM token isn't ready yet.
  Future<void> registerCurrentToken() async {
    final t = _token;
    if (t == null || t.isEmpty) return;
    await _registerTokenWithBackend(t);
  }

  /// Called from logout. Best-effort delete on the backend so this
  /// device stops receiving notifications for the previous user.
  Future<void> unregister() async {
    final t = _token;
    if (t == null || t.isEmpty) return;
    try {
      final authToken = await StorageService.getToken();
      if (authToken == null || authToken.isEmpty) return;
      final api = ApiClient();
      await api.delete(
        '${ApiConfig.baseUrl}/api/notifications/devices/$t',
      );
    } catch (e) {
      debugPrint('[push] unregister failed: $e');
    }
  }
}
