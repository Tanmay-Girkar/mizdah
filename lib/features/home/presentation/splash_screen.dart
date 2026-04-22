import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/theme_provider.dart';
import '../../auth/auth_provider.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.6, curve: Curves.easeIn)),
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.6, curve: Curves.easeOutBack)),
    );

    _controller.forward();
    _checkStatus();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _checkStatus() async {
    // Minimum wait for the splash animation
    await Future.delayed(const Duration(seconds: 2));
    
    // Check if the auth check is still in progress
    AuthState authState = ref.read(authProvider);
    
    // Wait until we have a settled status (authenticated or unauthenticated)
    // but don't wait forever (max 5 seconds total)
    int retryCount = 0;
    while ((authState.status == AuthStatus.initial || authState.status == AuthStatus.authenticating) && retryCount < 15) {
      await Future.delayed(const Duration(milliseconds: 200));
      authState = ref.read(authProvider);
      retryCount++;
    }

    if (!mounted) return;

    if (authState.status == AuthStatus.authenticated) {
      context.go('/');
    } else {
      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: isDark ? MizdahTheme.darkGradient : null,
          color: isDark ? null : MizdahTheme.lightBackground,
        ),
        child: Center(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Opacity(
                opacity: _fadeAnimation.value,
                child: Transform.scale(
                  scale: _scaleAnimation.value,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.02),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: MizdahTheme.primaryBlue.withValues(alpha: isDark ? 0.2 : 0.1),
                              blurRadius: 40,
                              spreadRadius: 10,
                            ),
                          ],
                        ),
                        child: Image.asset(
                          'assets/images/mizdahlogo.png',
                          height: 120,
                          // Optional: filter logo color for dark/light if it's a solid silhouette
                          // color: isDark ? Colors.white : MizdahTheme.primaryBlue,
                        ),
                      ),
                      const SizedBox(height: 32),
                      Text(
                        'MIZDAH',
                        style: theme.textTheme.headlineLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                          letterSpacing: 8,
                          color: isDark ? Colors.white : const Color(0xFF0B1220),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Premium Video Conferencing',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          letterSpacing: 2,
                          color: isDark ? Colors.white60 : Colors.black54,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 64),
                      SizedBox(
                        width: 40,
                        height: 40,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            isDark ? MizdahTheme.primaryBlue : theme.primaryColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
