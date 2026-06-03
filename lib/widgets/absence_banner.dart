import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/absence_period.dart';

/// Compact banner shown when an absence covers the given date.
/// Displayed above the event list to explain the custody flip.
class AbsenceBanner extends StatelessWidget {
  final AbsencePeriod absence;

  const AbsenceBanner({super.key, required this.absence});

  @override
  Widget build(BuildContext context) {
    final theme  = Theme.of(context);
    final fmt    = DateFormat('d MMM');
    final isSingle = absence.durationDays == 1;
    final dateLabel = isSingle
        ? fmt.format(absence.startDate)
        : '${fmt.format(absence.startDate)} – ${fmt.format(absence.endDate)}';

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 2),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.colorScheme.secondaryContainer,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.hiking, size: 18, color: theme.colorScheme.onSecondaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${absence.absentParent} is away · $dateLabel',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  absence.reason,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
