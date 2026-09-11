class ManualOverride {
  final String id;
  final DateTime targetDate;
  final String childName;
  final String? originalParent;  // null for ad-hoc events
  final String assignedParent;
  final String? overrideTime;
  final String? endTime;
  final String reason;
  final String? note;
  final String createdBy;

  // Ad-hoc event fields (only used when isAdhoc == true)
  final bool isAdhoc;
  final String? adhocActivity;
  final String? adhocLocation;

  /// When true both parents attend this one-off event.
  final bool isShared;

  /// '' for an ordinary one-off event, 'exam' for a school exam.
  final String kind;

  const ManualOverride({
    required this.id,
    required this.targetDate,
    required this.childName,
    this.originalParent,
    required this.assignedParent,
    this.overrideTime,
    this.endTime,
    required this.reason,
    this.note,
    required this.createdBy,
    this.isAdhoc = false,
    this.adhocActivity,
    this.adhocLocation,
    this.isShared = false,
    this.kind = '',
  });

  bool get isExam => kind == 'exam';

  factory ManualOverride.fromRecord(Map<String, dynamic> j) {
    final reason        = j['reason'] as String? ?? '';
    final activityField = j['activity'] as String? ?? '';

    // Older records may lack `is_adhoc`. Fall back to a reliable signal:
    // one-off event creation always writes a non-empty `reason`, while
    // parent-substitution overrides have no meaningful reason text.
    final isAdhocFlag = (j['is_adhoc'] as bool?) ?? reason.isNotEmpty;

    // Prefer the dedicated `activity` field; fall back to `reason`, which
    // one-off event creation mirrors the activity name into.
    final effectiveActivity = activityField.isNotEmpty ? activityField : reason;

    return ManualOverride(
      id:             j['id'] as String,
      targetDate:     DateTime.parse(j['target_date'] as String),
      childName:      j['child_name'] as String,
      originalParent: j['original_parent'] as String?,
      assignedParent: j['assigned_parent'] as String,
      overrideTime:   _nonEmpty(j['override_time'] as String?),
      endTime:        j['end_time'] as String?,
      reason:         reason,
      note:           j['note'] as String?,
      createdBy:      j['created_by'] as String? ?? '',
      isAdhoc:        isAdhocFlag,
      adhocActivity:  effectiveActivity.isNotEmpty ? effectiveActivity : null,
      adhocLocation:  j['location'] as String?,
      isShared:       (j['is_shared'] as bool?) ?? false,
      kind:           j['kind'] as String? ?? '',
    );
  }

  static String? _nonEmpty(String? s) => (s == null || s.isEmpty) ? null : s;
}
