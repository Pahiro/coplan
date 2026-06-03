class AbsencePeriod {
  final String id;
  final String householdId;
  final String absentParent;
  final DateTime startDate;
  final DateTime endDate;
  final String reason;
  final String? note;
  final String createdBy;

  const AbsencePeriod({
    required this.id,
    required this.householdId,
    required this.absentParent,
    required this.startDate,
    required this.endDate,
    required this.reason,
    this.note,
    required this.createdBy,
  });

  bool coversDate(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    final s = DateTime(startDate.year, startDate.month, startDate.day);
    final e = DateTime(endDate.year, endDate.month, endDate.day);
    return !d.isBefore(s) && !d.isAfter(e);
  }

  int get durationDays =>
      DateTime(endDate.year, endDate.month, endDate.day)
          .difference(DateTime(startDate.year, startDate.month, startDate.day))
          .inDays + 1;

  factory AbsencePeriod.fromRecord(Map<String, dynamic> j) => AbsencePeriod(
    id:            j['id'] as String,
    householdId:   j['household'] as String? ?? '',
    absentParent:  j['absent_parent'] as String? ?? '',
    startDate:     DateTime.parse(j['start_date'] as String),
    endDate:       DateTime.parse(j['end_date'] as String),
    reason:        j['reason'] as String? ?? '',
    note:          j['note'] as String?,
    createdBy:     j['created_by'] as String? ?? '',
  );
}
