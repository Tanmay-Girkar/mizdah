import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../ui/mizdah_design.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/home/presentation/splash_screen.dart';
import '../../features/call/presentation/start_call_screen.dart';
import '../../features/call/presentation/schedule_screen.dart';
import '../../features/call/presentation/call_hub_screen.dart';
import '../../features/call/presentation/p2p_call_screen.dart';
import '../../features/meetings/presentation/meetings_screen.dart';
import '../../features/chats/presentation/chats_screen.dart';
import '../../features/chats/presentation/chat_detail_screen.dart';
import '../../features/chats/presentation/new_chat_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/settings/presentation/privacy_screen.dart';
import '../../features/settings/presentation/report_screen.dart';
import '../../features/settings/presentation/meeting_settings_screen.dart';
import '../../features/settings/presentation/meeting_preferences_screen.dart';
import '../../features/settings/presentation/edit_profile_screen.dart';
import '../../features/settings/presentation/about_screen.dart';
import '../../features/meeting/presentation/meeting_room_screen.dart';
import '../../features/meeting/presentation/pre_join_screen.dart';
import '../../features/meeting/presentation/meeting_designs_preview.dart';
import '../../features/meeting/presentation/screen_share_designs_preview.dart';
import '../../features/meeting/presentation/recordings_list_screen.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/register_screen.dart';
import '../../features/auth/two_factor_screen.dart';

/// "No transition" page builder used by the five tab branches.
///
/// With `StatefulShellRoute.indexedStack` the IndexedStack itself
/// keeps every tab mounted and switching is an instant visibility
/// flip — there's no transition needed. We override the page
/// builder so go_router doesn't run its default Material slide
/// when go_router rebuilds the active branch.
NoTransitionPage<void> _branchPage(GoRouterState state, Widget child) {
  return NoTransitionPage<void>(key: state.pageKey, child: child);
}

final appRouter = GoRouter(
  initialLocation: '/splash',
  redirect: (context, state) {
    // Basic redirect logic if needed, but usually handled by
    // AuthProvider listeners in screens.
    return null;
  },
  routes: [
    // ── Auth + splash (no shell) ──────────────────────────────
    GoRoute(path: '/splash', builder: (context, state) => const SplashScreen()),
    GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
    GoRoute(path: '/register', builder: (context, state) => const RegisterScreen()),
    GoRoute(path: '/2fa', builder: (context, state) => const TwoFactorScreen()),

    // ── Five tab branches inside a shared StatefulShell ──────
    //
    // Each branch is a separate Navigator that keeps its own
    // navigation history + scroll state. The shell renders an
    // IndexedStack of the five branches and the floating nav,
    // so switching tabs is a near-instant visibility flip with
    // zero rebuilds and zero flicker (the WhatsApp / Telegram
    // / iOS native pattern).
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          MizdahTabsShell(navigationShell: navigationShell),
      branches: [
        // Branch 0 — Meetings (flat tab on the left edge,
        // deep-linkable via ?tab=recent)
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/meetings',
              pageBuilder: (context, state) {
                final tab = state.uri.queryParameters['tab'];
                return _branchPage(
                  state,
                  MeetingsScreen(
                    initialSegment: tab == 'recent' ? 1 : 0,
                  ),
                );
              },
            ),
          ],
        ),
        // Branch 1 — Chats
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/chats',
              pageBuilder: (context, state) =>
                  _branchPage(state, const ChatsScreen()),
            ),
          ],
        ),
        // Branch 2 — Home (prominent centre tab)
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/',
              pageBuilder: (context, state) =>
                  _branchPage(state, const HomeScreen()),
            ),
          ],
        ),
        // Branch 3 — Call hub
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/call-hub',
              pageBuilder: (context, state) =>
                  _branchPage(state, const CallHubScreen()),
            ),
          ],
        ),
        // Branch 4 — Settings
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/settings',
              pageBuilder: (context, state) =>
                  _branchPage(state, const SettingsScreen()),
            ),
          ],
        ),
      ],
    ),

    // ── Non-tab routes — open above the shell with the default
    //    Material slide so push/pop still feels native. ────────
    GoRoute(path: '/start-call', builder: (context, state) => const StartCallScreen()),
    GoRoute(path: '/schedule', builder: (context, state) => const ScheduleScreen()),
    GoRoute(path: '/p2p-call', builder: (context, state) => const P2PCallScreen()),
    GoRoute(
      path: '/meeting-settings/:id',
      builder: (context, state) => MeetingSettingsScreen(meetingId: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/chats/new',
      builder: (context, state) => const NewChatScreen(),
    ),
    GoRoute(
      path: '/chats/:id',
      builder: (context, state) => ChatDetailScreen(
        conversationId: state.pathParameters['id']!,
      ),
    ),
    GoRoute(path: '/report', builder: (context, state) => const ReportScreen()),
    GoRoute(path: '/privacy', builder: (context, state) => const PrivacyScreen()),
    GoRoute(
      path: '/meeting-preferences',
      builder: (context, state) => const MeetingPreferencesScreen(),
    ),
    GoRoute(
      path: '/edit-profile',
      builder: (context, state) => const EditProfileScreen(),
    ),
    GoRoute(
      path: '/about',
      builder: (context, state) => const AboutScreen(),
    ),
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
        // `host=true` is a fast-path hint passed by pre-join when
        // the user just created an instant meeting (so we know
        // they're the host without waiting for the REST round-trip).
        // Lets the meeting provider fire SFU bootstrap immediately.
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
