import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants.dart';
import '../core/pb_client.dart';
import '../models/custody_request.dart';
import '../services/offline_cache.dart';
import '../services/queue_service.dart';
import '../services/widget_cache_service.dart';
import 'auth_provider.dart';
import 'household_provider.dart';
import 'queue_count_provider.dart';
import 'schedule_provider.dart';

// ── Badge count ───────────────────────────────────────────────────────────────

/// Pending requests directed at the current user — drives the notification bell.
final pendingCustodyCountProvider = Provider<int>((ref) {
  final myId     = ref.watch(authProvider).valueOrNull?.userId ?? '';
  final requests = ref.watch(custodyRequestsProvider).valueOrNull ?? const [];
  return requests
      .where((r) =>
          r.requestedFrom == myId && r.status == CustodyStatus.pending)
      .length;
});

// ── Read ──────────────────────────────────────────────────────────────────────

final custodyRequestsProvider =
    AsyncNotifierProvider<CustodyRequestsNotifier, List<CustodyRequest>>(
  CustodyRequestsNotifier.new,
);

class CustodyRequestsNotifier
    extends AsyncNotifier<List<CustodyRequest>> {
  @override
  Future<List<CustodyRequest>> build() => _fetch();

  Future<List<CustodyRequest>> _fetch() {
    final userId = pb.authStore.record?.id ?? '';
    return fetchCachedList(
      collection: 'custody_requests_mine',
      fetch: () => pb.collection('custody_requests').getFullList(
            filter: 'created_by = "$userId" || requested_from = "$userId"',
            sort: '-date',
          ),
      parse: CustodyRequest.fromRecord,
    );
  }

  // ── Write: custody request ─────────────────────────────────────────────────

  /// Creates a custody request. Set [iAmTaking] to true when the current user
  /// will receive the kids, false when asking the other parent to take them.
  ///
  /// Omit [returnTime] and leave [returnTimeTbd] false for a day transfer
  /// (no return expected — kids stay overnight). Set [returnTimeTbd] for a
  /// window where the return time is yet to be confirmed.
  /// When [recipientUserId] and [recipientName] are supplied, the request is
  /// directed at that specific member (e.g. a helper) instead of the co-parent:
  /// the current user hands the kids to them. Helper requests are always
  /// one-off (repeatWeekly is ignored).
  Future<void> createRequest({
    required bool iAmTaking,
    required String date,
    required String childName,
    required String pickupTime,
    String? returnTime,
    bool returnTimeTbd = false,
    String? note,
    bool repeatWeekly = false,
    String? repeatReason,
    String? repeatEndDate,
    bool toParentCollects = true,
    bool toParentReturns  = false,
    String? recipientUserId,
    String? recipientName,
  }) async {
    final auth      = ref.read(authProvider).valueOrNull;
    final myId      = auth?.userId ?? '';
    final myName    = auth?.userName?.trim() ?? 'Parent';
    final household = await ref.read(householdProvider.future);
    final householdId = household?.id;
    if (householdId == null) throw Exception('No active household — cannot create custody request');

    final bool isHelperRequest =
        recipientUserId != null && recipientName != null;

    final String fromParent, toParent, requestedFrom;
    if (isHelperRequest) {
      // Current user hands the kids to the named recipient (helper).
      fromParent    = myName;
      toParent      = recipientName;
      requestedFrom = recipientUserId;
    } else {
      final otherName = _otherParentName(myName);
      fromParent    = iAmTaking ? otherName : myName;
      toParent      = iAmTaking ? myName    : otherName;
      requestedFrom = await otherParentId();
    }

    final body = {
      'from_parent':       fromParent,
      'to_parent':         toParent,
      'date':              date,
      'child_name':        childName,
      'pickup_time':       pickupTime,
      'return_time':       returnTime ?? '',
      'return_time_tbd':   returnTimeTbd,
      'status':            'pending',
      'note':              note ?? '',
      'created_by':        myId,
      'requested_from':    requestedFrom,
      'to_parent_collects': toParentCollects,
      'to_parent_returns':  toParentReturns,
      'household': householdId,
    };

    try {
      await pb.collection('custody_requests').create(body: body);
    } catch (e) {
      if (!isNetworkError(e)) rethrow;
      await QueueService.enqueue(PendingOp(
        id:         QueueService.newOpId(),
        collection: 'custody_requests',
        method:     'create',
        body:       body,
      ));
      _updateCount();
      return;
    }
    ref.invalidateSelf();
    ref.invalidate(acceptedCustodyProvider);
    ref.invalidate(dashboardProvider);

    // Recurring is parent-only; helper pickups are always one-off.
    if (repeatWeekly && !isHelperRequest) {
      final date_ = DateTime.parse(date);
      final reason = (repeatReason?.isNotEmpty ?? false)
          ? repeatReason!
          : '${iAmTaking ? "Weekly pickup" : "Weekly transfer"} by $myName';
      await ref.read(weekdayRulesNotifierProvider.notifier).create(
            dayOfWeek:      date_.weekday,
            assignedParent: toParent,
            reason:         reason,
            endDate:        repeatEndDate,
          );
    }
  }

  // ── Write: edit / delete ──────────────────────────────────────────────────

  Future<void> updateRequest(
    String id, {
    required String date,
    required String childName,
    required String pickupTime,
    String? returnTime,
    bool returnTimeTbd = false,
    String? note,
    bool toParentCollects = true,
    bool toParentReturns  = false,
  }) async {
    final body = {
      'date':              date,
      'child_name':        childName,
      'pickup_time':       pickupTime,
      'return_time':       returnTime ?? '',
      'return_time_tbd':   returnTimeTbd,
      'note':              note ?? '',
      'to_parent_collects': toParentCollects,
      'to_parent_returns':  toParentReturns,
    };
    try {
      await pb.collection('custody_requests').update(id, body: body);
    } catch (e) {
      if (!isNetworkError(e)) rethrow;
      await QueueService.enqueue(PendingOp(
        id:         QueueService.newOpId(),
        collection: 'custody_requests',
        method:     'update',
        body:       body,
        recordId:   id,
      ));
      _updateCount();
      return;
    }
    ref.invalidateSelf();
    ref.invalidate(acceptedCustodyProvider);
    ref.invalidate(dashboardProvider);
  }

  Future<void> deleteRequest(String id) async {
    await pb.collection('custody_requests').delete(id);
    ref.invalidateSelf();
    ref.invalidate(acceptedCustodyProvider);
    ref.invalidate(dashboardProvider);
  }

  // ── Write: respond / complete ──────────────────────────────────────────────

  /// Accept or decline a request. An optional [note] (e.g. a decline reason)
  /// is appended to the request's note so the requester sees the context.
  Future<void> respond(String id, {required bool accept, String? note}) async {
    final body = <String, dynamic>{'status': accept ? 'accepted' : 'declined'};
    if (note != null && note.trim().isNotEmpty) {
      final existing = state.valueOrNull
          ?.firstWhereOrNull((r) => r.id == id)?.note;
      final prefix = accept ? 'Accepted' : 'Declined';
      body['note'] = [
        if (existing != null && existing.isNotEmpty) existing,
        '$prefix: ${note.trim()}',
      ].join('\n');
    }
    try {
      await pb.collection('custody_requests').update(id, body: body);
    } catch (e) {
      if (!isNetworkError(e)) rethrow;
      await QueueService.enqueue(PendingOp(
        id:         QueueService.newOpId(),
        collection: 'custody_requests',
        method:     'update',
        body:       body,
        recordId:   id,
      ));
      _updateCount();
      return;
    }
    ref.invalidateSelf();
    ref.invalidate(acceptedCustodyProvider);
    ref.invalidate(dashboardProvider);
  }

  /// Mark a window request completed once the kids have been returned.
  Future<void> complete(String id) async {
    const body = {'status': 'completed'};
    try {
      await pb.collection('custody_requests').update(id, body: body);
    } catch (e) {
      if (!isNetworkError(e)) rethrow;
      await QueueService.enqueue(PendingOp(
        id:         QueueService.newOpId(),
        collection: 'custody_requests',
        method:     'update',
        body:       {'status': 'completed'},
        recordId:   id,
      ));
      _updateCount();
      return;
    }
    ref.invalidateSelf();
    ref.invalidate(acceptedCustodyProvider);
  }

  // ── Write: shared one-off event ────────────────────────────────────────────

  Future<void> createSharedEvent({
    required String targetDate,
    required String childName,
    required String time,
    required String activity,
    required String location,
    required String assignedParent,
    String? endTime,
    String? note,
  }) async {
    final auth = ref.read(authProvider).valueOrNull;
    final myId = auth?.userId ?? '';
    final hid  = ref.read(householdProvider).valueOrNull?.id;
    // Every create MUST stamp household — the hardened access rules deny
    // unstamped records with an opaque 400 otherwise.
    if (hid == null) {
      throw Exception('No active household yet — please try again in a moment.');
    }
    final body = {
      'target_date':     targetDate,
      'child_name':      childName,
      'original_parent': assignedParent,
      'assigned_parent': assignedParent,
      'override_time':   time,
      'reason':          activity,  // required field — use activity as reason
      'created_by':      myId,
      'is_adhoc':        true,
      'is_shared':       true,
      'activity':        activity,
      'location':        location,
      if (endTime != null && endTime.isNotEmpty) 'end_time': endTime,
      if (note != null && note.isNotEmpty) 'note': note,
      'household': hid,
    };
    try {
      await pb.collection('manual_overrides').create(body: body);
    } catch (e) {
      if (!isNetworkError(e)) rethrow;
      await QueueService.enqueue(PendingOp(
        id:         QueueService.newOpId(),
        collection: 'manual_overrides',
        method:     'create',
        body:       body,
      ));
      _updateCount();
      return;
    }
    ref.invalidate(manualOverridesProvider);
    ref.invalidate(dashboardProvider);
    ref.invalidate(weekEventsProvider);
    ref.invalidate(resolvedDayProvider);
    WidgetCacheService.updateCache(); // refresh home-screen widget immediately
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  /// Returns the PocketBase user id of the other parent.
  /// Returns the display name of the other parent in the household.
  String _otherParentName(String myName) {
    final household = ref.read(householdProvider).valueOrNull;
    if (household != null) {
      final other = household.parents
          .where((m) => m.displayName != myName)
          .firstOrNull;
      if (other != null) return other.displayName;
    }
    // Fallback for legacy setups
    return myName == AppConstants.parentBennet
        ? AppConstants.parentJana
        : AppConstants.parentBennet;
  }

  /// Resolves the PocketBase user ID of the other parent in this household.
  ///
  /// Three fallback strategies so this works offline after the first success:
  ///   1. Look up the other parent from household members.
  ///   2. List all users and take the one that isn't me.
  ///   3. Return the value cached in SharedPreferences from a previous call.
  Future<String> otherParentId() async {
    final myId = pb.authStore.record?.id ?? '';

    // Strategy 1: household members
    final household = ref.read(householdProvider).valueOrNull;
    if (household != null) {
      final other = household.parents
          .where((m) => m.userId != myId)
          .firstOrNull;
      if (other != null) {
        await QueueService.saveOtherParentId(other.userId);
        return other.userId;
      }
    }

    // Strategy 2: list users
    try {
      final users = await pb.collection('users').getFullList();
      final other = users.firstWhereOrNull((u) => u.id != myId);
      if (other != null) {
        await QueueService.saveOtherParentId(other.id);
        return other.id;
      }
    } catch (_) {}

    // Strategy 3: cached value
    final cached = await QueueService.loadOtherParentId();
    if (cached != null) return cached;

    throw Exception(
      'No co-parent found — invite them to join your household in CoPlan.',
    );
  }

  void _updateCount() async {
    final count = await QueueService.pendingCount();
    ref.read(pendingOpsCountProvider.notifier).state = count;
  }
}
