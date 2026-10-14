import 'package:flutter/material.dart';

/// Premium school theme - teacher app (emerald identity).
/// Redesigned: richer gradients, elevated surfaces, refined typography, bolder depth.
class AppTheme {
  static const Color seed = Color(0xFF064E3B);
  static const Color seedLight = Color(0xFF0B6B4F);
  static const Color seedAccent = Color(0xFF10B981);
  static const Color gold = Color(0xFFC9A227);

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      primary: seedLight,
      secondary: seedAccent,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFFF0F4F2),
      appBarTheme: AppBarTheme(
        backgroundColor: seed,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        scrolledUnderElevation: 2,
        shadowColor: Colors.black.withValues(alpha: 0.15),
        titleTextStyle: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.3),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      cardTheme: CardThemeData(
        elevation: 2,
        margin: const EdgeInsets.symmetric(vertical: 7),
        shadowColor: Colors.black.withValues(alpha: 0.06),
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
          elevation: 2,
          shadowColor: seed.withValues(alpha: 0.3),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: seedLight,
        foregroundColor: Colors.white,
        elevation: 4,
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.8)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: seedLight, width: 1.8),
        ),
        filled: true,
        fillColor: Colors.white,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        elevation: 4,
        indicatorColor: seedAccent.withValues(alpha: 0.18),
        labelTextStyle: WidgetStateProperty.all(const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return const IconThemeData(color: Color(0xFF064E3B));
          return IconThemeData(color: Colors.grey.shade500);
        }),
      ),
      drawerTheme: const DrawerThemeData(shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(24)),
      )),
      dialogTheme: DialogThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22))),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        backgroundColor: const Color(0xFF1E293B),
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: WidgetStateProperty.all(const Color(0xFFE8F5ED)),
        headingTextStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: Color(0xFF064E3B)),
        dataRowMinHeight: 44,
        dividerThickness: 1,
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      ),
      dividerTheme: DividerThemeData(color: Colors.grey.shade200, space: 1, thickness: 1),
      textTheme: const TextTheme(
        headlineSmall: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.5),
        titleLarge: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.3),
        titleMedium: TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }
}
