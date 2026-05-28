import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/pb_client.dart';
import '../models/household.dart';
import 'auth_provider.dart';

/// Provides the current user's active [HouseholdConfig] — members, children,
/// rotation settings.  All UI surfaces that previously relied on hardcoded
/// parent/child constants now read from this provider.
final householdProvider =
    AsyncNotifierProvider<HouseholdNotifier, HouseholdConfig?>(
  HouseholdNotifier.new,
);

class HouseholdNotifier extends AsyncNotifier<HouseholdConfig?> {
  @override
  Future<HouseholdConfig?> build() async {
    final auth = ref.watch(authProvider).valueOrNull;
    if (auth == null || !auth.isLoggedIn) return null;

    // Get active household id from the user record
    final userId = auth.userId ?? '';
    if (userId.isEmpty) return null;

    String? householdId;
    try {
      final user = await pb.collection('users').getOne(userId);
      householdId = user.data['active_household'] as String?;
    } catch (_) {
      return null;
    }

    if (householdId == null || householdId.isEmpty) return null;

    return _fetchHousehold(householdId);
  }

  Future<HouseholdConfig?> _fetchHousehold(String householdId) async {
    // Fetch household record
    final hRecord = await pb.collection('households').getOne(householdId);

    // Fetch members
    final memberRecords = await pb.collection('household_members').getFullList(
      filter: 'household = "$householdId"',
    );
    final members = memberRecords
        .map((r) => HouseholdMember.fromRecord(r.toJson()))
        .toList();

    // Fetch children
    final childRecords = await pb.collection('children').getFullList(
      filter: 'household = "$householdId"',
    );
    final children = childRecords
        .map((r) => HouseholdChild.fromRecord(r.toJson()))
        .toList();

    return HouseholdConfig.fromRecord(
      hRecord.toJson(),
      members: members,
      children: children,
    );
  }

  /// Create a new household and set it as the user's active household.
  Future<String> createHousehold({
    required String name,
    required String displayName,
  }) async {
    final auth = ref.read(authProvider).valueOrNull;
    final userId = auth?.userId ?? '';

    // Create household
    final hRecord = await pb.collection('households').create(body: {
      'name': name,
      'mode': 'custody',
    });

    // Add current user as parent member
    await pb.collection('household_members').create(body: {
      'household':    hRecord.id,
      'user':         userId,
      'role':         'parent',
      'display_name': displayName,
      'status':       'active',
    });

    // Set as active household
    await pb.collection('users').update(userId, body: {
      'active_household': hRecord.id,
    });

    ref.invalidateSelf();
    return hRecord.id;
  }

  /// Add a child to the current household.
  Future<void> addChild({
    required String name,
    String? color,
  }) async {
    final household = state.valueOrNull;
    if (household == null) return;

    await pb.collection('children').create(body: {
      'household': household.id,
      'name':      name,
      'color':     color ?? '',
    });
    ref.invalidateSelf();
  }

  /// Remove a child from the current household.
  Future<void> removeChild(String childId) async {
    await pb.collection('children').delete(childId);
    ref.invalidateSelf();
  }

  /// Update rotation settings for the current household.
  Future<void> updateRotation({
    required String anchor,
    required String evenParentUserId,
    required String oddParentUserId,
  }) async {
    final household = state.valueOrNull;
    if (household == null) return;

    await pb.collection('households').update(household.id, body: {
      'rotation_anchor':       anchor,
      'rotation_parent_even':  evenParentUserId,
      'rotation_parent_odd':   oddParentUserId,
    });
    ref.invalidateSelf();
  }

  /// Generate an invite code for this household.
  Future<String> createInvite({required String role}) async {
    final household = state.valueOrNull;
    final auth = ref.read(authProvider).valueOrNull;
    if (household == null || auth == null) throw Exception('No active household');

    final code = _generateCode();
    final expires = DateTime.now().add(const Duration(hours: 72));

    await pb.collection('household_invites').create(body: {
      'household':   household.id,
      'invite_code': code,
      'role':        role,
      'created_by':  auth.userId,
      'expires_at':  expires.toUtc().toIso8601String(),
    });

    return code;
  }

  /// Accept an invite code — joins the household.
  Future<void> acceptInvite(String code) async {
    final auth = ref.read(authProvider).valueOrNull;
    if (auth == null) throw Exception('Not logged in');
    final userId = auth.userId ?? '';
    final displayName = auth.userName ?? 'Member';

    // Find the invite
    final invites = await pb.collection('household_invites').getFullList(
      filter: 'invite_code = "$code" && used_by = ""',
    );
    if (invites.isEmpty) throw Exception('Invalid or expired invite code');

    final invite = invites.first;
    final expiresAt = DateTime.parse(invite.data['expires_at'] as String);
    if (DateTime.now().isAfter(expiresAt)) {
      throw Exception('Invite code has expired');
    }

    final householdId = invite.data['household'] as String;
    final role = invite.data['role'] as String? ?? 'parent';

    // Add as member
    await pb.collection('household_members').create(body: {
      'household':    householdId,
      'user':         userId,
      'role':         role,
      'display_name': displayName,
      'status':       'active',
    });

    // Mark invite as used
    await pb.collection('household_invites').update(invite.id, body: {
      'used_by': userId,
    });

    // Set as active household
    await pb.collection('users').update(userId, body: {
      'active_household': householdId,
    });

    ref.invalidateSelf();
  }

  String _generateCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = DateTime.now().millisecondsSinceEpoch;
    final buf = StringBuffer();
    for (var i = 0; i < 8; i++) {
      if (i == 4) buf.write('-');
      buf.write(chars[(r ~/ (i + 1) + i * 7) % chars.length]);
    }
    return buf.toString();
  }
}

/// Convenience: list of children from the active household for UI dropdowns/lists.
final householdChildNamesProvider = Provider<List<HouseholdChild>>((ref) {
  final household = ref.watch(householdProvider).valueOrNull;
  return household?.children ?? const [];
});
