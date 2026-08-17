import 'package:enersol_customer/core/state/screen_refresh.dart';
import 'package:enersol_customer/features/application/application_screen.dart';
import 'package:enersol_customer/features/documents/documents_screen.dart';
import 'package:enersol_customer/shared/widgets/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// A screen must not go on showing the answer it got when it was built.
///
/// THE COMPLAINT BEHIND THIS FILE, twice over: a document was published, the
/// phone said "a new document is available", and the Documents tab still read
/// "No documents yet" — right until the app was killed and reopened. Same for a
/// lead confirmed while the app sat open. Both screens load once in `initState`
/// and live forever inside the shell's IndexedStack, so nothing ever asked
/// again.
void main() {
  setUpAll(useOfflineFonts);

  group('a notification re-reads the visible screen', () {
    testWidgets('documents that arrive after the screen was built show up',
        (tester) async {
      var documents = <Map<String, dynamic>>[];
      var calls = 0;

      final repo = repoWith((body) {
        if (body['action'] == 'documents') {
          calls++;
          return ok({'documents': documents});
        }
        return ok(const {});
      });

      await tester.pumpWidget(harness(const DocumentsScreen(), repository: repo));
      await tester.pumpAndSettle();

      expect(find.text('No documents yet'), findsOneWidget);
      final before = calls;

      // The office publishes one, and the push lands.
      documents = [
        {
          'ecd_title_str': 'Panel Warranty Card',
          'ecd_category_str': 'Panel Warranty',
          'ecd_fileUrl_str': '/api/custom-api/enersol/serve-file?id=1',
          'ecd_issuedOn_date': '2026-08-07T04:30:00.000Z',
        },
      ];
      repo.invalidate();
      await tester.pumpAndSettle();

      expect(calls, greaterThan(before));
      expect(find.text('No documents yet'), findsNothing);
      expect(find.text('Panel Warranty Card'), findsOneWidget);
    });

    testWidgets('an application confirmed while the app was open appears',
        (tester) async {
      var applications = <Map<String, dynamic>>[];

      final repo = repoWith((body) {
        if (body['action'] == 'discoms') return ok({'discoms': ['MGVCL']});
        return ok({'applications': applications});
      });

      await tester.pumpWidget(harness(const ApplicationScreen(), repository: repo));
      await tester.pumpAndSettle();
      expect(find.text('No applications yet'), findsOneWidget);

      applications = [applicationRow()];
      repo.invalidate();
      await tester.pumpAndSettle();

      expect(find.text('No applications yet'), findsNothing);
      expect(find.text('RE1007'), findsOneWidget);
    });
  });

  group('a screen behind the visible tab waits its turn', () {
    testWidgets('it re-reads when its tab is opened, not before',
        (tester) async {
      var calls = 0;
      final repo = repoWith((body) {
        if (body['action'] == 'documents') calls++;
        return ok({'documents': const []});
      });

      // Documents mounted while another tab is on screen — exactly its position
      // in the shell, where every tab stays built and mounted.
      final visible = ValueNotifier<int>(ShellTab.home);
      await tester.pumpWidget(harness(
        VisibleTab(
          index: visible,
          child: const DocumentsScreen(),
        ),
        repository: repo,
      ));
      await tester.pumpAndSettle();

      final afterFirstLoad = calls;
      repo.invalidate();
      await tester.pumpAndSettle();

      // Still off screen: news is remembered, not acted on. Four tabs firing a
      // request each on every notification is the cost this avoids.
      expect(calls, afterFirstLoad);

      visible.value = ShellTab.docs;
      await tester.pumpAndSettle();

      expect(calls, greaterThan(afterFirstLoad));
    });
  });
}
