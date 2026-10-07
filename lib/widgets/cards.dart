/// The pieces the dashboard is built from: a titled card, a big figure, the streak, and the messages that
/// stand in for statistics when there are none to show.
library;

import 'package:flutter/material.dart';

import '../format.dart' as format;
import '../stats.dart';
import '../theme.dart';

/// Figures that line up digit under digit and do not shuffle sideways as they change.
const tabular = [FontFeature.tabularFigures()];

/// A card with a heading, and a line under it saying what the card has found.
class Section extends StatelessWidget {
  const Section({super.key, required this.title, required this.child, this.summary, this.trailing});

  final String title;
  final String? summary;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                ),
                ?trailing,
              ],
            ),
            if (summary case final summary?) ...[
              const SizedBox(height: 4),
              Text(summary, style: theme.textTheme.bodyMedium),
            ],
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

/// One of the four big numbers: the number over its name, or beside it in a row of its own once the text is
/// too large for two of them side by side.
class Figure extends StatelessWidget {
  const Figure({super.key, required this.icon, required this.value, required this.label, this.inRow = false});

  final IconData icon;
  final String value;
  final String label;
  final bool inRow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final badge = Container(
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: Night.accent.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, color: Night.accent, size: inRow ? 22 : 18),
    );
    // Already large, so it grows less than the text around it as the phone's text size goes up -- which is
    // also what Android does to large text itself -- and shrinks to fit rather than breaking a number across
    // two lines.
    final number = MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.35,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(
          value,
          maxLines: 1,
          style: theme.textTheme.displaySmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: Night.text,
            height: 1.05,
            letterSpacing: -.5,
            fontFeatures: tabular,
          ),
        ),
      ),
    );
    final name = Text(label, style: theme.textTheme.bodyMedium);
    return Semantics(
      label: '$value $label',
      excludeSemantics: true,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: inRow
              ? Row(
                  children: [
                    badge,
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [number, const SizedBox(height: 2), name],
                      ),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [badge, const SizedBox(height: 14), number, const SizedBox(height: 6), name],
                ),
        ),
      ),
    );
  }
}

/// The four figures, two by two, or one under another once the text is too large for two side by side.
class Figures extends StatelessWidget {
  const Figures({super.key, required this.stats});

  final Stats stats;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(1);
      final twoUp = constraints.maxWidth >= 2 * 150 * scale;
      final figures = [
        (Icons.play_arrow_rounded, format.count(stats.streams), 'Songs streamed'),
        (Icons.queue_music_rounded, format.count(stats.uniqueTracks), 'Different songs'),
        (Icons.mic_external_on_rounded, format.count(stats.artists), 'Artists'),
        (Icons.schedule_rounded, format.hours(stats.hours), 'Hours listened'),
      ].map((f) => Figure(icon: f.$1, value: f.$2, label: f.$3, inRow: !twoUp)).toList();
      if (!twoUp) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [for (final figure in figures) Padding(padding: const EdgeInsets.only(bottom: 12), child: figure)],
        );
      }
      Widget pair(Widget a, Widget b) => IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [Expanded(child: a), const SizedBox(width: 12), Expanded(child: b)],
            ),
          );
      return Column(children: [
        pair(figures[0], figures[1]),
        const SizedBox(height: 12),
        pair(figures[2], figures[3]),
        const SizedBox(height: 12),
      ]);
    });
  }
}

/// Days in a row: the one running now, and the longest there has been.
class StreakCard extends StatelessWidget {
  const StreakCard({super.key, required this.streak});

  final Streak streak;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = streak.current;
    final longest = streak.longest;
    final String headline;
    final String detail;
    if (current == 0) {
      headline = 'No streak running';
      detail = 'Play something today to start one. Your longest run is ${format.plural(longest, 'day')}.';
    } else if (current >= longest && current > 1) {
      headline = '${format.plural(current, 'day')} in a row';
      detail = 'Your longest run yet. Keep it going today.';
    } else {
      headline = '${format.plural(current, 'day')} in a row';
      detail = 'Your longest run is ${format.plural(longest, 'day')}.';
    }
    final burning = current > 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: burning
                    ? const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFFD9B8FF), Night.accent, Color(0xFF7B3FE0)],
                      )
                    : null,
                color: burning ? null : Night.raised,
              ),
              child: Icon(
                Icons.local_fire_department_rounded,
                color: burning ? onAccent : Night.subtext,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(headline, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(detail, style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// What stands where the statistics would be: nothing played yet, an error, no connection.
class StateMessage extends StatelessWidget {
  const StateMessage({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.action,
    this.actionLabel,
    this.secondaryAction,
    this.secondaryLabel,
  });

  final IconData icon;
  final String title;
  final String body;
  final VoidCallback? action;
  final String? actionLabel;
  final VoidCallback? secondaryAction;
  final String? secondaryLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 28),
        child: Column(
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Night.accent.withValues(alpha: .13),
                boxShadow: [BoxShadow(color: Night.accent.withValues(alpha: .18), blurRadius: 36)],
              ),
              child: Icon(icon, color: Night.accent, size: 34),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(body, textAlign: TextAlign.center, style: theme.textTheme.bodyLarge?.copyWith(color: Night.subtext)),
            if (action != null && actionLabel != null) ...[
              const SizedBox(height: 24),
              FilledButton(onPressed: action, child: Text(actionLabel!)),
            ],
            if (secondaryAction != null && secondaryLabel != null) ...[
              const SizedBox(height: 8),
              TextButton(onPressed: secondaryAction, child: Text(secondaryLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

/// A line over statistics that are still on screen but could not be brought up to date.
class StaleBanner extends StatelessWidget {
  const StaleBanner({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      decoration: BoxDecoration(
        color: const Color(0xFF3D0713).withValues(alpha: .7),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded, color: Night.error, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Text(message, style: const TextStyle(color: Night.text, height: 1.35))),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
