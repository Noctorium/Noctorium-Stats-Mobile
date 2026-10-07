/// The listener's statistics for one range at a time.
library;

import 'package:flutter/material.dart';

import '../app.dart';
import '../format.dart' as format;
import '../service.dart';
import '../stats.dart';
import '../theme.dart';
import '../update.dart';
import '../widgets/cards.dart';
import '../widgets/charts.dart';
import '../widgets/lists.dart';
import '../widgets/mark.dart';
import '../widgets/range_picker.dart';

/// What a range shows when nothing has been chosen before: a month is enough to have a shape, and recent
/// enough to recognise.
const StatsRange defaultRange = StatsRange.month;

enum _Menu { refresh, website, about, signOut }

class Dashboard extends StatefulWidget {
  const Dashboard({
    super.key,
    required this.deps,
    required this.token,
    required this.update,
    required this.onSignedOut,
    this.account,
  });

  final Dependencies deps;
  final String token;
  final Account? account;
  final Future<Release?> update;
  final Future<void> Function({String? notice}) onSignedOut;

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  StatsRange _range = defaultRange;
  bool _ready = false;
  Account? _account;

  /// Every range looked at this launch, so going back to one shows it at once while it is asked for again.
  final _loaded = <StatsRange, Stats>{};
  final _failed = <StatsRange, ServiceException>{};
  final _inFlight = <StatsRange>{};

  @override
  void initState() {
    super.initState();
    _account = widget.account;
    _start();
  }

  Future<void> _start() async {
    final saved = await widget.deps.preferences.lastRange();
    if (!mounted) return;
    setState(() {
      _range = saved ?? defaultRange;
      _ready = true;
    });
    if (_account == null) _whoAmI();
    await _load();
  }

  /// Whose statistics these are, for the heading; a saved token arrives without a name.
  Future<void> _whoAmI() async {
    try {
      final account = await widget.deps.service.me(widget.token);
      if (mounted) setState(() => _account = account);
    } on ServiceException catch (error) {
      if (error.failure == Failure.signedOut && mounted) await widget.onSignedOut(notice: error.message);
      // Anything else is the statistics' to report: they are asked for at the same moment.
    }
  }

  Future<void> _load() async {
    final range = _range;
    if (_inFlight.contains(range)) return;
    setState(() => _inFlight.add(range));
    try {
      final stats = await widget.deps.service.stats(widget.token, range, offset: widget.deps.offset());
      if (!mounted) return;
      setState(() {
        _loaded[range] = stats;
        _failed.remove(range);
      });
    } on ServiceException catch (error) {
      if (!mounted) return;
      if (error.failure == Failure.signedOut) {
        await widget.onSignedOut(notice: error.message);
        return;
      }
      setState(() => _failed[range] = error);
    } finally {
      if (mounted) setState(() => _inFlight.remove(range));
    }
  }

  void _choose(StatsRange range) {
    setState(() => _range = range);
    widget.deps.preferences.rememberRange(range);
    _load();
  }

  Future<void> _menu(_Menu choice) async {
    switch (choice) {
      case _Menu.refresh:
        await _load();
      case _Menu.website:
        await _open(widget.deps.service.website);
      case _Menu.about:
        _about();
      case _Menu.signOut:
        await widget.onSignedOut();
    }
  }

