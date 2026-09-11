import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/pb_client.dart';
import '../models/custody_request.dart';
import '../services/offline_cache.dart';
import '../services/queue_service.dart';
import '../services/widget_cache_service.dart';
import '../utils/ids.dart';
import 'auth_provider.dart';
import 'household_provider.dart';
import 'queue_count_provider.dart';
import 'schedule_provider.dart';

// ── Derived ───────────────────────────────────────────────────────────────────

/// Pending requests waiting for the current user's answer, soonest first.
/// A day swap counts once.
final pendingForMeProvider = Provider<List<RequestGroup>>((ref) {
  final myId     = ref.watch(authProvider).valueOrNull?.userId ?? '';
  final requests = ref.watch(custodyRequestsProvider).valueOrNull ?? const [];
  return groupRequests(requests)
      .where((g) => g.requestedFrom == myId && g.status == CustodyStatus.pending)
      .toList()
    ..sort((a, b) => a.firstDate.compareTo(b.firstDate));
});

/// Drives the notification bell badge.
final pendingCustodyCountProvider =
    Provider<int>((ref) => ref.watch(pendingForMeProvider).length);

// ── Read ──────────────────────────────────────────────────────────────────────

final custodyRequestsProvider =
    AsyncNotifierProvider<CustodyRequestsNotifier, List<CustodyRequest>>(
  CustodyRequestsNotifier.new,
);

/// The current user's requests (made by or addressed to them), plus all
/// custody writes.
class CustodyRequestsNotifier extends AsyncNotifier<List<CustodyRequest>> {
  @override
  Future<List<CustodyRequest>> build() {
    final userId = ref.watch(authProvider).valueOrNull?.userId ?? '';
    return fetchCachedList(
      collection: 'custody_requests_mine',
      fetch: () => pb.collection('custody_requests').getFullList(
            filter: 'created_by = "$userId" || requested_from = "$userId"',
            sort: '-date',
          ),
      parse: CustodyRequest.fromRecord,
    );
  }

  // ── Create ──────────────────────────────────────────────────────────────────

  /// A one-way day handover or time window with the co-parent. Set [iAmTaking]
  /// when the current user receives the kids.
  ///
  /// Omit [returnTime] and leave [returnTimeTbd] false for a day transfer.
  /// When [recipientUserId] and [recipientName] are supplied, the current user
  /// hands the kids to that member (e.g. a helper) instead.
  Future<void> createRequest({
    required bool iAmTaking,
    required String date,
    required String childName,
    required String pickupTime,
    String? returnTime,
    bool returnTimeTbd = false,
    String? note,
    bool toParentCollects = true,
    bool toParentReturns  = false,
    String? recipientUserId,
    String? recipientName,
  }) async {
    final p = _party();

    final String fromParent, toParent, requestedFrom;
    if (recipientUserId != null && recipientName != null) {
      fromParent    = p.myName;
      toParent      = recipientName;
      requestedFrom = recipientUserId;
    } else {
      final other   = p.requireCoParent();
      fromParent    = iAmTaking ? other.name : p.myName;
      toParent      = iAmTaking ? p.myName   : other.name;
      requestedFrom = other.userId;
    }

    await _createAll([
      {
        ..._base(p, requestedFrom, note),
        'from_parent':        fromParent,
        'to_parent':          toParent,
        'date':               date,
        'child_name':         childName,
        'pickup_time':        pickupTime,
        'return_time':        returnTime ?? '',
        'return_time_tbd':    returnTimeTbd,
        'to_parent_collects': toParentCollects,
        'to_parent_returns':  toParentReturns,
      },
    ]);
  }

  /// A day swap with the co-parent: they take the kids on [giveDate] (a day
  /// the current user has them) and the current user takes them on
  /// [takeDate]. Stored as two linked day transfers that are answered
  /// together. Pickup times default to the whole day.
  Future<void> createSwap({
    required String giveDate,
    required String takeDate,
    required String childName,
    String givePickup = '00:00',
    String takePickup = '00:00',
    String? note,
  }) async {
    final p     = _party();
    final other = p.requireCoParent();
    final group = newRecordId();

    Map<String, dynamic> leg(String from, String to, String date, String pickup) => {
          ..._base(p, other.userId, note),
          'from_parent':        from,
          'to_parent':          to,
          'date':               date,
          'child_name':         childName,
          'pickup_time':        pickup,
          'return_time':        '',
          'return_time_tbd':    false,
          'to_parent_collects': true,
          'to_parent_returns':  false,
          'swap_group':         group,
        };

    await _createAll([
      leg(p.myName, other.name, giveDate, givePickup),
      leg(other.name, p.myName, takeDate, takePickup),
    ]);
  }

  // ── Edit / delete ───────────────────────────────────────────────────────────

