import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/app_colors.dart';
import '../providers/colors_provider.dart';
import '../providers/schedule_provider.dart';
import '../utils/dates.dart';
import 'day_split.dart';

/// Horizontal 7-day strip for the calendar screen.
/// Each cell shows the day's owning parent colour and highlights today.
/// Accepted custody requests (handovers, swaps and windows) are reflected via
/// the engine so the strip matches the day panel below it.
class WeekStrip extends ConsumerWidget {
  /// The Monday of the week to display.
  final DateTime weekStart;
  final DateTime selectedDay;
  final ValueChanged<DateTime> onDaySelected;

  const WeekStrip({
    super.key,
    required this.weekStart,
    required this.selectedDay,
    required this.onDaySelected,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(colorsProvider).valueOrNull ?? const AppColors();
    final engine = ref.watch(scheduleEngineProvider);
    final today  = ref.watch(todayProvider);

    return SizedBox(
      height: 72,
      child: Row(
        children: List.generate(7, (i) {
          final day   = addDays(weekStart, i);
          final split = computeDaySplit(engine, colors, day);

          return Expanded(
            child: _DayCell(
              day:           day,
              owner:         split.owner,
              isSelected:    sameDay(day, selectedDay),
              isToday:       sameDay(day, today),
              colors:        colors,
              onTap:         () => onDaySelected(day),
              windowToColor: split.splitColor,
            ),
          );
        }),
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  final DateTime day;
  final String owner;
  final bool isSelected;
  final bool isToday;
  final AppColors colors;
  final VoidCallback onTap;

  /// When non-null, renders a diagonal split: day-owner top-left,
  /// window-recipient bottom-right (mirrors month_grid behaviour).
  final Color? windowToColor;

  const _DayCell({
    required this.day,
    required this.owner,
    required this.isSelected,
    required this.isToday,
    required this.colors,
    required this.onTap,
    this.windowToColor,
  });

  @override
  Widget build(BuildContext context) {
    final parentColor = colors.parentColor(owner);
    final bg = isSelected ? parentColor : parentColor.withValues(alpha: 0.15);
    final fg = isSelected ? Colors.white : parentColor;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
        decoration: BoxDecoration(
          color: windowToColor != null ? Colors.transparent : bg,
          borderRadius: BorderRadius.circular(10),
          border: isToday
              ? Border.all(color: parentColor, width: isSelected ? 0 : 2)
              : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (windowToColor != null)
                SizedBox.expand(
                  child: CustomPaint(
                    painter: SplitPainter(
                      primaryColor:   parentColor,
                      secondaryColor: windowToColor!,
                      opacity: isSelected ? 0.8 : 0.22,
                    ),
                  ),
                ),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    DateFormat('E').format(day).toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: fg,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${day.day}',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: fg,
                    ),
                  ),
                  if (isToday)
                    Container(
                      width: 4,
                      height: 4,
                      margin: const EdgeInsets.only(top: 2),
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.white : parentColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
