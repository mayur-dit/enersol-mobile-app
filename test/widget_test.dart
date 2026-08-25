import 'package:enersol_customer/core/state/settings_service.dart';
import 'package:enersol_customer/features/auth/login_screen.dart';
import 'package:enersol_customer/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

/// The app, booted.
///
/// Everything else in this suite tests a service, a model or one screen in
/// isolation. This is the only test that stands the whole thing up — the
/// providers, the theme, the session restore and the gate that chooses between
/// the splash, the login screen and the signed-in shell — which is the one
/// arrangement that cannot be checked by testing the pieces.
///
/// The failure it catches is a launch that never gets past the splash: a
/// provider missing, a service that throws in `initState`, or a session restore
/// that never completes. None of those show up anywhere else, and all of them
/// are a phone showing a logo for ever.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    useOfflineFonts();
    SharedPreferences.setMockInitialValues({});
    mockSecureStorage();
  });

  testWidgets('boots to the login screen when nobody is signed in', (tester) async {
    await tester.pumpWidget(const EnersolApp());

    // The first frame is the splash: `restore()` has not finished, and the gate
    // must not flash the login screen at a returning customer before it knows.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('leaves the splash even when there is no stored session at all', (tester) async {
    await tester.pumpWidget(const EnersolApp());
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  // The signed-in half of the gate is deliberately not booted here. `AppShell`
  // opens a WebSocket, registers for push and fetches five screens' worth of
  // data on its first frame, none of which a widget test can stand up honestly
  // — the screens behind it have their own tests, wired to a fake transport.

  testWidgets('paints in the theme the phone was last set to', (tester) async {
    SharedPreferences.setMockInitialValues({'settings_theme_mode': 'dark'});

    await tester.pumpWidget(const EnersolApp());
    await tester.pumpAndSettle();

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
    expect(app.theme, isNotNull);
    expect(app.darkTheme, isNotNull);
  });

  testWidgets('scales the whole app from the saved text size, not each screen', (tester) async {
    SharedPreferences.setMockInitialValues({'settings_font_size': 'large'});

    await tester.pumpWidget(const EnersolApp());
    await tester.pumpAndSettle();

    // One multiplier over the entire tree — the Settings slider works because
    // the scale is applied here rather than guessed at by each widget.
    final scaler = MediaQuery.of(tester.element(find.byType(LoginScreen))).textScaler;
    expect(scaler.scale(10), closeTo(10 * AppFontSize.large.scale, 0.001));
  });

  testWidgets('hides the debug banner, because this ships to customers', (tester) async {
    await tester.pumpWidget(const EnersolApp());
    await tester.pumpAndSettle();
    expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).debugShowCheckedModeBanner, isFalse);
  });
}
