import 'package:flutter/material.dart';

/// Cores que não fazem parte do [ColorScheme] padrão do Material — usadas
/// especialmente pelo painel de ações rápidas da Home (visual "tech" com
/// acentos neon no escuro, e uma variante em tons quentes de bege no claro).
/// Acessar via `Theme.of(context).extension<AppColors>()!`.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  final Color panelBackground;
  final Color tileBackground;
  final Color textBright;
  final Color textMuted;
  final Color brandAccent;
  final List<Color> tileAccents;
  final bool tileGlow;
  final bool isDark;

  const AppColors({
    required this.panelBackground,
    required this.tileBackground,
    required this.textBright,
    required this.textMuted,
    required this.brandAccent,
    required this.tileAccents,
    required this.tileGlow,
    required this.isDark,
  });

  static const dark = AppColors(
    panelBackground: Color(0xFF0B0E17),
    tileBackground: Color(0xFF141A29),
    textBright: Color(0xFFE6E9F2),
    textMuted: Color(0xFF6B7280),
    brandAccent: Color(0xFFFFC400),
    tileAccents: [
      Color(0xFF00E5FF), // ciano
      Color(0xFFFF2E9A), // magenta
      Color(0xFFFFC400), // âmbar
      Color(0xFF7C4DFF), // violeta
      Color(0xFF00FFA3), // verde neon
      Color(0xFFFF6D00), // laranja
      Color(0xFF2979FF), // azul elétrico
      Color(0xFF1DE9B6), // teal neon
      Color(0xFFFF1744), // vermelho neon
      Color(0xFFB2FF59), // verde limão neon
    ],
    tileGlow: true,
    isDark: true,
  );

  static const light = AppColors(
    panelBackground: Color(0xFFF6EFE0),
    tileBackground: Color(0xFFFFFBF2),
    textBright: Color(0xFF3B3025),
    textMuted: Color(0xFF8A7A61),
    brandAccent: Color(0xFFFFB300),
    tileAccents: [
      Color(0xFF00838F), // teal
      Color(0xFFAD1457), // pink
      Color(0xFFF9A825), // âmbar
      Color(0xFF5E35B1), // violeta
      Color(0xFF2E7D32), // verde
      Color(0xFFD84315), // laranja queimado
      Color(0xFF1565C0), // azul
      Color(0xFF00695C), // teal escuro
      Color(0xFFC62828), // vermelho
      Color(0xFF558B2F), // verde oliva
    ],
    tileGlow: false,
    isDark: false,
  );

  @override
  AppColors copyWith({
    Color? panelBackground,
    Color? tileBackground,
    Color? textBright,
    Color? textMuted,
    Color? brandAccent,
    List<Color>? tileAccents,
    bool? tileGlow,
    bool? isDark,
  }) {
    return AppColors(
      panelBackground: panelBackground ?? this.panelBackground,
      tileBackground: tileBackground ?? this.tileBackground,
      textBright: textBright ?? this.textBright,
      textMuted: textMuted ?? this.textMuted,
      brandAccent: brandAccent ?? this.brandAccent,
      tileAccents: tileAccents ?? this.tileAccents,
      tileGlow: tileGlow ?? this.tileGlow,
      isDark: isDark ?? this.isDark,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      panelBackground: Color.lerp(panelBackground, other.panelBackground, t)!,
      tileBackground: Color.lerp(tileBackground, other.tileBackground, t)!,
      textBright: Color.lerp(textBright, other.textBright, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      brandAccent: Color.lerp(brandAccent, other.brandAccent, t)!,
      tileAccents: [
        for (var i = 0; i < tileAccents.length; i++)
          Color.lerp(tileAccents[i], other.tileAccents[i], t)!,
      ],
      tileGlow: t < 0.5 ? tileGlow : other.tileGlow,
      isDark: t < 0.5 ? isDark : other.isDark,
    );
  }
}
