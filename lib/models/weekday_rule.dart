import 'resolved_event.dart';

class WeekdayRule {
  final String id;
  final int dayOfWeek;       // 1 = Monday … 7 = Sunday (ISO)
  final String assignedParent; // "Bennet" or "Jana"
  final String reason;
  final bool active;

  const WeekdayRule({
    required this.id,
    required this.dayOfWeek,
    required this.assignedParent,
    this.reason = '',
    this.active = true,
  });

  factory WeekdayRule.fromRecord(Map<String, dynamic> j) => WeekdayRule(
        id:             j['id'] as String,
        dayOfWeek:      (j['day_of_week'] as num).toInt(),
        assignedParent: j['assigned_parent'] as String,
        reason:         (j['reason'] as String?) ?? '',
        active:         (j['active'] as bool?) ?? true,
      );

  Parent get parent => parentFromString(assignedParent);
}
