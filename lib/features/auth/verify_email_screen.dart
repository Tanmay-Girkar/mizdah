// ════════════════════════════════════════════════════════════════════
//  Verify email — post-signup landing page
//  ────────────────────────────────────────────────────────────────────
//  Pushed by the register screen the moment the backend confirms the
//  account was created but flagged `requiresVerification: true`. The
//  user can't log in until they tap the link in the verification
//  email, so we lock the flow on a dedicated screen instead of
//  silently dropping back to /login with a stale form.
//
//  Receives the signup email via GoRouterState.extra (preferred) or
//  the ?email= query parameter (fallback). Displays the email so the
//  user knows which inbox to check.
// ════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/theme_provider.dart';
import '../../core/ui/mizdah_design.dart';
import '../../core/widgets/glass_card.dart';
import '../../core/widgets/mizdah_button.dart';

class VerifyEmailScreen extends ConsumerWidget {
  const VerifyEmailScreen({super.key});

  String _readEmail(BuildContext context) {
    final state = GoRouterState.of(context);
    final extra = state.extra;
    if (extra is Map && extra['email'] is String) {
      return extra['email'] as String;
    }
    final q = state.uri.queryParameters['email'];
    return q ?? '';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final email = _readEmail(context);
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: isDark ? MizdahTheme.darkGradient : null,
          color: isDark ? null : MizdahTheme.lightBackground,
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Big celebratory glyph — sets the tone that this
                  // is a SUCCESS, not an error. Gradient circle
                  // matches the brand hero gradient used elsewhere.
                  Container(
                    width: 96,
                    height: 96,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: MizdahTokens.heroGradient,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: MizdahTokens.primary.withValues(alpha: 0.40),
                          blurRadius: 24,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.mark_email_read_rounded,
                      color: Colors.white,
                      size: 44,
                    ),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    'Check your email',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    "We've sent a verification link to",
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                  ),
                  if (email.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      email,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: isDark ? Colors.white : Colors.black87,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    'Tap the link in the email to activate your account, '
                    'then come back here and sign in.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: isDark ? Colors.white60 : Colors.black54,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 32),
                  GlassCard(
                    child: Column(
                      children: [
                        MizdahButton(
                          label: 'Go to Sign In',
                          onTap: () => context.go('/login'),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          "Didn't get the email? Check your spam folder, "
                          'or try signing in — we can re-send the link.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: isDark ? Colors.white54 : Colors.black45,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
