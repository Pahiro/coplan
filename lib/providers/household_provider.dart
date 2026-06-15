import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/pb_client.dart';
import '../models/household.dart';
import '../models/rotation_scheme.dart';
import '../services/offline_cache.dart';
import '../services/queue_service.dart' show isNetworkError;
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

    final userId = auth.userId ?? '';
    if (userId.isEmpty) return null;

    String? householdId;
    try {
      final user = await pb.collection('users').getOne(userId);
      householdId = user.data['active_household'] as String?;
      if (householdId != null && householdId.isNotEmpty) {
        await OfflineCache.writeString('active_household', householdId);
      }
    } catch (e) {
      // Server unreachable — fall back to the last known active household so
      // the rest of the resolution chain can serve from its own cache.
      if (isNetworkError(e)) {
        householdId = OfflineCache.readString('active_household');
      }
      if (householdId == null || householdId.isEmpty) return null;
    }

    if (householdId == null || householdId.isEmpty) return null;

    return _fetchHousehold(householdId);
  }

  Future<HouseholdConfig?> _fetchHousehold(String householdId) async {
    try {
      final hRecord = await pb.collection('households').getOne(householdId);
      final memberRecords = await pb.collection('household_members').getFullList(
        filter: 'household = "$householdId"',
      );
      final childRecords = await pb.collection('children').getFullList(
        filter: 'household = "$householdId"',
      );

      final hJson = hRecord.toJson();
      final mJson = memberRecords.map((r) => r.toJson()).toList();
      final cJson = childRecords.map((r) => r.toJson()).toList();

      // Cache the raw records so the engine can rebuild the household config
      // (rotation anchor, parent names, children) while the server is down.
      await OfflineCache.writeMap('household_record', hJson);
      await OfflineCache.writeList('household_members', mJson);
      await OfflineCache.writeList('household_children', cJson);

      return HouseholdConfig.fromRecord(
        hJson,
        members: mJson.map(HouseholdMember.fromRecord).toList(),
        children: cJson.map(HouseholdChild.fromRecord).toList(),
      );
    } catch (e) {
      if (isNetworkError(e)) {
        final cached = _cachedHousehold();
        if (cached != null) return cached;
      }
      rethrow;
    }
  }

  /// Rebuilds the household config from cached raw records, or null if nothing
  /// has been cached yet (e.g. first launch was offline).
  HouseholdConfig? _cachedHousehold() {
    final hJson = OfflineCache.readMap('household_record');
    if (hJson == null) return null;
    final mJson = OfflineCache.readList('household_members') ?? const [];
    final cJson = OfflineCache.readList('household_children') ?? const [];
    return HouseholdConfig.fromRecord(
      hJson,
      members: mJson.map(HouseholdMember.fromRecord).toList(),
      children: cJson.map(HouseholdChild.fromRecord).toList(),
    );
  }

  /// Create a new household, add the creator as the owning parent, optionally
  /// add children, and set it as the user's active household.
  ///
  /// Children are created here (not via a separate [addChild] loop) using the
  /// new household id directly — right after creation the provider's state is
  /// still the previous value (null), so [addChild] would no-op.
  Future<String> createHousehold({
    required String name,
    required String displayName,
    List<String> childNames = const [],
  }) async {
    final auth = ref.read(authProvider).valueOrNull;
    final userId = auth?.userId ?? '';

    // Create household (creator becomes the owner)
    final hRecord = await pb.collection('households').create(body: {
      'name': name,
      'mode': 'custody',
      'owner': userId,
    });

    // Add current user as parent member (must precede child creation: the
    // children create rule requires the caller to be a member of the household).
    await pb.collection('household_members').create(body: {
      'household':    hRecord.id,
      'user':         userId,
      'role':         'parent',
      'display_name': displayName,
      'status':       'active',
    });

    // Add children
    for (final raw in childNames) {
      final childName = raw.trim();
      if (childName.isEmpty) continue;
      await pb.collection('children').create(body: {
        'household': hRecord.id,
        'name':      childName,
        'color':     '',
      });
    }

    // Set as active household
    await pb.collection('users').update(userId, body: {
      'active_household': hRecord.id,
    });

    ref.invalidateSelf();
    return hRecord.id;
  }

  /// Remove a member (parent or helper) from the current household.
  /// Intended for the household owner; the owner cannot be removed.
  Future<void> removeMember(String memberId) async {
    await pb.collection('household_members').delete(memberId);
    ref.invalidateSelf();
  }

  /// Transfer household ownership to another member (a parent's user id).
  Future<void> updateOwner(String newOwnerUserId) async {
    final household = state.valueOrNull;
    if (household == null) return;
    await pb.collection('households').update(household.id, body: {
      'owner': newOwnerUserId,
    });
    ref.invalidateSelf();
  }

  /// Rename the current household.
  Future<void> updateName(String name) async {
    final household = state.valueOrNull;
    if (household == null) return;
    await pb.collection('households').update(household.id, body: {'name': name});
    ref.invalidateSelf();
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

  /// Update the rotation scheme (pattern type) for the current household.
  Future<void> updateRotationScheme(RotationScheme scheme) async {
    final household = state.valueOrNull;
    if (household == null) return;

    await pb.collection('households').update(household.id, body: {
      'rotation_scheme_type': scheme.type,
      'rotation_pattern':     scheme.pattern,
    });
    ref.invalidateSelf();
  }

  /// Switch household mode between "custody" and "shared".
  Future<void> updateMode(String mode) async {
    final household = state.valueOrNull;
    if (household == null) return;

    await pb.collection('households').update(household.id, body: {
      'mode': mode,
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
  ///
  /// Redemption runs server-side (`/api/coplan/accept-invite`, see pb_hooks):
  /// a joiner is not yet a member, so under the household-scoped access rules
  /// they can't read the invite or create their own membership. The route
  /// validates the code, adds the membership, marks the invite used, and sets
  /// the user's active household — all with elevated privileges.
  Future<void> acceptInvite(String code) async {
    final auth = ref.read(authProvider).valueOrNull;
    if (auth == null) throw Exception('Not logged in');

    await pb.send(
      '/api/coplan/accept-invite',
      method: 'POST',
      body: {'code': code.trim().toUpperCase()},
    );

    // Refresh the auth store so pb.authStore.record has the updated
    // active_household — without this the authProvider rebuilds with stale
    // data and needsHousehold stays true, keeping the user on the setup screen.
    await pb.collection('users').authRefresh();

    ref.invalidate(authProvider);
    ref.invalidateSelf();
  }

  String _generateCode() {
    // Unambiguous charset (no 0/O/1/I). Cryptographically random so codes
    // can't be guessed or collide when generated close together.
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rand = Random.secure();
    final buf = StringBuffer();
    for (var i = 0; i < 8; i++) {
      if (i == 4) buf.write('-');
      buf.write(chars[rand.nextInt(chars.length)]);
    }
    return buf.toString();
  }
}

/// Convenience: list of children from the active household for UI dropdowns/lists.
final householdChildNamesProvider = Provider<List<HouseholdChild>>((ref) {
  final household = ref.watch(householdProvider).valueOrNull;
  return household?.children ?? const [];
});
