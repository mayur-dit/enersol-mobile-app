import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Named font sizes offered on the Settings screen.
///
/// The value is a multiplier applied to the whole text theme, so every screen
/// scales together instead of each one hand-rolling sizes.
enum AppFontSize {
  small('Small', 0.9),
  medium('Medium', 1.0),
  large('Large', 1.15),
  extraLarge('Extra Large', 1.3);

  const AppFontSize(this.label, this.scale);
  final String label;
  final double scale;
}

/// Theme mode + text scale, persisted across launches.
class SettingsService extends ChangeNotifier {
  SettingsService();

  static const _kThemeMode = 'settings_theme_mode';
  static const _kFontSize = 'settings_font_size';

  ThemeMode _themeMode = ThemeMode.system;
  ThemeMode get themeMode => _themeMode;

  AppFontSize _fontSize = AppFontSize.medium;
  AppFontSize get fontSize => _fontSize;

  bool _loaded = false;
  bool get loaded => _loaded;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();

    final themeRaw = prefs.getString(_kThemeMode);
    _themeMode = switch (themeRaw) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };

    final fontRaw = prefs.getString(_kFontSize);
    _fontSize = AppFontSize.values.firstWhere(
      (f) => f.name == fontRaw,
      orElse: () => AppFontSize.medium,
    );

    _loaded = true;
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kThemeMode, mode.name);
  }

  Future<void> setFontSize(AppFontSize size) async {
    if (_fontSize == size) return;
    _fontSize = size;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kFontSize, size.name);
  }
}
