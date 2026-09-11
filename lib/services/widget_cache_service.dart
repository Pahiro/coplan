import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:home_widget/home_widget.dart';

import '../core/constants.dart';
import '../core/pb_client.dart';
import '../engine/engine_factory.dart';
import '../models/absence_period.dart';
import '../models/app_colors.dart';
import '../models/base_rule.dart';
import '../models/custody_request.dart';
import '../models/holiday_block.dart';
import '../models/household.dart';
import '../models/manual_override.dart';
import '../utils/dates.dart';

/// Resolves the next few events with the real engine and writes them to
/// SharedPreferences for the Android Glance widgets. The Kotlin
/// `CoplanSyncWorker` writes the same data in the background; this is the
/// reliable path because Doze often defers the worker.
class WidgetCacheService {
  WidgetCacheService._();

  static Timer? _debounce;

  /// Coalesces bursts of changes (e.g. several realtime events) into one refresh.
  static void updateSoon() {
    if (kIsWeb) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), updateCache);
  }

  static Future<void> updateCache() async {
    if (kIsWeb) return;
    try {
      final household = await _fetchHousehold();
      if (household == null) return;

      final today = dateOnly(DateTime.now());
      final from  = isoDate(today);
      final to    = isoDate(addDays(today, 2));
      final mine  = 'household = "${household.id}"';

      Future<List<T>> list<T>(String collection, String filter,
          T Function(Map<String, dynamic>) parse) async {
        final records = await pb.collection(collection).getFullList(filter: filter);
        return records.map((r) => parse(r.toJson())).toList();
      }

      final engine = buildEngine(
        household: household,
        baseRules: await list('rules_base', mine, BaseRule.fromRecord),
        overrides: await list('manual_overrides',
            '$mine && target_date >= "$from" && target_date <= "$to"',
            ManualOverride.fromRecord),
        custodyRequests: await list('custody_requests',
            '$mine && status = "accepted" && date >= "$from" && date <= "$to"',
            CustodyRequest.fromRecord),
        absencePeriods: await list('absence_periods',
            '$mine && start_date <= "$to" && end_date >= "$from"',
            AbsencePeriod.fromRecord),
        holidayBlocks: await list('holiday_blocks',
            '$mine && start_date <= "$to" && end_date >= "$from"',
            HolidayBlock.fromRecord),
      );

      final colors = AppColors.forHousehold(household);
      final now    = DateTime.now();
      final nowMin = now.hour * 60 + now.minute;

      final upcoming = <Map<String, dynamic>>[];
      for (var i = 0; i < 3 && upcoming.length < 3; i++) {
        for (final e in engine.resolveDay(addDays(today, i))) {
          if (i == 0 && e.time.hour * 60 + e.time.minute < nowMin) continue;
          upcoming.add(e.toJson(
              parentColor: colors.parentColor(e.assignedParent).toARGB32()));
          if (upcoming.length == 3) break;
        }
      }

      await HomeWidget.saveWidgetData<String>(
          AppConstants.widgetCacheKey, jsonEncode(upcoming));
      // Each widget style is a separate Glance receiver — redraw all three.
      for (final receiver in AppConstants.widgetReceivers) {
        await HomeWidget.updateWidget(
          androidName: receiver,
          qualifiedAndroidName: '${AppConstants.widgetAppId}.$receiver',
        );
      }
    } catch (_) {
      // Keep the last good data; the next refresh or the worker will retry.
    }
  }

  static Future<HouseholdConfig?> _fetchHousehold() async {
    final userId = pb.authStore.record?.id;
    if (userId == null) return null;
    final user = await pb.collection('users').getOne(userId);
    final hid = user.data['active_household'] as String?;
    if (hid == null || hid.isEmpty) return null;

    final h        = await pb.collection('households').getOne(hid);
    final members  = await pb.collection('household_members').getFullList(filter: 'household = "$hid"');
    final children = await pb.collection('children').getFullList(filter: 'household = "$hid"');
    return HouseholdConfig.fromRecord(
      h.toJson(),
      members: members.map((r) => HouseholdMember.fromRecord(r.toJson())).toList(),
      children: children.map((r) => HouseholdChild.fromRecord(r.toJson())).toList(),
    );
  }
}
