enum CustodyStatus { pending, accepted, declined, completed }

/// A request between parents to transfer custody of the children.
///
/// Two kinds, distinguished by whether a return time is expected:
///   - Day transfer  (isDayTransfer == true): no return time; [toParent] keeps
///     the kids for the rest of the day / overnight. Accepted day transfers
///     override dayOwner() in the resolution engine.
///   - Window        (isDayTransfer == false): kids return to [fromParent] at
///     [returnTime] (or TBD). Affects parentAtTime() only.
///
/// A day swap is two day transfers sharing a [swapGroup]: one where the
/// requester hands over their day, one where they take the other parent's.
/// The legs are accepted, declined and cancelled together.
class CustodyRequest {
  final String id;
  final String fromParent;    // display name — releases custody
  final String toParent;      // display name — takes custody
  final DateTime date;
  final String childName;     // "All" | "Henri" | "Henri,Chris"
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

  /// Shared id linking the two legs of a day swap; null for single requests.
  final String? swapGroup;

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
    this.swapGroup,
  });

  bool get isAccepted => status == CustodyStatus.accepted;
  bool get isPending  => status == CustodyStatus.pending;
  bool get isSwapLeg  => swapGroup != null;

  /// No return time expected — [toParent] keeps the kids for the day/overnight.
  bool get isDayTransfer => returnTime == null && !returnTimeTbd;

  String get statusLabel => switch (status) {
        CustodyStatus.accepted  => 'Accepted',
        CustodyStatus.declined  => 'Declined',
        CustodyStatus.completed => 'Completed',
        CustodyStatus.pending   => 'Pending',
      };

  /// e.g. "14:30–19:00", "14:30–TBD", "16:00 onwards", or "All day".
  String get timeWindowLabel {
    if (isDayTransfer) {
      return pickupTime == '00:00' ? 'All day' : '$pickupTime onwards';
    }
    final end = returnTimeTbd ? 'TBD' : (returnTime ?? 'TBD');
    return '$pickupTime–$end';
  }

  factory CustodyRequest.fromRecord(Map<String, dynamic> j) => CustodyRequest(
        id:                j['id'] as String,
        fromParent:        j['from_parent'] as String,
        toParent:          j['to_parent'] as String,
        date:              DateTime.parse(j['date'] as String),
        childName:         j['child_name'] as String,
        pickupTime:        _nonEmpty(j['pickup_time'] as String?) ?? '00:00',
        returnTime:        _nonEmpty(j['return_time'] as String?),
        returnTimeTbd:     (j['return_time_tbd'] as bool?) ?? false,
        status:            _statusFrom(j['status'] as String? ?? 'pending'),
        note:              _nonEmpty(j['note'] as String?),
        createdBy:         j['created_by'] as String? ?? '',
        requestedFrom:     j['requested_from'] as String? ?? '',
        toParentCollects:  (j['to_parent_collects'] as bool?) ?? true,
        toParentReturns:   (j['to_parent_returns']  as bool?) ?? false,
        swapGroup:         _nonEmpty(j['swap_group'] as String?),
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

/// One actionable unit on the requests list: a single request, or both legs
/// of a day swap (sorted by date).
class RequestGroup {
  final List<CustodyRequest> legs;
  const RequestGroup(this.legs);

  CustodyRequest get first => legs.first;
  bool get isSwap => first.isSwapLeg;
  String get key => first.swapGroup ?? first.id;
  String get createdBy => first.createdBy;
  String get requestedFrom => first.requestedFrom;
  DateTime get firstDate => legs.first.date;
  DateTime get lastDate => legs.last.date;

  /// Pending while any leg is pending, otherwise the first leg's status.
  CustodyStatus get status =>
      legs.any((r) => r.isPending) ? CustodyStatus.pending : first.status;

  /// The leg where [parentName] receives the kids, if any.
  CustodyRequest? legTo(String parentName) {
    for (final r in legs) {
      if (r.toParent == parentName) return r;
    }
    return null;
  }
}

/// Collapses swap legs into a single [RequestGroup]; other requests become
/// groups of one. Order follows the first occurrence in [requests].
List<RequestGroup> groupRequests(Iterable<CustodyRequest> requests) {
  final groups = <RequestGroup>[];
  final swaps = <String, List<CustodyRequest>>{};
  for (final r in requests) {
    final g = r.swapGroup;
    if (g == null) {
      groups.add(RequestGroup([r]));
      continue;
    }
    final legs = swaps[g];
    if (legs == null) {
      final created = [r];
      swaps[g] = created;
      groups.add(RequestGroup(created));
    } else {
      legs.add(r);
    }
  }
  for (final legs in swaps.values) {
    legs.sort((a, b) => a.date.compareTo(b.date));
  }
  return groups;
}
