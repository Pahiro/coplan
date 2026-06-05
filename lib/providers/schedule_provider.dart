import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocketbase/pocketbase.dart';

import '../core/pb_client.dart';
import '../engine/resolution_engine.dart';
import '../models/absence_period.dart';
import '../models/base_rule.dart';
import '../models/custody_request.dart';
import '../models/manual_override.dart';
import '../models/recurring_arrangement.dart';
import '../models/resolved_event.dart';
import '../models/weekday_rule.dart';
import 'absence_provider.dart';
import 'household_provider.dart';

// ── Static data — fetched once, rarely changes ───────────────────────────────

final baseRulesProvider = FutureProvider<List<BaseRule>>((ref) async {
  final records = await pb.collection('rules_base').getFullList();
  return records.map((r) => BaseRule.fromRecord(r.toJson())).toList();
});

final weekdayRulesProvider = FutureProvider<List<WeekdayRule>>((ref) async {
  try {
    final records = await pb
        .collection('custody_weekday_rules')
        .getFullList(filter: 'active = true');
    return records.map((r) => WeekdayRule.fromRecord(r.toJson())).toList();
  } on ClientException catch (e) {
    // Collection doesn't exist yet (migration pending) — treat as no rules.
    if (e.statusCode == 404) return [];
    rethrow;
  }
});

final recurringArrangementsProvider =
    FutureProvider<List<RecurringArrangement>>((ref) async {
  try {
    final records = await pb
        .collection('custody_recurring')
        .getFullList(filter: 'active = true');
    return records
        .map((r) => RecurringArrangement.fromRecord(r.toJson()))
        .toList();
  } on ClientException catch (e) {
    // Collection doesn't exist yet (migration pending) — treat as none.
    if (e.statusCode == 404) return [];
    rethrow;
  }
});

// ── Resolved schedule for a single day ──────────────────────────────────────

final resolvedDayProvider =
    FutureProvider.family<List<ResolvedEvent>, DateTime>((ref, rawDate) async {
  final date    = DateTime(rawDate.year, rawDate.month, rawDate.day);
  final dateStr = _fmt(date);

  final rules        = await ref.watch(baseRulesProvider.future);
  final weekdayRules = await ref.watch(weekdayRulesProvider.future);
  final recurring    = await ref.watch(recurringArrangementsProvider.future);

  final overrideRecords = await pb
      .collection('manual_overrides')
      .getFullList(filter: 'target_date = "$dateStr"');
  final overrides =
      overrideRecords.map((r) => ManualOverride.fromRecord(r.toJson())).toList();

  final custodyRecords = await pb
      .collection('custody_requests')
      .getFullList(filter: 'date = "$dateStr" && status = "accepted"');
  final custodyRequests =
      custodyRecords.map((r) => CustodyRequest.fromRecord(r.toJson())).toList();

  final allAbsences = await ref.watch(absencePeriodsProvider.future);
  final absences    = allAbsences.where((a) => a.coversDate(date)).toList();

  final household = ref.watch(householdProvider).valueOrNull;
  final anchor    = household?.rotationAnchorDate ?? DateTime(2025, 1, 6);
  final evenName  = household?.rotationParentEvenName ?? 'Bennet';
  final oddName   = household?.rotationParentOddName  ?? 'Jana';

  return ResolutionEngine(
    baseRules:             rules,
    overrides:             overrides,
    custodyRequests:       custodyRequests,
    weekdayRules:          weekdayRules,
    recurringArrangements: recurring,
    absencePeriods:        absences,
    rotationAnchor:        anchor,
    rotationParentEven:    evenName,
    rotationParentOdd:     oddName,
    rotationScheme:        household?.rotationScheme,
    householdMode:         household?.mode ?? 'custody',
  ).resolveDay(date);
});

// ── Dashboard: today + tomorrow combined ─────────────────────────────────────

final dashboardProvider = FutureProvider<List<ResolvedEvent>>((ref) async {
  final today    = DateTime.now();
  final tomorrow = today.add(const Duration(days: 1));

  final results = await Future.wait([
    ref.watch(resolvedDayProvider(today).future),
    ref.watch(resolvedDayProvider(tomorrow).future),
  ]);
  return [...results[0], ...results[1]];
});

// ── Full week of events (for calendar screen) ────────────────────────────────

