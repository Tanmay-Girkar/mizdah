import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _onRegister() {
    if (_formKey.currentState!.validate()) {
      ref.read(authProvider.notifier).signup(
        _emailController.text,
        _passwordController.text,
        _nameController.text,
      );
    }
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
                  const SizedBox(height: 48),

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
                                ? 'Enter your name' : null,
                          ),
                          const SizedBox(height: 20),
                          MizdahTextField(
                            label: 'Email',
                            hintText: 'Enter your email',
                            controller: _emailController,
                            prefixIcon: Icons.email_outlined,
                            keyboardType: TextInputType.emailAddress,
                            validator: (val) => (val == null || !val.contains('@')) 
                                ? 'Enter a valid email' : null,
                          ),
                          const SizedBox(height: 20),
                          MizdahTextField(
                            label: 'Password',
                            hintText: 'Enter your password',
                            controller: _passwordController,
                            isPassword: true,
                            prefixIcon: Icons.lock_outline,
                            validator: (val) => (val == null || val.length < 6) 
                                ? 'Min 6 characters' : null,
                          ),
                           if (authState.errorMessage != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              authState.errorMessage!,
                              style: const TextStyle(color: Colors.red, fontSize: 13),
                            ),
                          ],
                          const SizedBox(height: 32),
                          MizdahButton(
                            label: 'Register',
                            onTap: authState.status == AuthStatus.authenticating 
                                ? null : _onRegister,
                            isLoading: authState.status == AuthStatus.authenticating,
                          ),
                          const SizedBox(height: 16),
                          Center(
                            child: TextButton(
                              onPressed: () => context.go('/login'),
                              child: const Text('Already have an account? Sign in'),
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
