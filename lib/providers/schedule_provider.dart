import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/pb_client.dart';
import '../engine/engine_factory.dart';
import '../engine/resolution_engine.dart';
import '../models/base_rule.dart';
import '../models/custody_request.dart';
import '../models/manual_override.dart';
import '../models/resolved_event.dart';
import '../services/offline_cache.dart';
import '../services/queue_service.dart';
import '../services/widget_cache_service.dart';
import '../utils/dates.dart';
import '../utils/ids.dart';
import 'absence_provider.dart';
import 'auth_provider.dart';
import 'holiday_provider.dart';
import 'household_provider.dart';
import 'queue_count_provider.dart';

// ── Clock ─────────────────────────────────────────────────────────────────────

/// Today's date at midnight. Date-sensitive providers watch this; the app
/// shell advances it when the day rolls over or the app resumes on a new day,
/// so "Today" never goes stale while the app stays open.
final todayProvider =
    StateProvider<DateTime>((ref) => dateOnly(DateTime.now()));

// ── Source data ───────────────────────────────────────────────────────────────

final baseRulesProvider = FutureProvider<List<BaseRule>>((ref) {
  return fetchCachedList(
    collection: 'rules_base',
    fetch: () => pb.collection('rules_base').getFullList(),
    parse: BaseRule.fromRecord,
  );
});

/// All manual overrides and one-off events for the household (the engine
/// filters by date). Fetched as a full list so cached data covers any date
/// while the server is unreachable.
final manualOverridesProvider = FutureProvider<List<ManualOverride>>((ref) {
  return fetchCachedList(
    collection: 'manual_overrides',
    fetch: () => pb.collection('manual_overrides').getFullList(),
    parse: ManualOverride.fromRecord,
  );
});

/// All accepted custody requests in the household. Distinct from
/// `custodyRequestsProvider`, which holds the current user's own requests.
final acceptedCustodyProvider = FutureProvider<List<CustodyRequest>>((ref) {
  return fetchCachedList(
    collection: 'custody_requests_accepted',
    fetch: () => pb
        .collection('custody_requests')
        .getFullList(filter: 'status = "accepted"'),
    parse: CustodyRequest.fromRecord,
  );
});

// ── Resolved schedule ─────────────────────────────────────────────────────────

/// An engine over everything currently loaded (empty lists while loading), for
/// synchronous UI such as calendar cells and form hints.
final scheduleEngineProvider = Provider<ResolutionEngine>((ref) {
  return buildEngine(
    household:       ref.watch(householdProvider).valueOrNull,
    baseRules:       ref.watch(baseRulesProvider).valueOrNull ?? const [],
    overrides:       ref.watch(manualOverridesProvider).valueOrNull ?? const [],
    custodyRequests: ref.watch(acceptedCustodyProvider).valueOrNull ?? const [],
    absencePeriods:  ref.watch(absencePeriodsProvider).valueOrNull ?? const [],
    holidayBlocks:   ref.watch(holidayBlocksProvider).valueOrNull ?? const [],
  );
});

/// Resolved events for one day. Key by a date-only [DateTime].
final resolvedDayProvider =
    FutureProvider.family<List<ResolvedEvent>, DateTime>((ref, rawDate) async {
  final date      = dateOnly(rawDate);
  final rules     = await ref.watch(baseRulesProvider.future);
  final overrides = await ref.watch(manualOverridesProvider.future);
  final custody   = await ref.watch(acceptedCustodyProvider.future);
  final absences  = await ref.watch(absencePeriodsProvider.future);
  final holidays  = await ref.watch(holidayBlocksProvider.future);

  return buildEngine(
    household:       ref.watch(householdProvider).valueOrNull,
    baseRules:       rules,
    overrides:       overrides,
    custodyRequests: custody,
    absencePeriods:  absences.where((a) => a.coversDate(date)).toList(),
    holidayBlocks:   holidays.where((b) => b.coversDate(date)).toList(),
  ).resolveDay(date);
});

/// Today + tomorrow, for the dashboard.
final dashboardProvider = FutureProvider<List<ResolvedEvent>>((ref) async {
  final today = ref.watch(todayProvider);
  final results = await Future.wait([
    ref.watch(resolvedDayProvider(today).future),
    ref.watch(resolvedDayProvider(addDays(today, 1)).future),
  ]);
  return [...results[0], ...results[1]];
});

/// Who has the kids on a given day, or null while inputs are loading or in
/// shared mode (where ownership is "Both" and not worth labelling).
final dayOwnerProvider = Provider.family<String?, DateTime>((ref, rawDate) {
  final household = ref.watch(householdProvider).valueOrNull;
  if (household == null || household.mode == 'shared') return null;
  final custody = ref.watch(acceptedCustodyProvider).valueOrNull;
  if (custody == null) return null;

  final date     = dateOnly(rawDate);
  final absences = ref.watch(absencePeriodsProvider).valueOrNull ?? const [];
  final holidays = ref.watch(holidayBlocksProvider).valueOrNull ?? const [];
  return buildEngine(
    household:       household,
    custodyRequests: custody,
    absencePeriods:  absences.where((a) => a.coversDate(date)).toList(),
    holidayBlocks:   holidays.where((b) => b.coversDate(date)).toList(),
  ).dayOwner(date);
});

