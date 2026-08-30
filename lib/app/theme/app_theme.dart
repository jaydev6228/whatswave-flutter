import 'package:flutter/material.dart';

import 'app_palette.dart';

abstract final class AppTheme {
  // The single UI typeface for the whole app -- every screen previously
  // fell back to Flutter's unset-fontFamily default (bundled Roboto) with
  // no deliberate choice made anywhere, which is what "1 or 2 families
  // throughout the app" is asking to fix. Bundled locally as a real asset
  // (see pubspec.yaml's fonts: entry) rather than fetched at runtime, so
  // this is a plain synchronous string, not an async font lookup.
  // Deliberate per-feature choices elsewhere (status text style presets'
  // serif/monospace, the emoji font fallback, the document viewer's
  // monospace) are content styling, not UI chrome, and are untouched by
  // this.
  static const String _uiFontFamily = 'Inter';

  static ThemeData lightTheme() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppPalette.emerald,
      brightness: Brightness.light,
      primary: AppPalette.emerald,
      secondary: AppPalette.green,
      error: AppPalette.rose,
      surface: Colors.white,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      fontFamily: _uiFontFamily,
      scaffoldBackgroundColor: AppPalette.cloud,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: AppPalette.ink,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
      ),
      dialogTheme: DialogThemeData(
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        modalBackgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: Colors.transparent,
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: isSelected ? AppPalette.emerald : AppPalette.slate,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return TextStyle(
            color: isSelected ? AppPalette.emerald : AppPalette.slate,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w700,
          );
        }),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppPalette.mist,
        selectedColor: AppPalette.emerald,
        disabledColor: AppPalette.mist,
        secondarySelectedColor: AppPalette.emerald,
        side: BorderSide.none,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
        ),
        labelStyle: const TextStyle(
          color: AppPalette.ink,
          fontWeight: FontWeight.w600,
        ),
      ),
      dividerColor: const Color(0xFFE5EBE8),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFFCFEFD),
        hintStyle: const TextStyle(color: AppPalette.slate),
        floatingLabelStyle: const TextStyle(
          color: AppPalette.emerald,
          fontWeight: FontWeight.w700,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(
            color: Color(0xFFD7E3DF),
            width: 1.2,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(
            color: Color(0xFFD7E3DF),
            width: 1.2,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppPalette.emerald, width: 1.5),
        ),
      ),
    );
  }

  static ThemeData darkTheme() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppPalette.green,
      brightness: Brightness.dark,
      primary: AppPalette.green,
      secondary: AppPalette.emerald,
      error: AppPalette.rose,
      surface: AppPalette.ink,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      fontFamily: _uiFontFamily,
      scaffoldBackgroundColor: AppPalette.deepOcean,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: const Color(0xFF111B21),
        elevation: 0,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
      ),
      // Set on the theme rather than per dialog: there are a dozen-odd
      // AlertDialogs across the app, and this is the one place that
      // reaches all of them. The hairline border is what ties them to the
      // app's glass surfaces, which all carry one.
      dialogTheme: DialogThemeData(
        backgroundColor: const Color(0xFF111B21),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Color(0xFF111B21),
        modalBackgroundColor: Color(0xFF111B21),
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: const Color(0xFF111B21),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: const Color(0xFF111B21),
        indicatorColor: Colors.transparent,
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: isSelected ? AppPalette.green : const Color(0xFF8A9AA3),
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return TextStyle(
            color: isSelected ? AppPalette.green : const Color(0xFF8A9AA3),
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w700,
          );
        }),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFF1B2A33),
        selectedColor: AppPalette.green,
        disabledColor: const Color(0xFF1B2A33),
        secondarySelectedColor: AppPalette.green,
        side: BorderSide.none,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
        ),
        labelStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
      dividerColor: const Color(0xFF22323B),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF101A20),
        hintStyle: const TextStyle(color: Color(0xFF8A9AA3)),
        floatingLabelStyle: const TextStyle(
          color: AppPalette.green,
          fontWeight: FontWeight.w700,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(
            color: Color(0xFF2C3B44),
            width: 1.2,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(
            color: Color(0xFF2C3B44),
            width: 1.2,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppPalette.green, width: 1.5),
        ),
      ),
    );
  }
}
