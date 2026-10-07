import 'package:flutter_test/flutter_test.dart';
import 'package:noctorium_stats/stats.dart';

import 'fixtures.dart';

void main() {
  group('A week of the listener', () {
    final stats = Stats.parse(fixture('stats-listener-7d.json'));

    test('has the four figures', () {
      expect(stats.range, StatsRange.week);
      expect(stats.streams, 32);
      expect(stats.uniqueTracks, 19);
      expect(stats.artists, 11);
      expect(stats.hours, 1.7);
      expect(stats.msPlayed, 6068133);
      expect(stats.isEmpty, isFalse);
    });

    test('reads instants as UTC', () {
      expect(stats.from, DateTime.utc(2026, 9, 30, 21));
      expect(stats.lastPlay, DateTime.utc(2026, 10, 7, 9, 0, 0, 405));
      expect(stats.lastPlay!.isUtc, isTrue);
    });

    test('splits by service, most played first, in the services\' colours', () {
      expect(stats.services.map((s) => s.service), [
        Service.youtubeMusic,
        Service.soundcloud,
        Service.spotify,
        Service.bandcamp,
        Service.vk,
      ]);
      expect(stats.services.first.streams, 13);
      expect(stats.services.first.hours, .7);
      expect(Service.spotify.colour.toARGB32(), 0xFF1ED760);
    });

    test('has the top songs and artists', () {
      expect(stats.topTracks, hasLength(10));
      expect(stats.topTracks.first.title, 'Harbour Lights');
      expect(stats.topTracks.first.artist, 'Night Tram');
      expect(stats.topTracks.first.service, Service.youtubeMusic);
      expect(stats.topTracks.first.streams, 5);
      expect(stats.topTracks.first.minutes, 21);
      expect(stats.topArtists, hasLength(10));
      expect(stats.topArtists.first.artist, 'Night Tram');
    });

    test('has a bar for every day, quiet ones included', () {
      expect(stats.timeline.bucket, Bucket.day);
      expect(stats.timeline.points, hasLength(7));
      expect(stats.timeline.points.first.start, DateTime.utc(2026, 10, 1));
      expect(stats.timeline.points.last.start, DateTime.utc(2026, 10, 7));
      expect(stats.timeline.points.fold<int>(0, (sum, p) => sum + p.streams), 32);
    });

    test('has every hour and every weekday', () {
      expect(stats.hourly.map((s) => s.index), List.generate(24, (i) => i));
      expect(stats.weekdays.map((s) => s.index), [1, 2, 3, 4, 5, 6, 7]);
      expect(stats.hourly.fold<int>(0, (sum, s) => sum + s.streams), 32);
    });

    test('has the recent plays and the streak', () {
      expect(stats.recent, hasLength(30));
      expect(stats.recent.first.title, 'Low Signal');
      expect(stats.recent.first.service, Service.soundcloud);
      expect(stats.streak.current, 12);
      expect(stats.streak.longest, 43);
    });
  });

  test('all time is counted by month, and whole hours arrive as integers', () {
    final stats = Stats.parse(fixture('stats-listener-all.json'));
    expect(stats.range, StatsRange.all);
    expect(stats.from, isNull);
    expect(stats.streams, 1553);
    expect(stats.hours, 78.0);
    expect(stats.services.first.hours, 32.0);
    expect(stats.timeline.bucket, Bucket.month);
    expect(stats.timeline.points, hasLength(15));
    expect(stats.timeline.points.first.start, DateTime.utc(2025, 8, 1));
    expect(stats.firstPlay, DateTime.utc(2025, 8, 14, 9, 3, 56, 754));
  });

  test('an account with nothing played is empty all the way through', () {
    final stats = Stats.parse(fixture('stats-empty-all.json'));
    expect(stats.isEmpty, isTrue);
    expect(stats.services, isEmpty);
    expect(stats.topTracks, isEmpty);
    expect(stats.timeline.points, isEmpty);
    expect(stats.recent, isEmpty);
    expect(stats.firstPlay, isNull);
    expect(stats.hourly, hasLength(24));
    expect(stats.hourly.every((slot) => slot.streams == 0), isTrue);
    expect(stats.streak.longest, 0);
  });

  test('YouTube videos are counted as YouTube Music', () {
    final stats = Stats.parse('''
      {"range": "30d", "streams": 6, "byProvider": [
        {"provider": "YOUTUBE_VIDEO", "streams": 2, "hours": 0.2},
        {"provider": "SPOTIFY", "streams": 3, "hours": 0.3},
        {"provider": "YOUTUBE_MUSIC", "streams": 2, "hours": 0.15},
        {"provider": "LOCAL", "streams": 1, "hours": 0.1},
        {"provider": "SOMETHING_NEW", "streams": 1, "hours": 0}
      ]}''');
    expect(stats.services.map((s) => (s.service, s.streams)), [
      (Service.youtubeMusic, 4),
      (Service.spotify, 3),
      (Service.local, 1),
      (Service.other, 1),
    ]);
    expect(stats.services.first.hours, .4);
    expect(Service.local.label, 'On this device');
  });

  test('missing parts read as nothing rather than failing', () {
    final stats = Stats.parse('{"streams": 3, "hourly": [{"hour": 21, "streams": 3, "minutes": 9}]}');
    expect(stats.range, StatsRange.all);
    expect(stats.hourly, hasLength(24));
    expect(stats.hourly[21].streams, 3);
    expect(stats.hourly[20].streams, 0);
    expect(stats.weekdays, hasLength(7));
    expect(stats.streak.current, 0);
  });

  test('anything that is not statistics is refused', () {
    expect(() => Stats.parse('{"error": "Not signed in."}'), throwsFormatException);
    expect(() => Stats.parse('<html><body>Bad gateway</body></html>'), throwsFormatException);
    expect(() => Stats.parse('[]'), throwsFormatException);
  });

  test('ranges round-trip through what the service is asked for', () {
    for (final range in StatsRange.values) {
      expect(StatsRange.fromQuery(range.query), range);
    }
    expect(StatsRange.fromQuery('3d'), isNull);
    expect(StatsRange.values.map((r) => r.label), ['7 days', '30 days', '90 days', 'Year', 'All time']);
  });
}
