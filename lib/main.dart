import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/services/push_notification_service.dart';
import 'core/theme/theme_provider.dart';
import 'core/navigation/app_router.dart';
import 'core/ui/mizdah_design.dart' show MizdahScrollBehavior;
import 'features/call/presentation/p2p_incoming_overlay.dart';
import 'firebase_options.dart';

/// FCM background-message handler. Must be a TOP-LEVEL function (not
/// a closure / method) because Android spawns a separate isolate for
/// it and only top-level entry points can be referenced from there.
///
/// Don't do heavy work here — Android kills the isolate after a few
/// seconds. The OS already displays the system notification when the
/// payload has a `notification` block; this hook is for analytics /
/// silent-data side-effects (e.g. pre-fetching the message body so
/// the app is warm when the user taps).
@pragma('vm:entry-point')
Future<void> _firebaseBackgroundMessageHandler(RemoteMessage message) async {
  // Initialise Firebase in the background isolate — required because
  // `main()` ran in a different isolate and the bindings don't carry.
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  debugPrint('[push] background message data=${message.data}');
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── Edge-to-edge layout ────────────────────────────────────────
  // Without this, Android draws opaque black bars behind the
  // status bar and gesture-nav so the app never reaches the screen
  // edges. `edgeToEdge` lets the lavender background flow under
  // both system bars; `SafeArea` widgets inside each screen still
  // protect interactive content from being clipped.
  await SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.edgeToEdge,
    // Empty overlays list = nothing forced visible; the OS still
    // shows status bar + gesture pill, but on top of our content.
  );

  // ── Dev-only: trust self-signed certs from local backend hosts ──
  // The local backend at https://192.168.1.18:3001 (and similar
  // 192.168.x.x dev boxes) typically presents a self-signed cert
  // that Dart's HttpClient rejects with CERTIFICATE_VERIFY_FAILED.
  //
  // Override the verifier ONLY for kDebugMode AND ONLY for hosts
  // that look like local-network dev boxes — production traffic to
  // mizdah-backend.ogoul.cloud still gets full TLS validation, and
  // release builds never see this code path at all (the kDebugMode
  // tree-shakes out).
  //
  // Covers Dio + socket_io_client (both delegate to dart:io's
  // HttpClient under the hood, which respects HttpOverrides.global).
  if (kDebugMode) {
    HttpOverrides.global = _DevHttpOverrides();
  }

  // ── Firebase + push notifications ─────────────────────────────
  // Initialised before runApp so the app sees notifications fired
  // during the launch boot. Errors are swallowed to keep the app
  // bootable even when Firebase is misconfigured (e.g. missing
  // google-services.json on a fresh checkout).
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundMessageHandler);
    // Wire the foreground / tap listeners + permission prompt + token
    // registration. Doesn't block runApp — the rest is a Future.
    unawaited(PushNotificationService.instance.init());
  } catch (e) {
    debugPrint('[push] Firebase init failed: $e');
  }

  runApp(const ProviderScope(child: MizdahApp()));
}

/// Trusts self-signed certs from local-network dev hosts in debug
/// builds. Any non-dev host falls through to default verification.
class _DevHttpOverrides extends HttpOverrides {
  // Hosts whose self-signed certs we accept in dev. Add new dev
  // boxes here as needed.
  static const _trustedDevHosts = <String>{
    '192.168.1.18',
    '192.168.1.100',
    '192.168.1.48',
    '192.168.1.117',
    'localhost',
    '127.0.0.1',
    '10.0.2.2', // Android emulator → host loopback
  };

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (cert, host, port) {
        final trusted = _trustedDevHosts.contains(host);
        if (trusted) {
          debugPrint('[HTTPS] accepting self-signed cert for dev host '
              '$host:$port (subject=${cert.subject})');
        } else {
          debugPrint('[HTTPS] REJECTING bad cert for $host:$port '
              '(not in dev allowlist)');
        }
        return trusted;
      };
  }
}

class MizdahApp extends ConsumerStatefulWidget {
  const MizdahApp({super.key});

  @override
  ConsumerState<MizdahApp> createState() => _MizdahAppState();
}

class _MizdahAppState extends ConsumerState<MizdahApp> {
  StreamSubscription<PushPayload>? _tapSub;

  @override
  void initState() {
    super.initState();
    // Notification taps deep-link into the app. The router is
    // already mounted by the time the first emission fires (the
    // service deliberately delays the initial-launch tap by 300ms
    // exactly so this listener can attach first).
    _tapSub = PushNotificationService.instance.taps.listen(_handleTap);
  }

  @override
  void dispose() {
    _tapSub?.cancel();
    super.dispose();
  }

  void _handleTap(PushPayload p) {
    debugPrint('[push] routing tap type=${p.type} data=${p.raw}');
    switch (p.type) {
      case 'chat':
        if (p.conversationId != null) {
          appRouter.push('/chats/${p.conversationId}');
        } else {
          appRouter.go('/chats');
        }
        break;
      case 'call':
        // P2P incoming-call signaling already flows over the socket
        // when the app is running; the push is mainly a wake-up.
        // If the user tapped the notif we want to land on the
        // pre-join / call screen so the incoming-call overlay can
        // present accept/decline UI.
        appRouter.push('/p2p-call');
        break;
      case 'meeting':
        if (p.meetingCode != null) {
          appRouter.push('/pre-join/${p.meetingCode}');
        } else {
          appRouter.push('/pre-join');
        }
        break;
      case 'schedule':
        appRouter.go('/meetings?tab=upcoming');
        break;
      default:
        // Unknown type — open the app on Home; the notification
        // tray badge tells the user *something* happened.
        appRouter.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeProvider);

    return MaterialApp.router(
      title: 'Mizdah',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: MizdahTheme.lightTheme,
      darkTheme: MizdahTheme.darkTheme,
      routerConfig: appRouter,
      // App-wide rigid scrolling — kills iOS bounce + Android
      // stretch overscroll. Every ListView / SingleChildScrollView
      // anywhere in the app inherits this unless it explicitly
      // overrides `physics:`.
      scrollBehavior: const MizdahScrollBehavior(),
      // Wrap every route in:
      //   1) An `AnnotatedRegion` that forces the OS system bars
      //      transparent so the app's gradient flows behind them.
      //      The icon brightness is derived from the active theme.
      //   2) The incoming-call overlay so a ringing P2P call can
      //      interrupt the user from any screen.
      builder: (context, child) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            // Status bar (top)
            statusBarColor: Colors.transparent,
            statusBarIconBrightness:
                isDark ? Brightness.light : Brightness.dark,
            statusBarBrightness:
                isDark ? Brightness.dark : Brightness.light,
            // Gesture nav bar (bottom)
            systemNavigationBarColor: Colors.transparent,
            systemNavigationBarIconBrightness:
                isDark ? Brightness.light : Brightness.dark,
            systemNavigationBarDividerColor: Colors.transparent,
            systemNavigationBarContrastEnforced: false,
          ),
          child: P2PIncomingOverlay(
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
    );
  }
}
