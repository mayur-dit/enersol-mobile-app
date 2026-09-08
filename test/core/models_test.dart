import 'package:enersol_customer/core/models/customer_models.dart';
import 'package:enersol_customer/core/models/notification.dart';
import 'package:enersol_customer/core/theme/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';

/// The values the cards read straight off the models.
void main() {
  SolarApplication app(List<AppStage> stages, {String stage = 'Design'}) =>
      SolarApplication(
        reference: 'LE-1007',
        status: 'Open',
        stage: stage,
        capacityKw: 5,
        submittedOn: DateTime(2026, 8, 1),
        stages: stages,
      );

  group('SolarApplication.progress', () {
    test('counts the step in flight as half', () {
      final a = app(const [
        AppStage(label: 'a', state: StageState.done),
        AppStage(label: 'b', state: StageState.current),
        AppStage(label: 'c', state: StageState.pending),
        AppStage(label: 'd', state: StageState.pending),
      ]);
      // 1 done + half of the current one, over four steps.
      expect(a.progress, closeTo(0.375, 0.0001));
    });

    test('a job sitting in the first column is not reported as 0%', () {
      final a = app(const [
        AppStage(label: 'a', state: StageState.current),
        AppStage(label: 'b', state: StageState.pending),
      ]);
      expect(a.progress, greaterThan(0));
    });

    test('is 1 when every step is done', () {
      final a = app(const [
        AppStage(label: 'a', state: StageState.done),
        AppStage(label: 'b', state: StageState.done),
      ]);
      expect(a.progress, 1);
    });

    test('is 0 with no steps at all rather than dividing by zero', () {
      expect(app(const []).progress, 0);
    });
  });

  group('SolarApplication.currentLabel', () {
    test('prefers the step marked current', () {
      final a = app(const [
        AppStage(label: 'Site survey', state: StageState.current),
      ]);
      expect(a.currentLabel, 'Site survey');
    });

    test('falls back to the stage the server named', () {
      final a = app(
        const [AppStage(label: 'a', state: StageState.done)],
        stage: 'Installation',
      );
      expect(a.currentLabel, 'Installation');
    });

    test('falls back to the status when there is no stage either', () {
      final a = app(const [], stage: '');
      expect(a.currentLabel, 'Open');
    });
  });

  test('AppStage.stateFrom maps the server\'s words', () {
    expect(AppStage.stateFrom('done'), StageState.done);
    expect(AppStage.stateFrom('current'), StageState.current);
    expect(AppStage.stateFrom('pending'), StageState.pending);
    expect(AppStage.stateFrom(''), StageState.pending);
  });

  test('a lost application does not read as nearly finished', () {
    final a = SolarApplication(
      reference: 'RE1',
      status: 'Lost',
      capacityKw: 0,
      submittedOn: DateTime(2026, 1, 1),
      stages: const [],
    );
    expect(a.statusGradient, AppColors.rose);
  });

  group('AppNotification', () {
    test('prefers the mobile link', () {
      final n = AppNotification.fromJson(const {
        '_id': '1',
        'enot_link_str': '/sales/leads',
        'enot_mobileLink_str': '/application',
      });
      expect(n.link, '/application');
    });

    test('falls back to the web link so the row is still tappable', () {
      final n = AppNotification.fromJson(const {
        '_id': '1',
        'enot_link_str': '/after-sales/documents',
      });
      expect(n.link, '/after-sales/documents');
    });

    test('reads the unread flag strictly', () {
      expect(
        AppNotification.fromJson(const {'enot_isRead_bl': true}).isRead,
        isTrue,
      );
      expect(AppNotification.fromJson(const {}).isRead, isFalse);
    });
  });
}
