import 'package:go_router/go_router.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/home/presentation/splash_screen.dart';
import '../../features/call/presentation/start_call_screen.dart';
import '../../features/call/presentation/schedule_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/settings/presentation/privacy_screen.dart';
import '../../features/settings/presentation/report_screen.dart';
import '../../features/settings/presentation/meeting_settings_screen.dart';
import '../../features/meeting/presentation/meeting_room_screen.dart';
import '../../features/meeting/presentation/pre_join_screen.dart';
import '../../features/meeting/presentation/meeting_designs_preview.dart';
import '../../features/meeting/presentation/screen_share_designs_preview.dart';
import '../../features/home/presentation/home_designs_preview.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/register_screen.dart';
import '../../features/auth/two_factor_screen.dart';

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
    GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
    GoRoute(path: '/start-call', builder: (context, state) => const StartCallScreen()),
    GoRoute(path: '/schedule', builder: (context, state) => const ScheduleScreen()),
    GoRoute(path: '/settings', builder: (context, state) => const SettingsScreen()),
    GoRoute(
      path: '/meeting-settings/:id', 
      builder: (context, state) => MeetingSettingsScreen(meetingId: state.pathParameters['id']!)
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
      path: '/home-designs',
      builder: (context, state) => const HomeDesignsPreviewScreen(),
    ),
    GoRoute(
      path: '/meeting/:id',
      builder: (context, state) {
        final video = state.uri.queryParameters['video'] == 'true';
        final audio = state.uri.queryParameters['audio'] == 'true';
        return MeetingRoomScreen(
          meetingId: state.pathParameters['id']!,
          initialVideo: video,
          initialAudio: audio,
        );
      },
    ),
  ],
);
