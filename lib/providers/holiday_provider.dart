import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocketbase/pocketbase.dart';

import '../core/pb_client.dart';
import '../utils/dates.dart';
import '../models/holiday_block.dart';
import '../services/widget_cache_service.dart';
import 'household_provider.dart';
import 'schedule_provider.dart';

final holidayBlocksProvider =
    AsyncNotifierProvider<HolidayBlocksNotifier, List<HolidayBlock>>(
  HolidayBlocksNotifier.new,
);

class HolidayBlocksNotifier extends AsyncNotifier<List<HolidayBlock>> {
  @override
  Future<List<HolidayBlock>> build() => _fetch();

  Future<List<HolidayBlock>> _fetch() async {
    try {
      final records = await pb
          .collection('holiday_blocks')
          .getFullList(sort: 'start_date');
      return records
          .map((r) => HolidayBlock.fromRecord(r.toJson()))
          .toList();
    } on ClientException catch (e) {
      if (e.statusCode == 404) return [];
      rethrow;
    }
  }

  Future<void> create({
    required String name,
    required String assignedParent,
    required DateTime startDate,
    required DateTime endDate,
    String? notes,
  }) async {
    final hid = ref.read(householdProvider).valueOrNull?.id;
    if (hid == null) throw Exception('No active household');

    await pb.collection('holiday_blocks').create(body: {
      'household':       hid,
      'name':            name,
      'assigned_parent': assignedParent,
      'start_date':      isoDate(startDate),
      'end_date':        isoDate(endDate),
      'notes':           notes ?? '',
      'created_by':      pb.authStore.record?.id ?? '',
    });

    _invalidate();
  }

  Future<void> delete(String id) async {
    await pb.collection('holiday_blocks').delete(id);
    _invalidate();
  }

  void _invalidate() {
    ref.invalidateSelf();
    ref.invalidate(dashboardProvider);
    ref.invalidate(weekEventsProvider);
    ref.invalidate(resolvedDayProvider);
    WidgetCacheService.updateCache();
  }
}

