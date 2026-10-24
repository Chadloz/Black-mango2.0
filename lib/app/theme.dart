import 'package:flutter/material.dart';
import 'skins.dart';
import 'skin_textures.dart';

/// Black Mango colors: always the active skin's (Settings > Skins), so the whole app
/// follows when you switch. Black Mango's own colors are the 'black_mango' skin in skins.dart.
class BMColors {
  static Color get background => Skins.skin.background;
  static Color get surface => Skins.skin.surface;
  static Color get surfaceHigh => Skins.skin.surfaceHigh;
  static Color get border => Skins.skin.border;
  static Color get mango => Skins.skin.accent; // the accent (mango orange in the normal skin)
  static Color get text => Skins.skin.text;
  static Color get dim => Skins.skin.dim;
  static Color get controls => Skins.skin.controls; // player buttons over the video

  /// Text and icons on an accent-colored button: black on bright accents, white on dark ones.
  static Color get onAccent => Skins.skin.accent.computeLuminance() > 0.18 ? Colors.black : Colors.white;
}

/// Fonts bundled in assets/fonts (SIL Open Font License).
class BMFonts {
  static const ui = 'Outfit';
  static const mono = 'JetBrainsMono';

  /// The wordmark and screen titles: the skin's title font (Halloween: dripping Nosifer).
  static String get title => Skins.skin.titleFont ?? ui;

  /// A screen title in the skin's title font. Decorative fonts run wide and come in one
  /// weight, so they're set a little smaller and regular.
  static TextStyle titleStyle(double size, {Color? color}) {
    final special = Skins.skin.titleFont != null;
    return TextStyle(
      fontFamily: title,
      fontSize: special ? size * 0.82 : size,
      fontWeight: special ? FontWeight.w400 : FontWeight.w700,
      color: color ?? BMColors.text,
    );
  }
}

ThemeData buildTheme() {
  return ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    fontFamily: BMFonts.ui,
    scaffoldBackgroundColor: BMColors.background,
    colorScheme: ColorScheme.dark(
      primary: BMColors.mango,
      secondary: BMColors.mango,
      surface: BMColors.surface,
      onPrimary: BMColors.onAccent,
      onSurface: BMColors.text,
    ),
    // Filled buttons carry the accent texture, clipped to their pill shape.
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        backgroundBuilder: SkinTextures.has(TextureArea.accent)
            ? (context, states, child) => DecoratedBox(
                  decoration: ShapeDecoration(shape: const StadiumBorder(), image: SkinTextures.image(Skins.skin, TextureArea.accent)),
                  child: child,
                )
            : null,
      ),
    ),
    dividerColor: BMColors.border,
    dividerTheme: DividerThemeData(color: BMColors.border),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: BMColors.surface,
      indicatorColor: BMColors.mango.withAlpha(0x33),
      selectedIconTheme: IconThemeData(color: BMColors.mango),
      unselectedIconTheme: IconThemeData(color: BMColors.dim),
      selectedLabelTextStyle: TextStyle(color: BMColors.mango, fontWeight: FontWeight.w600),
      unselectedLabelTextStyle: TextStyle(color: BMColors.dim),
    ),
  );
}
