class ManualOverride {
  final String id;
  final DateTime targetDate;
  final String childName;
  final String? originalParent;  // null for ad-hoc events
  final String assignedParent;
  final String? overrideTime;
  final String reason;
  final String createdBy;

  // Ad-hoc event fields (only used when isAdhoc == true)
  final bool isAdhoc;
  final String? adhocActivity;
  final String? adhocLocation;

  /// When true this one-off event is a shared obligation visible to both parents
  /// (e.g. birthday party, school trip).
  final bool isShared;

  const ManualOverride({
    required this.id,
    required this.targetDate,
    required this.childName,
    this.originalParent,
    required this.assignedParent,
    this.overrideTime,
    required this.reason,
    required this.createdBy,
    this.isAdhoc = false,
    this.adhocActivity,
    this.adhocLocation,
    this.isShared = false,
  });

  factory ManualOverride.fromRecord(Map<String, dynamic> j) {
    final reason        = j['reason'] as String? ?? '';
    final activityField = j['activity'] as String? ?? '';

    // PocketBase may silently drop unknown fields (like `is_adhoc`) if they
    // aren't in the collection schema.  Fall back to a reliable signal:
    // createSharedEvent() always writes a non-empty `reason` field, while
    // non-adhoc parent-substitution overrides do not go through any create
    // path in this codebase and therefore have no meaningful reason text.
    final isAdhocFlag = (j['is_adhoc'] as bool?) ?? reason.isNotEmpty;

    // Prefer the dedicated `activity` field; fall back to `reason` which
    // createSharedEvent() always mirrors the activity name into.
    final effectiveActivity = activityField.isNotEmpty ? activityField : reason;

    return ManualOverride(
      id:             j['id'] as String,
      targetDate:     DateTime.parse(j['target_date'] as String),
      childName:      j['child_name'] as String,
      originalParent: j['original_parent'] as String?,
      assignedParent: j['assigned_parent'] as String,
      overrideTime:   j['override_time'] as String?,
      reason:         reason,
      createdBy:      j['created_by'] as String? ?? '',
      isAdhoc:        isAdhocFlag,
      adhocActivity:  effectiveActivity.isNotEmpty ? effectiveActivity : null,
      adhocLocation:  j['location'] as String?,
      isShared:       (j['is_shared'] as bool?) ?? false,
    );
  }
}
