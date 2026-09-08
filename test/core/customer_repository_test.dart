import 'package:enersol_customer/core/models/customer_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// What the app makes of the portal's replies.
///
/// The timeline itself is composed server-side now (the milestones ARE the
/// office's editable pipeline columns, so only the server can name and order
/// them). These tests pin the mapping and the derived values the screens read.
void main() {
  group('applications', () {
    test('maps a server-shaped application', () async {
      final repo = repoWith((_) => ok({
            'applications': [applicationRow()],
          }));

      final apps = await repo.applications();
      expect(apps, hasLength(1));

      final a = apps.single;
      expect(a.reference, 'LE-1007');
      expect(a.stage, 'Site Survey');
      expect(a.isConfirmed, isFalse);
      expect(a.capacityKw, 5);
      expect(a.discom, 'MGVCL');
      expect(a.siteAddress, 'Alkapuri, Vadodara');
      expect(a.stages.map((s) => s.label),
          ['New Enquiry', 'Site Survey', 'Proposal']);
      expect(a.stages.map((s) => s.state), [
        StageState.done,
        StageState.current,
        StageState.pending,
      ]);
      expect(a.stages.first.group, 'Enquiry');
    });

    test('is empty when the customer owns nothing', () async {
      final repo = repoWith((_) => ok({'applications': []}));
      expect(await repo.applications(), isEmpty);
    });

    test('drops stages the server sent without a label', () async {
      final repo = repoWith((_) => ok({
            'applications': [
              applicationRow(stages: [
                {'label': 'Design', 'state': 'current', 'group': 'Project'},
                {'label': '', 'state': 'pending', 'group': 'Project'},
              ]),
            ],
          }));
      expect((await repo.applications()).single.stages, hasLength(1));
    });

    test('treats an unknown stage state as pending rather than throwing',
        () async {
      final repo = repoWith((_) => ok({
            'applications': [
              applicationRow(stages: [
                {'label': 'Somewhere new', 'state': 'sideways'},
              ]),
            ],
          }));
      expect(
        (await repo.applications()).single.stages.single.state,
        StageState.pending,
      );
    });

    test('surfaces the server message rather than a bare status code',
        () async {
      final repo = repoWith((_) => failure('Not signed in', status: 401));
      await expectLater(
        repo.applications(),
        throwsA(predicate((e) => '$e' == 'Not signed in')),
      );
    });

    test('reports whether any job is commissioned', () async {
      final repo = repoWith((_) => ok({
            'applications': [
              applicationRow(reference: 'ESL0042', isConfirmed: true)
                ..['eslNumber'] = 'ESL0042',
            ],
          }));
      expect(repo.hasCommissionedProject, isNull, reason: 'not loaded yet');
      await repo.applications();
      expect(repo.hasCommissionedProject, isTrue);
    });

    test('an enquiry-only customer has no commissioned project', () async {
      final repo = repoWith((_) => ok({
            'applications': [applicationRow()],
          }));
      await repo.applications();
      expect(repo.hasCommissionedProject, isFalse);
    });

    test('coalesces two near-simultaneous callers onto one request', () async {
      var calls = 0;
      final repo = repoWith((_) {
        calls++;
        return ok({'applications': []});
      });

      await Future.wait([repo.applications(), repo.applications()]);
      expect(calls, 1);
    });
  });

  group('submitApplication', () {
    test('goes through the portal, not create-lead', () async {
      String? action;
      String? path;
      final repo = repoWith((body) {
        action = '${body['action']}';
        path = '${body['city']}';
        return ok({'leadId': 'LE-1042'});
      });

      final ref = await repo.submitApplication(
        name: 'Ramesh Patel',
        mobile: '9876543210',
        address: 'Alkapuri',
        city: 'Vadodara',
        pincode: '390007',
        capacityKw: 0,
        discom: 'MGVCL',
      );

      expect(action, 'submitApplication');
      expect(path, 'Vadodara');
      expect(ref, 'LE-1042');
    });

    test('never sends a lead field the server writes itself', () async {
      Map<String, dynamic>? seen;
      final repo = repoWith((body) {
        seen = body;
        return ok({'leadId': 'LE-1042'});
      });
      await repo.submitApplication(
        name: 'A',
        mobile: '9',
        address: '',
        city: 'V',
        pincode: '',
        capacityKw: 3,
        discom: 'MGVCL',
      );
      // The whole point of the portal action: a customer token cannot set the
      // owner, the stage or the origin of their own lead.
      expect(seen!.keys.where((k) => k.startsWith('elead_')), isEmpty);
    });

    test('drops the notes key when the customer left it blank', () async {
      Map<String, dynamic>? seen;
      final repo = repoWith((body) {
        seen = body;
        return ok({'leadId': 'RE1'});
      });
      await repo.submitApplication(
        name: 'A',
        mobile: '9',
        address: '',
        city: 'V',
        pincode: '',
        capacityKw: 0,
        discom: 'MGVCL',
        notes: '   ',
      );
      expect(seen!.containsKey('notes'), isFalse);
    });
  });

  group('documents', () {
    test('asks for the group it was given and maps the rows', () async {
      String? group;
      final repo = repoWith((body) {
        group = '${body['group']}';
        return ok({
          'documents': [
            {
              'ecd_title_str': 'Panel Warranty Card',
              'ecd_category_str': 'Panel Warranty',
              'ecd_issuedOn_date': '2026-07-01T00:00:00.000Z',
              'ecd_fileUrl_str': 'https://example.test/w.pdf',
              'ecd_size_num': 2048,
            },
          ],
        });
      });

      final docs = await repo.warrantyDocuments();
      expect(group, 'warranty');
      expect(docs.single.title, 'Panel Warranty Card');
      expect(docs.single.category, 'Panel Warranty');
      expect(docs.single.isDownloadable, isTrue);
      expect(docs.single.sizeLabel, '2 KB');
    });

    test('a document with no file is not offered for download', () async {
      final repo = repoWith((_) => ok({
            'documents': [
              {'ecd_title_str': 'Pending scan'},
            ],
          }));
      expect((await repo.otherDocuments()).single.isDownloadable, isFalse);
    });
  });

  group('serviceRequests', () {
    test('hides log lines the office marked internal', () async {
      final repo = repoWith((_) => ok({
            'requests': [
              {
                'esr_requestNumber_str': 'SR-260806-A1B',
                'esr_type_str': 'Low generation',
                'esr_description_str': 'Output dropped after the rain.',
                'esr_status_str': 'In Progress',
                'createdAt': '2026-08-01T04:30:00.000Z',
                'esr_logs_arr': [
                  {
                    'log_note_str': 'Engineer assigned.',
                    'log_by_str': 'Enersol',
                    'log_isVisibleToCustomer_bl': true,
                  },
                  {
                    'log_note_str': 'Customer is behind on payment.',
                    'log_by_str': 'Accounts',
                    'log_isVisibleToCustomer_bl': false,
                  },
                ],
              },
            ],
          }));

      final r = (await repo.serviceRequests()).single;
      expect(r.logs, hasLength(1));
      expect(r.logs.single.note, 'Engineer assigned.');
      expect(r.isOpen, isTrue);
    });

    test('a resolved request is closed', () async {
      final repo = repoWith((_) => ok({
            'requests': [
              {
                'esr_requestNumber_str': 'SR-1',
                'esr_status_str': 'Resolved',
                'esr_resolvedAt_date': '2026-08-04T00:00:00.000Z',
                'createdAt': '2026-08-01T00:00:00.000Z',
              },
            ],
          }));
      expect((await repo.serviceRequests()).single.isOpen, isFalse);
    });
  });

  group('raiseService', () {
    test('sends the type and description and returns the reference', () async {
      Map<String, dynamic>? seen;
      final repo = repoWith((body) {
        seen = body;
        return ok({'requestNumber': 'SR-260806-XYZ'});
      });

      final ref = await repo.raiseServiceRequest(
        type: 'Panel cleaning',
        description: 'Dust build-up after the storm.',
      );

      expect(seen?['action'], 'raiseService');
      expect(seen?['type'], 'Panel cleaning');
      expect(ref, 'SR-260806-XYZ');
    });

    test('surfaces the server sentence instead of a 500', () async {
      final repo =
          repoWith((_) => failure('Please describe the problem before sending.'));
      await expectLater(
        repo.raiseServiceRequest(type: 'Other', description: ''),
        throwsA(predicate(
            (e) => '$e' == 'Please describe the problem before sending.')),
      );
    });
  });

  group('generation', () {
    test('returns null when nothing has been recorded', () async {
      final repo = repoWith((_) => ok({'readings': [], 'capacityKw': 0}));
      expect(await repo.generation(), isNull);
    });

    test('reads real readings rather than a sample week', () async {
      final repo = repoWith((_) => ok({
            'capacityKw': 5.4,
            'readings': [
              {
                'egr_date': '2026-08-06T00:00:00.000Z',
                'egr_kwh_num': 21.5,
                'egr_lifetimeKwh_num': 1200,
                'egr_currentKw_num': 2.7,
              },
              {
                'egr_date': '2026-08-05T00:00:00.000Z',
                'egr_kwh_num': 19,
                'egr_lifetimeKwh_num': 1178.5,
              },
            ],
          }));

      final g = await repo.generation();
      expect(g, isNotNull);
      expect(g!.capacityKw, 5.4);
      expect(g.lifetimeKwh, 1200);
      // Newest first from the query; the chart reads oldest first.
      expect(g.last7Days.map((p) => p.kwh), [19, 21.5]);
    });
  });

  group('referrals', () {
    test('still returns a summary when the portal fails', () async {
      final repo = repoWith((_) => failure('boom'));
      final summary = await repo.referrals();
      expect(summary.referrals, isEmpty);
      expect(summary.code, isNotEmpty);
    });

    test('totals the points across referrals', () async {
      final repo = repoWith((_) => ok({
            'code': 'ENSL-1007',
            'referrals': [
              {'erf_name_str': 'A', 'erf_pointsEarned_num': 100},
              {
                'erf_name_str': 'B',
                'erf_pointsEarned_num': 250,
                'erf_status_str': 'Installed',
              },
            ],
          }));
      final summary = await repo.referrals();
      expect(summary.code, 'ENSL-1007');
      expect(summary.totalPoints, 350);
      expect(summary.convertedCount, 1);
    });
  });
}
