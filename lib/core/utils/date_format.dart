import 'package:intl/intl.dart';

/// ONE date format for the whole app — `05 Aug 2026`, matching the admin panel
/// and the engineer PWA.
///
/// Before this file every screen carried its own `DateFormat('d MMM yyyy')`,
/// which printed `5 Aug 2026` — and, worse, printed the wrong DAY. The API
/// sends UTC (`2026-08-04T18:30:00.000Z`); `DateTime.parse` keeps that flag,
/// and `DateFormat` reads the calendar fields off the object as-is. For IST
/// (+5:30) a date saved as midnight local came back out as the previous day.
/// [fmtDate] converts to local time before formatting, so the customer sees the
/// same day the office entered.

final DateFormat _date = DateFormat('dd MMM yyyy');
final DateFormat _dateTime = DateFormat('dd MMM yyyy, h:mm a');
final DateFormat _time = DateFormat('h:mm a');
final DateFormat _monthYear = DateFormat('MMM yyyy');
final DateFormat _weekday = DateFormat('E');

/// `05 Aug 2026`. Returns [fallback] when there is no date.
String fmtDate(DateTime? value, {String fallback = '—'}) =>
    value == null ? fallback : _date.format(value.toLocal());

/// `05 Aug 2026, 6:30 PM`. Returns [fallback] when there is no date.
String fmtDateTime(DateTime? value, {String fallback = '—'}) =>
    value == null ? fallback : _dateTime.format(value.toLocal());

/// `6:30 PM`, for when the date is already on screen.
String fmtTime(DateTime? value, {String fallback = '—'}) =>
    value == null ? fallback : _time.format(value.toLocal());

/// `Aug 2026`, for a validity or completion window with no meaningful day.
String fmtMonthYear(DateTime? value, {String fallback = '—'}) =>
    value == null ? fallback : _monthYear.format(value.toLocal());

/// `Wed`, for chart axes and day labels.
String fmtWeekday(DateTime? value, {String fallback = ''}) =>
    value == null ? fallback : _weekday.format(value.toLocal());

/// Parse anything the portal may send for a date, in LOCAL time.
///
/// The single parse point for the app: API Maker returns dates as ISO strings,
/// as `{ $date: … }` wrappers, or as epoch milliseconds depending on the field,
/// and every one of them has to end up local before it is read or formatted.
DateTime? parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value.toLocal();
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value).toLocal();
    if (value is Map && value[r'$date'] != null) return parseDate(value[r'$date']);
    return DateTime.tryParse('$value')?.toLocal();
}
