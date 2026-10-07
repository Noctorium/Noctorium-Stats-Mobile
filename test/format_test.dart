import 'package:flutter_test/flutter_test.dart';
import 'package:noctorium_stats/format.dart';
import 'package:noctorium_stats/stats.dart';

import 'fixtures.dart';

void main() {
  test('counts are grouped in thousands', () {
    expect(count(0), '0');
    expect(count(1553), '1,553');
    expect(count(1234567), '1,234,567');
  });

  test('hours keep a decimal only while it means something', () {
    expect(hours(0), '0');
    expect(hours(.4), '0.4');
    expect(hours(1.7), '1.7');
    expect(hours(9.96), '10.0');
    expect(hours(64.8), '65');
    expect(hours(1234.4), '1,234');
  });

  test('minutes become hours, and the minutes go once they are noise', () {
    expect(minutes(0), '0 min');
    expect(minutes(45), '45 min');
    expect(minutes(60), '1 h');
    expect(minutes(200), '3 h 20 min');
    expect(minutes(1227), '20 h');
    expect(minutes(60000), '1,000 h');
  });

  test('plurals', () {
    expect(plural(1, 'song'), '1 song');
    expect(plural(32, 'song'), '32 songs');
    expect(plural(1553, 'play'), '1,553 plays');
    expect(plural(2, 'day'), '2 days');
  });

  test('hours of the day on either kind of clock', () {
    expect(hourOfDay(0, use24: true), '00:00');
    expect(hourOfDay(21, use24: true), '21:00');
    expect(hourOfDay(0, use24: false), '12 am');
    expect(hourOfDay(12, use24: false), '12 pm');
    expect(hourOfDay(21, use24: false), '9 pm');
  });

  test('weekdays count from Monday', () {
    expect(weekday(1), 'Monday');
    expect(weekday(7), 'Sunday');
    expect(weekdayShort(6), 'Sat');
  });

  group('when something was played', () {
    final now = DateTime.utc(2026, 10, 7, 18, 47); // 21:47 on the listener's clock
    const offset = Duration(hours: 3);
    String at(DateTime instant, {bool use24 = true}) => whenPlayed(instant, now, offset, use24: use24);

    test('moments ago', () {
      expect(at(now.subtract(const Duration(seconds: 20))), 'Just now');
      expect(at(now.subtract(const Duration(minutes: 12))), '12 min ago');
    });

    test('today and yesterday on the listener\'s clock, not the server\'s', () {
      expect(at(DateTime.utc(2026, 10, 7, 9)), 'Today, 12:00');
      // 22:25 UTC on the 6th is 01:25 on the 7th three hours east: today, not yesterday.
      expect(at(DateTime.utc(2026, 10, 6, 22, 25)), 'Today, 01:25');
      expect(at(DateTime.utc(2026, 10, 6, 19, 10)), 'Yesterday, 22:10');
      expect(at(DateTime.utc(2026, 10, 6, 19, 10), use24: false), 'Yesterday, 10:10 pm');
    });

    test('this week by day, then by date', () {
      expect(at(DateTime.utc(2026, 10, 3, 18, 10)), 'Saturday, 21:10');
      expect(at(DateTime.utc(2026, 9, 28, 18, 10)), '28 Sep, 21:10');
      expect(at(DateTime.utc(2025, 12, 31, 12)), '31 Dec 2025');
    });

    test('the last play as a sentence', () {
      expect(lastPlayed(null, now, offset, use24: true), 'Nothing played yet');
      expect(lastPlayed(now.subtract(const Duration(minutes: 5)), now, offset, use24: true), 'Last played 5 min ago');
      expect(lastPlayed(DateTime.utc(2026, 10, 7, 9), now, offset, use24: true), 'Last played today at 12:00');
      expect(lastPlayed(DateTime.utc(2026, 10, 6, 9), now, offset, use24: true), 'Last played yesterday at 12:00');
      expect(lastPlayed(DateTime.utc(2026, 10, 3, 9), now, offset, use24: true), 'Last played on Saturday');
      expect(lastPlayed(DateTime.utc(2026, 8, 3, 9), now, offset, use24: true), 'Last played on 3 August');
    });
  });

  group('what a range covers', () {
    test('a week, a month, all time', () {
      expect(period(Stats.parse(fixture('stats-listener-7d.json')), fixtureNow, fixtureOffset), '1 – 7 October 2026');
      expect(period(Stats.parse(fixture('stats-listener-30d.json')), fixtureNow, fixtureOffset), '8 Sep – 7 Oct 2026');
      expect(period(Stats.parse(fixture('stats-listener-365d.json')), fixtureNow, fixtureOffset),
          '8 Oct 2025 – 7 Oct 2026');
      expect(period(Stats.parse(fixture('stats-listener-all.json')), fixtureNow, fixtureOffset), 'Since 14 Aug 2025');
      expect(period(Stats.parse(fixture('stats-empty-all.json')), fixtureNow, fixtureOffset),
          'Everything you have played');
      expect(rangeSpan(StatsRange.quarter, fixtureNow, fixtureOffset), '10 Jul – 7 Oct 2026');
      expect(rangeSpan(StatsRange.all, fixtureNow, fixtureOffset), 'Everything you have played');
    });
  });

  test('timeline bars are named for their tooltips and under the axis', () {
    final day = TimelinePoint(start: DateTime.utc(2026, 10, 3), streams: 7, minutes: 22);
    final month = TimelinePoint(start: DateTime.utc(2026, 3, 1), streams: 104, minutes: 300);
    final january = TimelinePoint(start: DateTime.utc(2026, 1, 1), streams: 1, minutes: 1);
    expect(bucketName(day, Bucket.day), 'Sat 3 Oct');
    expect(bucketName(month, Bucket.month), 'March 2026');
    expect(bucketTick(day, Bucket.day), '3 Oct');
    expect(bucketTick(month, Bucket.month), 'Mar');
    expect(bucketTick(january, Bucket.month), "Jan '26");
    expect(bucketTick(month, Bucket.month, withYear: true), "Mar '26");
    expect(dayTick(day), 'Sat');
  });
}
