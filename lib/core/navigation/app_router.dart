import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/home/presentation/splash_screen.dart';
import '../../features/call/presentation/start_call_screen.dart';
import '../../features/call/presentation/schedule_screen.dart';
import '../../features/call/presentation/call_hub_screen.dart';
import '../../features/call/presentation/p2p_call_screen.dart';
import '../../features/meetings/presentation/meetings_screen.dart';
import '../../features/people/presentation/people_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/settings/presentation/privacy_screen.dart';
import '../../features/settings/presentation/report_screen.dart';
import '../../features/settings/presentation/meeting_settings_screen.dart';
import '../../features/meeting/presentation/meeting_room_screen.dart';
import '../../features/meeting/presentation/pre_join_screen.dart';
import '../../features/meeting/presentation/meeting_designs_preview.dart';
import '../../features/meeting/presentation/screen_share_designs_preview.dart';
import '../../features/meeting/presentation/recordings_list_screen.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/register_screen.dart';
import '../../features/auth/two_factor_screen.dart';

/// Smooth fade-through transition for the five floating-nav tabs.
/// Material 3 calls this "shared axis (fade-through)" — the outgoing
/// page fades + scales out as the incoming one fades + scales in,
/// instead of the abrupt no-transition default go_router uses.
CustomTransitionPage<void> _tabPage(
  GoRouterState state,
  Widget child,
) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 260),
    reverseTransitionDuration: const Duration(milliseconds: 220),
    transitionsBuilder: (context, animation, secondary, child) {
      // Outgoing page (secondary > 0): fade + 4 % shrink.
      // Incoming page (animation): fade + 2 % grow from below.
      final outFade =
          Tween<double>(begin: 1, end: 0).animate(CurvedAnimation(
        parent: secondary,
        curve: const Interval(0, 0.45, curve: Curves.easeIn),
      ));
      final outScale =
          Tween<double>(begin: 1, end: 0.96).animate(CurvedAnimation(
        parent: secondary,
        curve: Curves.easeOut,
      ));
      final inFade = Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(
        parent: animation,
        curve: const Interval(0.35, 1, curve: Curves.easeOut),
      ));
      final inScale =
          Tween<double>(begin: 1.02, end: 1).animate(CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      ));
      return FadeTransition(
        opacity: outFade,
        child: ScaleTransition(
          scale: outScale,
          child: FadeTransition(
            opacity: inFade,
            child: ScaleTransition(scale: inScale, child: child),
          ),
        ),
      );
    },
  );
}

final appRouter = GoRouter(
  initialLocation: '/splash',
  redirect: (context, state) {
    // Basic redirect logic if needed, but usually handled by AuthProvider listeners in screens
    return null;
  },
  routes: [
    GoRoute(path: '/splash', builder: (context, state) => const SplashScreen()),
    GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
    GoRoute(path: '/register', builder: (context, state) => const RegisterScreen()),
    GoRoute(path: '/2fa', builder: (context, state) => const TwoFactorScreen()),
    // ── Five floating-nav tabs — all use the fade-through transition.
    GoRoute(
      path: '/',
      pageBuilder: (context, state) => _tabPage(state, const HomeScreen()),
    ),
    GoRoute(
      path: '/meetings',
      pageBuilder: (context, state) {
        // `?tab=recent` deep-links the Recent segment, used by the
        // home screen's "View all" link on the Recent Activity card.
        final tab = state.uri.queryParameters['tab'];
        return _tabPage(
          state,
          MeetingsScreen(initialSegment: tab == 'recent' ? 1 : 0),
        );
      },
    ),
    GoRoute(
      path: '/call-hub',
      pageBuilder: (context, state) =>
          _tabPage(state, const CallHubScreen()),
    ),
    GoRoute(
      path: '/people',
      pageBuilder: (context, state) =>
          _tabPage(state, const PeopleScreen()),
    ),
    GoRoute(
      path: '/settings',
      pageBuilder: (context, state) =>
          _tabPage(state, const SettingsScreen()),
    ),

    // ── Non-tab routes — keep go_router's default Material transition.
    GoRoute(path: '/start-call', builder: (context, state) => const StartCallScreen()),
    GoRoute(path: '/schedule', builder: (context, state) => const ScheduleScreen()),
    GoRoute(path: '/p2p-call', builder: (context, state) => const P2PCallScreen()),
    GoRoute(
      path: '/meeting-settings/:id',
      builder: (context, state) => MeetingSettingsScreen(meetingId: state.pathParameters['id']!),
    ),
    GoRoute(path: '/report', builder: (context, state) => const ReportScreen()),
    GoRoute(path: '/privacy', builder: (context, state) => const PrivacyScreen()),
    GoRoute(
      path: '/pre-join',
      builder: (context, state) => const PreJoinScreen(),
    ),
    GoRoute(
      path: '/pre-join/:id',
      builder: (context, state) => PreJoinScreen(meetingId: state.pathParameters['id']),
    ),
    GoRoute(
      path: '/meeting-designs',
      builder: (context, state) => const MeetingDesignsPreviewScreen(),
    ),
    GoRoute(
      path: '/screen-share-designs',
      builder: (context, state) => const ScreenShareDesignsPreviewScreen(),
    ),
    GoRoute(
      path: '/recordings/:code',
      builder: (context, state) => RecordingsListScreen(
        meetingCode: state.pathParameters['code']!,
      ),
    ),
    GoRoute(
      path: '/meeting/:id',
      builder: (context, state) {
        final video = state.uri.queryParameters['video'] == 'true';
        final audio = state.uri.queryParameters['audio'] == 'true';
        // `host=true` is a fast-path hint passed by pre-join when the
        // user just created an instant meeting (so we know they're the
        // host without waiting for the REST round-trip). Lets the
        // meeting provider fire SFU bootstrap immediately.
        final isHostHint = state.uri.queryParameters['host'] == 'true';
        return MeetingRoomScreen(
          meetingId: state.pathParameters['id']!,
          initialVideo: video,
          initialAudio: audio,
          isHostHint: isHostHint,
        );
      },
    ),
  ],
);
