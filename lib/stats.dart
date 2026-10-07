/// A listener's statistics, as the Noctorium service's `/api/stats` answers them.
///
/// Kept apart from the screens so it can be tested without one: everything here is a function of JSON that
/// came back from the service, read leniently -- a field the service adds later is ignored, and one it stops
/// sending reads as nothing rather than failing the whole dashboard.
library;

import 'dart:convert';
import 'dart:ui' show Color;

/// The five spans the service counts over, in the order the chips show them.
enum StatsRange {
  week('7d', '7 days', 7),
  month('30d', '30 days', 30),
  quarter('90d', '90 days', 90),
  year('365d', 'Year', 365),
  all('all', 'All time', null);

  const StatsRange(this.query, this.label, this.days);

  /// What the service is asked for: `range=7d` and so on.
  final String query;

  /// What the chip says.
  final String label;

  /// How many days back it reaches, today included; null for everything.
  final int? days;

  /// The range a stored value names, or null for one this build does not know.
  static StatsRange? fromQuery(String? value) {
    for (final range in values) {
      if (range.query == value) return range;
    }
    return null;
  }
}

/// Where a song was played from, as the listener knows it.
///
/// Several of the service's provider names are one service to a person -- a YouTube video played as music is
/// still YouTube Music -- so the split by service is counted over these rather than over the raw names.
enum Service {
  youtubeMusic('YouTube Music', Color(0xFFFF4E45)),
  soundcloud('SoundCloud', Color(0xFFFF7A1A)),
  spotify('Spotify', Color(0xFF1ED760)),
  bandcamp('Bandcamp', Color(0xFF629AA9)),
  vk('VK', Color(0xFF4C9BFF)),
  local('On this device', Color(0xFFCFC5DA)),
  other('Elsewhere', Color(0xFF8B8296));

  const Service(this.label, this.colour);

  final String label;
  final Color colour;

  static Service fromProvider(String provider) => switch (provider.toUpperCase()) {
        'YOUTUBE_MUSIC' || 'YOUTUBE_VIDEO' || 'YOUTUBE' => Service.youtubeMusic,
        'SOUNDCLOUD' => Service.soundcloud,
        'SPOTIFY' => Service.spotify,
        'BANDCAMP' => Service.bandcamp,
        'VK' => Service.vk,
        'LOCAL' => Service.local,
        _ => Service.other,
      };
}

class ServiceShare {
  const ServiceShare({required this.service, required this.streams, required this.hours});

  final Service service;
  final int streams;
  final double hours;
}

class TopTrack {
  const TopTrack({
    required this.title,
    required this.artist,
    required this.service,
    required this.streams,
    required this.minutes,
  });

  final String title;
  final String artist;
  final Service service;
  final int streams;
  final int minutes;
}

class TopArtist {
  const TopArtist({required this.artist, required this.streams, required this.minutes, required this.tracks});

  final String artist;
  final int streams;
  final int minutes;

  /// How many different songs of theirs were played.
  final int tracks;
}

/// Whether each bar of the timeline is a day or a month: the service switches to months past about four
/// months of days, which no phone could show legibly.
enum Bucket { day, month }

class TimelinePoint {
  const TimelinePoint({required this.start, required this.streams, required this.minutes});

  /// The first day the bar covers, as a date on the listener's own calendar (held at midnight UTC so that
  /// nothing here ever moves it by a time zone).
  final DateTime start;
  final int streams;
  final int minutes;
}

class Timeline {
  const Timeline({required this.bucket, required this.points});

  final Bucket bucket;
  final List<TimelinePoint> points;
}

/// Plays in one hour of the day (0 to 23) or one day of the week (1 Monday to 7 Sunday), on the listener's
/// own clock.
class Slot {
  const Slot({required this.index, required this.streams, required this.minutes});

  final int index;
  final int streams;
  final int minutes;
}

class RecentPlay {
  const RecentPlay({
    required this.title,
    required this.artist,
    required this.service,
    required this.playedAt,
    required this.msPlayed,
  });

  final String title;
  final String artist;
  final Service service;

  /// The instant it was played, in UTC.
  final DateTime playedAt;
  final int msPlayed;
}

class Streak {
  const Streak({required this.current, required this.longest});

  /// Days in a row up to today, or up to yesterday when today has nothing yet.
  final int current;
  final int longest;
}

class Stats {
  const Stats({
    required this.range,
    required this.from,
    required this.streams,
    required this.uniqueTracks,
    required this.artists,
    required this.msPlayed,
    required this.hours,
    required this.firstPlay,
    required this.lastPlay,
    required this.services,
    required this.topTracks,
    required this.topArtists,
    required this.timeline,
    required this.hourly,
    required this.weekdays,
    required this.recent,
    required this.streak,
  });

  final StatsRange range;

  /// Where the range begins, or null for all time.
  final DateTime? from;
  final int streams;
  final int uniqueTracks;
  final int artists;
  final int msPlayed;
  final double hours;
  final DateTime? firstPlay;
  final DateTime? lastPlay;

  /// The split by service, most played first.
  final List<ServiceShare> services;
  final List<TopTrack> topTracks;
  final List<TopArtist> topArtists;
  final Timeline timeline;

  /// Always 24 entries, hour 0 first.
  final List<Slot> hourly;

