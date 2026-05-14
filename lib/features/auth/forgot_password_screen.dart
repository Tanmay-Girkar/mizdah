// ════════════════════════════════════════════════════════════════════
//  Forgot password — request reset email
//  ────────────────────────────────────────────────────────────────────
//  Reachable from:
//    • Login screen → "Forgot password?" link
//    • Change-password sheet → "Forgot your password?" link
//
//  The user types their email, taps Send, the backend either emails
//  them a reset link or silently does nothing — we get back the
//  same 200 either way (anti-enumeration, see
//  docs/PASSWORD_CHANGE_AND_RESET_BACKEND.md §4.2).
//
//  The UI mirrors that: after a successful POST we ALWAYS show the
//  generic "If an account exists for that email, we sent a reset
//  link" confirmation. Doesn't matter whether the email was real.
// ════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/theme_provider.dart';
import '../../core/ui/mizdah_design.dart';
import '../../core/widgets/glass_card.dart';
import '../../core/widgets/mizdah_button.dart';
import '../../core/widgets/mizdah_text_field.dart';
import '../../data/repositories/auth_repository.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState
    extends ConsumerState<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final AuthRepository _authRepo = AuthRepository();

  bool _emailPrefilled = false;
  bool _busy = false;
  bool _sent = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_emailPrefilled) return;
    final state = GoRouterState.of(context);
    final extra = state.extra;
    if (extra is Map && extra['email'] is String) {
      _emailController.text = extra['email'] as String;
    }
    _emailPrefilled = true;
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _onSend() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _authRepo.forgotPassword(_emailController.text.trim());
      if (!mounted) return;
      setState(() {
        _busy = false;
        _sent = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not send. Check your connection and retry.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: isDark ? MizdahTheme.darkGradient : null,
          color: isDark ? null : MizdahTheme.lightBackground,
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: _sent ? _SentConfirmation() : _form(theme, isDark),
            ),
          ),
        ),
      ),
    );
  }

  Widget _form(ThemeData theme, bool isDark) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 84,
          height: 84,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: MizdahTokens.heroGradient,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: MizdahTokens.primary.withValues(alpha: 0.35),
                blurRadius: 22,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Icon(Icons.lock_reset_rounded,
              color: Colors.white, size: 40),
        ),
        const SizedBox(height: 18),
        Text(
          'Reset your password',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          "Enter the email on your Mizdah account and we'll send "
          'a link to set a new password.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: isDark ? Colors.white70 : Colors.black54,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 28),
        GlassCard(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MizdahTextField(
                  label: 'Email',
                  hintText: 'you@example.com',
                  controller: _emailController,
                  prefixIcon: Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                  validator: (val) =>
                      (val == null || !val.contains('@'))
                          ? 'Enter a valid email'
                          : null,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(Icons.error_outline_rounded,
                          color: Colors.redAccent, size: 14),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _error!,
                          style: const TextStyle(
                            color: Colors.redAccent,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 24),
                MizdahButton(
                  label: 'Send reset link',
                  onTap: _busy ? null : _onSend,
                  isLoading: _busy,
                ),
                const SizedBox(height: 14),
                Center(
                  child: TextButton(
                    onPressed: () => context.pop(),
                    child: const Text('Back to Sign In'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Shown after the POST succeeds. Same copy regardless of whether
/// the email actually exists — see anti-enumeration note in the
/// file header.
class _SentConfirmation extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
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
          child: const Icon(Icons.mark_email_read_rounded,
              color: Colors.white, size: 44),
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
        const SizedBox(height: 8),
        Text(
          'If an account exists for that email, we sent a reset link. '
          'It expires in 15 minutes and can only be used once.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: isDark ? Colors.white70 : Colors.black54,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 28),
        GlassCard(
          child: MizdahButton(
            label: 'Back to Sign In',
            onTap: () => context.go('/login'),
          ),
        ),
      ],
    );
  }
}
