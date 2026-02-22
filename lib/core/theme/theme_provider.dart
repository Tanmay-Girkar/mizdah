import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final themeProvider = NotifierProvider<ThemeManager, ThemeMode>(() {
  return ThemeManager();
});

class ThemeManager extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    _loadTheme();
    return ThemeMode.system;
  }

  static const _themeKey = 'theme_preference';

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final themeIndex = prefs.getInt(_themeKey);
    if (themeIndex != null) {
      state = ThemeMode.values[themeIndex];
    }
  }

  Future<void> setTheme(ThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_themeKey, mode.index);
  }
}

class MizdahTheme {
  // Primary Palette
  static const Color primaryBlue = Color(0xFF00B2FF); // Neon Blue
  static const Color primaryGlow = Color(0x3300B2FF);
  
  // Dark Theme Palette
  static const Color darkBackgroundTop = Color(0xFF0B1220);
  static const Color darkBackgroundBottom = Color(0xFF111827);
  static const Color darkSurface = Color(0xFF1F2937);
  static const Color darkBorder = Color(0x1AFFFFFF);
  
  // Light Theme Palette
  static const Color lightBackground = Color(0xFFF5F7FB);
  static const Color lightSurface = Colors.white;
  static const Color lightBorder = Color(0x0D000000);

  // Gradients
  static const LinearGradient darkGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [darkBackgroundTop, darkBackgroundBottom],
  );

  // Glassmorphism Utility
  static BoxDecoration glassDecoration({
    required BuildContext context,
    double opacity = 0.1,
    double blur = 10.0,
    double radius = 24.0,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return BoxDecoration(
      color: (isDark ? Colors.white : Colors.black).withOpacity(opacity),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: (isDark ? Colors.white : Colors.black).withOpacity(0.1),
      ),
    );
  }

  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: lightBackground,
    colorScheme: ColorScheme.fromSeed(
      seedColor: primaryBlue,
      primary: primaryBlue,
      surface: lightSurface,
      onSurface: const Color(0xFF111827),
      brightness: Brightness.light,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: lightSurface,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(color: Color(0xFF111827), fontSize: 18, fontWeight: FontWeight.bold),
      iconTheme: IconThemeData(color: Color(0xFF111827)),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: lightSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: lightBorder),
      ),
    ),
  );

  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: darkBackgroundTop,
    colorScheme: ColorScheme.fromSeed(
      seedColor: primaryBlue,
      primary: primaryBlue,
      surface: darkSurface,
      onSurface: Colors.white,
      brightness: Brightness.dark,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
      iconTheme: IconThemeData(color: Colors.white),
    ),
    drawerTheme: const DrawerThemeData(backgroundColor: darkSurface),
    cardTheme: CardThemeData(
      elevation: 2,
      color: darkSurface,
      shadowColor: Colors.black.withOpacity(0.05),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: Colors.white10),
      ),
    ),
  );
}
