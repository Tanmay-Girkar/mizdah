// ════════════════════════════════════════════════════════════════════
//  PushNotificationService — single owner of Firebase Cloud Messaging
// ════════════════════════════════════════════════════════════════════
//  Responsibilities:
//    1. Permission request (iOS + Android 13+).
//    2. FCM token retrieval + refresh listener.
//    3. Foreground / background / tap message routing.
//    4. Foreground notification display via flutter_local_notifications
//       (FCM does NOT auto-display when the app is in the foreground;
//       this plugin draws the system notification using the same
//       `mizdah_general_v1` channel created in MainActivity.kt).
//    5. Backend registration of the device token (best-effort —
//       retries on the next app start if the call fails / backend
//       is offline).
//
//  This service NEVER calls Firebase.initializeApp() — that is the
//  exclusive responsibility of main.dart's bootstrap (and the
//  background isolate handler). Calling it here a second time throws
//  `[core/duplicate-app]` and silently disables the whole pipeline.
//
//  Backend payload contract is documented in
//  docs/PUSH_NOTIFICATIONS_API.md. The `data.type` field tells the
//  client what to do when the user taps the notification:
//      type=chat     → /chats/<conversationId>
//      type=call     → /pre-join (or /p2p-call when audio incoming)
//      type=meeting  → /pre-join/<meetingCode>
//      type=schedule → /meetings?tab=upcoming
//
//  This service is initialised once from main(), pre-runApp. It keeps
//  two broadcast streams the UI can listen on:
//      foregroundMessages — fires for messages received while the app
//                           is in the foreground (we ALSO draw a
//                           system notification — UI can use the
//                           stream for in-app banners on top of that
//                           if it wants).
//      taps              — fires when the user taps a notification
//                           (either while app was backgrounded, was
//                           killed and is now starting up, or tapped
//                           a foreground-drawn local notification).

import 'dart:async';
import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../config/api_config.dart';
import '../network/api_client.dart';
import 'push_reply_handler.dart';
import 'storage_service.dart';

