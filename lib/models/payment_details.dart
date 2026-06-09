/// Banking / payment details for a household member.
///
/// Visible to all household members (so they know where to pay) but only
/// editable by the owning user.
class PaymentDetails {
  final String id;
  final String household;
  final String user;
  final String? bankName;
  final String? accountHolder;
  final String? accountNumber;
  final String? branchCode;
  final String? paymentLink;
  final String? paymentReference;
  final String? notes;

  const PaymentDetails({
    required this.id,
    required this.household,
    required this.user,
    this.bankName,
    this.accountHolder,
    this.accountNumber,
    this.branchCode,
    this.paymentLink,
    this.paymentReference,
    this.notes,
  });

  /// Whether any meaningful payment info has been provided.
  bool get hasDetails =>
      (bankName?.isNotEmpty ?? false) ||
      (paymentLink?.isNotEmpty ?? false);

  /// Masked account number for display (e.g. "****1234").
  String get maskedAccountNumber {
    if (accountNumber == null || accountNumber!.length < 4) return '****';
    return '****${accountNumber!.substring(accountNumber!.length - 4)}';
  }

  factory PaymentDetails.fromRecord(Map<String, dynamic> j) => PaymentDetails(
        id:               j['id'] as String,
        household:        j['household'] as String? ?? '',
        user:             j['user'] as String? ?? '',
        bankName:         _nonEmpty(j['bank_name'] as String?),
        accountHolder:    _nonEmpty(j['account_holder'] as String?),
        accountNumber:    _nonEmpty(j['account_number'] as String?),
        branchCode:       _nonEmpty(j['branch_code'] as String?),
        paymentLink:      _nonEmpty(j['payment_link'] as String?),
        paymentReference: _nonEmpty(j['payment_reference'] as String?),
        notes:            _nonEmpty(j['notes'] as String?),
      );

  static String? _nonEmpty(String? s) => (s == null || s.isEmpty) ? null : s;
}
