import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocketbase/pocketbase.dart';

import '../core/pb_client.dart';
import '../models/absence_period.dart';
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

  Future<List<AbsencePeriod>> _fetch() async {
    try {
      final records = await pb
          .collection('absence_periods')
          .getFullList(sort: 'start_date');
      return records
          .map((r) => AbsencePeriod.fromRecord(r.toJson()))
          .toList();
    } on ClientException catch (e) {
      if (e.statusCode == 404) return [];
      rethrow;
    }
  }

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
      'start_date':    _fmt(startDate),
      'end_date':      _fmt(endDate),
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

String _fmt(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
