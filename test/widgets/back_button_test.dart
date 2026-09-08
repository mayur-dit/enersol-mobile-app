import 'package:enersol_customer/features/service/service_screen.dart';
import 'package:enersol_customer/shared/widgets/app_drawer.dart';
import 'package:enersol_customer/shared/widgets/app_shell.dart';
import 'package:enersol_customer/shared/widgets/page_title.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// What the Android back button does, everywhere it can be pressed.
///
/// The rule the app follows: back undoes ONE thing at a time — an open drawer,
/// then a pushed screen, then a tab that is not Home — and only asks to close
/// the app once there is nothing left to undo. It used to close the app the
/// moment Home was on screen, with no question asked, and it walked straight
/// past an open drawer.
void main() {
  setUpAll(useOfflineFonts);

  /// Records the `SystemNavigator.pop` the app sends when the user confirms.
  ///
  /// Nothing closes an app in a widget test, so the platform call IS the
  /// observable behaviour — without capturing it a test cannot tell "asked and
  /// left" from "asked and stayed".
  List<String> captureSystemCalls() {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      // Only the one call this is about — the channel also carries the theme's
      // chrome and the task-switcher title on every build.
      if (call.method == 'SystemNavigator.pop') calls.add(call.method);
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    return calls;
  }

  Future<void> pumpShell(WidgetTester tester) async {
    await tester.pumpWidget(harness(const AppShell()));
    await tester.pumpAndSettle();
  }

  /// A footer destination, by its INACTIVE icon.
  ///
  /// Not by its label: "Service" is also a word on the screen that tab opens,
  /// and Home spells the same destinations out on its quick-action tiles — but
  /// those tiles carry the filled icons, and only the footer draws the outlined
  /// ones.
  Finder footerTab(IconData icon) => find.byIcon(icon);

  /// The page's heading, told apart from the footer label of the same name.
  ///
  /// Since the screen name became a [PageTitle] instead of an all-caps caption
  /// in the app bar, "Service" is a word in two places at once — the heading
  /// and the footer destination — so a bare `find.text` matches both.
  Finder heading(String text) =>
      find.descendant(of: find.byType(PageTitle), matching: find.text(text));

  /// "We are on Home, with nothing pushed over it."
  ///
  /// NOT `find.text('HOME')`. The screen's name used to be a caption in the app
  /// bar and that string was the anchor; the name is a [PageTitle] in the page
  /// now, and Home is the one tab that has none — its greeting is its heading.
  /// The two facts together pin the shell down: no heading means Home, and no
  /// back arrow means nothing is pushed over it.
  void expectOnHome() {
    expect(find.byType(PageTitle), findsNothing);
    expect(find.byTooltip('Back'), findsNothing);
  }

  /// The system back button, as the engine delivers it.
  Future<void> pressBack(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
  }

  testWidgets('back on another tab returns to Home', (tester) async {
    await pumpShell(tester);

    await tester.tap(footerTab(Icons.build_outlined));
    await tester.pumpAndSettle();
    expect(heading('Service'), findsOneWidget);

    await pressBack(tester);

    expectOnHome();
    // …and it did NOT also ask to leave: one press, one thing undone.
    expect(find.text('Exit Enersol?'), findsNothing);
  });

  testWidgets('back on Home asks before closing the app', (tester) async {
    final calls = captureSystemCalls();
    await pumpShell(tester);

    await pressBack(tester);

    expect(find.text('Exit Enersol?'), findsOneWidget);
    expect(calls, isEmpty);

    await tester.tap(find.text('Stay'));
    await tester.pumpAndSettle();

    expect(find.text('Exit Enersol?'), findsNothing);
    expectOnHome();
    expect(calls, isEmpty);
  });

  testWidgets('confirming the question closes the app', (tester) async {
    final calls = captureSystemCalls();
    await pumpShell(tester);

    await pressBack(tester);
    await tester.tap(find.text('Exit'));
    await tester.pumpAndSettle();

    expect(calls, contains('SystemNavigator.pop'));
  });

  testWidgets('back again while the question is up dismisses it, and stays',
      (tester) async {
    final calls = captureSystemCalls();
    await pumpShell(tester);

    await pressBack(tester);
    expect(find.text('Exit Enersol?'), findsOneWidget);

    // The question is a route of its own, so back takes it away — the way it
    // takes away any dialog. What it must not do is read as an answer.
    await pressBack(tester);

    expect(find.text('Exit Enersol?'), findsNothing);
    expectOnHome();
    expect(calls, isEmpty);
  });

  testWidgets('back closes an open drawer before anything else',
      (tester) async {
    await pumpShell(tester);

    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    expect(find.byType(AppDrawer), findsOneWidget);

    await pressBack(tester);

    expect(find.byType(AppDrawer), findsNothing);
    // The screen behind it is untouched, and the app is not asking to leave.
    expectOnHome();
    expect(find.text('Exit Enersol?'), findsNothing);
  });

  testWidgets('back pops a pushed screen rather than switching tab',
      (tester) async {
    await pumpShell(tester);

    await tester.tap(find.byTooltip('Alerts'));
    await tester.pumpAndSettle();
    expect(heading('Alerts'), findsOneWidget);

    await pressBack(tester);

    expect(heading('Alerts'), findsNothing);
    expectOnHome();
    expect(find.text('Exit Enersol?'), findsNothing);
  });

  group('a sheet with something half-written in it', () {
    Future<void> openRaiseSheet(WidgetTester tester) async {
      await tester.pumpWidget(harness(
        const ServiceScreen(),
        repository: repoWith((_) => ok(const {'requests': []})),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Raise a request'));
      await tester.pumpAndSettle();
      expect(find.text('Raise a service request'), findsOneWidget);
    }

    testWidgets('back closes it outright when nothing has been typed',
        (tester) async {
      await openRaiseSheet(tester);

      await pressBack(tester);

      expect(find.text('Raise a service request'), findsNothing);
      expect(find.text('Discard this request?'), findsNothing);
    });

    testWidgets('back asks before throwing away what was typed',
        (tester) async {
      await openRaiseSheet(tester);
      await tester.enterText(
        find.byType(TextFormField).last,
        'Output dropped after the rain last week.',
      );
      await tester.pumpAndSettle();

      await pressBack(tester);
      expect(find.text('Discard this request?'), findsOneWidget);

      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();

      // Still there, still typed in.
      expect(find.text('Raise a service request'), findsOneWidget);
      expect(
        find.text('Output dropped after the rain last week.'),
        findsOneWidget,
      );

      await pressBack(tester);
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();

      expect(find.text('Raise a service request'), findsNothing);
    });
  });
}
