import 'dart:ui';
import 'package:flutter/material.dart';

class GlassCard extends StatelessWidget {
  final Widget child;
  final double opacity;
  final double blur;
  final double radius;
  final EdgeInsetsGeometry padding;
  final Border? border;

  const GlassCard({
    super.key,
    required this.child,
    this.opacity = 0.05,
    this.blur = 15.0,
    this.radius = 24.0,
    this.padding = const EdgeInsets.all(16),
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: (isDark ? Colors.white : Colors.black).withValues(alpha: opacity),
            borderRadius: BorderRadius.circular(radius),
            border: border ?? Border.all(
              color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.1),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}
