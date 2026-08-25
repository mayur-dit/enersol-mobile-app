import 'package:enersol_customer/core/models/customer_models.dart';
import 'package:enersol_customer/features/documents/document_requests_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// The document chase, from the customer's side.
///
/// This screen is the whole point of the request feature — the office asks for
/// a paper, the customer sends it — and it shipped with no tests at all.
void main() {
  setUpAll(useOfflineFonts);

  Future<void> pumpRequests(
    WidgetTester tester, {
    List<Map<String, dynamic>>? requests,
    bool fails = false,
  }) async {
    // Tall enough that every section is built rather than left below the
    // ListView's cache extent.
    tester.view.physicalSize = const Size(1200, 3600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(harness(
      const DocumentRequestsScreen(),
      repository: repoWith(
        (_) => fails
            ? failure('Could not reach the office.')
            : ok({'requests': requests ?? const []}),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('outstanding requests lead, and are counted', (tester) async {
    await pumpRequests(tester, requests: [
      documentRequestRow(id: 'a', title: 'Electricity bill'),
      documentRequestRow(id: 'b', title: 'Aadhaar card'),
      documentRequestRow(id: 'c', title: 'Sanction letter', status: 'Completed'),
    ]);

    expect(find.text('2 documents needed'), findsOneWidget);
    expect(find.text('Electricity bill'), findsOneWidget);
    // Done rows are still listed, just not counted as outstanding.
    // SectionTitle upper-cases what it is given.
    expect(find.text('DONE'), findsOneWidget);
  });

  testWidgets('a request already sent waits on the office, not the customer',
      (tester) async {
    await pumpRequests(tester, requests: [
      documentRequestRow(status: 'Submitted'),
    ]);

    expect(find.text('SENT, WAITING ON US'), findsOneWidget);
    // Nothing is being asked of them, so the banner must not nag.
    expect(find.textContaining('documents needed'), findsNothing);
  });

  testWidgets('a rejected request comes back to the customer', (tester) async {
    await pumpRequests(tester, requests: [
      documentRequestRow(status: 'Rejected'),
    ]);

    expect(find.text('1 document needed'), findsOneWidget);
  });

  testWidgets('nothing outstanding says so plainly', (tester) async {
    await pumpRequests(tester);

    expect(find.text('Nothing needed from you'), findsOneWidget);
  });

  testWidgets('a failed read is an error, not "nothing needed"',
      (tester) async {
    // Telling somebody with four outstanding requests that they have none is
    // how a request sits open for a fortnight.
    await pumpRequests(tester, fails: true);

    expect(find.text("Couldn't load"), findsOneWidget);
    expect(find.text('Nothing needed from you'), findsNothing);
  });

  group('the upload sheet', () {
    testWidgets('will not send under the file count the office asked for',
        (tester) async {
      await pumpRequests(tester, requests: [
        documentRequestRow(title: 'Both sides of the bill', minFiles: 2),
      ]);

      await tester.tap(find.text('Both sides of the bill'));
      await tester.pumpAndSettle();

      expect(find.textContaining('needs 2 files in total'), findsOneWidget);
      expect(find.textContaining('2 still to add'), findsOneWidget);
    });

    testWidgets('counts what the office already holds towards the minimum',
        (tester) async {
      await pumpRequests(tester, requests: [
        documentRequestRow(
          title: 'Both sides of the bill',
          minFiles: 2,
          files: [
            {
              'name': 'front.jpg',
              'url': '/api/custom-api/enersol/serve-file?id=1&type=main',
              'source': 'customer',
              'size': 120,
            },
          ],
        ),
      ]);

      await tester.tap(find.text('Both sides of the bill'));
      await tester.pumpAndSettle();

      // One received, so one owed — not two.
      expect(find.textContaining('1 still to add'), findsOneWidget);
      expect(find.text('front.jpg'), findsOneWidget);
    });

    testWidgets('says nothing about a count when only one file is wanted',
        (tester) async {
      await pumpRequests(tester, requests: [documentRequestRow(minFiles: 1)]);

      await tester.tap(find.text('Latest electricity bill'));
      await tester.pumpAndSettle();

      expect(find.textContaining('in total'), findsNothing);
      expect(find.text('Add a file to send'), findsOneWidget);
    });
  });

  group('DocumentRequest', () {
    test('reads a due date in every shape the portal sends it', () {
      final iso = DocumentRequest.fromJson(
        documentRequestRow(dueDate: '2026-08-30T04:30:00.000Z'),
      );
      final wrapped = DocumentRequest.fromJson(
        documentRequestRow(dueDate: {r'$date': '2026-08-30T04:30:00.000Z'}),
      );
      final millis = DocumentRequest.fromJson(
        documentRequestRow(
          dueDate: DateTime.utc(2026, 8, 30, 4, 30).millisecondsSinceEpoch,
        ),
      );

      // A due date that parsed to null would take `isOverdue` with it, and the
      // request would sit there looking optional.
      for (final r in [iso, wrapped, millis]) {
        expect(r.dueDate, isNotNull);
        expect(r.dueDate!.toUtc(), DateTime.utc(2026, 8, 30, 4, 30));
      }
    });

    test('no due date at all is not overdue', () {
      final r = DocumentRequest.fromJson(documentRequestRow());
      expect(r.dueDate, isNull);
      expect(r.isOverdue, isFalse);
    });

    test('a passed deadline on a request still owed is overdue', () {
      final r = DocumentRequest.fromJson(
        documentRequestRow(dueDate: '2026-01-01T04:30:00.000Z'),
      );
      expect(r.isOverdue, isTrue);
    });

    test('a passed deadline on a request already sent is not', () {
      final r = DocumentRequest.fromJson(
        documentRequestRow(
          status: 'Submitted',
          dueDate: '2026-01-01T04:30:00.000Z',
        ),
      );
      // They have done their part; chasing them for it would be wrong.
      expect(r.isOverdue, isFalse);
    });
  });
}
