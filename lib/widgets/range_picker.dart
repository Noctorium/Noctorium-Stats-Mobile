import 'package:flutter/material.dart';

import '../stats.dart';
import '../theme.dart';

/// The five ranges: one bar of equal segments while they fit side by side, and chips that wrap onto more
/// lines once the phone's text is too large for that -- rather than a row that scrolls sideways and hides
/// "All time" off the edge of the screen.
class RangePicker extends StatelessWidget {
  const RangePicker({super.key, required this.selected, required this.onSelected});

  final StatsRange selected;
  final ValueChanged<StatsRange> onSelected;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelLarge!.copyWith(fontWeight: FontWeight.w600);
    final scaler = MediaQuery.textScalerOf(context);
    return LayoutBuilder(builder: (context, constraints) {
      var widest = 0.0;
      for (final range in StatsRange.values) {
        final painter = TextPainter(
          text: TextSpan(text: range.label, style: style),
          textDirection: TextDirection.ltr,
          textScaler: scaler,
          maxLines: 1,
        )..layout();
        if (painter.width > widest) widest = painter.width;
      }
      final fits = (widest + 16) * StatsRange.values.length + 8 <= constraints.maxWidth;
      return fits ? _bar(style) : _chips(style);
    });
  }

  Widget _bar(TextStyle style) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: Night.card, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          for (final range in StatsRange.values)
            Expanded(child: _Segment(range: range, selected: range == selected, style: style, onTap: onSelected)),
        ],
      ),
    );
  }

  Widget _chips(TextStyle style) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final range in StatsRange.values)
          _Segment(range: range, selected: range == selected, style: style, onTap: onSelected, chip: true),
      ],
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.range,
    required this.selected,
    required this.style,
    required this.onTap,
    this.chip = false,
  });

  final StatsRange range;
  final bool selected;
  final TextStyle style;
  final ValueChanged<StatsRange> onTap;
  final bool chip;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(12);
    return Semantics(
      selected: selected,
      button: true,
      inMutuallyExclusiveGroup: true,
      child: Material(
        color: selected ? Night.accent : (chip ? Night.card : Colors.transparent),
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: selected ? null : () => onTap(range),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: chip ? 16 : 4, vertical: 8),
              child: Center(
                widthFactor: 1,
                child: Text(
                  range.label,
                  maxLines: 1,
                  softWrap: false,
                  style: style.copyWith(color: selected ? onAccent : Night.subtext),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
