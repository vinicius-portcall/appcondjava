import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Guarda e persiste a escolha entre o tema escuro "tech" (padrão) e o
/// tema claro em tons de bege.
class ThemeService extends ChangeNotifier {
  static const _kTemaClaro = 'tema_claro';

  ThemeMode _mode = ThemeMode.dark;
  ThemeMode get mode => _mode;
  bool get isDark => _mode == ThemeMode.dark;

  Future<void> carregar() async {
    final prefs = await SharedPreferences.getInstance();
    final claro = prefs.getBool(_kTemaClaro) ?? false;
    _mode = claro ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();
  }

  Future<void> alternar() async {
    _mode = isDark ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kTemaClaro, !isDark);
  }
}
