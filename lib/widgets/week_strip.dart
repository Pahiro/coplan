import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../engine/resolution_engine.dart';
import '../models/app_colors.dart';
import '../models/custody_request.dart';
import '../models/recurring_arrangement.dart';
import '../models/resolved_event.dart';
import '../models/weekday_rule.dart';
import '../providers/colors_provider.dart';
import '../providers/custody_provider.dart';
import '../providers/schedule_provider.dart';

/// Horizontal 7-day strip for the calendar screen.
/// Each cell shows the day's owning parent colour and highlights today.
/// Accepted custody requests (day transfers and windows) are reflected via
/// the engine so the strip matches the calendar day panel.
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
    final colors          = ref.watch(colorsProvider).valueOrNull ?? const AppColors();
    final rulesAsync      = ref.watch(baseRulesProvider);
    final weekdayRules    = ref.watch(weekdayRulesProvider).valueOrNull
            ?? const <WeekdayRule>[];
    final recurring       = ref.watch(recurringArrangementsProvider).valueOrNull
            ?? const <RecurringArrangement>[];
    final custodyRequests = ref.watch(custodyRequestsProvider).valueOrNull
            ?.where((r) => r.isAccepted)
            .toList() ??
        const <CustodyRequest>[];

    return rulesAsync.when(
      loading: () => const SizedBox(height: 72),
      error: (_, __) => const SizedBox(height: 72),
      data: (rules) {
        final engine = ResolutionEngine(
            baseRules:             rules,
            overrides:             const [],
            custodyRequests:       custodyRequests,
            weekdayRules:          weekdayRules,
            recurringArrangements: recurring);
        return SizedBox(
          height: 72,
          child: Row(
            children: List.generate(7, (i) {
              final day    = weekStart.add(Duration(days: i));
              final window = engine.custodyWindows(day).firstOrNull;

              // Default: schedule owner with no split.
              Parent effectiveOwner = engine.dayOwner(day);
              Color? windowToColor;

              if (window != null) {
                final windowParent = parentFromString(window.toParent);
                // Use solid window-recipient colour only when all events are
                // covered AND the window has no definite return time.  If a
                // return time is set the base owner gets the kids back, so
                // show a split even when all scheduled events fall inside the
                // window.
                final windowHasDefiniteReturn =
                    !window.returnTimeTbd && window.returnTime != null;
                if (engine.windowCoversAllEvents(day) && !windowHasDefiniteReturn) {
                  effectiveOwner = windowParent;
                } else {
                  // Partial overlap OR window ends at a known time → split.
                  windowToColor = colors.parentColor(windowParent);
                }
              } else {
                // Partial-day transfer (pickup after midnight) → split.
                // Use fromParent/toParent directly — avoids weekday rules
                // incorrectly overriding the "before handover" half when the
                // standing rule and the same-day transfer point to the same
                // parent.  dayTransferFor() also surfaces virtual recurring
                // occurrences so future weeks render the same split.
                final transfer = engine.dayTransferFor(day);
                if (transfer != null) {
                  final p = transfer.pickupTime.split(':');
                  final pickupMin = int.parse(p[0]) * 60 + int.parse(p[1]);
                  if (pickupMin > 0) {
                    effectiveOwner = parentFromString(transfer.fromParent);
                    windowToColor  = colors.parentColor(
                        parentFromString(transfer.toParent));
                  }
                }
              }

              return Expanded(
                child: _DayCell(
                  day:           day,
                  owner:         effectiveOwner,
                  isSelected:    _sameDay(day, selectedDay),
                  isToday:       _sameDay(day, DateTime.now()),
                  colors:        colors,
                  onTap:         () => onDaySelected(day),
                  windowToColor: windowToColor,
                ),
              );
            }),
          ),
        );
      },
    );
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _DayCell extends StatelessWidget {
  final DateTime day;
  final Parent owner;
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
    final bg = isSelected ? parentColor : parentColor.withOpacity(0.15);
    final fg = isSelected ? Colors.white : parentColor;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
        decoration: BoxDecoration(
          // Split days: painter fills the background; solid otherwise.
          color: windowToColor != null
              ? Colors.transparent
              : bg,
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
              // Diagonal split background — shown even when selected
              // (higher opacity so the selection state is still visible).
              if (windowToColor != null)
                SizedBox.expand(
                  child: CustomPaint(
                    painter: _SplitPainter(
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

/// Paints a diagonal split: [primaryColor] top-left, [secondaryColor] bottom-right.
/// Opacity matches the month_grid soft-tint style.
class _SplitPainter extends CustomPainter {
  final Color  primaryColor;
  final Color  secondaryColor;
  final double opacity;

  const _SplitPainter({
    required this.primaryColor,
    required this.secondaryColor,
    this.opacity = 0.22,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final topLeft = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(0, size.height)
      ..close();
    final bottomRight = Path()
      ..moveTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(topLeft,
        Paint()..color = primaryColor.withOpacity(opacity));
    canvas.drawPath(bottomRight,
        Paint()..color = secondaryColor.withOpacity(opacity));
  }

  @override
  bool shouldRepaint(_SplitPainter old) =>
      old.primaryColor   != primaryColor   ||
      old.secondaryColor != secondaryColor ||
      old.opacity        != opacity;
}
