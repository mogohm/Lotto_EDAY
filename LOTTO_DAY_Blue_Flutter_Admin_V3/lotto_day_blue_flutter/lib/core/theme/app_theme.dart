import 'package:flutter/material.dart';

/// Inspired by the reference's light-blue digital-wallet feel, not a copy of any branded app.
abstract final class LottoColors {
  static const primary = Color(0xFF0078D7);
  static const secondary = Color(0xFF00AEEF);
  static const surface = Color(0xFFE8F6FF);
  static const accent = Color(0xFFFFC700);
  static const navy = Color(0xFF123C63);
  static const ink = Color(0xFF183153);
  static const background = Color(0xFFF4FAFF);
  static const border = Color(0xFFD9EAF8);
  static const positive = Color(0xFF16835C);
  static const negative = Color(0xFFC93B50);
}

abstract final class AppTheme {
  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: LottoColors.primary,
      brightness: Brightness.light,
      primary: LottoColors.primary,
      secondary: LottoColors.secondary,
      surface: Colors.white,
      onPrimary: Colors.white,
      onSurface: LottoColors.ink,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: LottoColors.background,
      fontFamily: 'NotoSansThai', // falls back to platform Thai fonts until font assets are licensed/bundled
      appBarTheme: const AppBarTheme(
        backgroundColor: LottoColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w700),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: LottoColors.border)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: LottoColors.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: LottoColors.border)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: LottoColors.accent,
          foregroundColor: LottoColors.navy,
          minimumSize: const Size(48, 50),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: LottoColors.surface,
        labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
              fontSize: 11,
              color: states.contains(WidgetState.selected) ? LottoColors.primary : LottoColors.ink,
              fontWeight: states.contains(WidgetState.selected) ? FontWeight.w800 : FontWeight.w500,
            )),
      ),
      dividerTheme: const DividerThemeData(color: LottoColors.border),
    );
  }
}
