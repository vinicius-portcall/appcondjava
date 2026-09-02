import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Os dois temas do app: escuro "tech" (padrão) e claro em tons de bege.
/// Ambos mantêm a identidade azul/amarelo da marca, só muda a superfície.
class AppTheme {
  AppTheme._();

  static const _azul = Color(0xFF1565C0);
  static const _amarelo = Color(0xFFFFB300);

  static ThemeData dark() {
    final colors = AppColors.dark;
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: _azul,
          brightness: Brightness.dark,
        ).copyWith(
          surface: colors.panelBackground,
          secondary: colors.brandAccent,
          onSecondary: Colors.black,
          secondaryContainer: colors.brandAccent,
          onSecondaryContainer: Colors.black,
          tertiary: colors.brandAccent,
        );

    return _base(colorScheme, colors);
  }

  static ThemeData light() {
    final colors = AppColors.light;
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: _azul,
          brightness: Brightness.light,
        ).copyWith(
          surface: colors.panelBackground,
          surfaceContainerLowest: const Color(0xFFFBF6EC),
          surfaceContainer: colors.tileBackground,
          surfaceContainerHigh: const Color(0xFFEFE3C8),
          secondary: _amarelo,
          onSecondary: Colors.black,
          secondaryContainer: _amarelo,
          onSecondaryContainer: Colors.black,
          tertiary: _amarelo,
        );

    return _base(colorScheme, colors);
  }

  static ThemeData _base(ColorScheme colorScheme, AppColors colors) {
    final appBarBg = colorScheme.brightness == Brightness.dark
        ? const Color(0xFF10141F)
        : _azul;
    final appBarFg = colorScheme.brightness == Brightness.dark
        ? colors.textBright
        : Colors.white;

    return ThemeData(
      useMaterial3: true,
      brightness: colorScheme.brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colors.panelBackground,
      appBarTheme: AppBarTheme(
        backgroundColor: appBarBg,
        foregroundColor: appBarFg,
        iconTheme: IconThemeData(color: colors.brandAccent),
        actionsIconTheme: IconThemeData(color: colors.brandAccent),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colors.brandAccent,
        foregroundColor: Colors.black,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colors.brandAccent,
      ),
      extensions: [colors],
    );
  }
}
