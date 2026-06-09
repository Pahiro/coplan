/// A shared expense between household members.
///
/// Amounts are stored in cents (integer) to avoid floating-point issues.
/// A once-off expense has [isRecurring] = false; recurring expenses repeat
/// on [recurrence] intervals starting from [startDate].
class SharedExpense {
  final String id;
  final String household;
  final String title;
  final String? description;
  final String childName;     // "All" | specific child
  final int amount;           // in cents
  final String currency;
  final String? category;     // education, sport, medical, clothing, other
  final bool isRecurring;
  final String? recurrence;   // monthly, quarterly, annually
  final int? dueDay;          // day of month
  final DateTime? nextDueDate;
  final DateTime? startDate;
  final DateTime? endDate;
  final String? paidBy;       // user id of parent who pays the vendor
  final bool active;
  final String createdBy;
  final DateTime created;
  final DateTime updated;

  const SharedExpense({
    required this.id,
    required this.household,
    required this.title,
    this.description,
    this.childName = 'All',
    required this.amount,
    this.currency = 'ZAR',
    this.category,
    this.isRecurring = false,
    this.recurrence,
    this.dueDay,
    this.nextDueDate,
    this.startDate,
    this.endDate,
    this.paidBy,
    this.active = true,
    required this.createdBy,
    required this.created,
    required this.updated,
  });

  /// Display amount as rands (ZAR).
  double get amountInRands => amount / 100.0;

  /// Formatted display amount.
  String get formattedAmount => 'R ${amountInRands.toStringAsFixed(2)}';

  factory SharedExpense.fromRecord(Map<String, dynamic> j) => SharedExpense(
        id:          j['id'] as String,
        household:   j['household'] as String? ?? '',
        title:       j['title'] as String? ?? '',
        description: _nonEmpty(j['description'] as String?),
        childName:   j['child_name'] as String? ?? 'All',
        amount:      (j['amount'] as num?)?.toInt() ?? 0,
        currency:    j['currency'] as String? ?? 'ZAR',
        category:    _nonEmpty(j['category'] as String?),
        isRecurring: (j['is_recurring'] as bool?) ?? false,
        recurrence:  _nonEmpty(j['recurrence'] as String?),
        dueDay:      (j['due_day'] as num?)?.toInt(),
        nextDueDate: _parseDate(j['next_due_date'] as String?),
        startDate:   _parseDate(j['start_date'] as String?),
        endDate:     _parseDate(j['end_date'] as String?),
        paidBy:      _nonEmpty(j['paid_by'] as String?),
        active:      (j['active'] as bool?) ?? true,
        createdBy:   j['created_by'] as String? ?? '',
        created:     DateTime.tryParse(j['created'] as String? ?? '') ?? DateTime.now(),
        updated:     DateTime.tryParse(j['updated'] as String? ?? '') ?? DateTime.now(),
      );

  static String? _nonEmpty(String? s) => (s == null || s.isEmpty) ? null : s;

  static DateTime? _parseDate(String? s) {
    if (s == null || s.isEmpty) return null;
    return DateTime.tryParse(s);
  }
}
