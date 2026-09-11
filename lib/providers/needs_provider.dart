import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/pb_client.dart';
import '../models/need.dart';
import '../services/offline_cache.dart';
import '../services/queue_service.dart';
import '../utils/dates.dart';
import '../utils/ids.dart';
import 'auth_provider.dart';
import 'household_provider.dart';
import 'queue_count_provider.dart';

/// The household's shared "to buy" list, newest first.
final needsProvider =
    AsyncNotifierProvider<NeedsNotifier, List<Need>>(NeedsNotifier.new);

/// Items not yet bought — shown on the Today card.
final openNeedsCountProvider = Provider<int>((ref) =>
    (ref.watch(needsProvider).valueOrNull ?? const [])
        .where((n) => !n.isBought)
        .length);

class NeedsNotifier extends AsyncNotifier<List<Need>> {
  @override
  Future<List<Need>> build() {
    ref.watch(authProvider);
    return fetchCachedList(
      collection: 'needs',
      fetch: () => pb.collection('needs').getFullList(sort: '-created'),
      parse: Need.fromRecord,
    );
  }

  String get _myId => ref.read(authProvider).valueOrNull?.userId ?? '';

  Future<void> add({
    required String title,
    String childName = 'All',
    String? note,
    DateTime? neededBy,
  }) async {
    final hid = ref.read(householdProvider).valueOrNull?.id;
    if (hid == null) {
      throw Exception('No active household yet — please try again in a moment.');
    }
    final body = {
      'id':         newRecordId(),
      'household':  hid,
      'title':      title,
      'child_name': childName,
      'note':       note ?? '',
      'needed_by':  neededBy != null ? isoDate(neededBy) : '',
      'status':     'open',
      'created_by': _myId,
    };
    try {
      await pb.collection('needs').create(body: body);
    } catch (e) {
      if (!isNetworkError(e)) rethrow;
      await QueueService.enqueue(PendingOp(
        id: QueueService.newOpId(), collection: 'needs', method: 'create', body: body,
      ));
      await _updateQueueCount();
    }
    ref.invalidateSelf();
  }

  Future<void> edit(
    Need need, {
    required String title,
    required String childName,
    String? note,
    DateTime? neededBy,
  }) =>
      _update(need, {
        'title':      title,
        'child_name': childName,
        'note':       note ?? '',
        'needed_by':  neededBy != null ? isoDate(neededBy) : '',
      });

  /// "I'll get it" — tells the other parent not to buy it too.
  Future<void> claim(Need need) =>
      _update(need, {'status': 'claimed', 'claimed_by': _myId});

  Future<void> release(Need need) =>
      _update(need, {'status': 'open', 'claimed_by': ''});

  Future<void> markBought(Need need) => _update(need, {
        'status':    'bought',
        'bought_by': _myId,
        'bought_at': isoDate(DateTime.now()),
      });

  Future<void> linkExpense(Need need, String expenseId) =>
      _update(need, {'expense': expenseId});

  /// Puts a bought item back on the list.
  Future<void> reopen(Need need) => _update(need, {
        'status':     'open',
        'claimed_by': '',
        'bought_by':  '',
        'bought_at':  '',
        'expense':    '',
      });

  Future<void> delete(Need need) async {
    await pb.collection('needs').delete(need.id);
    ref.invalidateSelf();
  }

  Future<void> _update(Need need, Map<String, dynamic> body) async {
    try {
      await pb.collection('needs').update(need.id, body: body);
    } catch (e) {
      if (!isNetworkError(e)) rethrow;
      await QueueService.enqueue(PendingOp(
        id: QueueService.newOpId(), collection: 'needs', method: 'update',
        body: body, recordId: need.id,
      ));
      await _updateQueueCount();
    }
    ref.invalidateSelf();
  }

  Future<void> _updateQueueCount() async {
    ref.read(pendingOpsCountProvider.notifier).state =
        await QueueService.pendingCount();
  }
}