  /// Edits a pending request (the server refuses edits once it's answered).
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
    await _updateAll([id], {
      'date':               date,
      'child_name':         childName,
      'pickup_time':        pickupTime,
      'return_time':        returnTime ?? '',
      'return_time_tbd':    returnTimeTbd,
      'note':               note ?? '',
      'to_parent_collects': toParentCollects,
      'to_parent_returns':  toParentReturns,
    });
  }

  /// Withdraws a pending request or cancels an agreement (both legs of a
  /// swap). Only the requester may do this; the other parent is notified.
  Future<void> deleteGroup(RequestGroup group) async {
    for (final leg in group.legs) {
      await pb.collection('custody_requests').delete(leg.id);
    }
    _changed();
  }

  /// Finds the full group (both swap legs) for a request id.
  RequestGroup? groupFor(String requestId, {List<CustodyRequest> extra = const []}) {
    final all = [...?state.valueOrNull, ...extra];
    final r = all.where((x) => x.id == requestId).firstOrNull;
    if (r == null) return null;
    if (r.swapGroup == null) return RequestGroup([r]);
    final seen = <String>{};
    final legs = all
        .where((x) => x.swapGroup == r.swapGroup && seen.add(x.id))
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    return RequestGroup(legs);
  }

  // ── Respond ─────────────────────────────────────────────────────────────────

  /// Accept or decline (every leg of a swap together). An optional [note]
  /// (e.g. a decline reason) is appended so the requester sees the context.
  Future<void> respond(RequestGroup group,
      {required bool accept, String? note}) async {
    final status = accept ? 'accepted' : 'declined';
    final reason = note?.trim() ?? '';
    for (var i = 0; i < group.legs.length; i++) {
      final leg  = group.legs[i];
      final body = <String, dynamic>{'status': status};
      if (reason.isNotEmpty) {
        body['note'] = [
          if (leg.note != null && leg.note!.isNotEmpty) leg.note,
          '${accept ? 'Accepted' : 'Declined'}: $reason',
        ].join('\n');
      }
      try {
        await pb.collection('custody_requests').update(leg.id, body: body);
      } catch (e) {
        if (!isNetworkError(e)) rethrow;
        for (final rest in group.legs.sublist(i)) {
          await QueueService.enqueue(PendingOp(
            id:         QueueService.newOpId(),
            collection: 'custody_requests',
            method:     'update',
            body:       body,
            recordId:   rest.id,
          ));
        }
        await _updateQueueCount();
        break;
      }
    }
    _changed();
  }

  // ── Internals ───────────────────────────────────────────────────────────────

  _Party _party() {
    final household = ref.read(householdProvider).valueOrNull;
    if (household == null) {
      throw Exception('No active household yet — please try again in a moment.');
    }
    final co = ref.read(coParentProvider);
    return _Party(
      householdId: household.id,
      myId:        ref.read(authProvider).valueOrNull?.userId ?? '',
      myName:      ref.read(myDisplayNameProvider),
      coParent:    co == null ? null : (userId: co.userId, name: co.displayName),
    );
  }

  Map<String, dynamic> _base(_Party p, String requestedFrom, String? note) => {
        'id':             newRecordId(),
        'status':         'pending',
        'note':           note ?? '',
        'created_by':     p.myId,
        'requested_from': requestedFrom,
        'household':      p.householdId,
      };

  /// Creates records in order. Offline, the rest are queued (their ids make
  /// replays safe). If the server rejects a later record, earlier ones are
  /// rolled back so a swap never exists with only one leg.
  Future<void> _createAll(List<Map<String, dynamic>> bodies) async {
    final created = <String>[];
    for (var i = 0; i < bodies.length; i++) {
      try {
        await pb.collection('custody_requests').create(body: bodies[i]);
        created.add(bodies[i]['id'] as String);
      } catch (e) {
        if (isNetworkError(e)) {
          for (final body in bodies.sublist(i)) {
            await QueueService.enqueue(PendingOp(
              id:         QueueService.newOpId(),
              collection: 'custody_requests',
              method:     'create',
              body:       body,
            ));
          }
          await _updateQueueCount();
          break;
        }
        for (final id in created) {
          try {
            await pb.collection('custody_requests').delete(id);
          } catch (_) {}
        }
        rethrow;
      }
    }
    _changed();
  }

  Future<void> _updateAll(List<String> ids, Map<String, dynamic> body) async {
    for (var i = 0; i < ids.length; i++) {
      try {
        await pb.collection('custody_requests').update(ids[i], body: body);
      } catch (e) {
        if (!isNetworkError(e)) rethrow;
        for (final id in ids.sublist(i)) {
          await QueueService.enqueue(PendingOp(
            id:         QueueService.newOpId(),
            collection: 'custody_requests',
            method:     'update',
            body:       body,
            recordId:   id,
          ));
        }
        await _updateQueueCount();
        break;
      }
    }
    _changed();
  }

  void _changed() {
    ref.invalidateSelf();
    ref.invalidate(acceptedCustodyProvider);
    WidgetCacheService.updateSoon();
  }

  Future<void> _updateQueueCount() async {
    ref.read(pendingOpsCountProvider.notifier).state =
        await QueueService.pendingCount();
  }
}

class _Party {
  final String householdId;
  final String myId;
  final String myName;
  final ({String userId, String name})? coParent;

  const _Party({
    required this.householdId,
    required this.myId,
    required this.myName,
    required this.coParent,
  });

  ({String userId, String name}) requireCoParent() {
    final co = coParent;
    if (co == null) {
      throw Exception(
          'Invite your co-parent to the household first — requests go to them.');
    }
    return co;
  }
}
