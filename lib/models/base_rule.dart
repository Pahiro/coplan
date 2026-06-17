class BaseRule {
  final String id;
  final String childName;
  final int dayOfWeek;   // 1 = Monday … 7 = Sunday (DateTime.weekday convention)
  final String eventTime; // "HH:mm"
  final String location;
  final String activity;

  /// When true this event happens regardless of whose parenting day it is
  /// (e.g. rugby every Saturday, music lesson every Wednesday).
  /// The responsible parent is still determined by the normal resolution logic,
  /// but the event is tagged so both parents can see it is a shared obligation.
  final bool isShared;

  /// When set, this rule only renders on weeks where the named parent is the
  /// outgoing custody holder (i.e. their rotation week is ending on this day).
  /// Used for directional handover rules — one per parent with different times.
  final String? handoverFrom;

  /// Optional last date (inclusive) this standing event repeats on. When set,
  /// the rule no longer renders on dates after [endDate]. Null = repeats forever.
  final DateTime? endDate;

  const BaseRule({
    required this.id,
    required this.childName,
    required this.dayOfWeek,
    required this.eventTime,
    required this.location,
    required this.activity,
    this.isShared = false,
    this.handoverFrom,
    this.endDate,
  });

  factory BaseRule.fromRecord(Map<String, dynamic> j) => BaseRule(
        id: j['id'] as String,
        childName: j['child_name'] as String,
        dayOfWeek: (j['day_of_week'] as num).toInt(),
        eventTime: j['event_time'] as String,
        location: j['location'] as String,
        activity: j['activity'] as String,
        isShared: (j['is_shared'] as bool?) ?? false,
        handoverFrom: (j['handover_from'] as String?)?.isNotEmpty == true
            ? j['handover_from'] as String
            : null,
        endDate: _parseDate(j['end_date'] as String?),
      );

  static DateTime? _parseDate(String? s) =>
      (s == null || s.isEmpty) ? null : DateTime.tryParse(s);
}
