import 'package:enersol_customer/shared/widgets/app_header.dart';
import 'package:enersol_customer/shared/widgets/app_logo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// The logo must be centred on the SCREEN, not on whatever space the buttons
/// leave over.
///
/// Regression suite for a real complaint: the bell was added to the trailing
/// side and nothing balanced the leading side, so the logo sat 22 logical
/// pixels left of centre on every shell tab while the footer's own items stayed
/// centred. A tolerance of half a pixel, because a Row/Stack layout should land
/// this exactly.
void main() {
  setUpAll(useOfflineFonts);

  const tolerance = 0.5;

  Future<double> logoOffsetFromCentre(
    WidgetTester tester, {
    required bool bell,
    required bool menu,
    required bool back,
    String? title,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        appBar: AppHeader(
          title: title,
          showBack: back,
          onBack: () {},
          onAlertsTap: bell ? () {} : null,
          onMenuTap: menu ? () {} : null,
        ),
        body: const SizedBox.shrink(),
      ),
    ));

    final logo = tester.getCenter(find.byType(AppLogo));
    final screen = tester.getSize(find.byType(MaterialApp)).width / 2;
    return logo.dx - screen;
  }

  testWidgets('is centred with the bell and the menu both present',
      (tester) async {
    final offset = await logoOffsetFromCentre(
      tester,
      bell: true,
      menu: true,
      back: false,
    );
    expect(offset.abs(), lessThan(tolerance));
  });

  testWidgets('is centred on a pushed screen, with only the back button',
      (tester) async {
    final offset = await logoOffsetFromCentre(
      tester,
      bell: false,
      menu: false,
      back: true,
    );
    expect(offset.abs(), lessThan(tolerance));
  });

  testWidgets('does not shift when the back button appears', (tester) async {
    final without = await logoOffsetFromCentre(
      tester,
      bell: true,
      menu: true,
      back: false,
    );
    final with_ = await logoOffsetFromCentre(
      tester,
      bell: true,
      menu: true,
      back: true,
    );
    expect((with_ - without).abs(), lessThan(tolerance));
  });

  testWidgets('the title caption is centred under the logo', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        appBar: AppHeader(
          title: 'SETTINGS',
          showBack: true,
          onAlertsTap: () {},
          onMenuTap: () {},
        ),
        body: const SizedBox.shrink(),
      ),
    ));

    final caption = tester.getCenter(find.text('SETTINGS'));
    final screen = tester.getSize(find.byType(MaterialApp)).width / 2;
    expect((caption.dx - screen).abs(), lessThan(tolerance));
  });

  testWidgets('the bell shows the unread count, and hides it at zero',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        appBar: AppHeader(unread: 7, onAlertsTap: () {}, showBack: false),
        body: const SizedBox.shrink(),
      ),
    ));
    expect(find.text('7'), findsOneWidget);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        appBar: AppHeader(unread: 0, onAlertsTap: () {}, showBack: false),
        body: const SizedBox.shrink(),
      ),
    ));
    expect(find.text('0'), findsNothing);
  });

  testWidgets('caps the badge at 99+', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        appBar: AppHeader(unread: 250, onAlertsTap: () {}, showBack: false),
        body: const SizedBox.shrink(),
      ),
    ));
    expect(find.text('99+'), findsOneWidget);
  });

  testWidgets('the bell is tappable through the logo layer', (tester) async {
    // The logo fills the bar in a Stack; without IgnorePointer it would swallow
    // taps meant for the buttons underneath it.
    var tapped = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        appBar: AppHeader(
          onAlertsTap: () => tapped = true,
          showBack: false,
        ),
        body: const SizedBox.shrink(),
      ),
    ));
    await tester.tap(find.byIcon(Icons.notifications_none_rounded));
    expect(tapped, isTrue);
  });
}