/// A full week of events keyed by ISO date, for the calendar.
final weekEventsProvider =
    FutureProvider.family<Map<String, List<ResolvedEvent>>, DateTime>(
        (ref, rawMonday) async {
  final monday    = dateOnly(rawMonday);
  final rules     = await ref.watch(baseRulesProvider.future);
  final overrides = await ref.watch(manualOverridesProvider.future);
  final custody   = await ref.watch(acceptedCustodyProvider.future);
  final absences  = await ref.watch(absencePeriodsProvider.future);
  final holidays  = await ref.watch(holidayBlocksProvider.future);

  // One engine for the whole week — it filters by date internally.
  final engine = buildEngine(
    household:       ref.watch(householdProvider).valueOrNull,
    baseRules:       rules,
    overrides:       overrides,
    custodyRequests: custody,
    absencePeriods:  absences,
    holidayBlocks:   holidays,
  );

  return {
    for (var i = 0; i < 7; i++)
      isoDate(addDays(monday, i)): engine.resolveDay(addDays(monday, i)),
  };
});

// ── Mutations ─────────────────────────────────────────────────────────────────

/// The active household id, or throws with a clear message. Every create MUST
/// stamp `household` — the access rules deny unstamped records.
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
    String? endDate,
  }) async {
    await pb.collection('rules_base').create(body: {
      'child_name':    childName,
      'day_of_week':   dayOfWeek,
      'event_time':    eventTime,
      'activity':      activity,
      'location':      location,
      'is_shared':     isShared,
      'handover_from': handoverFrom ?? '',
      'end_date':      endDate ?? '',
      'household':     _requireHouseholdId(ref),
    });
    _changed();
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
    String? endDate,
  }) async {
    await pb.collection('rules_base').update(id, body: {
      'child_name':    childName,
      'day_of_week':   dayOfWeek,
      'event_time':    eventTime,
      'activity':      activity,
      'location':      location,
      'is_shared':     isShared,
      'handover_from': handoverFrom ?? '',
      'end_date':      endDate ?? '',
    });
    _changed();
  }

  Future<void> delete(String id) async {
    await pb.collection('rules_base').delete(id);
    _changed();
  }

  void _changed() {
    ref.invalidate(baseRulesProvider);
    WidgetCacheService.updateSoon();
  }
}

final baseRulesNotifierProvider =
    AsyncNotifierProvider<BaseRulesNotifier, void>(BaseRulesNotifier.new);

/// A one-off event (or exam paper) to create.
class NewEvent {
  final DateTime date;
  final String time;       // "HH:mm"
  final String? endTime;   // "HH:mm"
  final String activity;
  final String location;
  final String childName;
  final String? note;
  final bool isShared;
  final String kind;       // '' | 'exam'

  const NewEvent({
    required this.date,
    required this.time,
    this.endTime,
    required this.activity,
    this.location = '',
    required this.childName,
    this.note,
    this.isShared = true,
    this.kind = '',
  });
}

class ManualOverridesNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// Creates one-off events — a single outing, or a child's whole exam
  /// timetable. Each record carries a client-generated id, so whatever can't
  /// reach the server is queued and replayed safely later.
  Future<void> createEvents(List<NewEvent> events) async {
    final hid    = _requireHouseholdId(ref);
    final myId   = ref.read(authProvider).valueOrNull?.userId ?? '';
    final engine = ref.read(scheduleEngineProvider);

    final bodies = [
      for (final e in events)
        {
          'id':              newRecordId(),
          'target_date':     isoDate(e.date),
          'child_name':      e.childName,
          // Kept for older app versions; the engine resolves the parent live.
          'original_parent': engine.dayOwner(e.date),
          'assigned_parent': engine.dayOwner(e.date),
          'override_time':   e.time,
          'reason':          e.activity,
          'created_by':      myId,
          'is_adhoc':        true,
          'is_shared':       e.isShared,
          'activity':        e.activity,
          'location':        e.location,
          'end_time':        e.endTime ?? '',
          'note':            e.note ?? '',
          'kind':            e.kind,
          'household':       hid,
        },
    ];

    for (var i = 0; i < bodies.length; i++) {
      try {
        await pb.collection('manual_overrides').create(body: bodies[i]);
      } catch (e) {
        if (!isNetworkError(e)) rethrow;
        for (final body in bodies.sublist(i)) {
          await QueueService.enqueue(PendingOp(
            id:         QueueService.newOpId(),
            collection: 'manual_overrides',
            method:     'create',
            body:       body,
          ));
        }
        ref.read(pendingOpsCountProvider.notifier).state =
            await QueueService.pendingCount();
        break;
      }
    }
    _changed();
  }

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
      'reason':        activity,
      'activity':      activity,
      'location':      location,
      'is_shared':     isShared,
      'end_time':      endTime ?? '',
      'note':          note ?? '',
    });
    _changed();
  }

  Future<void> delete(String id) async {
    await pb.collection('manual_overrides').delete(id);
    _changed();
  }

  void _changed() {
    ref.invalidate(manualOverridesProvider);
    WidgetCacheService.updateSoon();
  }
}

final manualOverridesNotifierProvider =
    AsyncNotifierProvider<ManualOverridesNotifier, void>(ManualOverridesNotifier.new);

// ── Helpers ───────────────────────────────────────────────────────────────────

DateTime weekMonday(DateTime date) =>
    addDays(dateOnly(date), -(date.weekday - 1));
