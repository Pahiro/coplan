class HolidayBlock {
  final String id;
  final String householdId;
  final String name;
  final String assignedParent;
  final DateTime startDate;
  final DateTime endDate;
  final String? notes;
  final String createdBy;

  const HolidayBlock({
    required this.id,
    required this.householdId,
    required this.name,
    required this.assignedParent,
    required this.startDate,
    required this.endDate,
    this.notes,
    required this.createdBy,
  });

  bool coversDate(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    final s = DateTime(startDate.year, startDate.month, startDate.day);
    final e = DateTime(endDate.year, endDate.month, endDate.day);
    return !d.isBefore(s) && !d.isAfter(e);
  }

  factory HolidayBlock.fromRecord(Map<String, dynamic> j) => HolidayBlock(
        id:             j['id'] as String,
        householdId:    j['household'] as String? ?? '',
        name:           j['name'] as String? ?? '',
        assignedParent: j['assigned_parent'] as String? ?? '',
        startDate:      DateTime.parse(j['start_date'] as String),
        endDate:        DateTime.parse(j['end_date'] as String),
        notes:          (j['notes'] as String?)?.isNotEmpty == true
                            ? j['notes'] as String : null,
        createdBy:      j['created_by'] as String? ?? '',
      );
}
