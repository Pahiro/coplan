import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/pb_client.dart';
import '../utils/dates.dart';
import '../models/absence_period.dart';
import '../services/offline_cache.dart';
import '../services/widget_cache_service.dart';
import 'household_provider.dart';
import 'schedule_provider.dart';

final absencePeriodsProvider =
    AsyncNotifierProvider<AbsencePeriodsNotifier, List<AbsencePeriod>>(
  AbsencePeriodsNotifier.new,
);

class AbsencePeriodsNotifier extends AsyncNotifier<List<AbsencePeriod>> {
  @override
  Future<List<AbsencePeriod>> build() => _fetch();

  Future<List<AbsencePeriod>> _fetch() => fetchCachedList(
        collection: 'absence_periods',
        fetch: () =>
            pb.collection('absence_periods').getFullList(sort: 'start_date'),
        parse: AbsencePeriod.fromRecord,
      );

  Future<void> create({
    required String absentParent,
    required DateTime startDate,
    required DateTime endDate,
    required String reason,
    String? note,
  }) async {
    final hid = ref.read(householdProvider).valueOrNull?.id;
    if (hid == null) throw Exception('No active household');

    await pb.collection('absence_periods').create(body: {
      'household':     hid,
      'absent_parent': absentParent,
      'start_date':    isoDate(startDate),
      'end_date':      isoDate(endDate),
      'reason':        reason,
      'note':          note ?? '',
      'created_by':    pb.authStore.record?.id ?? '',
    });

    _invalidate();
  }

  Future<void> delete(String id) async {
    await pb.collection('absence_periods').delete(id);
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