  /// Always 7 entries, Monday first.
  final List<Slot> weekdays;
  final List<RecentPlay> recent;
  final Streak streak;

  /// Nothing at all was played in this range.
  bool get isEmpty => streams == 0;

  /// Reads the body `/api/stats` answers with.
  ///
  /// Throws [FormatException] for anything that is not statistics -- an HTML error page from a proxy, say,
  /// or the `{ error }` the service answers a problem with.
  static Stats parse(String body) {
    final dynamic root;
    try {
      root = jsonDecode(body);
    } on FormatException {
      throw const FormatException('The service did not answer with statistics');
    }
    if (root is! Map<String, dynamic> || root['streams'] is! num) {
      throw const FormatException('The service did not answer with statistics');
    }
    return Stats.fromJson(root);
  }

  factory Stats.fromJson(Map<String, dynamic> json) {
    final timeline = _map(json['timeline']);
    return Stats(
      range: StatsRange.fromQuery(json['range'] as String?) ?? StatsRange.all,
      from: _instant(json['from']),
      streams: _int(json['streams']),
      uniqueTracks: _int(json['uniqueTracks']),
      artists: _int(json['artists']),
      msPlayed: _int(json['msPlayed']),
      hours: _double(json['hours']),
      firstPlay: _instant(json['firstPlay']),
      lastPlay: _instant(json['lastPlay']),
      services: _services(_list(json['byProvider'])),
      topTracks: [
        for (final row in _list(json['topTracks']))
          TopTrack(
            title: _string(row['title']),
            artist: _string(row['artist']),
            service: Service.fromProvider(_string(row['provider'])),
            streams: _int(row['streams']),
            minutes: _int(row['minutes']),
          ),
      ],
      topArtists: [
        for (final row in _list(json['topArtists']))
          TopArtist(
            artist: _string(row['artist']),
            streams: _int(row['streams']),
            minutes: _int(row['minutes']),
            tracks: _int(row['tracks']),
          ),
      ],
      timeline: Timeline(
        bucket: timeline['bucket'] == 'month' ? Bucket.month : Bucket.day,
        points: [
          for (final row in _list(timeline['points']))
            if (_date(row['start']) case final start?)
              TimelinePoint(start: start, streams: _int(row['streams']), minutes: _int(row['minutes'])),
        ],
      ),
      hourly: _slots(_list(json['hourly']), 'hour', first: 0, count: 24),
      weekdays: _slots(_list(json['weekdays']), 'day', first: 1, count: 7),
      recent: [
        for (final row in _list(json['recent']))
          if (_instant(row['playedAt']) case final playedAt?)
            RecentPlay(
              title: _string(row['title']),
              artist: _string(row['artist']),
              service: Service.fromProvider(_string(row['provider'])),
              playedAt: playedAt,
              msPlayed: _int(row['msPlayed']),
            ),
      ],
      streak: Streak(
        current: _int(_map(json['streak'])['current']),
        longest: _int(_map(json['streak'])['longest']),
      ),
    );
  }
}

/// The provider rows folded into services, so YouTube Music and YouTube videos are one bar.
List<ServiceShare> _services(List<Map<String, dynamic>> rows) {
  final streams = <Service, int>{};
  final hours = <Service, double>{};
  for (final row in rows) {
    final service = Service.fromProvider(_string(row['provider']));
    streams[service] = (streams[service] ?? 0) + _int(row['streams']);
    hours[service] = (hours[service] ?? 0) + _double(row['hours']);
  }
  final shares = [
    for (final service in streams.keys)
      ServiceShare(service: service, streams: streams[service]!, hours: (hours[service]! * 10).round() / 10),
  ];
  // Most played first; a tie goes the way the services are listed, so the order never flickers.
  shares.sort((a, b) {
    final byStreams = b.streams.compareTo(a.streams);
    return byStreams != 0 ? byStreams : a.service.index.compareTo(b.service.index);
  });
  return shares;
}

/// Exactly [count] slots, [first] onwards, whatever the service sent: one it left out is a quiet one.
List<Slot> _slots(List<Map<String, dynamic>> rows, String key, {required int first, required int count}) {
  final byIndex = {for (final row in rows) _int(row[key]): row};
  return [
    for (var index = first; index < first + count; index++)
      Slot(index: index, streams: _int(byIndex[index]?['streams']), minutes: _int(byIndex[index]?['minutes'])),
  ];
}

Map<String, dynamic> _map(Object? value) => value is Map<String, dynamic> ? value : const {};

List<Map<String, dynamic>> _list(Object? value) =>
    value is List ? value.whereType<Map<String, dynamic>>().toList() : const [];

String _string(Object? value) => value is String ? value : '';

int _int(Object? value) => value is num ? value.round() : 0;

double _double(Object? value) => value is num ? value.toDouble() : 0;

DateTime? _instant(Object? value) => value is String && value.isNotEmpty ? DateTime.tryParse(value)?.toUtc() : null;

/// A `YYYY-MM-DD` day, held at midnight UTC.
DateTime? _date(Object? value) {
  if (value is! String || value.length < 10) return null;
  final parsed = DateTime.tryParse('${value.substring(0, 10)}T00:00:00Z');
  return parsed;
}
