// ════════════════════════════════════════════════════════════════════
//  Reset password — consume email-link token + set new password
//  ────────────────────────────────────────────────────────────────────
//  Reached via the deep link in the reset email:
//
//      https://mizdah.app/reset-password?token=<RAW_TOKEN>
//
//  The token also arrives via `GoRouterState.extra` if the screen is
//  pushed programmatically (e.g. from a future deep-link handler);
//  the query parameter is the canonical source.
//
//  POSTs to /api/auth/reset-password (spec §5). On success the
//  backend returns a fresh JWT + user — we drop the user straight
//  onto Home so they don't have to log in again.
// ════════════════════════════════════════════════════════════════════

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/theme_provider.dart';
import '../../core/ui/mizdah_design.dart';
import '../../core/widgets/glass_card.dart';
import '../../core/widgets/mizdah_button.dart';
import '../../core/widgets/mizdah_text_field.dart';
import '../../data/repositories/auth_repository.dart';
import 'auth_provider.dart';

class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState
    extends ConsumerState<ResetPasswordScreen> {
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final AuthRepository _authRepo = AuthRepository();

  String? _token;
  bool _busy = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_token != null) return;
    final state = GoRouterState.of(context);
    String? token = state.uri.queryParameters['token'];
    if ((token == null || token.isEmpty) && state.extra is Map) {
      final extra = state.extra as Map;
      token = extra['token']?.toString();
    }
    _token = token;
  }

  @override
  void dispose() {
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _onSubmit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_newCtrl.text != _confirmCtrl.text) {
      setState(() => _error = 'Passwords do not match');
      return;
    }
    final token = _token;
    if (token == null || token.isEmpty) {
      setState(() => _error =
          'Reset link is missing. Open the link from your email again.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await _authRepo.resetPassword(
        token: token,
        newPassword: _newCtrl.text,
      );
      // The notifier handles secure-storage persistence + FCM token
      // registration; we just hand it the fresh JWT + user.
      await ref.read(authProvider.notifier).adoptResetPasswordSession(
            token: result.token,
            user: result.user,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password reset. You are signed in.')),
      );
      // Defer the nav so the form's controllers finish their build
      // cycle before the route unmounts.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        context.go('/');
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _mapResetError(e);
      });
    }
  }

  String _mapResetError(Object e) {
    if (e is DioException) {
      final body = e.response?.data;
      final code = body is Map ? body['code']?.toString() : null;
      switch (code) {
        case 'TOKEN_INVALID':
          return "Reset link isn't valid. Request a new one.";
        case 'TOKEN_ALREADY_USED':
          return 'This reset link has already been used.';
        case 'TOKEN_EXPIRED':
          return 'Reset link has expired. Request a new one.';
        case 'WEAK_PASSWORD':
          return 'Password must be at least 8 characters.';
        case 'RATE_LIMITED':
          return 'Too many attempts. Try again later.';
      }
      final human = body is Map
          ? (body['error']?.toString() ?? body['message']?.toString())
          : null;
      if (human != null && human.isNotEmpty) return human;
    }
    return 'Could not reset password. Try again.';
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
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 84,
                    height: 84,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: MizdahTokens.heroGradient,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.lock_reset_rounded,
                        color: Colors.white, size: 40),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Set a new password',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Enter your new password. It must be at least '
                    '8 characters. You\'ll be signed in once it\'s saved.',
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
                            label: 'New password',
                            hintText: 'Enter new password',
                            controller: _newCtrl,
                            prefixIcon: Icons.lock_outline,
                            isPassword: true,
                            validator: (val) => (val == null || val.length < 8)
                                ? 'At least 8 characters'
                                : null,
                          ),
                          const SizedBox(height: 14),
                          MizdahTextField(
                            label: 'Confirm new password',
                            hintText: 'Re-enter new password',
                            controller: _confirmCtrl,
                            prefixIcon: Icons.lock_outline,
                            isPassword: true,
                            validator: (val) {
                              if (val == null || val.length < 8) {
                                return 'At least 8 characters';
                              }
                              if (val != _newCtrl.text) {
                                return 'Passwords do not match';
                              }
                              return null;
                            },
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 14),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
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
                            label: 'Save new password',
                            onTap: _busy ? null : _onSubmit,
                            isLoading: _busy,
                          ),
                          const SizedBox(height: 14),
                          Center(
                            child: TextButton(
                              onPressed: () => context.go('/login'),
                              child: const Text('Cancel'),
                            ),
                          ),
                        ],
                      ),
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
