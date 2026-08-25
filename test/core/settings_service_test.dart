import 'package:enersol_customer/core/state/settings_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Theme and text scale — the two settings that survive a launch.
///
/// Both are read back into an enum, and both have to cope with a stored value
/// that is no longer valid: a preference written by an older build, or a blob
/// hand-edited on a rooted phone. Falling over there is a customer stuck on a
/// crashing launch with no way to clear it, so the rule is that anything
/// unreadable reads as the default.
///
/// The other property worth pinning is that the setters notify BEFORE the write
/// completes. The Settings screen is a radio list: waiting for the disk would
/// leave the tick on the old option for as long as the write takes, which reads
/// as the tap not registering.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppFontSize', () {
    test('offers four steps, with medium as the neutral scale', () {
      expect(AppFontSize.values, hasLength(4));
      expect(AppFontSize.medium.scale, 1.0);
    });

    test('runs from smallest to largest in declaration order', () {
      final scales = AppFontSize.values.map((f) => f.scale).toList();
      expect(scales, orderedEquals([...scales]..sort()));
      expect(AppFontSize.small.scale, lessThan(AppFontSize.medium.scale));
      expect(AppFontSize.extraLarge.scale, greaterThan(AppFontSize.large.scale));
    });

    test('gives every step a label the Settings screen can print', () {
      for (final size in AppFontSize.values) {
        expect(size.label, isNotEmpty);
      }
    });

    test('keeps the extremes legible rather than unusable', () {
      // A multiplier applied to the WHOLE text theme: too small is unreadable
      // and too large breaks every fixed-height row in the app.
      expect(AppFontSize.small.scale, greaterThanOrEqualTo(0.8));
      expect(AppFontSize.extraLarge.scale, lessThanOrEqualTo(1.5));
    });
  });

  group('before anything is loaded', () {
    test('follows the phone, and reports that it has not read the disk yet', () {
      final settings = SettingsService();
      expect(settings.themeMode, ThemeMode.system);
      expect(settings.fontSize, AppFontSize.medium);
      expect(settings.loaded, isFalse);
    });
  });

  group('load', () {
    test('reads back a saved theme and text size', () async {
      SharedPreferences.setMockInitialValues({
        'settings_theme_mode': 'dark',
        'settings_font_size': 'large',
      });
      final settings = SettingsService();
      await settings.load();
      expect(settings.themeMode, ThemeMode.dark);
      expect(settings.fontSize, AppFontSize.large);
      expect(settings.loaded, isTrue);
    });

    test('falls back to following the phone when nothing was ever saved', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsService();
      await settings.load();
      expect(settings.themeMode, ThemeMode.system);
      expect(settings.fontSize, AppFontSize.medium);
      expect(settings.loaded, isTrue);
    });

    test('falls back rather than throwing on a value it does not recognise', () async {
      SharedPreferences.setMockInitialValues({
        'settings_theme_mode': 'sepia',
        'settings_font_size': 'enormous',
      });
      final settings = SettingsService();
      await settings.load();
      expect(settings.themeMode, ThemeMode.system);
      expect(settings.fontSize, AppFontSize.medium);
    });

    test('reads light back as light', () async {
      SharedPreferences.setMockInitialValues({'settings_theme_mode': 'light'});
      final settings = SettingsService();
      await settings.load();
      expect(settings.themeMode, ThemeMode.light);
    });

    test('tells the app to repaint once it has read the disk', () async {
      SharedPreferences.setMockInitialValues({'settings_theme_mode': 'dark'});
      final settings = SettingsService();
      var notified = 0;
      settings.addListener(() => notified++);
      await settings.load();
      expect(notified, 1);
    });
  });

  group('setThemeMode', () {
    test('applies the choice and writes it for next launch', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsService();
      await settings.load();

      await settings.setThemeMode(ThemeMode.dark);
      expect(settings.themeMode, ThemeMode.dark);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('settings_theme_mode'), 'dark');
    });

    test('repaints before the write finishes, so the tick moves on tap', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsService();
      await settings.load();

      var notified = 0;
      settings.addListener(() => notified++);
      final pending = settings.setThemeMode(ThemeMode.light);
      expect(settings.themeMode, ThemeMode.light);
      expect(notified, 1);
      await pending;
    });

    test('does nothing at all when the current choice is tapped again', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsService();
      await settings.load();

      var notified = 0;
      settings.addListener(() => notified++);
      await settings.setThemeMode(ThemeMode.system);
      expect(notified, 0);
    });

    test('round-trips through a fresh service, as a relaunch would', () async {
      SharedPreferences.setMockInitialValues({});
      final first = SettingsService();
      await first.load();
      await first.setThemeMode(ThemeMode.dark);

      final second = SettingsService();
      await second.load();
      expect(second.themeMode, ThemeMode.dark);
    });
  });

  group('setFontSize', () {
    test('applies the choice and writes it under its own name', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsService();
      await settings.load();

      await settings.setFontSize(AppFontSize.extraLarge);
      expect(settings.fontSize, AppFontSize.extraLarge);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('settings_font_size'), 'extraLarge');
    });

    test('does nothing when the current size is chosen again', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsService();
      await settings.load();

      var notified = 0;
      settings.addListener(() => notified++);
      await settings.setFontSize(AppFontSize.medium);
      expect(notified, 0);
    });

    test('round-trips every step through a relaunch', () async {
      for (final size in AppFontSize.values) {
        SharedPreferences.setMockInitialValues({});
        final first = SettingsService();
        await first.load();
        await first.setFontSize(size);

        final second = SettingsService();
        await second.load();
        expect(second.fontSize, size, reason: '${size.name} did not survive a relaunch');
      }
    });

    test('leaves the theme alone when only the text size changes', () async {
      SharedPreferences.setMockInitialValues({'settings_theme_mode': 'dark'});
      final settings = SettingsService();
      await settings.load();
      await settings.setFontSize(AppFontSize.small);
      expect(settings.themeMode, ThemeMode.dark);
    });
  });
}
