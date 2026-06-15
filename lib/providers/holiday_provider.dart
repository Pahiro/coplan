import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/pb_client.dart';
import '../utils/dates.dart';
import '../models/holiday_block.dart';
import '../services/offline_cache.dart';
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

  Future<List<HolidayBlock>> _fetch() => fetchCachedList(
        collection: 'holiday_blocks',
        fetch: () =>
            pb.collection('holiday_blocks').getFullList(sort: 'start_date'),
        parse: HolidayBlock.fromRecord,
      );

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

