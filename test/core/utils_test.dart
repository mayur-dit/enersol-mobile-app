import 'package:enersol_customer/core/api/api_client.dart';
import 'package:enersol_customer/core/utils/date_format.dart';
import 'package:enersol_customer/core/utils/errors.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('date format', () {
    test('is the product-wide 05 Aug 2026', () {
      expect(fmtDate(DateTime(2026, 8, 5)), '05 Aug 2026');
    });

    test('pads a single-digit day', () {
      expect(fmtDate(DateTime(2026, 8, 5)), startsWith('05'));
    });

    test('shows the fallback for no date', () {
      expect(fmtDate(null), '—');
      expect(fmtDate(null, fallback: 'Not set'), 'Not set');
    });

    test('month/year for a validity window', () {
      expect(fmtMonthYear(DateTime(2031, 3, 20)), 'Mar 2031');
    });
  });

  group('parseDate', () {
    test('lands a UTC string in local time', () {
      final parsed = parseDate('2026-08-04T18:30:00.000Z');
      expect(parsed, isNotNull);
      expect(parsed!.isUtc, isFalse,
          reason:
              'a UTC DateTime formats on its UTC calendar day, which is how an '
              'IST date used to render as the day before');
      expect(parsed, DateTime.utc(2026, 8, 4, 18, 30).toLocal());
    });

    test('accepts an epoch-millisecond number', () {
      final ms = DateTime.utc(2026, 8, 5, 12).millisecondsSinceEpoch;
      expect(parseDate(ms), DateTime.fromMillisecondsSinceEpoch(ms).toLocal());
    });

    test(r'unwraps Mongo’s {$date: …}', () {
      expect(
        parseDate({r'$date': '2026-08-05T00:00:00.000Z'}),
        DateTime.utc(2026, 8, 5).toLocal(),
      );
    });

    test('is null for junk rather than throwing', () {
      expect(parseDate(null), isNull);
      expect(parseDate('not a date'), isNull);
    });
  });

  group('friendlyError', () {
    test('passes an ApiException message through', () {
      expect(
        friendlyError(ApiException('Please describe the problem.')),
        'Please describe the problem.',
      );
    });

    test('never leaks a Dart exception at a customer', () {
      final message = friendlyError(
        TypeError(),
        fallback: 'Something went wrong. Please try again.',
      );
      expect(message, 'Something went wrong. Please try again.');
      expect(message, isNot(contains('TypeError')));
    });

    test('falls back for a blank server message', () {
      expect(friendlyError(ApiException('   ')), isNotEmpty);
    });

    test('falls back for null', () {
      expect(friendlyError(null, fallback: 'nope'), 'nope');
    });
  });
}
