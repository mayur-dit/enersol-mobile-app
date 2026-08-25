import 'package:enersol_customer/features/generation/generation_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// The generation tab, on the readings it actually gets.
void main() {
  setUpAll(useOfflineFonts);

  Map<String, dynamic> reading(String day, double kwh) => {
        'egr_date': '${day}T04:30:00.000Z',
        'egr_kwh_num': kwh,
        'egr_lifetimeKwh_num': 1200,
        'egr_currentKw_num': 0,
      };

  Future<void> pumpWith(
    WidgetTester tester,
    List<Map<String, dynamic>> readings,
  ) async {
    // Tall enough that the whole screen — hero, stats, the week chart and the
    // impact card — is built rather than left below the ListView's cache
    // extent, so a chart that throws throws here.
    tester.view.physicalSize = const Size(1200, 3600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(harness(
      const GenerationScreen(),
      repository: repoWith(
        (_) => ok({'readings': readings, 'capacityKw': 5}),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('a week of zero readings draws instead of throwing',
      (tester) async {
    // A commissioned system that has not produced yet — or an engineer who
    // keyed in a row of zeros — collapsed the chart's whole y range to 0, and
    // the grid interval computed from it came out as 0. fl_chart asserts on
    // that, so the tab threw where it should have drawn a flat line.
    await pumpWith(tester, [
      reading('2026-08-16', 0),
      reading('2026-08-17', 0),
      reading('2026-08-18', 0),
    ]);

    expect(tester.takeException(), isNull);
    expect(find.text('LAST 7 DAYS'), findsOneWidget);
  });

  testWidgets('real readings still render', (tester) async {
    await pumpWith(tester, [
      reading('2026-08-16', 18.4),
      reading('2026-08-17', 21.2),
    ]);

    expect(tester.takeException(), isNull);
    expect(find.text('YOUR IMPACT'), findsOneWidget);
  });

  testWidgets('no readings at all is an empty state, not an error',
      (tester) async {
    await pumpWith(tester, const []);

    expect(find.text('Coming soon'), findsOneWidget);
  });

  testWidgets('a failed read says so rather than claiming nothing is connected',
      (tester) async {
    await tester.pumpWidget(harness(
      const GenerationScreen(),
      repository: repoWith((_) => failure('Could not reach the meter.')),
    ));
    await tester.pumpAndSettle();

    expect(find.text("Couldn't load"), findsOneWidget);
    expect(find.text('Coming soon'), findsNothing);
  });

  group('fmtKw', () {
    test('drops the decimal a whole number does not need', () {
      expect(fmtKw(3), '3 kW');
      expect(fmtKw(3.0), '3 kW');
    });

    test('keeps one decimal when there is one', () {
      expect(fmtKw(3.5), '3.5 kW');
      expect(fmtKw(3.45), '3.5 kW');
    });
  });
}
