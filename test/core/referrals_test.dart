import 'package:enersol_customer/core/models/customer_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// Refer & Earn: what is quoted on the way in, and what is shown on the way out.
void main() {
  group('submitApplication', () {
    test('sends a quoted referral code, upper-cased', () async {
      Map<String, dynamic> sent = const {};
      final repo = repoWith((body) {
        if (body['action'] == 'submitApplication') sent = body;
        return ok({'leadId': 'RE1042'});
      });

      await repo.submitApplication(
        name: 'Ramesh Patel',
        mobile: '9876543210',
        address: 'Alkapuri',
        city: 'Vadodara',
        pincode: '390007',
        capacityKw: 0,
        projectType: 'Residential',
        discom: 'MGVCL',
        referralCode: ' ensl-2 ',
      );

      expect(sent['referralCode'], 'ENSL-2');
    });

    test('omits the key entirely when no code was given', () async {
      Map<String, dynamic> sent = const {};
      final repo = repoWith((body) {
        if (body['action'] == 'submitApplication') sent = body;
        return ok({'leadId': 'RE1042'});
      });

      await repo.submitApplication(
        name: 'Ramesh Patel',
        mobile: '9876543210',
        address: 'Alkapuri',
        city: 'Vadodara',
        pincode: '390007',
        capacityKw: 0,
        projectType: 'Residential',
        discom: 'MGVCL',
      );

      expect(sent.containsKey('referralCode'), isFalse);
    });
  });

  group('referrals', () {
    Map<String, dynamic> referralRow({
      String name = 'Suresh',
      String status = 'Enquiry',
      num points = 0,
    }) =>
        {
          'erf_name_str': name,
          'erf_status_str': status,
          'erf_pointsEarned_num': points,
          'erf_referredOn_date': '2026-08-01T04:30:00.000Z',
        };

    test('carries the server\'s reward figure onto the summary', () async {
      final repo = repoWith((_) => ok({
            'code': 'ENSL-2',
            'pointsOnInstall': 1000,
            'referrals': [referralRow()],
          }));

      final summary = await repo.referrals();

      expect(summary.code, 'ENSL-2');
      expect(summary.pointsOnInstall, 1000);
      // Nothing is earned until the installation is done.
      expect(summary.totalPoints, 0);
      expect(summary.pendingCount, 1);
    });

    test('totals only what has actually been credited', () async {
      final repo = repoWith((_) => ok({
            'code': 'ENSL-2',
            'pointsOnInstall': 1000,
            'referrals': [
              referralRow(name: 'Suresh', status: 'Installed', points: 1000),
              referralRow(name: 'Mehul', status: 'In Progress'),
              referralRow(name: 'Kiran', status: 'Lost'),
            ],
          }));

      final summary = await repo.referrals();

      expect(summary.totalPoints, 1000);
      expect(summary.convertedCount, 1);
      // Lost referrals are not waiting on anything.
      expect(summary.pendingCount, 1);
    });

    test('a server that names no figure promises none', () async {
      final repo = repoWith((_) => ok({'code': 'ENSL-2', 'referrals': []}));

      final summary = await repo.referrals();

      expect(summary.pointsOnInstall, 0);
    });

    test('falls back to a summary rather than failing the screen', () async {
      final repo = repoWith((_) => failure('Not signed in', status: 401));

      final summary = await repo.referrals();

      expect(summary, isA<ReferralSummary>());
      expect(summary.referrals, isEmpty);
    });
  });
}
