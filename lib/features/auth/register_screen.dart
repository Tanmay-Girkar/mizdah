import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:intl_phone_field/phone_number.dart';
import '../../core/widgets/glass_card.dart';
import '../../core/widgets/mizdah_button.dart';
import '../../core/widgets/mizdah_text_field.dart';
import '../../core/theme/theme_provider.dart';
import 'auth_provider.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  // Updated by IntlPhoneField on every change. The package emits the
  // FULL E.164 number on `onChanged.completeNumber` and reports the
  // selected ISO country in `onChanged.countryISOCode`. We carry both
  // through to the provider because the backend wants them both per
  // docs/PHONE_AND_CONTACTS_BACKEND.md §2.1.
  String _phoneCompleteE164 = '';
  String _phoneCountryIso = 'IN';
  bool _phoneIsValid = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _onRegister() {
    if (!_formKey.currentState!.validate()) return;
    // IntlPhoneField runs its own validator inside the form, but
    // belt-and-braces: refuse to submit if the phone never reached a
    // valid state (e.g. user typed nothing, then submitted).
    if (!_phoneIsValid || _phoneCompleteE164.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid phone number')),
      );
      return;
    }
    ref.read(authProvider.notifier).signup(
          _emailController.text.trim(),
          _passwordController.text,
          _nameController.text.trim(),
          phone: _phoneCompleteE164,
          phoneCountry: _phoneCountryIso,
        );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Listen for registration success
    ref.listen<AuthState>(authProvider, (previous, next) {
      if (next.status == AuthStatus.authenticated) {
        context.go('/');
      }
    });

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
                  Text(
                    'Create Account',
                    style: theme.textTheme.headlineLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  Text(
                    'Join the Mizdah community',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Register Form Card
                  GlassCard(
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          MizdahTextField(
                            label: 'Full Name',
                            hintText: 'Enter your full name',
                            controller: _nameController,
                            prefixIcon: Icons.person_outline,
                            validator: (val) => (val == null || val.isEmpty)
                                ? 'Enter your name'
                                : null,
                          ),
                          const SizedBox(height: 20),
                          MizdahTextField(
                            label: 'Email',
                            hintText: 'Enter your email',
                            controller: _emailController,
                            prefixIcon: Icons.email_outlined,
                            keyboardType: TextInputType.emailAddress,
                            validator: (val) => (val == null || !val.contains('@'))
                                ? 'Enter a valid email'
                                : null,
                          ),
                          const SizedBox(height: 20),
                          _PhoneField(
                            isDark: isDark,
                            // India default — matches the bulk of our
                            // dev / test users; the picker lets the user
                            // change it before submitting.
                            initialCountryCode: 'IN',
                            onChanged: (PhoneNumber p) {
                              setState(() {
                                _phoneCompleteE164 = p.completeNumber;
                                _phoneCountryIso = p.countryISOCode;
                                _phoneIsValid = p.isValidNumber();
                              });
                            },
                          ),
                          const SizedBox(height: 20),
                          MizdahTextField(
                            label: 'Password',
                            hintText: 'Enter your password',
                            controller: _passwordController,
                            isPassword: true,
                            prefixIcon: Icons.lock_outline,
                            validator: (val) => (val == null || val.length < 6)
                                ? 'Min 6 characters'
                                : null,
                          ),
                          if (authState.errorMessage != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              authState.errorMessage!,
                              style: const TextStyle(
                                  color: Colors.red, fontSize: 13),
                            ),
                          ],
                          const SizedBox(height: 32),
                          MizdahButton(
                            label: 'Register',
                            onTap: authState.status == AuthStatus.authenticating
                                ? null
                                : _onRegister,
                            isLoading:
                                authState.status == AuthStatus.authenticating,
                          ),
                          const SizedBox(height: 16),
                          Center(
                            child: TextButton(
                              onPressed: () => context.go('/login'),
                              child: const Text(
                                  'Already have an account? Sign in'),
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

/// Phone input row matching the rest of the form's visual rhythm.
///
/// Wraps `IntlPhoneField` so we get the country picker + on-the-fly
/// formatting for free, but theme it to look like the other
/// `MizdahTextField` rows above (same label position, same fill
/// colour, same rounded border).
class _PhoneField extends StatelessWidget {
  final bool isDark;
  final String initialCountryCode;
  final ValueChanged<PhoneNumber> onChanged;
  const _PhoneField({
    required this.isDark,
    required this.initialCountryCode,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final labelColor = isDark ? Colors.white70 : Colors.black54;
    final fillColor =
        isDark ? Colors.white.withValues(alpha: 0.06) : Colors.grey.shade100;
    final borderColor =
        isDark ? Colors.white.withValues(alpha: 0.12) : Colors.transparent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Phone',
          style: TextStyle(
            color: labelColor,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 6),
        IntlPhoneField(
          initialCountryCode: initialCountryCode,
          onChanged: onChanged,
          dropdownTextStyle: TextStyle(
            color: isDark ? Colors.white : Colors.black87,
            fontSize: 15,
          ),
          dropdownIcon: Icon(
            Icons.arrow_drop_down_rounded,
            color: isDark ? Colors.white70 : Colors.black54,
          ),
          flagsButtonPadding: const EdgeInsets.symmetric(horizontal: 8),
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black87,
            fontSize: 15,
          ),
          decoration: InputDecoration(
            hintText: 'Phone number',
            hintStyle: TextStyle(
              color: isDark ? Colors.white38 : Colors.black38,
            ),
            filled: true,
            fillColor: fillColor,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 14,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: borderColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: borderColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: isDark ? Colors.white24 : Colors.black26,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.redAccent),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.redAccent),
            ),
          ),
          // `intl_phone_field` runs its own internal length-based
          // validation per country. We rely on that — disableLengthCheck
          // is FALSE by default so it'll surface "invalid number" inline
          // without us writing a validator.
        ),
      ],
    );
  }
}
