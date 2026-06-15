import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/pb_client.dart';
import '../engine/engine_factory.dart';
import '../models/base_rule.dart';
import '../models/custody_request.dart';
import '../models/manual_override.dart';
import '../models/recurring_arrangement.dart';
import '../models/resolved_event.dart';
import '../models/weekday_rule.dart';
import '../services/offline_cache.dart';
import '../utils/dates.dart';
import 'absence_provider.dart';
import 'holiday_provider.dart';
import 'household_provider.dart';

// ── Static data — fetched once, rarely changes ───────────────────────────────

final baseRulesProvider = FutureProvider<List<BaseRule>>((ref) async {
  return fetchCachedList(
    collection: 'rules_base',
    fetch: () => pb.collection('rules_base').getFullList(),
    parse: BaseRule.fromRecord,
  );
});

final weekdayRulesProvider = FutureProvider<List<WeekdayRule>>((ref) async {
  return fetchCachedList(
    collection: 'custody_weekday_rules',
    fetch: () =>
        pb.collection('custody_weekday_rules').getFullList(filter: 'active = true'),
    parse: WeekdayRule.fromRecord,
  );
});

final recurringArrangementsProvider =
    FutureProvider<List<RecurringArrangement>>((ref) async {
  return fetchCachedList(
    collection: 'custody_recurring',
    fetch: () =>
        pb.collection('custody_recurring').getFullList(filter: 'active = true'),
    parse: RecurringArrangement.fromRecord,
  );
});

/// All manual overrides for the household (the engine filters by date itself).
/// Fetched as a full list rather than per-day so cached data covers any date
/// while the server is unreachable.
final manualOverridesProvider = FutureProvider<List<ManualOverride>>((ref) async {
  return fetchCachedList(
    collection: 'manual_overrides',
    fetch: () => pb.collection('manual_overrides').getFullList(),
    parse: ManualOverride.fromRecord,
  );
});

/// All accepted custody requests in the household (engine filters by date and
/// re-checks acceptance). Distinct from `custodyRequestsProvider`, which is
/// scoped to the current user's own requests for the requests screen.
final acceptedCustodyProvider = FutureProvider<List<CustodyRequest>>((ref) async {
  return fetchCachedList(
    collection: 'custody_requests_accepted',
    fetch: () => pb
        .collection('custody_requests')
        .getFullList(filter: 'status = "accepted"'),
    parse: CustodyRequest.fromRecord,
  );
});

// ── Resolved schedule for a single day ──────────────────────────────────────

