import Flutter
import UIKit
import FirebaseCore
import FirebaseMessaging
import UserNotifications

/// AppDelegate — boots Firebase early, registers the device for
/// remote notifications, and wires the UNUserNotificationCenter
/// delegate so iOS can deliver foreground / tap callbacks into the
/// Flutter side via the firebase_messaging plugin.
///
/// Why each piece matters:
///
///   • `FirebaseApp.configure()` MUST run before plugin registration.
///     The firebase_messaging plugin builds its method-channel and
///     swizzles APNs callbacks during `register(with:)`; without
///     a configured FirebaseApp it logs a warning and runs in a
///     degraded mode where `Messaging.messaging().apnsToken` is
///     never set — which is exactly the `[firebase_messaging/
///     apns-token-not-set]` error the user reported.
///
///   • `UNUserNotificationCenter.current().delegate = self` makes
///     this class the system delegate. `FlutterAppDelegate` already
///     conforms to `UNUserNotificationCenterDelegate` (via the
///     Flutter framework) and forwards `willPresent` / `didReceive`
///     into the firebase_messaging plugin. Without setting the
///     delegate, those callbacks go unhandled and the Flutter
///     `onMessage` / tap streams stay silent.
///
///   • `application.registerForRemoteNotifications()` is what tells
///     iOS "hand me an APNs device token." Without this call the
///     OS never invokes `didRegisterForRemoteNotificationsWithDeviceToken`,
///     so Firebase never receives an APNs token, so `getToken()`
///     throws `apns-token-not-set` forever.
///
///   • The explicit override of `didRegisterForRemoteNotificationsWithDeviceToken`
///     is defensive: the FlutterFire plugin tries to swizzle this
///     callback, but the swizzle has historically broken with new
///     Flutter / Firebase versions. Setting `Messaging.messaging().apnsToken`
///     ourselves makes the wiring robust to that drift.
///
///   • `FlutterImplicitEngineDelegate` is the project's existing
///     plugin-registration mechanism — kept as-is so we don't
///     change unrelated behaviour.
@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // 1. Configure Firebase BEFORE plugin registration. Idempotent —
    //    calling .configure() a second time logs a warning but
    //    doesn't crash, so it's safe even if some other path also
    //    initialises Firebase.
    if FirebaseApp.app() == nil {
      FirebaseApp.configure()
    }

    // 2. Take ownership of the notification-centre delegate so iOS
    //    delivers tap + foreground callbacks into us → which
    //    FlutterAppDelegate forwards into firebase_messaging.
    UNUserNotificationCenter.current().delegate = self

    // 3. Ask iOS to mint an APNs token. We DON'T request permission
    //    here — the Dart side (`PushNotificationService.init`)
    //    already pops the permission dialog via
    //    `FirebaseMessaging.requestPermission(...)`, and calling
    //    `registerForRemoteNotifications` BEFORE permission is
    //    granted is fine: iOS just queues the registration and
    //    fulfils it the moment the user taps Allow. If the user
    //    denies, we never get a token (correct — no permission).
    application.registerForRemoteNotifications()

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  /// Explicit pass-through to make sure FirebaseMessaging gets the
  /// APNs token even if the plugin's swizzle ever misfires. Without
  /// this override, the swizzle is the only thing setting
  /// `Messaging.messaging().apnsToken` — and if the swizzle fails
  /// silently (it has, on some Flutter+Firebase version combos),
  /// the token never reaches Firebase and `getToken()` throws.
  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    Messaging.messaging().apnsToken = deviceToken
    NSLog("[push] APNs token registered (length=%d)", deviceToken.count)
    super.application(
      application,
      didRegisterForRemoteNotificationsWithDeviceToken: deviceToken
    )
  }

  /// Log APNs registration failures so they're easy to spot in
  /// device logs. The most common cause is running on the iOS
  /// simulator pre-Xcode-14 (no APNs there); the next most common
  /// is a missing / mis-signed Push Notifications entitlement.
  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    NSLog("[push] APNs registration FAILED: %@", error.localizedDescription)
    super.application(
      application,
      didFailToRegisterForRemoteNotificationsWithError: error
    )
  }

  // ─── Foreground notification presentation ─────────────────────
  //
  // The whole reason this override exists: iOS does NOT auto-show
  // notifications while the app is in the foreground (unlike
  // Android). The OS calls this method to ask "should I display
  // this banner / play this sound / update the badge?" — and if
  // we return `[]` or never respond, the notification is silently
  // swallowed and the user sees nothing.
  //
  // We previously relied on the Dart-side
  // `FirebaseMessaging.setForegroundNotificationPresentationOptions(
  //   alert: true, badge: true, sound: true)`
  // to push these options through the firebase_messaging plugin's
  // swizzled `willPresent`. That swizzle is fragile: it can collide
  // with flutter_local_notifications' own delegate registration,
  // and when there are two `UNUserNotificationCenterDelegate`
  // claimants in the runtime, one of them wins and the other's
  // options get dropped.
  //
  // Implementing `willPresent` directly in AppDelegate sidesteps the
  // race entirely — this Swift method runs FIRST in the responder
  // chain, so whatever we hand to `completionHandler` is what iOS
  // displays.
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler:
      @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    let userInfo = notification.request.content.userInfo
    NSLog("[push] foreground notification: %@", userInfo)
    // Show banner + play sound + update badge. `.list` keeps a copy
    // in Notification Centre so the user can revisit it after
    // dismissing the banner — matches WhatsApp's behaviour.
    if #available(iOS 14.0, *) {
      completionHandler([.banner, .list, .sound, .badge])
    } else {
      // iOS 13 — pre-banner API: `.alert` is the umbrella option
      // that covers banner display on older systems.
      completionHandler([.alert, .sound, .badge])
    }
  }

  // ─── Notification-tap callback ────────────────────────────────
  //
  // Fired when the user taps a delivered notification from
  // Notification Centre / a banner. We just log here — the Dart
  // side's `FirebaseMessaging.onMessageOpenedApp` listener is the
  // one that routes the tap into the right screen (chat thread,
  // meeting pre-join, etc.). Calling super hands control back to
  // the firebase_messaging plugin's swizzled `didReceive`, which is
  // what posts the event to the Dart stream.
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    NSLog("[push] notification tapped: %@",
          response.notification.request.content.userInfo)
    super.userNotificationCenter(
      center,
      didReceive: response,
      withCompletionHandler: completionHandler
    )
  }
}
