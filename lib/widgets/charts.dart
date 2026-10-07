/// The charts: the timeline and the week as bars, the hours of the day as a clock face, and the split by
/// service in the services' own colours.
library;

import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../format.dart' as format;
import '../stats.dart';
import '../theme.dart';
import 'cards.dart';

/// A step for an axis that lands on round numbers: 1, 2, 5, 10, 20, 50 and so on, about [lines] of them.
double niceStep(num max, {int lines = 3}) {
  if (max <= 0) return 1;
  final rough = max / lines;
  final magnitude = math.pow(10, (math.log(rough) / math.ln10).floor()).toDouble();
  for (final step in [1, 2, 5, 10]) {
    if (rough <= step * magnitude) return math.max(1, step * magnitude);
  }
  return 10 * magnitude;
}

/// Axis labels stay small whatever the text size: they are there to be glanced at, the tooltips and the
/// summaries say the same things in full, and labels the size of headings would overlap.
Widget _clampedTicks(Widget child) => MediaQuery.withClampedTextScaling(maxScaleFactor: 1.25, child: child);

TextStyle _tick(BuildContext context) =>
    Theme.of(context).textTheme.labelSmall!.copyWith(color: Night.faint, fontFeatures: tabular);

BarTouchTooltipData _tooltip(String Function(int index) say) => BarTouchTooltipData(
      getTooltipColor: (_) => Night.raised,
      tooltipBorderRadius: BorderRadius.circular(10),
      tooltipPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      fitInsideHorizontally: true,
      fitInsideVertically: true,
      maxContentWidth: 180,
      getTooltipItem: (group, groupIndex, rod, rodIndex) =>
          BarTooltipItem(say(group.x), const TextStyle(color: Night.text, fontSize: 12, height: 1.35)),
    );

/// Songs per day, or per month over a longer range.
class TimelineChart extends StatelessWidget {
  const TimelineChart({super.key, required this.timeline});

  final Timeline timeline;

  @override
  Widget build(BuildContext context) {
    final points = timeline.points;
    final most = points.fold<int>(0, (top, point) => math.max(top, point.streams));
    final step = niceStep(most);
    final top = (most / step).ceil() * step;
    final count = points.length;
    final days = timeline.bucket == Bucket.day;
    // Which bars are named under the axis: every one of a week, then a handful counted back from the
    // newest, so today (or this month) is always one of them.
    final every = days ? (count <= 7 ? 1 : count <= 31 ? 7 : 30) : (count <= 6 ? 1 : count <= 13 ? 3 : 4);
    final firstNamed = (count - 1) % every;
    String tick(int index) {
      final point = points[index];
      if (days && count <= 7) return format.dayTick(point);
      return format.bucketTick(point, timeline.bucket, withYear: index == firstNamed);
    }

    return Semantics(
      label: 'A bar chart of songs played ${days ? 'each day' : 'each month'}.',
      child: SizedBox(
        height: 190,
        child: LayoutBuilder(builder: (context, constraints) {
          final width = (constraints.maxWidth - 36) / math.max(count, 1);
          final barWidth = (width * (count <= 7 ? .5 : .66)).clamp(1.5, 28.0);
          return _clampedTicks(
            BarChart(
              BarChartData(
                maxY: top <= 0 ? 1 : top,
                alignment: BarChartAlignment.spaceAround,
                barGroups: [
                  for (var i = 0; i < count; i++)
                    BarChartGroupData(x: i, barRods: [
                      BarChartRodData(
                        toY: points[i].streams.toDouble(),
                        width: barWidth,
                        gradient: const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0xFFCDA6FF), Night.accent],
                        ),
                        borderRadius: BorderRadius.vertical(top: Radius.circular(math.min(6, barWidth / 2))),
                      ),
                    ]),
                ],
                gridData: FlGridData(
                  drawVerticalLine: false,
                  horizontalInterval: step,
                  getDrawingHorizontalLine: (_) => FlLine(color: Night.line, strokeWidth: 1, dashArray: [3, 4]),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(),
                  rightTitles: const AxisTitles(),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      interval: step,
                      getTitlesWidget: (value, meta) => value == meta.max && value != top
                          ? const SizedBox.shrink()
                          : SideTitleWidget(
                              meta: meta,
                              space: 6,
                              child: Text(format.count(value.round()), style: _tick(context)),
                            ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 26,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index < 0 || index >= count || (count - 1 - index) % every != 0) {
                          return const SizedBox.shrink();
                        }
                        return SideTitleWidget(
                          meta: meta,
                          space: 6,
                          fitInside: SideTitleFitInsideData.fromTitleMeta(meta, distanceFromEdge: 0),
                          child: Text(tick(index), style: _tick(context), maxLines: 1, softWrap: false),
                        );
                      },
                    ),
                  ),
                ),
                barTouchData: BarTouchData(
                  touchTooltipData: _tooltip((index) {
                    final point = points[index];
                    return '${format.bucketName(point, timeline.bucket)}\n'
                        '${format.plural(point.streams, 'song')} · ${format.minutes(point.minutes)}';
                  }),
                ),
              ),
              duration: const Duration(milliseconds: 250),
            ),
          );
        }),
      ),
    );
  }
}

