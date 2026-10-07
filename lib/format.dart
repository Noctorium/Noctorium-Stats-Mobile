/// Numbers, durations and times, written the way the dashboard shows them.
///
/// Every time here is turned into a wall-clock time with an offset it is handed, rather than with the
/// phone's `toLocal()`, so the same instant reads the same in a test on any machine as on the phone the
/// offset came from -- and the offset is the one the service was asked to count with, so the dashboard's
/// days and the service's days are the same days.
///
/// Dates are written day first, "7 Oct", in patterns spelled out here. They borrow intl's `en_US` names of
/// months and days only because that is the one locale it carries without loading anything; nothing about
/// the order is American.
library;

import 'package:intl/intl.dart';

import 'stats.dart';

final NumberFormat _whole = NumberFormat.decimalPattern('en');
final NumberFormat _tenths = NumberFormat('#,##0.0', 'en');

/// 1553 as "1,553".
String count(int value) => _whole.format(value);

/// Hours as the website shows them: a decimal while it means something, whole hours after that.
String hours(double value) {
  if (value <= 0) return '0';
  if (value < 10) return _tenths.format(value);
  return _whole.format(value.round());
}

/// "1 song", "32 songs".
String plural(int value, String one, [String? many]) => '${count(value)} ${value == 1 ? one : (many ?? '${one}s')}';

/// Minutes of listening: "45 min", "3 h 20 min", and only hours once there are enough of them that the
/// minutes are noise.
String minutes(int value) {
  if (value < 60) return '$value min';
  final h = value ~/ 60;
  final m = value % 60;
  if (h >= 10 || m == 0) return '${count(h)} h';
  return '$h h $m min';
}

/// [instant] on a clock [offset] from UTC, as a DateTime whose fields are that clock's (held as UTC so that
/// nothing moves it again).
DateTime wallClock(DateTime instant, Duration offset) => instant.toUtc().add(offset);

DateTime _day(DateTime wall) => DateTime.utc(wall.year, wall.month, wall.day);

/// The hour as a clock face says it: "21:00", or "9 pm" for somebody whose phone uses a 12-hour clock.
String hourOfDay(int hour, {required bool use24}) {
  if (use24) return '${hour.toString().padLeft(2, '0')}:00';
  final twelve = hour % 12 == 0 ? 12 : hour % 12;
  return '$twelve ${hour < 12 ? 'am' : 'pm'}';
}

String clockTime(DateTime wall, {required bool use24}) {
  if (use24) return '${wall.hour.toString().padLeft(2, '0')}:${wall.minute.toString().padLeft(2, '0')}';
  final twelve = wall.hour % 12 == 0 ? 12 : wall.hour % 12;
  return '$twelve:${wall.minute.toString().padLeft(2, '0')} ${wall.hour < 12 ? 'am' : 'pm'}';
}

const _weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

/// 1 is Monday, as the service and ISO count them.
String weekday(int day) => _weekdays[(day - 1) % 7];

String weekdayShort(int day) => weekday(day).substring(0, 3);

/// When something was played, relative to [now], on a clock [offset] from UTC: "Just now", "12 min ago",
/// "Today, 09:00", "Yesterday, 22:25", "Saturday, 21:10", "3 Oct, 21:10", "3 Oct 2025".
String whenPlayed(DateTime playedAt, DateTime now, Duration offset, {required bool use24}) {
  final ago = now.difference(playedAt);
  if (ago.inMinutes < 1) return 'Just now';
  if (ago.inMinutes < 60) return '${ago.inMinutes} min ago';
  final wall = wallClock(playedAt, offset);
  final today = _day(wallClock(now, offset));
  final days = today.difference(_day(wall)).inDays;
  final time = clockTime(wall, use24: use24);
  if (days <= 0) return 'Today, $time';
  if (days == 1) return 'Yesterday, $time';
  if (days < 7) return '${weekday(wall.weekday)}, $time';
  if (wall.year == today.year) return '${DateFormat('d MMM', 'en_US').format(wall)}, $time';
  return DateFormat('d MMM y', 'en_US').format(wall);
}

/// What the range covers, in words: "1 – 7 October", "8 Jul – 5 Oct 2026", "Since 14 Aug 2025".
String period(Stats stats, DateTime now, Duration offset) {
  final first = stats.firstPlay;
  if (stats.range == StatsRange.all && first != null) {
    return 'Since ${DateFormat('d MMM y', 'en_US').format(wallClock(first, offset))}';
  }
  return rangeSpan(stats.range, now, offset);
}

/// What a range covers before anything is known about what was played in it: today and the days before.
String rangeSpan(StatsRange range, DateTime now, Duration offset) {
  final days = range.days;
  if (days == null) return 'Everything you have played';
  final today = _day(wallClock(now, offset));
  return span(today.subtract(Duration(days: days - 1)), today);
}

/// Two days as a span, saying the month and year once where they are shared.
String span(DateTime start, DateTime end) {
  if (start.year != end.year) {
    return '${DateFormat('d MMM y', 'en_US').format(start)} – ${DateFormat('d MMM y', 'en_US').format(end)}';
  }
  if (start.month != end.month) {
    return '${DateFormat('d MMM', 'en_US').format(start)} – ${DateFormat('d MMM y', 'en_US').format(end)}';
  }
  return '${start.day} – ${DateFormat('d MMMM y', 'en_US').format(end)}';
}

/// A bar of the timeline, named as fully as a tooltip has room for: "Sat 3 Oct", "October 2026".
String bucketName(TimelinePoint point, Bucket bucket) => bucket == Bucket.month
    ? DateFormat('MMMM y', 'en_US').format(point.start)
    : DateFormat('EEE d MMM', 'en_US').format(point.start);

/// A bar of the timeline under its axis: "3 Oct", "Oct", or "Jan '26" where a year begins -- and with the year
/// wherever [withYear] asks, which the chart does for the first month it names.
String bucketTick(TimelinePoint point, Bucket bucket, {bool withYear = false}) {
  if (bucket == Bucket.day) return DateFormat('d MMM', 'en_US').format(point.start);
  final month = DateFormat('MMM', 'en_US').format(point.start);
  if (point.start.month != 1 && !withYear) return month;
  return "$month '${(point.start.year % 100).toString().padLeft(2, '0')}";
}

/// A day of the week the way a 7-day chart labels it: "Wed".
String dayTick(TimelinePoint point) => DateFormat('EEE', 'en_US').format(point.start);

/// The last play as a sentence: "Last played 12 min ago", "Last played today at 09:00", "Last played on
/// Saturday", "Last played on 3 Oct 2025".
String lastPlayed(DateTime? lastPlay, DateTime now, Duration offset, {required bool use24}) {
  if (lastPlay == null) return 'Nothing played yet';
  final ago = now.difference(lastPlay);
  if (ago.inMinutes < 1) return 'Last played just now';
  if (ago.inMinutes < 60) return 'Last played ${ago.inMinutes} min ago';
  final wall = wallClock(lastPlay, offset);
  final today = _day(wallClock(now, offset));
  final days = today.difference(_day(wall)).inDays;
  final time = clockTime(wall, use24: use24);
  if (days <= 0) return 'Last played today at $time';
  if (days == 1) return 'Last played yesterday at $time';
  if (days < 7) return 'Last played on ${weekday(wall.weekday)}';
  return 'Last played on ${DateFormat(wall.year == today.year ? 'd MMMM' : 'd MMM y', 'en_US').format(wall)}';
}
