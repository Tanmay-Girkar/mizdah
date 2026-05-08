import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/theme_provider.dart';
import 'core/navigation/app_router.dart';
import 'features/call/presentation/p2p_incoming_overlay.dart';

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
  // The local backend at https://192.168.1.48:3001 (and similar
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

  runApp(const ProviderScope(child: MizdahApp()));
}

/// Trusts self-signed certs from local-network dev hosts in debug
/// builds. Any non-dev host falls through to default verification.
class _DevHttpOverrides extends HttpOverrides {
  // Hosts whose self-signed certs we accept in dev. Add new dev
  // boxes here as needed.
  static const _trustedDevHosts = <String>{
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

class MizdahApp extends ConsumerWidget {
  const MizdahApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);

    return MaterialApp.router(
      title: 'Mizdah',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: MizdahTheme.lightTheme,
      darkTheme: MizdahTheme.darkTheme,
      routerConfig: appRouter,
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