final resolvedDayProvider =
    FutureProvider.family<List<ResolvedEvent>, DateTime>((ref, rawDate) async {
  final date = DateTime(rawDate.year, rawDate.month, rawDate.day);

  final rules           = await ref.watch(baseRulesProvider.future);
  final weekdayRules    = await ref.watch(weekdayRulesProvider.future);
  final recurring       = await ref.watch(recurringArrangementsProvider.future);
  final overrides       = await ref.watch(manualOverridesProvider.future);
  final custodyRequests = await ref.watch(acceptedCustodyProvider.future);

  final allAbsences = await ref.watch(absencePeriodsProvider.future);
  final allHolidays = await ref.watch(holidayBlocksProvider.future);

  return buildEngine(
    household:             ref.watch(householdProvider).valueOrNull,
    baseRules:             rules,
    overrides:             overrides,
    custodyRequests:       custodyRequests,
    weekdayRules:          weekdayRules,
    recurringArrangements: recurring,
    absencePeriods:        allAbsences.where((a) => a.coversDate(date)).toList(),
    holidayBlocks:         allHolidays.where((b) => b.coversDate(date)).toList(),
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

// ── Day owner (dashboard headers, etc.) ──────────────────────────────────────

/// Who has the kids on a given day, or null while inputs are loading or in
/// shared mode (where ownership is "Both" and not worth labelling).
final dayOwnerProvider = Provider.family<String?, DateTime>((ref, rawDate) {
  final household = ref.watch(householdProvider).valueOrNull;
  if (household == null || household.mode == 'shared') return null;

  final date         = DateTime(rawDate.year, rawDate.month, rawDate.day);
  final weekdayRules = ref.watch(weekdayRulesProvider).valueOrNull;
  if (weekdayRules == null) return null;
  final recurring = ref.watch(recurringArrangementsProvider).valueOrNull ?? const [];
  final absences  = ref.watch(absencePeriodsProvider).valueOrNull ?? const [];
  final holidays  = ref.watch(holidayBlocksProvider).valueOrNull ?? const [];

  return buildEngine(
    household:             household,
    weekdayRules:          weekdayRules,
    recurringArrangements: recurring,
    absencePeriods:        absences.where((a) => a.coversDate(date)).toList(),
    holidayBlocks:         holidays.where((b) => b.coversDate(date)).toList(),
  ).dayOwner(date);
});

// ── Full week of events (for calendar screen) ────────────────────────────────

final weekEventsProvider =
    FutureProvider.family<Map<String, List<ResolvedEvent>>, DateTime>(
        (ref, rawMonday) async {
  final monday       = DateTime(rawMonday.year, rawMonday.month, rawMonday.day);
  final rules        = await ref.watch(baseRulesProvider.future);
  final weekdayRules = await ref.watch(weekdayRulesProvider.future);
  final recurring    = await ref.watch(recurringArrangementsProvider.future);

  final allOverrides = await ref.watch(manualOverridesProvider.future);
  final allCustody   = await ref.watch(acceptedCustodyProvider.future);

  final allAbsences = await ref.watch(absencePeriodsProvider.future);
  final allHolidays = await ref.watch(holidayBlocksProvider.future);

  // One engine for the whole week — the engine filters overrides/custody/
  // absences by date internally, so per-day re-construction is wasted work.
  final engine = buildEngine(
    household:             ref.watch(householdProvider).valueOrNull,
    baseRules:             rules,
    overrides:             allOverrides,
    custodyRequests:       allCustody,
    weekdayRules:          weekdayRules,
    recurringArrangements: recurring,
    absencePeriods:        allAbsences,
    holidayBlocks:         allHolidays,
  );

  final result = <String, List<ResolvedEvent>>{};
  for (int i = 0; i < 7; i++) {
    final date = monday.add(Duration(days: i));
    result[isoDate(date)] = engine.resolveDay(date);
  }
  return result;
});

// ── Base rules mutations ──────────────────────────────────────────────────────

/// The active household id, or throws with a clear message. Every create MUST
/// stamp `household` — the hardened access rules deny unstamped records with
/// an opaque 400 otherwise.
String _requireHouseholdId(Ref ref) {
  final hid = ref.read(householdProvider).valueOrNull?.id;
  if (hid == null) {
    throw Exception('No active household yet — please try again in a moment.');
  }
  return hid;
}

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
    String? handoverFrom,
  }) async {
    await pb.collection('rules_base').create(body: {
      'child_name':    childName,
      'day_of_week':   dayOfWeek,
      'event_time':    eventTime,
      'activity':      activity,
      'location':      location,
      'is_shared':     isShared,
      'handover_from': handoverFrom ?? '',
      'household':     _requireHouseholdId(ref),
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
    String? handoverFrom,
  }) async {
    await pb.collection('rules_base').update(id, body: {
      'child_name':    childName,
      'day_of_week':   dayOfWeek,
      'event_time':    eventTime,
      'activity':      activity,
      'location':      location,
      'is_shared':     isShared,
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
    ref.invalidate(manualOverridesProvider);
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

    await pb.collection('custody_weekday_rules').create(body: {
      'day_of_week':     dayOfWeek,
      'assigned_parent': assignedParent,
      'reason':          reason,
      'active':          true,
      'household':       _requireHouseholdId(ref),
    });
    _invalidate();
  }

  Future<void> delete(String id) async {
    await pb.collection('custody_weekday_rules').delete(id);
    _invalidate();
  }

  void _invalidate() {
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
      'household':          _requireHouseholdId(ref),
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
