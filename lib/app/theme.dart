import 'package:flutter/material.dart';

/// Black Mango colors. Change them here and the whole app follows.
class BMColors {
  static const background = Color(0xFF0B0B0B);
  static const surface = Color(0xFF151515);
  static const surfaceHigh = Color(0xFF1E1E1E);
  static const border = Color(0xFF2A2A2A);
  static const mango = Color(0xFFFF8C00);
  static const text = Color(0xFFEDEDED);
  static const dim = Color(0xFF8A8A8A);
}

ThemeData buildTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: BMColors.background,
    colorScheme: base.colorScheme.copyWith(
      primary: BMColors.mango,
      secondary: BMColors.mango,
      surface: BMColors.surface,
      onPrimary: Colors.black,
    ),
    dividerColor: BMColors.border,
    navigationRailTheme: const NavigationRailThemeData(
      backgroundColor: BMColors.surface,
      indicatorColor: Color(0x33FF8C00),
      selectedIconTheme: IconThemeData(color: BMColors.mango),
      unselectedIconTheme: IconThemeData(color: BMColors.dim),
      selectedLabelTextStyle: TextStyle(color: BMColors.mango, fontWeight: FontWeight.w600),
      unselectedLabelTextStyle: TextStyle(color: BMColors.dim),
    ),
  );
}
