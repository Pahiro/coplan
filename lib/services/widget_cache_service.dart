import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:home_widget/home_widget.dart';

import '../core/constants.dart';
import '../core/pb_client.dart';
import '../engine/resolution_engine.dart';
import '../models/base_rule.dart';
import '../models/custody_request.dart';
import '../models/manual_override.dart';
import '../models/recurring_arrangement.dart';
import '../models/resolved_event.dart';
import '../models/weekday_rule.dart';

/// Fetches the next upcoming events from PocketBase and writes them to
/// SharedPreferences so the Android Glance widget can read them offline.
///
/// Call this on app resume and after any schedule mutation.
class WidgetCacheService {
  WidgetCacheService._();

  static Future<void> updateCache() async {
    if (kIsWeb) return; // Widget is Android-only
    try {
      final rules        = await _fetchBaseRules();
      final weekdayRules = await _fetchWeekdayRules();
      final recurring    = await _fetchRecurring();
      final upcoming     = await _nextUpcomingEvents(rules, weekdayRules, recurring);

      final json = jsonEncode(upcoming.map((e) => e.toJson()).toList());
      await HomeWidget.saveWidgetData<String>(AppConstants.widgetCacheKey, json);
      await HomeWidget.updateWidget(
        androidName: AppConstants.widgetName,
        qualifiedAndroidName:
            '${AppConstants.widgetAppId}.${AppConstants.widgetName}',
      );
    } catch (_) {
      // Fail silently — widget will show stale data until next successful sync
    }
  }

  static Future<List<ResolvedEvent>> _nextUpcomingEvents(
    List<BaseRule> rules,
    List<WeekdayRule> weekdayRules,
    List<RecurringArrangement> recurring,
  ) async {
    final now       = DateTime.now();
    final nowMinutes = now.hour * 60 + now.minute;
    final events    = <ResolvedEvent>[];

    for (int i = 0; i < 3; i++) {
      final date     = now.add(Duration(days: i));
      final overrides = await _fetchOverridesForDate(date);
      final custody   = await _fetchCustodyForDate(date);
      final dayEvents = ResolutionEngine(
        baseRules:             rules,
        overrides:             overrides,
        custodyRequests:       custody,
        weekdayRules:          weekdayRules,
        recurringArrangements: recurring,
      ).resolveDay(date);
      events.addAll(dayEvents);
    }

    final upcoming = events.where((e) {
      final eMin    = e.time.hour * 60 + e.time.minute;
      final isToday = e.date.year  == now.year &&
                      e.date.month == now.month &&
                      e.date.day   == now.day;
      return !isToday || eMin >= nowMinutes;
    });

    return upcoming.take(3).toList();
  }

  static Future<List<BaseRule>> _fetchBaseRules() async {
    final records = await pb.collection('rules_base').getFullList();
    return records.map((r) => BaseRule.fromRecord(r.toJson())).toList();
  }

  static Future<List<WeekdayRule>> _fetchWeekdayRules() async {
    try {
      final records = await pb
          .collection('custody_weekday_rules')
          .getFullList(filter: 'active = true');
      return records.map((r) => WeekdayRule.fromRecord(r.toJson())).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<List<RecurringArrangement>> _fetchRecurring() async {
    try {
      final records = await pb
          .collection('custody_recurring')
          .getFullList(filter: 'active = true');
      return records
          .map((r) => RecurringArrangement.fromRecord(r.toJson()))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<List<ManualOverride>> _fetchOverridesForDate(
      DateTime date) async {
    final dateStr =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final records = await pb
        .collection('manual_overrides')
        .getFullList(filter: 'target_date = "$dateStr"');
    return records.map((r) => ManualOverride.fromRecord(r.toJson())).toList();
  }

  static Future<List<CustodyRequest>> _fetchCustodyForDate(
      DateTime date) async {
    final dateStr =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    try {
      final records = await pb.collection('custody_requests').getFullList(
          filter: 'date = "$dateStr" && status = "accepted"');
      return records
          .map((r) => CustodyRequest.fromRecord(r.toJson()))
          .toList();
    } catch (_) {
      return [];
    }
  }
}
