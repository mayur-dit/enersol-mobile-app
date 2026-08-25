import 'package:enersol_customer/core/models/customer_models.dart';
import 'package:enersol_customer/features/application/project_progress_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// The full progress of one job, and what is holding it up.
void main() {
  setUpAll(useOfflineFonts);

  /// The application the customer tapped to get here.
  Future<SolarApplication> anApplication() async {
    final repo = repoWith((_) => ok({
          'applications': [applicationRow(reference: 'RE1007')],
        }));
    return (await repo.applications()).first;
  }

  Future<void> pumpProgress(
    WidgetTester tester,
    SolarApplication app, {
    List<Map<String, dynamic>> requests = const [],
    bool requestsFail = false,
    bool applicationsFail = false,
  }) async {
    tester.view.physicalSize = const Size(1200, 3600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(harness(
      ProjectProgressScreen(application: app),
      repository: repoWith((body) {
        if (body['action'] == 'documentRequests') {
          return requestsFail
              ? failure('Could not reach the office.')
              : ok({'requests': requests});
        }
        return applicationsFail
            ? failure('Not signed in', status: 401)
            : ok({
                'applications': [applicationRow(reference: 'RE1007')],
              });
      }),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('draws the milestone ladder the customer came for',
      (tester) async {
    await pumpProgress(tester, await anApplication());

    expect(find.text('Site Survey'), findsWidgets);
    expect(find.text('Proposal'), findsOneWidget);
  });

  testWidgets('a failed blockers read does not hide the progress',
      (tester) async {
    // The ladder is the screen; the blockers are an annotation on it. A
    // `Future.wait` over both used to fail the pair, so a document-requests
    // read that errored answered "why has my project not moved?" with
    // "Couldn't load".
    await pumpProgress(tester, await anApplication(), requestsFail: true);

    expect(find.text("Couldn't load"), findsNothing);
    expect(find.text('Proposal'), findsOneWidget);
  });

  testWidgets('outstanding documents are announced at the top',
      (tester) async {
    await pumpProgress(
      tester,
      await anApplication(),
      requests: [
        documentRequestRow(id: 'a', title: 'Electricity bill'),
        documentRequestRow(id: 'b', title: 'Aadhaar card'),
      ],
    );

    // Somebody who opens this because their job has not moved should not have
    // to scroll a ladder to find out that the answer is "you".
    expect(find.textContaining('2'), findsWidgets);
    expect(find.text('ALSO NEEDED FROM YOU'), findsOneWidget);
    expect(find.text('Electricity bill'), findsOneWidget);
  });

  testWidgets('a request already answered is not counted as a blocker',
      (tester) async {
    await pumpProgress(
      tester,
      await anApplication(),
      requests: [documentRequestRow(status: 'Completed')],
    );

    expect(find.text('ALSO NEEDED FROM YOU'), findsNothing);
  });

  testWidgets('a failed application read is still an error', (tester) async {
    await pumpProgress(tester, await anApplication(), applicationsFail: true);

    expect(find.text("Couldn't load"), findsOneWidget);
  });
}