final weekEventsProvider =
    FutureProvider.family<Map<String, List<ResolvedEvent>>, DateTime>(
        (ref, rawMonday) async {
  final monday       = DateTime(rawMonday.year, rawMonday.month, rawMonday.day);
  final rules        = await ref.watch(baseRulesProvider.future);
  final weekdayRules = await ref.watch(weekdayRulesProvider.future);
  final recurring    = await ref.watch(recurringArrangementsProvider.future);

  final weekEnd = monday.add(const Duration(days: 6));

  final overrideRecords = await pb.collection('manual_overrides').getFullList(
      filter:
          'target_date >= "${_fmt(monday)}" && target_date <= "${_fmt(weekEnd)}"');
  final allOverrides =
      overrideRecords.map((r) => ManualOverride.fromRecord(r.toJson())).toList();

  final custodyRecords = await pb.collection('custody_requests').getFullList(
      filter:
          'date >= "${_fmt(monday)}" && date <= "${_fmt(weekEnd)}" && status = "accepted"');
  final allCustody =
      custodyRecords.map((r) => CustodyRequest.fromRecord(r.toJson())).toList();

  final allAbsences = await ref.watch(absencePeriodsProvider.future);

  final result = <String, List<ResolvedEvent>>{};
  for (int i = 0; i < 7; i++) {
    final date         = monday.add(Duration(days: i));
    final dayOverrides = allOverrides
        .where((o) =>
            o.targetDate.year  == date.year &&
            o.targetDate.month == date.month &&
            o.targetDate.day   == date.day)
        .toList();
    final dayCustody = allCustody
        .where((r) =>
            r.date.year  == date.year &&
            r.date.month == date.month &&
            r.date.day   == date.day)
        .toList();
    final dayAbsences = allAbsences.where((a) => a.coversDate(date)).toList();
    final household = ref.watch(householdProvider).valueOrNull;
    final anchor    = household?.rotationAnchorDate ?? DateTime(2025, 1, 6);
    final evenName  = household?.rotationParentEvenName ?? 'Bennet';
    final oddName   = household?.rotationParentOddName  ?? 'Jana';

    result[_fmt(date)] = ResolutionEngine(
      baseRules:             rules,
      overrides:             dayOverrides,
      custodyRequests:       dayCustody,
      weekdayRules:          weekdayRules,
      recurringArrangements: recurring,
      absencePeriods:        dayAbsences,
      rotationAnchor:        anchor,
      rotationParentEven:    evenName,
      rotationParentOdd:     oddName,
      rotationScheme:        household?.rotationScheme,
      householdMode:         household?.mode ?? 'custody',
    ).resolveDay(date);
  }
  return result;
});

// ── Base rules mutations ──────────────────────────────────────────────────────

class BaseRulesNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> create({
    required String childName,
    required int dayOfWeek,
    required String eventTime,
    required String activity,
    required String location,
    required bool isShared,
    bool isLogistics = false,
    String? handoverFrom,
  }) async {
    final hid = ref.read(householdProvider).valueOrNull?.id;
    await pb.collection('rules_base').create(body: {
      'child_name':    childName,
      'day_of_week':   dayOfWeek,
      'event_time':    eventTime,
      'activity':      activity,
      'location':      location,
      'is_shared':     isShared,
      'is_logistics':  isLogistics,
      'handover_from': handoverFrom ?? '',
      if (hid != null) 'household': hid,
    });
    _invalidate();
  }

  Future<void> updateRule(
    String id, {
    required String childName,
    required int dayOfWeek,
    required String eventTime,
    required String activity,
    required String location,
    required bool isShared,
    bool isLogistics = false,
    String? handoverFrom,
  }) async {
    await pb.collection('rules_base').update(id, body: {
      'child_name':    childName,
      'day_of_week':   dayOfWeek,
      'event_time':    eventTime,
      'activity':      activity,
      'location':      location,
      'is_shared':     isShared,
      'is_logistics':  isLogistics,
      'handover_from': handoverFrom ?? '',
    });
    _invalidate();
  }

  Future<void> delete(String id) async {
    await pb.collection('rules_base').delete(id);
    _invalidate();
  }

  void _invalidate() {
    ref.invalidate(baseRulesProvider);
    ref.invalidate(dashboardProvider);
    ref.invalidate(weekEventsProvider);
    ref.invalidate(resolvedDayProvider);
  }
}

final baseRulesNotifierProvider =
    AsyncNotifierProvider<BaseRulesNotifier, void>(BaseRulesNotifier.new);

// ── Manual override mutations ─────────────────────────────────────────────────

class ManualOverridesNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> updateOverride(
    String id, {
    required String childName,
    required String targetDate,
    required String? overrideTime,
    required String activity,
    required String location,
    required bool isShared,
    String? endTime,
    String? note,
  }) async {
    await pb.collection('manual_overrides').update(id, body: {
      'child_name':    childName,
      'target_date':   targetDate,
      'override_time': overrideTime ?? '',
      'activity':      activity,
      'location':      location,
      'is_shared':     isShared,
      'end_time':      endTime ?? '',
      'note':          note ?? '',
    });
    _invalidate();
  }

  Future<void> delete(String id) async {
    await pb.collection('manual_overrides').delete(id);
    _invalidate();
  }

  void _invalidate() {
    ref.invalidate(dashboardProvider);
    ref.invalidate(weekEventsProvider);
    ref.invalidate(resolvedDayProvider);
  }
}

