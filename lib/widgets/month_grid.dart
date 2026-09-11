import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_colors.dart';
import '../providers/colors_provider.dart';
import '../providers/schedule_provider.dart';
import '../utils/dates.dart';
import 'day_split.dart';

/// Full-month colour-coded grid.
/// Each cell background reflects who has the kids that day; days outside the
/// month are faded. Mid-day changes (a handover, or a time window) render as a
/// diagonal split. Dots under the date mark one-off events — exams in the
/// child's colour.
class MonthGrid extends ConsumerWidget {
  /// Any date within the target month.
  final DateTime month;
  final DateTime selectedDay;
  final ValueChanged<DateTime> onDaySelected;

  const MonthGrid({
    super.key,
    required this.month,
    required this.selectedDay,
    required this.onDaySelected,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs        = Theme.of(context).colorScheme;
    final colors    = ref.watch(colorsProvider).valueOrNull ?? const AppColors();
    final engine    = ref.watch(scheduleEngineProvider);
    final today     = ref.watch(todayProvider);
    final overrides = ref.watch(manualOverridesProvider).valueOrNull ?? const [];

    final markers = <String, List<Color>>{};
    for (final o in overrides) {
      if (!o.isAdhoc) continue;
      final color = o.isExam
          ? (colors.isChildSpecific(o.childName)
              ? colors.childColor(o.childName)
              : cs.tertiary)
          : cs.onSurfaceVariant;
      final dots = markers.putIfAbsent(isoDate(o.targetDate), () => []);
      if (dots.length < 3 && !dots.contains(color)) dots.add(color);
    }

    final firstOfMonth = DateTime(month.year, month.month, 1);
    final gridStart    = addDays(firstOfMonth, -(firstOfMonth.weekday - 1));
    final lastOfMonth  = DateTime(month.year, month.month + 1, 0);
    final gridEnd      = addDays(lastOfMonth, DateTime.sunday - lastOfMonth.weekday);
    // UTC dates so a DST change inside the month can't shorten the count.
    final totalDays = DateTime.utc(gridEnd.year, gridEnd.month, gridEnd.day)
            .difference(DateTime.utc(gridStart.year, gridStart.month, gridStart.day))
            .inDays +
        1;
    final weekCount = totalDays ~/ 7;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
                .map((d) => Expanded(
                      child: Center(
                        child: Text(
                          d,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ))
                .toList(),
          ),
        ),
        const SizedBox(height: 4),
        for (int week = 0; week < weekCount; week++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            child: Row(
              children: List.generate(7, (d) {
                final date    = addDays(gridStart, week * 7 + d);
                final inMonth = date.month == month.month;
                final split   = computeDaySplit(engine, colors, date);

                return Expanded(
                  child: _MonthCell(
                    date:          date,
                    owner:         split.owner,
                    inMonth:       inMonth,
                    isSelected:    sameDay(date, selectedDay),
                    isToday:       sameDay(date, today),
                    colors:        colors,
                    onTap:         () => onDaySelected(date),
                    windowToColor: split.splitColor,
                    markers:       markers[isoDate(date)] ?? const [],
                  ),
                );
              }),
            ),
          ),
        const SizedBox(height: 4),
      ],
    );
  }
}

class _MonthCell extends StatelessWidget {
  final DateTime date;
  final String owner;
  final bool inMonth;
  final bool isSelected;
  final bool isToday;
  final AppColors colors;
  final VoidCallback onTap;

  /// When non-null, renders a diagonal split: day owner top-left,
  /// window-recipient bottom-right.
  final Color? windowToColor;

  /// Up to three dot colours for one-off events on this day.
  final List<Color> markers;

  const _MonthCell({
    required this.date,
    required this.owner,
    required this.inMonth,
    required this.isSelected,
    required this.isToday,
    required this.colors,
    required this.onTap,
    this.windowToColor,
    this.markers = const [],
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final parentColor = colors.parentColor(owner);

    final Color fg;
    if (isSelected) {
      fg = Colors.white;
    } else if (inMonth) {
      fg = cs.onSurface;
    } else {
      fg = cs.onSurface.withValues(alpha: 0.28);
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 40,
        margin: const EdgeInsets.all(1.5),
        decoration: BoxDecoration(
          color: windowToColor != null
              ? Colors.transparent
              : isSelected
                  ? parentColor
                  : inMonth
                      ? parentColor.withValues(alpha: 0.14)
                      : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: isToday && !isSelected
              ? Border.all(color: parentColor, width: 1.5)
              : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            children: [
              if (inMonth && windowToColor != null)
                SizedBox.expand(
                  child: CustomPaint(
                    painter: SplitPainter(
                      primaryColor:   parentColor,
                      secondaryColor: windowToColor!,
                      opacity: isSelected ? 0.8 : 0.14,
                    ),
                  ),
                ),
              Center(
                child: Text(
                  '${date.day}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isToday || isSelected
                        ? FontWeight.bold
                        : FontWeight.normal,
                    color: fg,
                  ),
                ),
              ),
              if (inMonth && markers.isNotEmpty)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 4,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (final c in markers)
                        Container(
                          width: 4,
                          height: 4,
                          margin: const EdgeInsets.symmetric(horizontal: 1),
                          decoration: BoxDecoration(
                            color: isSelected ? Colors.white : c,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
