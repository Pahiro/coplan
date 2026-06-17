class WeekdayRule {
  final String id;
  final int dayOfWeek;       // 1 = Monday … 7 = Sunday (ISO)
  final String assignedParent; // display name
  final String reason;
  final bool active;

  /// Optional last date (inclusive) this weekday rule applies on. When set, the
  /// rule no longer assigns the day after [endDate] (custody falls back to the
  /// rotation). Null = applies forever.
  final DateTime? endDate;

  const WeekdayRule({
    required this.id,
    required this.dayOfWeek,
    required this.assignedParent,
    this.reason = '',
    this.active = true,
    this.endDate,
  });

  factory WeekdayRule.fromRecord(Map<String, dynamic> j) => WeekdayRule(
        id:             j['id'] as String,
        dayOfWeek:      (j['day_of_week'] as num).toInt(),
        assignedParent: j['assigned_parent'] as String,
        reason:         (j['reason'] as String?) ?? '',
        active:         (j['active'] as bool?) ?? true,
        endDate:        _parseDate(j['end_date'] as String?),
      );

  static DateTime? _parseDate(String? s) =>
      (s == null || s.isEmpty) ? null : DateTime.tryParse(s);
}
