enum NeedStatus { open, claimed, bought }

/// An item on the household's shared "to buy" list — new school shoes, a
/// tennis racket. One parent claims it ("I'll get it") so both don't buy it,
/// then marks it bought and can link the resulting shared expense.
class Need {
  final String id;
  final String householdId;
  final String title;
  final String childName;     // "All" | child name
  final String? note;         // size, brand, link…
  final DateTime? neededBy;
  final NeedStatus status;
  final String? claimedBy;    // user id
  final String? boughtBy;     // user id
  final DateTime? boughtAt;
  final String? expenseId;
  final String createdBy;
  final DateTime created;

  const Need({
    required this.id,
    required this.householdId,
    required this.title,
    this.childName = 'All',
    this.note,
    this.neededBy,
    this.status = NeedStatus.open,
    this.claimedBy,
    this.boughtBy,
    this.boughtAt,
    this.expenseId,
    required this.createdBy,
    required this.created,
  });

  bool get isBought  => status == NeedStatus.bought;
  bool get isClaimed => status == NeedStatus.claimed && claimedBy != null;

  factory Need.fromRecord(Map<String, dynamic> j) => Need(
        id:          j['id'] as String,
        householdId: j['household'] as String? ?? '',
        title:       j['title'] as String? ?? '',
        childName:   _nonEmpty(j['child_name'] as String?) ?? 'All',
        note:        _nonEmpty(j['note'] as String?),
        neededBy:    _date(j['needed_by'] as String?),
        status:      switch (j['status'] as String?) {
          'claimed' => NeedStatus.claimed,
          'bought'  => NeedStatus.bought,
          _         => NeedStatus.open,
        },
        claimedBy:   _nonEmpty(j['claimed_by'] as String?),
        boughtBy:    _nonEmpty(j['bought_by'] as String?),
        boughtAt:    _date(j['bought_at'] as String?),
        expenseId:   _nonEmpty(j['expense'] as String?),
        createdBy:   j['created_by'] as String? ?? '',
        created:     DateTime.tryParse(j['created'] as String? ?? '') ?? DateTime.now(),
      );

  static String? _nonEmpty(String? s) => (s == null || s.isEmpty) ? null : s;
  static DateTime? _date(String? s) =>
      (s == null || s.isEmpty) ? null : DateTime.tryParse(s);
}
