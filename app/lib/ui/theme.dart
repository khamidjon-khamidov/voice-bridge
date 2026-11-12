import 'package:flutter/material.dart';

/// Same palette as the hub's web page, so the two feel like one product.
class Palette {
  static const accent = Color(0xFF2F6FDE);
  static const warn = Color(0xFFC7780A);
  static const bad = Color(0xFFC9372C);
  static const good = Color(0xFF1F8A4C);

  static Color stateColor(String state) => switch (state) {
        'working' => accent,
        'waiting' || 'needs_terminal' => warn,
        'idle' => good,
        _ => Colors.grey,
      };

  static String stateText(String state) => switch (state) {
        'working' => 'working',
        'waiting' => 'needs answer',
        'needs_terminal' => 'at terminal',
        'idle' => 'idle',
        'ended' => 'ended',
        _ => state,
      };
}

ThemeData buildTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final scheme = ColorScheme.fromSeed(seedColor: Palette.accent, brightness: b).copyWith(
    primary: dark ? const Color(0xFF4F8CF0) : Palette.accent,
    surface: dark ? const Color(0xFF111214) : const Color(0xFFF6F6F4),
    surfaceContainer: dark ? const Color(0xFF1B1D20) : Colors.white,
    outlineVariant: dark ? const Color(0xFF2C2F33) : const Color(0xFFE4E4E0),
  );
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(backgroundColor: scheme.surface, scrolledUnderElevation: 0),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainer,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