/// Android channel ID for all FCM-driven notifications. Must match
/// the channel created in `android/app/.../MainActivity.kt` and the
/// `com.google.firebase.messaging.default_notification_channel_id`
/// meta-data in AndroidManifest.xml. The OS silently drops any
/// notification targeting a non-existent channel on API 26+.
const String kNotificationChannelId = 'mizdah_general_v1';
const String kNotificationChannelName = 'General notifications';
const String kNotificationChannelDescription =
    'Chats, calls, meetings, and scheduling alerts.';

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

  /// Reconstruct a payload from the JSON blob we encoded into the
  /// flutter_local_notifications payload string (so taps on a
  /// foreground-drawn local notif route exactly like background
  /// taps).
  factory PushPayload.fromLocalPayload(String json) {
    final data = Map<String, dynamic>.from(jsonDecode(json) as Map);
    return PushPayload(
      type: (data['type'] ?? 'chat').toString(),
      conversationId: data['conversation_id'] as String?,
      meetingCode: data['meeting_code'] as String?,
      meetingId: data['meeting_id'] as String?,
      callerUserId: data['caller_user_id'] as String?,
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
  final _localNotifications = FlutterLocalNotificationsPlugin();

  /// Fires for messages received while the app is in the foreground.
  /// FCM does NOT auto-display these — we draw a system notification
  /// via flutter_local_notifications AND emit on this stream so the
  /// UI can additionally render an in-app banner / toast.
  Stream<PushPayload> get foregroundMessages => _foregroundCtrl.stream;

  /// Fires when the user taps a notification — either from the OS
  /// notification tray (app was backgrounded), from a foreground-
  /// drawn local notification, or by launching the app from a cold
  /// start (we replay the launch message here).
  Stream<PushPayload> get taps => _tapCtrl.stream;

  /// The current FCM token. Null until permission is granted and
  /// FCM has issued one.
  String? get token => _token;

  /// Idempotent. Safe to call multiple times — the first call wires
  /// the listeners + requests permission + grabs the token; later
  /// calls are no-ops. This method does NOT initialise Firebase —
  /// that must already have happened in main().
  Future<void> init() async {
    if (_initialised) return;
    _initialised = true;
    try {
      final messaging = FirebaseMessaging.instance;

      // ── 1. iOS foreground presentation ─────────────────────────
      // Tells the iOS OS to show banners / play sound / badge for
      // notifications received while the app is foregrounded. Android
      // ignores these flags (we use flutter_local_notifications for
      // the equivalent on Android).
      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      // ── 2. Permission ──────────────────────────────────────────
      // Android 13+ pops a system POST_NOTIFICATIONS dialog the first
      // time. Pre-13 implicitly granted. iOS pops the standard prompt.
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      debugPrint(
          '[push] permission status=${settings.authorizationStatus.name}');
      // Verbose diagnostic so we can rule permission out as a suspect
      // when a test push doesn't appear.
      final current = await messaging.getNotificationSettings();
      debugPrint('[push] settings: '
          'auth=${current.authorizationStatus.name}, '
          'alert=${current.alert.name}, '
          'badge=${current.badge.name}, '
          'sound=${current.sound.name}, '
          'notificationCenter=${current.notificationCenter.name}, '
          'lockScreen=${current.lockScreen.name}, '
          'criticalAlert=${current.criticalAlert.name}, '
          'announcement=${current.announcement.name}');

      // ── 3. flutter_local_notifications ─────────────────────────
      // Wire up before any onMessage listener so a foreground push
      // received during the same boot has a place to render.
      await _initLocalNotifications();

      // ── 4. Token ───────────────────────────────────────────────
      // May be null briefly after install on iOS until the APNs
      // handshake completes — the onTokenRefresh listener below
      // catches the first real token in that case.
      _token = await messaging.getToken();
      if (_token != null) {
        // Print the FULL token in debug builds so it's easy to
        // copy-paste into the Firebase Console "Test on device"
        // dialog. Release builds print only the prefix.
        debugPrint(kDebugMode
            ? '[push] token=$_token'
            : '[push] token=${_token!.substring(0, 16)}…');
        unawaited(_registerTokenWithBackend(_token!));
      } else {
        debugPrint('[push] token=null (will arrive via onTokenRefresh)');
      }

      messaging.onTokenRefresh.listen((t) async {
        _token = t;
        debugPrint(kDebugMode
            ? '[push] token refreshed=$t'
            : '[push] token refreshed=${t.substring(0, 16)}…');
        unawaited(_registerTokenWithBackend(t));
      });

      // ── 5. Foreground messages ─────────────────────────────────
      // Emit on the broadcast stream AND draw a system notification
      // (FCM doesn't auto-display in foreground).
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

      // ── 6. Background tap → onMessageOpenedApp ────────────────
      // Fires when the user taps the system tray notification while
      // the app was running in the background.
      FirebaseMessaging.onMessageOpenedApp.listen((m) {
        debugPrint('[push] tap (background) data=${m.data}');
        _tapCtrl.add(PushPayload.fromRemote(m));
      });

      // ── 7. Terminated-app launch tap ──────────────────────────
      // If the app was killed and the user tapped a notif to launch
      // us, the launch message is on `getInitialMessage`. Replay it
      // 300ms later so the router + listeners have time to mount.
      final initial = await messaging.getInitialMessage();
      if (initial != null) {
        debugPrint('[push] initial-launch tap data=${initial.data}');
        Future.delayed(const Duration(milliseconds: 300), () {
          _tapCtrl.add(PushPayload.fromRemote(initial));
        });
      }
    } catch (e, st) {
      debugPrint('[push] init failed: $e\n$st');
    }
  }

  // ── flutter_local_notifications setup ────────────────────────────

  Future<void> _initLocalNotifications() async {
    // Use the launcher icon for the small status-bar icon. For a
    // proper monochrome push icon, drop a white-on-transparent PNG
    // in res/drawable/ic_notification and reference it here instead
    // — but ic_launcher renders correctly out of the box.
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');

    // iOS: don't request permissions here — FirebaseMessaging
    // .requestPermission already covered it above. Double-prompting
    // would be jarring. We DO register notification categories: the
    // chat category exposes the [Reply] + [Mark as Read] action
    // buttons under chat banners. Without this category registration,
    // iOS shows the notification but with NO actions — only the
    // tap target.
    // DarwinNotificationAction.text / .plain are factory constructors
    // (not const), so the category + the iOS init settings must be
    // non-const too. Build them once per init — they get cached by
    // the plugin against the category id.
    final chatCategory = DarwinNotificationCategory(
      kChatCategoryId,
      actions: <DarwinNotificationAction>[
        // Inline text-input action — the "Reply" pill that opens an
        // iOS text field directly under the banner. Tapping Send
        // fires `notificationTapBackground` with `resp.actionId =
        // kChatReplyActionId` and `resp.input` = the typed text.
        DarwinNotificationAction.text(
          kChatReplyActionId,
          'Reply',
          buttonTitle: 'Send',
          placeholder: 'Reply…',
          // No `.foreground` — keeps the app backgrounded so the
          // user stays where they are after sending. This is the
          // standard WhatsApp / Telegram behaviour.
          options: const <DarwinNotificationActionOption>{},
        ),
        DarwinNotificationAction.plain(
          kChatMarkReadActionId,
          'Mark as Read',
          options: const <DarwinNotificationActionOption>{
            DarwinNotificationActionOption.destructive,
          },
        ),
      ],
      options: const <DarwinNotificationCategoryOption>{
        DarwinNotificationCategoryOption.hiddenPreviewShowTitle,
      },
    );

    final iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
      notificationCategories: <DarwinNotificationCategory>[chatCategory],
    );

    await _localNotifications.initialize(
      InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: _handleLocalNotificationTap,
      // Top-level @pragma('vm:entry-point') callback — runs in a
      // separate isolate when the user taps a notification action
      // while the app is backgrounded or killed. Handles the
      // [Reply] / [Mark as Read] flows end-to-end (REST call +
      // dismissing the original notification). See
      // lib/core/services/push_reply_handler.dart.
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );

    // Idempotently (re-)create the channel from the Dart side as
    // well. The Kotlin MainActivity also creates it on first launch;
    // having both ensures the channel always exists before the first
    // FCM push, regardless of which init order wins. Channels with
    // the same id are deduped by the OS.
    const channel = AndroidNotificationChannel(
      kNotificationChannelId,
      kNotificationChannelName,
      description: kNotificationChannelDescription,
      importance: Importance.high,
      enableVibration: true,
      enableLights: true,
    );
    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    // Timezone DB — required for `zonedSchedule` (meeting reminders).
    // Idempotent. The data table is bundled with the `timezone`
    // package; `tz.local` defaults to UTC after init, so we override
    // it to the device's IANA name when discoverable.
    if (!_tzInitialised) {
      try {
        tzdata.initializeTimeZones();
        // `DateTime.now().timeZoneName` is an abbreviation on most
        // platforms (e.g. "IST", "PST") — not a valid IANA name —
        // so we can't pass it to `tz.getLocation` directly. Easier:
        // build TZDateTimes against the local offset at fire time
        // (see _tzFromUtc). Leaving tz.local at UTC is fine.
        _tzInitialised = true;
      } catch (e) {
        debugPrint('[push] timezone init failed: $e');
      }
    }
  }

  bool _tzInitialised = false;

  void _handleForegroundMessage(RemoteMessage m) {
    debugPrint('[push] foreground message data=${m.data}');
    _foregroundCtrl.add(PushPayload.fromRemote(m));

    final notif = m.notification;
    final title = notif?.title ?? (m.data['title']?.toString());
    final body = notif?.body ?? (m.data['body']?.toString());
    if (title == null && body == null) {
      // Data-only message with no displayable text — skip the local
      // notification. The onMessage listener already fired so the UI
      // can react (e.g. update an unread badge) without a banner.
      return;
    }

    // ── Platform-specific dedupe rule ─────────────────────────
    // On iOS, the system has ALREADY shown the banner via
    // `userNotificationCenter:willPresent:` in AppDelegate.swift
    // (which we explicitly return `.banner|.sound|.badge` from). If
    // we also call `_localNotifications.show(...)` here, the user
    // sees TWO banners stacked — once from FCM's auto-display, once
    // from our manual draw. So on iOS we early-return: the stream
    // emit above is enough for any in-app reaction (badges,
    // banners-in-our-own-UI), and the OS handles the system banner.
    //
    // On Android, FCM does NOT auto-display foreground messages —
    // we MUST draw the local notification ourselves or the user
    // sees nothing while the app is open.
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      debugPrint('[push] iOS foreground — banner shown by willPresent, '
          'skipping local-notif draw to avoid duplicate');
      return;
    }

    // ── Build the notification with action buttons ────────────
    // Only chat-type messages get the inline-reply / mark-read
    // actions. Calls, meetings, schedule pushes don't need them —
    // they're fire-and-forget alerts.
    final messageType = (m.data['type'] ?? 'chat').toString();
    final isChat = messageType == 'chat';
    final notifId = m.hashCode;

    // Embed the notification id back into the payload so the
    // background isolate (which can't see this notifId) knows
    // which OS notification to dismiss after the reply API call
    // returns. Without this the original notification lingers in
    // the tray even after the user has replied.
    final payloadMap = <String, dynamic>{
      ...m.data,
      '__notif_id': notifId,
    };

    final androidDetails = AndroidNotificationDetails(
      kNotificationChannelId,
      kNotificationChannelName,
      channelDescription: kNotificationChannelDescription,
      icon: '@mipmap/ic_launcher',
      importance: Importance.high,
      priority: Priority.high,
      // Group chat notifications by conversation so multiple
      // unreads from the same thread collapse into one expandable
      // bundle (matches WhatsApp's behaviour).
      groupKey: isChat ? 'mizdah_chat_${m.data['conversation_id'] ?? 'unknown'}' : null,
      actions: isChat
          ? <AndroidNotificationAction>[
              AndroidNotificationAction(
                kChatReplyActionId,
                'Reply',
                allowGeneratedReplies: true,
                showsUserInterface: false,
                // The text-input field that appears when the user
                // taps Reply. `label` is the placeholder; `allowedInputs`
                // is empty → free-form text.
                inputs: <AndroidNotificationActionInput>[
                  AndroidNotificationActionInput(
                    label: 'Reply…',
                  ),
                ],
              ),
              const AndroidNotificationAction(
                kChatMarkReadActionId,
                'Mark as Read',
                showsUserInterface: false,
                cancelNotification: true,
              ),
            ]
          : null,
    );

    final iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      // Attach the chat category we registered in init() so iOS
      // shows the Reply + Mark as Read action buttons. Without
      // this identifier, iOS treats the notification as plain.
      categoryIdentifier: isChat ? kChatCategoryId : null,
      // Group iOS notifications by conversation — pulling them
      // together in Notification Centre.
      threadIdentifier: isChat
          ? 'mizdah_chat_${m.data['conversation_id'] ?? 'unknown'}'
          : null,
    );

    _localNotifications.show(
      notifId,
      title,
      body,
      NotificationDetails(android: androidDetails, iOS: iosDetails),
      // Encode the data payload (including __notif_id) so taps and
      // action invocations have everything they need to act in the
      // background isolate.
      payload: jsonEncode(payloadMap),
    );
  }

  void _handleLocalNotificationTap(NotificationResponse resp) {
    final payload = resp.payload;
    if (payload == null || payload.isEmpty) return;
    try {
      debugPrint('[push] tap (foreground local) payload=$payload');
      _tapCtrl.add(PushPayload.fromLocalPayload(payload));
    } catch (e) {
      debugPrint('[push] local tap payload decode failed: $e');
    }
  }

  // ── Backend registration ────────────────────────────────────────

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

  // ── Scheduled local notifications (meeting reminders) ──────────

  /// Schedule a one-shot local notification to fire at `when`. Used
  /// by the meeting scheduler to remind the user 10 minutes before
  /// (and again at start). No-op when `when` is already past or the
  /// plugin can't initialise.
  ///
  /// `payload` is a JSON blob the tap handler reuses to deep-link
  /// the user into the right route. Pass `{type: 'meeting',
  /// meeting_code: '<code>'}` so the existing `_handleLocalNotificationTap`
  /// routes the same way as a real FCM tap.
  Future<void> scheduleLocalNotification({
    required int id,
    required DateTime when,
    required String title,
    required String body,
    required Map<String, dynamic> payload,
  }) async {
    if (when.isBefore(DateTime.now())) return; // in the past — skip
    try {
      // Make sure the channel + init has already run. `init()` is
      // idempotent so re-calling is harmless if the user hasn't
      // logged in / opened the app yet.
      if (!_initialised) {
        await _initLocalNotifications();
      }
      await _localNotifications.zonedSchedule(
        id,
        title,
        body,
        _tzFromUtc(when),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            kNotificationChannelId,
            kNotificationChannelName,
            channelDescription: kNotificationChannelDescription,
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
        payload: jsonEncode(payload),
        // `inexactAllowWhileIdle` is the right tradeoff for meeting
        // reminders — fires within a few minutes of the scheduled
        // time even in Doze. Use `exactAllowWhileIdle` only if we
        // ever ship a feature that needs second-level precision
        // (it requires SCHEDULE_EXACT_ALARM on Android 13+).
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        // iOS legacy-API flag — required by the plugin signature.
        // `absoluteTime` means "fire at this wall-clock instant",
        // which is what we want for meeting reminders.
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (e) {
      debugPrint('[push] scheduleLocalNotification failed: $e');
    }
  }

  /// Cancel a previously-scheduled local notification. Safe to call
  /// for an id that was never scheduled — the plugin no-ops.
  Future<void> cancelLocalNotification(int id) async {
    try {
      await _localNotifications.cancel(id);
    } catch (e) {
      debugPrint('[push] cancelLocalNotification failed: $e');
    }
  }

  /// Convert a UTC `DateTime` to the `TZDateTime` the plugin needs.
  /// We build it against `tz.local` (which after init either points
  /// at the device's IANA zone or falls back to UTC) and pass the
  /// device-local wall-clock fields. The plugin uses these to
  /// schedule against the device's clock, so the notification fires
  /// at the right wall-clock instant regardless of timezone.
  tz.TZDateTime _tzFromUtc(DateTime utc) {
    final local = utc.toLocal();
    return tz.TZDateTime(
      tz.local,
      local.year,
      local.month,
      local.day,
      local.hour,
      local.minute,
      local.second,
    );
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