final manualOverridesNotifierProvider =
    AsyncNotifierProvider<ManualOverridesNotifier, void>(ManualOverridesNotifier.new);

// ── Weekday rules mutations ───────────────────────────────────────────────────

class WeekdayRulesNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// Creates a standing weekday rule, replacing any existing rule for that day.
  Future<void> create({
    required int dayOfWeek,
    required String assignedParent,
    required String reason,
  }) async {
    try {
      final existing = await pb
          .collection('custody_weekday_rules')
          .getFullList(filter: 'day_of_week = $dayOfWeek');
      for (final r in existing) {
        await pb.collection('custody_weekday_rules').delete(r.id);
      }
    } catch (_) {}

    final hid = ref.read(householdProvider).valueOrNull?.id;
    await pb.collection('custody_weekday_rules').create(body: {
      'day_of_week':     dayOfWeek,
      'assigned_parent': assignedParent,
      'reason':          reason,
      'active':          true,
      if (hid != null) 'household': hid,
    });

    ref.invalidate(weekdayRulesProvider);
    ref.invalidate(dashboardProvider);
    ref.invalidate(weekEventsProvider);
    ref.invalidate(resolvedDayProvider);
  }

  Future<void> delete(String id) async {
    await pb.collection('custody_weekday_rules').delete(id);
    ref.invalidate(weekdayRulesProvider);
    ref.invalidate(dashboardProvider);
    ref.invalidate(weekEventsProvider);
    ref.invalidate(resolvedDayProvider);
  }
}

final weekdayRulesNotifierProvider =
    AsyncNotifierProvider<WeekdayRulesNotifier, void>(WeekdayRulesNotifier.new);

// ── Recurring arrangement mutations ───────────────────────────────────────────

class RecurringArrangementsNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// Creates a standing recurring arrangement, replacing any existing one for
  /// the same weekday + recipient so there's a single rule per pattern.
  Future<void> upsert({
    required int dayOfWeek,
    required String toParent,
    required String childName,
    required String pickupTime,
    String? returnTime,
    bool returnTimeTbd = false,
    bool toParentCollects = true,
    bool toParentReturns = false,
    required String startDate,
    String? note,
  }) async {
    try {
      final existing = await pb
          .collection('custody_recurring')
          .getFullList(filter: 'day_of_week = $dayOfWeek && to_parent = "$toParent"');
      for (final r in existing) {
        await pb.collection('custody_recurring').delete(r.id);
      }
    } catch (_) {}

    final hid = ref.read(householdProvider).valueOrNull?.id;
    await pb.collection('custody_recurring').create(body: {
      'day_of_week':        dayOfWeek,
      'to_parent':          toParent,
      'child_name':         childName,
      'pickup_time':        pickupTime,
      'return_time':        returnTime ?? '',
      'return_time_tbd':    returnTimeTbd,
      'to_parent_collects': toParentCollects,
      'to_parent_returns':  toParentReturns,
      'start_date':         startDate,
      'note':               note ?? '',
      'active':             true,
      'created_by':         pb.authStore.record?.id ?? '',
      if (hid != null) 'household': hid,
    });
    _invalidate();
  }

  Future<void> delete(String id) async {
    await pb.collection('custody_recurring').delete(id);
    _invalidate();
  }

  /// Removes arrangements for a given weekday, optionally scoped to a specific
  /// recipient [toParent]. Without [toParent] all arrangements on that weekday
  /// are deleted (current two-parent behaviour).
  Future<void> deleteForDay(int dayOfWeek, {String? toParent}) async {
    try {
      var filter = 'day_of_week = $dayOfWeek';
      if (toParent != null) filter += ' && to_parent = "$toParent"';
      final existing = await pb
          .collection('custody_recurring')
          .getFullList(filter: filter);
      for (final r in existing) {
        await pb.collection('custody_recurring').delete(r.id);
      }
    } catch (_) {}
    _invalidate();
  }

  void _invalidate() {
    ref.invalidate(recurringArrangementsProvider);
    ref.invalidate(dashboardProvider);
    ref.invalidate(weekEventsProvider);
    ref.invalidate(resolvedDayProvider);
  }
}

final recurringArrangementsNotifierProvider =
    AsyncNotifierProvider<RecurringArrangementsNotifier, void>(
        RecurringArrangementsNotifier.new);

// ── Helpers ──────────────────────────────────────────────────────────────────

DateTime weekMonday(DateTime date) =>
    DateTime(date.year, date.month, date.day)
        .subtract(Duration(days: date.weekday - 1));

String _fmt(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
