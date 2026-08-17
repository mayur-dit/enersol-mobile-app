import 'package:enersol_customer/core/data/customer_repository.dart';
import 'package:enersol_customer/features/application/application_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// "My Applications" — the screen the whole customer app exists for.
///
/// Regression suite for two real complaints: a confirmed lead showed "no
/// application yet", and nothing said which stage the job had reached.
void main() {
  setUpAll(useOfflineFonts);

  Future<void> pumpWith(
    WidgetTester tester,
    List<Map<String, dynamic>> applications,
  ) async {
    await tester.pumpWidget(harness(
      const ApplicationScreen(),
      repository: repoWith((body) {
        if (body['action'] == 'discoms') return ok({'discoms': ['MGVCL']});
        return ok({'applications': applications});
      }),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('an enquiry with a customer login shows up, not "none yet"',
      (tester) async {
    await pumpWith(tester, [applicationRow()]);

    expect(find.text('No applications yet'), findsNothing);
    expect(find.text('RE1007'), findsOneWidget);
    expect(find.text('Enquiry'), findsOneWidget);
  });

  testWidgets('a confirmed job reads as a project', (tester) async {
    await pumpWith(tester, [
      applicationRow(
        reference: 'ESL0042',
        isConfirmed: true,
        status: 'In Progress',
        stage: 'Installation',
        stages: const [
          {'label': 'Enquiry confirmed', 'state': 'done', 'group': 'Enquiry'},
          {'label': 'Installation', 'state': 'current', 'group': 'Project'},
        ],
      ),
    ]);

    expect(find.text('ESL0042'), findsOneWidget);
    expect(find.text('Project'), findsOneWidget);
  });

  testWidgets('names the stage the job is actually in', (tester) async {
    await pumpWith(tester, [applicationRow(stage: 'Site Survey')]);
    expect(find.text('Now: Site Survey'), findsOneWidget);
  });

  testWidgets('falls back to the server stage when no step is current',
      (tester) async {
    await pumpWith(tester, [
      applicationRow(
        stage: 'Awaiting Sanction',
        stages: const [
          {'label': 'New Enquiry', 'state': 'done', 'group': 'Enquiry'},
        ],
      ),
    ]);
    expect(find.text('Now: Awaiting Sanction'), findsOneWidget);
  });

  testWidgets('counts the steps done', (tester) async {
    await pumpWith(tester, [applicationRow()]);
    expect(find.text('1 of 3 steps done'), findsOneWidget);
  });

  testWidgets('the timeline opens on tap, with its phase headings',
      (tester) async {
    await pumpWith(tester, [
      applicationRow(
        stages: const [
          {'label': 'Enquiry confirmed', 'state': 'done', 'group': 'Enquiry'},
          {'label': 'Design', 'state': 'current', 'group': 'Project'},
          {'label': 'DISCOM approval', 'state': 'pending', 'group': 'Approvals'},
        ],
      ),
    ]);

    expect(find.text('View timeline'), findsOneWidget);
    await tester.tap(find.text('View timeline'));
    await tester.pumpAndSettle();

    expect(find.text('Hide timeline'), findsOneWidget);
    expect(find.text('ENQUIRY'), findsOneWidget);
    expect(find.text('PROJECT'), findsOneWidget);
    expect(find.text('APPROVALS'), findsOneWidget);
    expect(find.text('DISCOM approval'), findsOneWidget);
  });

  testWidgets('the empty state offers the way to apply', (tester) async {
    await pumpWith(tester, const []);

    expect(find.text('No applications yet'), findsOneWidget);
    expect(find.text('Apply for solar'), findsOneWidget);

    await tester.tap(find.text('Apply for solar'));
    await tester.pumpAndSettle();
    expect(find.text('Apply for a solar installation'), findsOneWidget);
  });

  testWidgets('a failed load says so instead of "no applications"',
      (tester) async {
    await tester.pumpWidget(harness(
      const ApplicationScreen(),
      repository: repoWith((_) => failure('Not signed in', status: 401)),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Not signed in'), findsOneWidget);
    expect(find.text('No applications yet'), findsNothing);
  });

  group('the apply form', () {
    // A phone-shaped but TALL surface. The form runs to four cards and a
    // submit button; on the 800×600 default the button sits below the fold and
    // every attempt to scroll to it races the layout shifts that entering text
    // causes. Giving the test a window the form fits in tests the form, not
    // Flutter's scrolling.
    setUp(() {
      final view = TestWidgetsFlutterBinding.instance.platformDispatcher.views
          .first;
      view.physicalSize = const Size(1080, 3600);
      view.devicePixelRatio = 3;
    });

    tearDown(() {
      final view = TestWidgetsFlutterBinding.instance.platformDispatcher.views
          .first;
      view.resetPhysicalSize();
      view.resetDevicePixelRatio();
    });

    Future<void> submit(WidgetTester tester) async {
      await tester.tap(find.text('Submit application'));
      await tester.pumpAndSettle();
    }

    Future<void> openForm(WidgetTester tester) async {
      await pumpWith(tester, const []);
      await tester.tap(find.text('New Application'));
      await tester.pumpAndSettle();
    }

    testWidgets('will not submit without the required fields', (tester) async {
      await openForm(tester);
      await submit(tester);
      expect(find.textContaining('required'), findsWidgets);
    });

    testWidgets('rejects a mobile number that is not a real one',
        (tester) async {
      await openForm(tester);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Mobile number *'),
        '12345',
      );
      await submit(tester);

      expect(find.text('Enter a valid 10-digit mobile number'), findsOneWidget);
    });

    testWidgets('will not submit without an electricity board', (tester) async {
      await openForm(tester);

      for (final (label, value) in const [
        ('Full name *', 'Ramesh Patel'),
        ('Mobile number *', '9876543210'),
        ('Site address *', 'Alkapuri'),
        ('City *', 'Vadodara'),
        ('Pincode *', '390007'),
      ]) {
        await tester.enterText(
          find.widgetWithText(TextFormField, label),
          value,
        );
      }
      await submit(tester);

      // A dropdown cannot be caught by a TextFormField validator, so the form
      // says so itself rather than letting the server reject the lead.
      expect(
        find.text('Please select your electricity board.'),
        findsOneWidget,
      );
    });
  });

  testWidgets('a fresh submission is not answered from the coalescing cache',
      (tester) async {
    var applicationCalls = 0;
    final repo = repoWith((body) {
      switch ('${body['action']}') {
        case 'applications':
          applicationCalls++;
          return ok({'applications': []});
        case 'submitApplication':
          return ok({'leadId': 'RE1042'});
        default:
          return ok(const {});
      }
    });

    await repo.applications();
    expect(applicationCalls, 1);

    await repo.submitApplication(
      name: 'A',
      mobile: '9876543210',
      address: '',
      city: 'Vadodara',
      pincode: '',
      capacityKw: 0,
      projectType: 'Residential',
      discom: 'MGVCL',
    );
    await repo.applications();

    expect(applicationCalls, 2,
        reason: 'the list must not serve a stale "nothing here" straight after '
            'the customer filed something');
    // Keeps the analyzer honest about the import.
    expect(repo, isA<CustomerRepository>());
  });
}
