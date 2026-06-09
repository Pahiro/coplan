/// A split of a shared expense assigned to a specific household member.
///
/// Tracks how much the parent owes and whether they've paid.
/// Amounts in cents (integer).
enum SplitStatus { pending, paid, overdue }

class ExpenseSplit {
  final String id;
  final String expense;     // shared_expenses id
  final String household;
  final String user;        // user id of the parent who owes
  final String splitType;   // "percentage" or "fixed"
  final double splitValue;  // percentage (e.g. 100) or fixed amount in cents
  final int amountDue;      // calculated amount in cents
  final SplitStatus status;
  final DateTime? dueDate;
  final DateTime? paidDate;
  final String? paymentReference;
  final String? paymentNote;
  final DateTime created;
  final DateTime updated;

  const ExpenseSplit({
    required this.id,
    required this.expense,
    required this.household,
    required this.user,
    required this.splitType,
    required this.splitValue,
    required this.amountDue,
    required this.status,
    this.dueDate,
    this.paidDate,
    this.paymentReference,
    this.paymentNote,
    required this.created,
    required this.updated,
  });

  /// Display amount as rands.
  double get amountInRands => amountDue / 100.0;

  String get formattedAmount => 'R ${amountInRands.toStringAsFixed(2)}';

  bool get isPaid => status == SplitStatus.paid;
  bool get isOverdue => status == SplitStatus.overdue;

  factory ExpenseSplit.fromRecord(Map<String, dynamic> j) => ExpenseSplit(
        id:               j['id'] as String,
        expense:          j['expense'] as String? ?? '',
        household:        j['household'] as String? ?? '',
        user:             j['user'] as String? ?? '',
        splitType:        j['split_type'] as String? ?? 'percentage',
        splitValue:       (j['split_value'] as num?)?.toDouble() ?? 100,
        amountDue:        (j['amount_due'] as num?)?.toInt() ?? 0,
        status:           _statusFrom(j['status'] as String? ?? 'pending'),
        dueDate:          _parseDate(j['due_date'] as String?),
        paidDate:         _parseDate(j['paid_date'] as String?),
        paymentReference: _nonEmpty(j['payment_reference'] as String?),
        paymentNote:      _nonEmpty(j['payment_note'] as String?),
        created:          DateTime.tryParse(j['created'] as String? ?? '') ?? DateTime.now(),
        updated:          DateTime.tryParse(j['updated'] as String? ?? '') ?? DateTime.now(),
      );

  static SplitStatus _statusFrom(String s) => switch (s) {
        'paid'    => SplitStatus.paid,
        'overdue' => SplitStatus.overdue,
        _         => SplitStatus.pending,
      };

  static String? _nonEmpty(String? s) => (s == null || s.isEmpty) ? null : s;

  static DateTime? _parseDate(String? s) {
    if (s == null || s.isEmpty) return null;
    return DateTime.tryParse(s);
  }
}