  Future<void> _open(Uri link) async {
    final opened = await widget.deps.openLink(link);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No browser could open $link')));
    }
  }

  void _about() {
    showAboutDialog(
      context: context,
      applicationName: 'Noctorium Stats',
      applicationVersion: _versionLine,
      applicationIcon: const Mark(size: 48),
      applicationLegalese: 'Free software under the GNU General Public License, version 3.',
      children: [
        const SizedBox(height: 16),
        Text(
          'Your listening, counted by the Noctorium service at ${widget.deps.service.base.host} from what the '
          'Noctorium player records while you are signed in.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }

  String get _versionLine => 'Version ${widget.deps.versionLabel}';

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.paddingOf(context);
    final stats = _loaded[_range];
    final failure = _failed[_range];
    final loading = _inFlight.contains(_range) || !_ready;
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        color: Night.accent,
        backgroundColor: Night.card,
        edgeOffset: insets.top + kToolbarHeight,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            _appBar(loading && stats != null),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(16 + insets.left, 4, 16 + insets.right, 24 + insets.bottom),
              sliver: SliverList.list(children: [
                _heading(stats),
                const SizedBox(height: 16),
                RangePicker(selected: _range, onSelected: _choose),
                const SizedBox(height: 16),
                ..._body(stats, failure, loading),
                const SizedBox(height: 8),
                _Footer(version: widget.deps.versionLabel, update: widget.update, onOpen: _open),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _appBar(bool refreshing) {
    return SliverAppBar(
      pinned: true,
      backgroundColor: Night.page,
      titleSpacing: 16,
      title: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.3,
        child: const Row(
          children: [
            Mark(size: 30),
            SizedBox(width: 12),
            Flexible(
              child: Text(
                'Noctorium Stats',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20),
              ),
            ),
          ],
        ),
      ),
      actions: [
        PopupMenuButton<_Menu>(
          tooltip: 'More',
          icon: const Icon(Icons.more_vert_rounded),
          onSelected: _menu,
          itemBuilder: (context) => [
            const PopupMenuItem(value: _Menu.refresh, child: _MenuRow(Icons.refresh_rounded, 'Refresh')),
            const PopupMenuItem(value: _Menu.website, child: _MenuRow(Icons.open_in_new_rounded, 'Open the website')),
            const PopupMenuItem(value: _Menu.about, child: _MenuRow(Icons.info_outline_rounded, 'About Noctorium Stats')),
            const PopupMenuDivider(),
            const PopupMenuItem(value: _Menu.signOut, child: _MenuRow(Icons.logout_rounded, 'Sign out')),
          ],
        ),
        const SizedBox(width: 4),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(2),
        child: SizedBox(
          height: 2,
          child: refreshing ? const LinearProgressIndicator(minHeight: 2, backgroundColor: Colors.transparent) : null,
        ),
      ),
    );
  }

  Widget _heading(Stats? stats) {
    final theme = Theme.of(context);
    final now = widget.deps.now();
    final offset = widget.deps.offset();
    final use24 = MediaQuery.alwaysUse24HourFormatOf(context);
    final name = _account?.displayName;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          name ?? 'Your listening',
          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          stats == null
              ? format.rangeSpan(_range, now, offset)
              : '${format.period(stats, now, offset)} · ${format.lastPlayed(stats.lastPlay, now, offset, use24: use24)}',
          style: theme.textTheme.bodyMedium,
        ),
      ],
    );
  }

  List<Widget> _body(Stats? stats, ServiceException? failure, bool loading) {
    if (stats == null) {
      if (failure != null && !loading) return [_failure(failure)];
      return const [_Loading()];
    }
    final banner = failure != null && !loading
        ? [StaleBanner(message: 'Not up to date. ${failure.message}', onRetry: _load), const SizedBox(height: 16)]
        : const <Widget>[];
    if (stats.isEmpty) return [...banner, ..._empty(stats)];
    return [...banner, ..._statistics(stats)];
  }

  Widget _failure(ServiceException failure) {
    final offline = failure.failure == Failure.offline;
    return StateMessage(
      icon: offline ? Icons.cloud_off_rounded : Icons.error_outline_rounded,
      title: switch (failure.failure) {
        Failure.offline => 'You are offline',
        Failure.throttled => 'Too many requests',
        Failure.server => 'The service is having trouble',
        _ => 'Something went wrong',
      },
      body: failure.message,
      action: _load,
      actionLabel: 'Try again',
    );
  }

  List<Widget> _empty(Stats stats) {
    final everything = stats.range == StatsRange.all;
    return [
      StateMessage(
        icon: Icons.headphones_rounded,
        title: everything ? 'Nothing played yet' : 'Nothing in ${_rangeWords(stats.range)}',
        body: everything
            ? 'Play something in Noctorium while you are signed in to this account, and it will be counted here.'
            : 'Nothing was played in this range. Try a longer one, or play something in Noctorium while you '
                'are signed in.',
        action: everything ? null : () => _choose(StatsRange.all),
        actionLabel: everything ? null : 'Show all time',
        secondaryAction: () => _open(widget.deps.service.website),
        secondaryLabel: 'Open the website',
      ),
      if (stats.streak.longest > 0) ...[const SizedBox(height: 12), StreakCard(streak: stats.streak)],
    ];
  }

  static String _rangeWords(StatsRange range) => switch (range) {
        StatsRange.week => 'the last 7 days',
        StatsRange.month => 'the last 30 days',
        StatsRange.quarter => 'the last 90 days',
        StatsRange.year => 'the last year',
        StatsRange.all => 'all time',
      };

  List<Widget> _statistics(Stats stats) {
    final now = widget.deps.now();
    final offset = widget.deps.offset();
    final use24 = MediaQuery.alwaysUse24HourFormatOf(context);
    const gap = SizedBox(height: 12);
    final timeline = stats.timeline;
    final busiest = timeline.points.isEmpty
        ? null
        : timeline.points.reduce((a, b) => b.streams > a.streams ? b : a);
    // Songs a day, or a month: over the bars the chart draws, so the quiet ones count too.
    final average = timeline.points.isEmpty ? null : stats.streams / timeline.points.length;
    final week = stats.weekdays.reduce((a, b) => b.streams > a.streams ? b : a);
    final part = busiestPartOfDay(stats.hourly);

    return [
      Figures(stats: stats),
      StreakCard(streak: stats.streak),
      gap,
      Section(
        title: timeline.bucket == Bucket.day ? 'Day by day' : 'Month by month',
        summary: [
          if (average != null)
            '${average < 10 ? average.toStringAsFixed(1) : format.count(average.round())} songs a '
                '${timeline.bucket == Bucket.day ? 'day' : 'month'}',
          if (busiest != null && busiest.streams > 0)
            'most ${timeline.bucket == Bucket.day ? 'on' : 'in'} ${format.bucketName(busiest, timeline.bucket)}',
        ].join(', ').capitalised,
        child: TimelineChart(timeline: timeline),
      ),
      gap,
      Section(
        title: 'By service',
        summary: stats.services.length == 1
            ? 'All of it on ${stats.services.first.service.label}'
            : 'Most of it on ${stats.services.first.service.label}',
        child: ServiceSplit(services: stats.services),
      ),
      gap,
      Section(
        title: 'Top songs',
        child: TopSongs(tracks: stats.topTracks),
      ),
      gap,
      Section(
        title: 'Top artists',
        child: TopArtists(artists: stats.topArtists),
      ),
      gap,
      Section(
        title: 'Hours of the day',
        summary: '${part.percent}% of it in the ${part.name}',
        child: ListeningClock(hourly: stats.hourly, use24: use24),
      ),
      gap,
      Section(
        title: 'Days of the week',
        summary: '${format.weekday(week.index)}s are the busiest: ${format.plural(week.streams, 'song')}',
        child: WeekChart(weekdays: stats.weekdays),
      ),
      gap,
      Section(
        title: 'Recently played',
        child: RecentPlays(plays: stats.recent, now: now, offset: offset, use24: use24),
      ),
      gap,
    ];
  }
}

