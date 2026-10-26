import 'package:flutter/material.dart';

abstract final class WalkaboutColors {
  static const navy = Color(0xFF082C54);
  static const blue = Color(0xFF006CCE);
  static const teal = Color(0xFF008B94);
  static const pink = Color(0xFFDC006D);
  static const surface = Color(0xFFF7F9FC);
  static const divider = Color(0xFFE4EAF1);
}

ThemeData walkAboutTheme(Brightness brightness) {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: WalkaboutColors.blue,
        brightness: Brightness.light,
      ).copyWith(
        primary: WalkaboutColors.navy,
        secondary: WalkaboutColors.teal,
        tertiary: WalkaboutColors.pink,
        surface: Colors.white,
        onSurface: WalkaboutColors.navy,
        outlineVariant: WalkaboutColors.divider,
      );
  const body = TextStyle(
    fontFamily: 'Inter',
    fontSize: 16,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    height: 1.4,
  );
  final title = body.copyWith(fontWeight: FontWeight.w600);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: WalkaboutColors.surface,
    fontFamily: 'Inter',
    textTheme:
        TextTheme(
          displayLarge: title,
          displayMedium: title,
          displaySmall: title,
          headlineLarge: title,
          headlineMedium: title,
          headlineSmall: title,
          titleLarge: title,
          titleMedium: title,
          titleSmall: title,
          bodyLarge: body,
          bodyMedium: body,
          bodySmall: body,
          labelLarge: title,
          labelMedium: title,
          labelSmall: body,
        ).apply(
          bodyColor: WalkaboutColors.navy,
          displayColor: WalkaboutColors.navy,
        ),
    iconTheme: const IconThemeData(size: 24, color: WalkaboutColors.navy),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: WalkaboutColors.navy,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: title.copyWith(color: WalkaboutColors.navy),
      iconTheme: const IconThemeData(size: 24, color: WalkaboutColors.navy),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: WalkaboutColors.divider),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 52),
        textStyle: title,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        textStyle: title,
        side: const BorderSide(color: WalkaboutColors.divider),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        textStyle: title,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(48, 48),
        iconSize: 24,
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: WalkaboutColors.pink,
      foregroundColor: Colors.white,
      shape: CircleBorder(),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.all(16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: WalkaboutColors.divider),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: WalkaboutColors.divider),
      ),
    ),
    chipTheme: ChipThemeData(
      labelStyle: body.copyWith(color: WalkaboutColors.navy),
      secondaryLabelStyle: body.copyWith(color: WalkaboutColors.navy),
      checkmarkColor: WalkaboutColors.navy,
      backgroundColor: Colors.white,
      shape: const StadiumBorder(),
      side: const BorderSide(color: WalkaboutColors.divider),
      selectedColor: const Color(0xFFDFF3F4),
      secondarySelectedColor: const Color(0xFFDFF3F4),
    ),
    dividerTheme: const DividerThemeData(
      color: WalkaboutColors.divider,
      space: 24,
    ),
  );
}

class WalkHeading extends StatelessWidget {
  const WalkHeading(this.text, {this.size = 16, super.key});
  final String text;
  final double size;
  @override
  Widget build(BuildContext context) =>
      Text(text, style: Theme.of(context).textTheme.titleLarge);
}

class WalkaboutBrand extends StatelessWidget {
  const WalkaboutBrand({super.key});
  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/brand/walkabout-logo.png',
    width: 136,
    height: 68,
    fit: BoxFit.contain,
    semanticLabel: 'Walkabout',
  );
}
