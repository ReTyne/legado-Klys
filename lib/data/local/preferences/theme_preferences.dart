import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 主题偏好设置
class ThemePreferences {
  final SharedPreferences _prefs;
  ThemePreferences(this._prefs);

  static Future<ThemePreferences> create() async =>
      ThemePreferences(await SharedPreferences.getInstance());

  ThemeMode get themeMode {
    switch (_prefs.getString('theme_mode') ?? 'system') {
      case 'light': return ThemeMode.light;
      case 'dark': return ThemeMode.dark;
      default: return ThemeMode.system;
    }
  }

  Future<void> setThemeMode(ThemeMode mode) =>
      _prefs.setString('theme_mode', mode.name);

  int get seedColor => _prefs.getInt('theme_seed') ?? 0xFF6750A4;
  Future<void> setSeedColor(int v) => _prefs.setInt('theme_seed', v);

  bool get dynamicColor => _prefs.getBool('theme_dynamic') ?? true;
  Future<void> setDynamicColor(bool v) => _prefs.setBool('theme_dynamic', v);
}
