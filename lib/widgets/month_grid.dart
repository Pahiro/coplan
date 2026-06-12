import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/engine_factory.dart';
import '../models/app_colors.dart';
import '../models/base_rule.dart';
import '../models/custody_request.dart';
import '../models/recurring_arrangement.dart';
import '../models/weekday_rule.dart';
import '../providers/absence_provider.dart';
import '../providers/holiday_provider.dart';
import '../providers/colors_provider.dart';
import '../providers/custody_provider.dart';
import '../providers/household_provider.dart';
import '../providers/schedule_provider.dart';
import '../utils/dates.dart';
import 'day_split.dart';

/// Full-month colour-coded grid.
/// Each cell background reflects [ResolutionEngine.dayOwner] for that date.
/// Days outside the current month are dimmed. Tapping a day calls [onDaySelected].
///
/// Accepted window requests (with a return time) are shown as a diagonal split:
/// the day owner's colour top-left, the window recipient's colour bottom-right.
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
    final colors          = ref.watch(colorsProvider).valueOrNull ?? const AppColors();
    final rules           = ref.watch(baseRulesProvider).valueOrNull ?? const <BaseRule>[];
    final weekdayRules    = ref.watch(weekdayRulesProvider).valueOrNull
            ?? const <WeekdayRule>[];
    final recurring       = ref.watch(recurringArrangementsProvider).valueOrNull
            ?? const <RecurringArrangement>[];
    final custodyRequests = ref.watch(custodyRequestsProvider).valueOrNull
            ?.where((r) => r.isAccepted)
            .toList() ??
        const <CustodyRequest>[];
    final absences  = ref.watch(absencePeriodsProvider).valueOrNull ?? const [];
    final holidays  = ref.watch(holidayBlocksProvider).valueOrNull ?? const [];

    final engine = buildEngine(
      household:             ref.watch(householdProvider).valueOrNull,
      baseRules:             rules,
      custodyRequests:       custodyRequests,
      weekdayRules:          weekdayRules,
      recurringArrangements: recurring,
      absencePeriods:        absences,
      holidayBlocks:         holidays,
    );

    final firstOfMonth = DateTime(month.year, month.month, 1);
    final gridStart =
        firstOfMonth.subtract(Duration(days: firstOfMonth.weekday - 1));

    final lastOfMonth = DateTime(month.year, month.month + 1, 0);
    final gridEnd =
        lastOfMonth.add(Duration(days: DateTime.sunday - lastOfMonth.weekday));
    final totalDays  = gridEnd.difference(gridStart).inDays + 1;
    final weekCount  = totalDays ~/ 7;

    final today = DateTime.now();

    return Column(
      children: [
        // ── Day-of-week header ────────────────────────────────────────────
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
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                      ),
                    ))
                .toList(),
          ),
        ),
        const SizedBox(height: 4),
        // ── Week rows ─────────────────────────────────────────────────────
        for (int week = 0; week < weekCount; week++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            child: Row(
              children: List.generate(7, (d) {
                final date    = gridStart.add(Duration(days: week * 7 + d));
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

  const _MonthCell({
    required this.date,
    required this.owner,
    required this.inMonth,
    required this.isSelected,
    required this.isToday,
    required this.colors,
    required this.onTap,
    this.windowToColor,
  });

  @override
  Widget build(BuildContext context) {
    final parentColor = colors.parentColor(owner);

    final Color fg;
    if (isSelected) {
      fg = Colors.white;
    } else if (inMonth) {
      fg = Theme.of(context).colorScheme.onSurface;
    } else {
      fg = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.28);
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
              // Diagonal split — shown even when selected (higher opacity).
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
            ],
          ),
        ),
      ),
    );
  }
}
