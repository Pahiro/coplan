enum CustodyStatus { pending, accepted, declined, completed }

/// A request between parents to transfer custody of the children.
///
/// Two kinds, distinguished by whether a return time is expected:
///   - Day transfer  (isDayTransfer == true): no return time; [toParent] keeps
///     the kids for the rest of the day / overnight. Accepted day transfers
///     override dayOwner() in the resolution engine.
///   - Window        (isDayTransfer == false): kids return to [fromParent] at
///     [returnTime] (or TBD). Affects parentAtTime() only.
class CustodyRequest {
  final String id;
  final String fromParent;    // "Bennet" | "Jana" — releases custody
  final String toParent;      // "Bennet" | "Jana" — takes custody
  final DateTime date;
  final String childName;     // "All" | "Henri" | "Chris"
  final String pickupTime;    // "HH:MM"
  final String? returnTime;   // "HH:MM"; null when isDayTransfer
  final bool returnTimeTbd;
  final CustodyStatus status;
  final String? note;
  final String createdBy;     // PocketBase user id
  final String requestedFrom; // PocketBase user id of the acceptor

  /// Who physically drives the kids at handover time.
  /// true  = toParent goes to collect them (or collects from school/event).
  /// false = fromParent drops them off at toParent's location.
  final bool toParentCollects;

  /// Who physically drives the kids at return time (windows only).
  /// true  = toParent drops them back to fromParent.
  /// false = fromParent comes to collect them from toParent.
  final bool toParentReturns;

  const CustodyRequest({
    required this.id,
    required this.fromParent,
    required this.toParent,
    required this.date,
    required this.childName,
    required this.pickupTime,
    this.returnTime,
    this.returnTimeTbd = false,
    required this.status,
    this.note,
    required this.createdBy,
    required this.requestedFrom,
    this.toParentCollects = true,
    this.toParentReturns  = false,
  });

  bool get isAccepted => status == CustodyStatus.accepted;

  /// No return time expected — [toParent] keeps the kids for the day/overnight.
  bool get isDayTransfer => returnTime == null && !returnTimeTbd;

  String get statusLabel => switch (status) {
        CustodyStatus.accepted  => 'Accepted',
        CustodyStatus.declined  => 'Declined',
        CustodyStatus.completed => 'Completed',
        CustodyStatus.pending   => 'Pending',
      };

  /// e.g. "14:30–19:00", "14:30–TBD", or "16:00 onwards" for day transfers.
  String get timeWindowLabel {
    if (isDayTransfer) return '$pickupTime onwards';
    final end = returnTimeTbd ? 'TBD' : (returnTime ?? 'TBD');
    return '$pickupTime–$end';
  }

  factory CustodyRequest.fromRecord(Map<String, dynamic> j) => CustodyRequest(
        id:                j['id'] as String,
        fromParent:        j['from_parent'] as String,
        toParent:          j['to_parent'] as String,
        date:              DateTime.parse(j['date'] as String),
        childName:         j['child_name'] as String,
        pickupTime:        j['pickup_time'] as String,
        returnTime:        _nonEmpty(j['return_time'] as String?),
        returnTimeTbd:     (j['return_time_tbd'] as bool?) ?? false,
        status:            _statusFrom(j['status'] as String? ?? 'pending'),
        note:              _nonEmpty(j['note'] as String?),
        createdBy:         j['created_by'] as String? ?? '',
        requestedFrom:     j['requested_from'] as String? ?? '',
        toParentCollects:  (j['to_parent_collects'] as bool?) ?? true,
        toParentReturns:   (j['to_parent_returns']  as bool?) ?? false,
      );

  static String? _nonEmpty(String? s) =>
      (s == null || s.isEmpty) ? null : s;

  static CustodyStatus _statusFrom(String s) => switch (s) {
        'accepted'  => CustodyStatus.accepted,
        'declined'  => CustodyStatus.declined,
        'completed' => CustodyStatus.completed,
        _           => CustodyStatus.pending,
      };
}
