import 'dart:ui';
import 'package:flutter/material.dart';

class ControlIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool isActive;
  final Color? activeColor;
  final Color? inactiveColor;
  final Color? backgroundColor;
  final double size;

  const ControlIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.isActive = false,
    this.activeColor,
    this.inactiveColor,
    this.backgroundColor,
    this.size = 56,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final color = isActive 
        ? (activeColor ?? Colors.red) 
        : (inactiveColor ?? (isDark ? Colors.white : Colors.black87));

    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size / 2),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: size,
            width: size,
            decoration: BoxDecoration(
              color: backgroundColor ?? (isActive 
                  ? color.withOpacity(0.2) 
                  : (isDark ? Colors.white10 : Colors.black.withOpacity(0.05))),
              shape: BoxShape.circle,
              border: Border.all(
                color: isActive 
                    ? color.withOpacity(0.3) 
                    : (isDark ? Colors.white10 : Colors.black12),
              ),
            ),
            child: Icon(
              icon,
              color: color,
              size: size * 0.45,
            ),
          ),
        ),
      ),
    );
  }
}