/// Monday to Sunday, with the busiest day lit.
class WeekChart extends StatelessWidget {
  const WeekChart({super.key, required this.weekdays});

  final List<Slot> weekdays;

  @override
  Widget build(BuildContext context) {
    final most = weekdays.fold<int>(0, (top, slot) => math.max(top, slot.streams));
    return Semantics(
      label: 'A bar chart of songs played on each day of the week.',
      child: SizedBox(
        height: 150,
        child: _clampedTicks(
          BarChart(
            BarChartData(
              maxY: most <= 0 ? 1 : most * 1.08,
              alignment: BarChartAlignment.spaceAround,
              barGroups: [
                for (var i = 0; i < weekdays.length; i++)
                  BarChartGroupData(x: i, barRods: [
                    BarChartRodData(
                      toY: weekdays[i].streams.toDouble(),
                      width: 26,
                      color: weekdays[i].streams == most && most > 0
                          ? Night.accent
                          : Night.accent.withValues(alpha: .38),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
                      backDrawRodData: BackgroundBarChartRodData(
                        show: true,
                        toY: most <= 0 ? 1 : most * 1.08,
                        color: Night.raised.withValues(alpha: .55),
                      ),
                    ),
                  ]),
              ],
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(),
                rightTitles: const AxisTitles(),
                leftTitles: const AxisTitles(),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 26,
                    getTitlesWidget: (value, meta) => SideTitleWidget(
                      meta: meta,
                      space: 6,
                      child: Text(format.weekdayShort(weekdays[value.toInt()].index), style: _tick(context)),
                    ),
                  ),
                ),
              ),
              barTouchData: BarTouchData(
                touchTooltipData: _tooltip((index) {
                  final slot = weekdays[index];
                  return '${format.weekday(slot.index)}s\n'
                      '${format.plural(slot.streams, 'song')} · ${format.minutes(slot.minutes)}';
                }),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The hours of the day as a clock face: midnight at the top, noon at the bottom, each hour a petal as long
/// as the listening in it.
class ListeningClock extends StatelessWidget {
  const ListeningClock({super.key, required this.hourly, required this.use24});

  final List<Slot> hourly;
  final bool use24;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final most = hourly.fold<int>(0, (top, slot) => math.max(top, slot.streams));
    final peak = hourly.firstWhere((slot) => slot.streams == most, orElse: () => hourly.first);
    final labels = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.25);
    final labelStyle = _tick(context);
    return LayoutBuilder(builder: (context, constraints) {
      final side = math.min(constraints.maxWidth, 280.0);
      final face = _ClockPainter.faceRadius(side, labels.scale(labelStyle.fontSize!)) * 2;
      return Center(
        child: Semantics(
          label: most == 0
              ? 'Nothing played at any hour.'
              : 'A clock of listening by hour. The most at ${format.hourOfDay(peak.index, use24: use24)}.',
          excludeSemantics: true,
          child: SizedBox.square(
            dimension: side,
            child: CustomPaint(
              painter: _ClockPainter(
                hourly: hourly,
                most: most,
                labelStyle: labelStyle,
                // The same ceiling as the other charts' labels; a painter is not given one by itself.
                textScaler: labels,
                use24: use24,
              ),
              // The busiest hour, written on the face and shrunk to fit inside it whatever the text size.
              child: Center(
                child: SizedBox(
                  width: face * .78,
                  height: face * .6,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            most == 0 ? '–' : format.hourOfDay(peak.index, use24: use24),
                            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, fontFeatures: tabular),
                          ),
                        ),
                        Text('busiest hour', style: theme.textTheme.labelSmall?.copyWith(color: Night.subtext)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    });
  }
}

class _ClockPainter extends CustomPainter {
  _ClockPainter({
    required this.hourly,
    required this.most,
    required this.labelStyle,
    required this.textScaler,
    required this.use24,
  });

  final List<Slot> hourly;
  final int most;
  final TextStyle labelStyle;
  final TextScaler textScaler;
  final bool use24;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final outer = size.shortestSide / 2;
    final labelSize = textScaler.scale(labelStyle.fontSize!);
    final labelRoom = labelSize * 2.4;
    final reach = outer - labelRoom;
    final face = faceRadius(size.shortestSide, labelSize);
    final inner = face + 5;
    const sweep = 2 * math.pi / 24;
    const gap = sweep * .14; // either side of each petal

    // Two faint rings, half way and all the way, so a petal's length can be read against something.
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Night.line;
    canvas.drawCircle(centre, reach, ring);
    canvas.drawCircle(centre, inner + (reach - inner) / 2, ring..color = Night.line.withValues(alpha: .55));

    for (final slot in hourly) {
      final start = -math.pi / 2 + slot.index * sweep + gap;
      if (slot.streams == 0 || most == 0) {
        // A quiet hour is still an hour on the face: a stub, so the clock never looks as if it has a gap.
        _petal(canvas, centre, inner, inner + 3, start, sweep - 2 * gap, Paint()..color = Night.line);
        continue;
      }
      final share = slot.streams / most;
      final length = inner + (reach - inner) * (.1 + .9 * share);
      final paint = Paint()
        ..color = Color.lerp(Night.accent.withValues(alpha: .42), const Color(0xFFDCC2FF), share * share)!;
      _petal(canvas, centre, inner, length, start, sweep - 2 * gap, paint);
    }
    // The face, with a hairline round it, where the busiest hour is written.
    canvas.drawCircle(centre, face, Paint()..color = Night.raised);
    canvas.drawCircle(
      centre,
      face,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Night.accent.withValues(alpha: .28),
    );

    for (final hour in const [0, 6, 12, 18]) {
      final angle = -math.pi / 2 + hour * sweep;
      final text = TextPainter(
        text: TextSpan(text: use24 ? hour.toString().padLeft(2, '0') : _short(hour), style: labelStyle),
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
      )..layout();
      final at = centre + Offset(math.cos(angle), math.sin(angle)) * (reach + labelRoom / 2);
      text.paint(canvas, at - Offset(text.width / 2, text.height / 2));
    }
  }

  /// The radius of the face in the middle: the petals start just outside it, and the widget over the painter
  /// writes the busiest hour inside it.
  static double faceRadius(double side, double labelSize) => (side / 2 - labelSize * 2.4) * .44 - 5;

  static String _short(int hour) => switch (hour) { 0 => '12a', 6 => '6a', 12 => '12p', _ => '6p' };

  void _petal(Canvas canvas, Offset centre, double from, double to, double start, double sweep, Paint paint) {
    final path = Path()
      ..arcTo(Rect.fromCircle(center: centre, radius: to), start, sweep, true)
      ..arcTo(Rect.fromCircle(center: centre, radius: from), start + sweep, -sweep, false)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ClockPainter old) =>
      old.hourly != hourly || old.most != most || old.use24 != use24 || old.textScaler != textScaler;
}

/// The part of the day most of the listening falls in, for the line over the clock.
({String name, int percent}) busiestPartOfDay(List<Slot> hourly) {
  const parts = [('nights', 0, 6), ('mornings', 6, 12), ('afternoons', 12, 18), ('evenings', 18, 24)];
  final total = hourly.fold<int>(0, (sum, slot) => sum + slot.streams);
  var best = parts.first;
  var bestCount = -1;
  for (final part in parts) {
    final count = hourly.where((slot) => slot.index >= part.$2 && slot.index < part.$3).fold<int>(0, (s, x) => s + x.streams);
    if (count > bestCount) {
      best = part;
      bestCount = count;
    }
  }
  return (name: best.$1, percent: total == 0 ? 0 : (bestCount * 100 / total).round());
}

/// One bar split between the services, and a row for each under it.
class ServiceSplit extends StatelessWidget {
  const ServiceSplit({super.key, required this.services});

  final List<ServiceShare> services;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = services.fold<int>(0, (sum, share) => sum + share.streams);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExcludeSemantics(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 14,
              child: Row(
                children: [
                  for (final (i, share) in services.indexed)
                    if (share.streams > 0)
                      Expanded(
                        flex: share.streams,
                        child: Container(
                          margin: EdgeInsets.only(left: i == 0 ? 0 : 2),
                          color: share.service.colour,
                        ),
                      ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        for (final share in services)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(color: share.service.colour, shape: BoxShape.circle),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(share.service.label, style: theme.textTheme.titleSmall),
                      Text(
                        '${format.plural(share.streams, 'song')} · ${format.hours(share.hours)} h',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '${total == 0 ? 0 : (share.streams * 100 / total).round()}%',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, fontFeatures: tabular),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
