/// The lists: top songs, top artists, and what was played most recently.
library;

import 'package:flutter/material.dart';

import '../format.dart' as format;
import '../stats.dart';
import '../theme.dart';
import 'cards.dart';

/// A list that shows its first few rows and the rest on asking, so one card does not take the whole screen.
class _Expandable extends StatefulWidget {
  const _Expandable({required this.rows, required this.first, required this.more});

  final List<Widget> rows;
  final int first;

  /// What the button says, given how many rows it would add.
  final String Function(int hidden) more;

  @override
  State<_Expandable> createState() => _ExpandableState();
}

class _ExpandableState extends State<_Expandable> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final rows = widget.rows;
    final shown = _open ? rows : rows.take(widget.first).toList();
    final hidden = rows.length - widget.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...shown,
        if (hidden > 0)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _open = !_open),
                icon: Icon(_open ? Icons.expand_less_rounded : Icons.expand_more_rounded),
                label: Text(_open ? 'Show fewer' : widget.more(hidden)),
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
              ),
            ),
          ),
      ],
    );
  }
}

/// A ranked row: the position, what it is, a thin bar for how it compares with the first, and its count.
class _RankedRow extends StatelessWidget {
  const _RankedRow({
    required this.rank,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.detail,
    required this.share,
    this.dot,
  });

  final int rank;
  final String title;
  final String subtitle;
  final String value;
  final String detail;

  /// Against the first row, 0 to 1.
  final double share;
  final Color? dot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: '$rank. $title, $subtitle, $value, $detail',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 28,
                  child: Text(
                    '$rank',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: rank == 1 ? Night.accent : Night.faint,
                      fontWeight: FontWeight.w700,
                      fontFeatures: tabular,
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          if (dot != null) ...[
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Flexible(
                            child: Text(
                              subtitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(value, style: theme.textTheme.titleSmall?.copyWith(fontFeatures: tabular)),
                    Text(detail, style: theme.textTheme.bodySmall?.copyWith(fontFeatures: tabular)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Under the whole row, so every bar is measured against the same length whatever the counts
            // beside it take up.
            Padding(
              padding: const EdgeInsets.only(left: 28),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: share.clamp(0.02, 1.0),
                  minHeight: 3,
                  color: rank == 1 ? Night.accent : Night.accent.withValues(alpha: .55),
                  backgroundColor: Night.raised,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TopSongs extends StatelessWidget {
  const TopSongs({super.key, required this.tracks});

  final List<TopTrack> tracks;

  @override
  Widget build(BuildContext context) {
    final most = tracks.isEmpty ? 1 : tracks.first.streams;
    return _Expandable(
      first: 5,
      more: (hidden) => 'Show $hidden more',
      rows: [
        for (final (i, track) in tracks.indexed)
          _RankedRow(
            rank: i + 1,
            title: track.title,
            subtitle: '${track.artist} · ${track.service.label}',
            dot: track.service.colour,
            value: format.plural(track.streams, 'play'),
            detail: format.minutes(track.minutes),
            share: track.streams / most,
          ),
      ],
    );
  }
}

class TopArtists extends StatelessWidget {
  const TopArtists({super.key, required this.artists});

  final List<TopArtist> artists;

  @override
  Widget build(BuildContext context) {
    final most = artists.isEmpty ? 1 : artists.first.streams;
    return _Expandable(
      first: 5,
      more: (hidden) => 'Show $hidden more',
      rows: [
        for (final (i, artist) in artists.indexed)
          _RankedRow(
            rank: i + 1,
            title: artist.artist,
            subtitle: format.plural(artist.tracks, 'different song'),
            value: format.plural(artist.streams, 'play'),
            detail: format.minutes(artist.minutes),
            share: artist.streams / most,
          ),
      ],
    );
  }
}

class RecentPlays extends StatelessWidget {
  const RecentPlays({super.key, required this.plays, required this.now, required this.offset, required this.use24});

  final List<RecentPlay> plays;
  final DateTime now;
  final Duration offset;
  final bool use24;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Beside the title while there is room, and under it once the text is large enough that a column of
    // times would leave the titles a few letters each.
    final stacked = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    return _Expandable(
      first: 8,
      more: (hidden) => 'Show $hidden more',
      rows: [
        for (final play in plays)
          _recent(theme, play, format.whenPlayed(play.playedAt, now, offset, use24: use24), stacked),
      ],
    );
  }

  Widget _recent(ThemeData theme, RecentPlay play, String when, bool stacked) {
    final time = Text(
      when,
      textAlign: stacked ? TextAlign.start : TextAlign.end,
      style: theme.textTheme.bodySmall?.copyWith(color: Night.faint, fontFeatures: tabular),
    );
    return Semantics(
      label: '${play.title}, ${play.artist}, on ${play.service.label}, $when',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: stacked ? CrossAxisAlignment.start : CrossAxisAlignment.center,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: play.service.colour.withValues(alpha: .16),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.music_note_rounded, color: play.service.colour, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    play.title,
                    maxLines: stacked ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                  Text(
                    '${play.artist} · ${play.service.label}',
                    maxLines: stacked ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                  if (stacked) time,
                ],
              ),
            ),
            if (!stacked) ...[
              const SizedBox(width: 12),
              ConstrainedBox(constraints: const BoxConstraints(maxWidth: 130), child: time),
            ],
          ],
        ),
      ),
    );
  }
}
