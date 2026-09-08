import 'package:enersol_customer/features/home/home_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// The landing tab, and what it does when only half its data arrives.
void main() {
  setUpAll(useOfflineFonts);

  Future<void> pumpHome(
    WidgetTester tester, {
    required List<Map<String, dynamic>> applications,
    required bool generationFails,
  }) async {
    await tester.pumpWidget(harness(
      HomeScreen(onNavigate: (_) {}),
      repository: repoWith((body) {
        if (body['action'] == 'generation') {
          return generationFails
              ? failure('Meter sync is down.')
              : ok(const {'readings': []});
        }
        return ok({'applications': applications});
      }),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('a generation failure does not take the project card with it',
      (tester) async {
    // Home reads applications and generation together. `Future.wait` fails the
    // pair as soon as either side throws, so a meter read that errored used to
    // put "Couldn't load" over a project that had come back perfectly well.
    await pumpHome(
      tester,
      applications: [applicationRow(reference: 'LE-1007')],
      generationFails: true,
    );

    expect(find.text('LE-1007'), findsOneWidget);
    expect(find.text("Couldn't load"), findsNothing);
    // The strip is simply absent, exactly as for a system not yet commissioned.
    expect(find.text('YOUR GENERATION'), findsNothing);
  });

  testWidgets('a failed applications read is still an error, not an empty home',
      (tester) async {
    await tester.pumpWidget(harness(
      HomeScreen(onNavigate: (_) {}),
      repository: repoWith((_) => failure('Not signed in', status: 401)),
    ));
    await tester.pumpAndSettle();

    expect(find.text("Couldn't load"), findsOneWidget);
    expect(find.text('Go solar'), findsNothing);
  });

  testWidgets('no applications offers the way to start one', (tester) async {
    await pumpHome(tester, applications: const [], generationFails: false);

    expect(find.text('Go solar'), findsOneWidget);
    expect(find.text('Apply for solar'), findsWidgets);
  });
}
