import 'package:flutter/material.dart';

import '../barbershop/models.dart';

Color parseColor(String? value, Color fallback) {
  if (value == null || !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(value)) {
    return fallback;
  }
  return Color(0xff000000 | int.parse(value.substring(1), radix: 16));
}

Color accentText(Color color) {
  final luminance = color.computeLuminance();
  final whiteContrast = 1.05 / (luminance + .05);
  final blackContrast = (luminance + .05) / .05;
  return whiteContrast >= blackContrast ? Colors.white : Colors.black;
}

ThemeData shopTheme(Barbershop? shop) {
  final primary = parseColor(shop?.primaryColor, const Color(0xffd5f66b));
  final secondary = parseColor(shop?.secondaryColor, const Color(0xffb6a4ff));
  final scheme =
      ColorScheme.fromSeed(
        seedColor: primary,
        brightness: Brightness.dark,
      ).copyWith(
        primary: primary,
        onPrimary: accentText(primary),
        secondary: secondary,
        onSecondary: accentText(secondary),
        surface: const Color(0xff141616),
      );
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: const Color(0xff0b0d0d),
    fontFamily: 'BricolageGrotesque',
    cardTheme: CardThemeData(
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: Color(0xff343838)),
        borderRadius: BorderRadius.circular(20),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 52),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
  );
}
