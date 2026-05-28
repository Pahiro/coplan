/// A member of a household — parent or helper (e.g. grandparent).
class HouseholdMember {
  final String id;
  final String householdId;
  final String userId;
  final String role;         // "parent" | "helper"
  final String displayName;
  final String status;       // "active" | "invited"

  const HouseholdMember({
    required this.id,
    required this.householdId,
    required this.userId,
    required this.role,
    required this.displayName,
    this.status = 'active',
  });

  bool get isParent => role == 'parent';
  bool get isHelper => role == 'helper';

  factory HouseholdMember.fromRecord(Map<String, dynamic> j) => HouseholdMember(
    id:          j['id'] as String,
    householdId: j['household'] as String? ?? '',
    userId:      j['user'] as String? ?? '',
    role:        j['role'] as String? ?? 'parent',
    displayName: j['display_name'] as String? ?? '',
    status:      j['status'] as String? ?? 'active',
  );
}

/// A child belonging to a household.
class HouseholdChild {
  final String id;
  final String householdId;
  final String name;
  final String? color; // hex e.g. "#E65100"

  const HouseholdChild({
    required this.id,
    required this.householdId,
    required this.name,
    this.color,
  });

  factory HouseholdChild.fromRecord(Map<String, dynamic> j) => HouseholdChild(
    id:          j['id'] as String,
    householdId: j['household'] as String? ?? '',
    name:        j['name'] as String? ?? '',
    color:       j['color'] as String?,
  );
}

/// Full household configuration: the household record plus its members and
/// children. Replaces all hardcoded parent/child constants.
class HouseholdConfig {
  final String id;
  final String name;
  final String rotationAnchor;       // "YYYY-MM-DD"
  final String? rotationParentEvenId; // user id
  final String? rotationParentOddId;  // user id
  final String mode;                  // "custody" | "shared"
  final List<HouseholdMember> members;
  final List<HouseholdChild> children;

  const HouseholdConfig({
    required this.id,
    required this.name,
    this.rotationAnchor = '2026-05-18',
    this.rotationParentEvenId,
    this.rotationParentOddId,
    this.mode = 'custody',
    this.members = const [],
    this.children = const [],
  });

  /// The two parents (role == "parent") in this household.
  List<HouseholdMember> get parents =>
      members.where((m) => m.isParent).toList();

  /// Helpers (grandparents, etc.) in this household.
  List<HouseholdMember> get helpers =>
      members.where((m) => m.isHelper).toList();

  /// Display name of the parent who owns even weeks.
  String? get rotationParentEvenName {
    final m = members.where((m) => m.userId == rotationParentEvenId).firstOrNull;
    return m?.displayName;
  }

  /// Display name of the parent who owns odd weeks.
  String? get rotationParentOddName {
    final m = members.where((m) => m.userId == rotationParentOddId).firstOrNull;
    return m?.displayName;
  }

  /// All child names plus "All" — for use in dropdowns.
  List<String> get childDropdownItems =>
      [...children.map((c) => c.name), 'All'];

  /// Resolve a display name to a member, or null if unknown.
  HouseholdMember? memberByName(String displayName) =>
      members.where((m) => m.displayName == displayName).firstOrNull;

  /// Resolve a user id to a member.
  HouseholdMember? memberByUserId(String userId) =>
      members.where((m) => m.userId == userId).firstOrNull;

  factory HouseholdConfig.fromRecord(
    Map<String, dynamic> j, {
    List<HouseholdMember> members = const [],
    List<HouseholdChild> children = const [],
  }) => HouseholdConfig(
    id:                     j['id'] as String,
    name:                   j['name'] as String? ?? '',
    rotationAnchor:         j['rotation_anchor'] as String? ?? '2026-05-18',
    rotationParentEvenId:   j['rotation_parent_even'] as String?,
    rotationParentOddId:    j['rotation_parent_odd'] as String?,
    mode:                   j['mode'] as String? ?? 'custody',
    members:                members,
    children:               children,
  );
}
