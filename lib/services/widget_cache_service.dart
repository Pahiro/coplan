import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:home_widget/home_widget.dart';

import '../core/constants.dart';
import '../core/pb_client.dart';
import '../engine/resolution_engine.dart';
import '../models/base_rule.dart';
import '../models/custody_request.dart';
import '../models/holiday_block.dart';
import '../models/manual_override.dart';
import '../models/recurring_arrangement.dart';
import '../models/resolved_event.dart';
import '../models/rotation_scheme.dart';
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
      final holidays     = await _fetchHolidayBlocks();
      final upcoming     = await _nextUpcomingEvents(rules, weekdayRules, recurring, holidays);

      // Only overwrite the cache when we actually have events — an empty result
      // from a transient auth blip or network hiccup should never wipe good data.
      if (upcoming.isEmpty) return;
      final json = jsonEncode(upcoming.map((e) => e.toJson()).toList());
      await HomeWidget.saveWidgetData<String>(AppConstants.widgetCacheKey, json);
      // Redraw every placed widget style. Each style is a separate Glance
      // receiver, so we must broadcast an update to all three — updating only
      // 'CoplanWidget' left Material/Timeline widgets showing stale data.
      for (final receiver in AppConstants.widgetReceivers) {
        await HomeWidget.updateWidget(
          androidName: receiver,
          qualifiedAndroidName: '${AppConstants.widgetAppId}.$receiver',
        );
      }
    } catch (_) {
      // Fail silently — widget will show stale data until next successful sync
    }
  }

  static Future<List<ResolvedEvent>> _nextUpcomingEvents(
    List<BaseRule> rules,
    List<WeekdayRule> weekdayRules,
    List<RecurringArrangement> recurring,
    List<HolidayBlock> holidays,
  ) async {
    final now       = DateTime.now();
    final nowMinutes = now.hour * 60 + now.minute;
    final events    = <ResolvedEvent>[];

    // Fetch rotation config from household or fall back to app_settings
    final rotation = await _fetchRotationConfig();

    for (int i = 0; i < 3; i++) {
      final date     = now.add(Duration(days: i));
      final overrides    = await _fetchOverridesForDate(date);
      final custody      = await _fetchCustodyForDate(date);
      final dayHolidays  = holidays.where((b) => b.coversDate(date)).toList();
      final dayEvents = ResolutionEngine(
        baseRules:             rules,
        overrides:             overrides,
        custodyRequests:       custody,
        weekdayRules:          weekdayRules,
        recurringArrangements: recurring,
        holidayBlocks:         dayHolidays,
        rotationAnchor:        rotation.$1,
        rotationParentEven:    rotation.$2,
        rotationParentOdd:     rotation.$3,
        rotationScheme:        rotation.$4,
        householdMode:         rotation.$5,
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

  static Future<List<HolidayBlock>> _fetchHolidayBlocks() async {
    try {
      final records = await pb.collection('holiday_blocks').getFullList();
      return records.map((r) => HolidayBlock.fromRecord(r.toJson())).toList();
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

  /// Fetches rotation anchor + parent names + scheme from the active household.
  /// Falls back to app_settings for legacy single-household setups.
  static Future<(DateTime, String, String, RotationScheme?, String)> _fetchRotationConfig() async {
    try {
      final userId = pb.authStore.record?.id ?? '';
      final user = await pb.collection('users').getOne(userId);
      final householdId = user.data['active_household'] as String?;
      if (householdId != null && householdId.isNotEmpty) {
        final h = await pb.collection('households').getOne(householdId);
        final anchorStr = h.data['rotation_anchor'] as String? ?? '';
        final parts = anchorStr.split('-');
        final anchor = parts.length == 3
            ? DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]))
            : DateTime(2025, 1, 6);

        // Resolve parent display names from household_members
        final members = await pb.collection('household_members')
            .getFullList(filter: 'household = "$householdId" && role = "parent"');
        final evenId = h.data['rotation_parent_even'] as String? ?? '';
        final oddId  = h.data['rotation_parent_odd'] as String? ?? '';
        String evenName = 'Parent A';
        String oddName  = 'Parent B';
        for (final m in members) {
          if (m.data['user'] == evenId) evenName = m.data['display_name'] as String? ?? evenName;
          if (m.data['user'] == oddId)  oddName  = m.data['display_name'] as String? ?? oddName;
        }

        // Rotation scheme
        final schemeType = h.data['rotation_scheme_type'] as String? ?? 'weekly';
        List<int>? pattern;
        final rawPattern = h.data['rotation_pattern'];
        if (rawPattern is List) pattern = rawPattern.cast<int>();
        final scheme = RotationScheme.fromJson(schemeType, pattern);

        final mode = h.data['mode'] as String? ?? 'custody';
        return (anchor, evenName, oddName, scheme, mode);
      }
    } catch (_) {}

    // Legacy fallback: read from app_settings
    try {
      final settings = await pb.collection('app_settings').getFullList();
      DateTime anchor = DateTime(2025, 1, 6);
      for (final s in settings) {
        if (s.data['key'] == 'rotation_anchor') {
          final parts = (s.data['value'] as String).split('-');
          if (parts.length == 3) {
            anchor = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
          }
        }
      }
      return (anchor, AppConstants.parentBennet, AppConstants.parentJana, null, 'custody');
    } catch (_) {
      return (DateTime(2025, 1, 6), AppConstants.parentBennet, AppConstants.parentJana, null, 'custody');
    }
  }
}
