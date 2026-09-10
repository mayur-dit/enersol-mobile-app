import 'package:enersol_customer/features/service/service_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// One call to action at a time.
///
/// Regression suite for a real complaint: on an empty list the screen showed a
/// full-width "Raise a request" button AND a floating "New request" button over
/// it — two labels, two shapes, one action. The FAB also sat over the spinner
/// and over the error panel.
void main() {
  setUpAll(useOfflineFonts);

  Map<String, dynamic> request({
    String reference = 'SR-260806-A1B',
    String status = 'Open',
  }) =>
      {
        'esr_requestNumber_str': reference,
        'esr_type_str': 'Low generation',
        'esr_description_str': 'Output dropped after the rain last week.',
        'esr_status_str': status,
        'esr_createdAt_date': '2026-08-01T04:30:00.000Z',
        'esr_logs_arr': const [],
      };

  Future<void> pumpWith(
    WidgetTester tester,
    List<Map<String, dynamic>> requests,
  ) async {
    await tester.pumpWidget(harness(
      const ServiceScreen(),
      repository: repoWith((_) => ok({'requests': requests})),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('an empty list offers exactly one way to raise a request',
      (tester) async {
    await pumpWith(tester, const []);

    expect(find.text('No service requests yet'), findsOneWidget);
    expect(find.text('Raise a request'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.text('New request'), findsNothing);
  });

  testWidgets('the floating button appears once there is a list',
      (tester) async {
    await pumpWith(tester, [request()]);

    expect(find.text('SR-260806-A1B  ·  01 Aug 2026'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
    // …and the empty state's button is gone with it.
    expect(find.text('Raise a request'), findsNothing);
  });

  testWidgets('no floating button over a failed load', (tester) async {
    await tester.pumpWidget(harness(
      const ServiceScreen(),
      repository: repoWith((_) => failure('Cannot reach the server.')),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Cannot reach the server.'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets('open and resolved requests are filed separately',
      (tester) async {
    await pumpWith(tester, [
      request(reference: 'SR-1'),
      {
        ...request(reference: 'SR-2', status: 'Resolved'),
        'esr_resolvedAt_date': '2026-08-04T00:00:00.000Z',
      },
    ]);

    expect(find.text('OPEN REQUESTS'), findsOneWidget);
    expect(find.text('HISTORY'), findsOneWidget);
  });

  testWidgets('the raise sheet opens from the empty state', (tester) async {
    await pumpWith(tester, const []);
    await tester.tap(find.text('Raise a request'));
    await tester.pumpAndSettle();

    expect(find.text('Raise a service request'), findsOneWidget);
    expect(find.text('Panel cleaning'), findsOneWidget);
  });

  testWidgets('the sheet refuses an empty description rather than the server',
      (tester) async {
    await pumpWith(tester, const []);
    await tester.tap(find.text('Raise a request'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Submit request'));
    await tester.pumpAndSettle();

    expect(find.text('Please describe the problem'), findsOneWidget);
  });

  testWidgets('warns a customer with no commissioned system, before they send',
      (tester) async {
    // The repository has to have loaded applications for it to know.
    final repo = repoWith((body) {
      if (body['action'] == 'applications') {
        return ok({
          'applications': [applicationRow()],
        });
      }
      return ok({'requests': []});
    });
    await repo.applications();

    await tester.pumpWidget(harness(const ServiceScreen(), repository: repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Raise a request'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('not commissioned yet'),
      findsOneWidget,
      reason: 'said up front, rather than discovered by being refused',
    );
  });
}