extension on String {
  String get capitalised => isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';
}

class _MenuRow extends StatelessWidget {
  const _MenuRow(this.icon, this.label);

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Night.subtext),
        const SizedBox(width: 14),
        Flexible(child: Text(label)),
      ],
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 72),
      child: Column(
        children: [
          const SizedBox.square(dimension: 36, child: CircularProgressIndicator(strokeWidth: 3)),
          const SizedBox(height: 18),
          Text('Counting your listening…', style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

/// The version, and a line when a newer one is out.
class _Footer extends StatelessWidget {
  const _Footer({required this.version, required this.update, required this.onOpen});

  final String version;
  final Future<Release?> update;
  final Future<void> Function(Uri) onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<Release?>(
      future: update,
      builder: (context, snapshot) {
        final release = snapshot.data;
        return Column(
          children: [
            if (release != null) ...[
              Card(
                color: Night.accent.withValues(alpha: .14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(22),
                  onTap: () => onOpen(release.page),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                    child: Row(
                      children: [
                        const Icon(Icons.system_update_rounded, color: Night.accent),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            'Noctorium Stats ${release.version} is out.',
                            style: theme.textTheme.titleSmall,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text('Get it', style: theme.textTheme.labelLarge?.copyWith(color: Night.accent)),
                        const Icon(Icons.chevron_right_rounded, color: Night.accent),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            Text(
              'Noctorium Stats $version',
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall,
            ),
          ],
        );
      },
    );
  }
}
