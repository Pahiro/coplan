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

  /// Logistics events (school pickup, regular handover) are greyed out in the
  /// UI when a custody override has changed who has the kids that day.
  final bool isLogistics;

  const BaseRule({
    required this.id,
    required this.childName,
    required this.dayOfWeek,
    required this.eventTime,
    required this.location,
    required this.activity,
    this.isShared = false,
    this.isLogistics = false,
  });

  factory BaseRule.fromRecord(Map<String, dynamic> j) => BaseRule(
        id: j['id'] as String,
        childName: j['child_name'] as String,
        dayOfWeek: (j['day_of_week'] as num).toInt(),
        eventTime: j['event_time'] as String,
        location: j['location'] as String,
        activity: j['activity'] as String,
        isShared: (j['is_shared'] as bool?) ?? false,
        isLogistics: (j['is_logistics'] as bool?) ?? false,
      );
}
