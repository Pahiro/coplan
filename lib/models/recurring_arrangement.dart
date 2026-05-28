import 'custody_request.dart';

/// A standing weekly custody transfer (e.g. "every Tuesday Jana hands the kids
/// to Bennet at 17:30").  Unlike a one-off [CustodyRequest] it has no fixed
/// date — the resolution engine expands it into a virtual request for any
/// future date where:
///   • the weekday matches and the date is on/after [startDate];
///   • the day's rotation owner is NOT [toParent] (you can't be handed kids you
///     already have that week — this self-suppresses on your own weeks).
///
/// Past occurrences are frozen into real custody_requests rows by the server
/// cron, so editing or deleting an arrangement never rewrites history.
class RecurringArrangement {
  final String id;
  final int dayOfWeek;        // 1 = Monday … 7 = Sunday (ISO)
  final String toParent;      // receives the kids at pickupTime
  final String childName;     // "All" | "Henri" | "Chris"
  final String pickupTime;    // "HH:MM"
  final String? returnTime;   // "HH:MM"; null = day transfer
  final bool returnTimeTbd;
  final bool toParentCollects;
  final bool toParentReturns;
  final DateTime startDate;
  final String? note;
  final bool active;

  const RecurringArrangement({
    required this.id,
    required this.dayOfWeek,
    required this.toParent,
    required this.childName,
    required this.pickupTime,
    this.returnTime,
    this.returnTimeTbd = false,
    this.toParentCollects = true,
    this.toParentReturns = false,
    required this.startDate,
    this.note,
    this.active = true,
  });

  factory RecurringArrangement.fromRecord(Map<String, dynamic> j) =>
      RecurringArrangement(
        id:               j['id'] as String,
        dayOfWeek:        (j['day_of_week'] as num).toInt(),
        toParent:         j['to_parent'] as String,
        childName:        (j['child_name'] as String?) ?? 'All',
        pickupTime:       (j['pickup_time'] as String?) ?? '00:00',
        returnTime:       _nonEmpty(j['return_time'] as String?),
        returnTimeTbd:    (j['return_time_tbd'] as bool?) ?? false,
        toParentCollects: (j['to_parent_collects'] as bool?) ?? true,
        toParentReturns:  (j['to_parent_returns'] as bool?) ?? false,
        startDate:        DateTime.parse(j['start_date'] as String),
        note:             _nonEmpty(j['note'] as String?),
        active:           (j['active'] as bool?) ?? true,
      );

  /// Builds a virtual accepted [CustodyRequest] for [date].  [fromParent] is
  /// whoever owns the day that week (the parent releasing the kids).
  CustodyRequest toVirtualRequest(DateTime date, {required String fromParent}) =>
      CustodyRequest(
        id:               'recurring:$id:${_iso(date)}',
        fromParent:       fromParent,
        toParent:         toParent,
        date:             date,
        childName:        childName,
        pickupTime:       pickupTime,
        returnTime:       returnTime,
        returnTimeTbd:    returnTimeTbd,
        status:           CustodyStatus.accepted,
        note:             note,
        createdBy:        '',
        requestedFrom:    '',
        toParentCollects: toParentCollects,
        toParentReturns:  toParentReturns,
      );

  /// Extracts the arrangement id from a virtual request id, or null.
  static String? recurringIdFrom(String requestId) =>
      requestId.startsWith('recurring:') ? requestId.split(':')[1] : null;

  static String? _nonEmpty(String? s) => (s == null || s.isEmpty) ? null : s;

  static String _iso(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
