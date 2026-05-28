import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';

import 'package:coplan/engine/resolution_engine.dart';
import 'package:coplan/models/base_rule.dart';
import 'package:coplan/models/custody_request.dart';
import 'package:coplan/models/manual_override.dart';
import 'package:coplan/models/recurring_arrangement.dart';
import 'package:coplan/models/rotation_scheme.dart';
import 'package:coplan/models/weekday_rule.dart';

// ── Builders ──────────────────────────────────────────────────────────────────

ResolutionEngine engine({
  List<BaseRule> baseRules = const [],
  List<ManualOverride> overrides = const [],
  List<CustodyRequest> custody = const [],
  List<WeekdayRule> weekdayRules = const [],
  List<RecurringArrangement> recurring = const [],
  required DateTime anchor,
  String even = 'Alice',
  String odd = 'Bob',
  RotationScheme? scheme,
  String mode = 'custody',
}) =>
    ResolutionEngine(
      baseRules: baseRules,
      overrides: overrides,
      custodyRequests: custody,
      weekdayRules: weekdayRules,
      recurringArrangements: recurring,
      rotationAnchor: anchor,
      rotationParentEven: even,
      rotationParentOdd: odd,
      rotationScheme: scheme,
      householdMode: mode,
    );

BaseRule rule(int dow, String time,
        {String child = 'All', String activity = 'Event', String id = 'r'}) =>
    BaseRule(
        id: id,
        childName: child,
        dayOfWeek: dow,
        eventTime: time,
        location: '',
        activity: activity);

CustodyRequest custodyReq({
  required DateTime date,
  required String to,
  String from = 'Alice',
  String pickup = '09:00',
  String? returnTime,
  bool tbd = false,
  String child = 'All',
  CustodyStatus status = CustodyStatus.accepted,
  String id = 'c',
}) =>
    CustodyRequest(
      id: id,
      fromParent: from,
      toParent: to,
      date: date,
      childName: child,
      pickupTime: pickup,
      returnTime: returnTime,
      returnTimeTbd: tbd,
      status: status,
      createdBy: 'u1',
      requestedFrom: 'u2',
    );

RecurringArrangement recurring({
  required int dow,
  required String to,
  String pickup = '17:30',
  String child = 'All',
  required DateTime start,
  String id = 'arr',
}) =>
    RecurringArrangement(
      id: id,
      dayOfWeek: dow,
      toParent: to,
      childName: child,
      pickupTime: pickup,
      startDate: start,
    );

ManualOverride override({
  required DateTime date,
  required String assigned,
  String child = 'All',
  String reason = '',
  String? time,
  String id = 'o',
}) =>
    ManualOverride(
      id: id,
      targetDate: date,
      childName: child,
      assignedParent: assigned,
      overrideTime: time,
      reason: reason,
      createdBy: 'u1',
    );

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
DateTime daysFromToday(int n) =>
    dateOnly(DateTime.now()).add(Duration(days: n));

void main() {
  final monAnchor = DateTime(2025, 1, 6); // a Monday

  group('weekOwner (weekly rotation, UTC epoch math)', () {
    final e = engine(anchor: monAnchor);

    test('anchor week is the even parent', () {
      expect(e.weekOwner(DateTime(2025, 1, 6)), 'Alice'); // Mon
      expect(e.weekOwner(DateTime(2025, 1, 8)), 'Alice'); // Wed same week
    });

    test('next week flips to the odd parent', () {
      expect(e.weekOwner(DateTime(2025, 1, 13)), 'Bob');
    });

    test('alternates and wraps correctly weeks out', () {
      expect(e.weekOwner(DateTime(2025, 1, 20)), 'Alice'); // +14d
      expect(e.weekOwner(DateTime(2025, 3, 31)), 'Alice'); // +84d (12 wk, even)
    });

    test('weeks before the anchor keep consistent parity', () {
      expect(e.weekOwner(DateTime(2024, 12, 30)), 'Bob'); // -7d
      expect(e.weekOwner(DateTime(2024, 12, 23)), 'Alice'); // -14d
    });
  });

  group('baseOwner / dayOwner', () {
    test('baseOwner follows rotation without rules', () {
      final e = engine(anchor: monAnchor);
      expect(e.baseOwner(DateTime(2025, 1, 13)), 'Bob');
    });

    test('weekday rule overrides rotation for baseOwner and dayOwner', () {
      final e = engine(anchor: monAnchor, weekdayRules: [
        const WeekdayRule(id: 'w', dayOfWeek: 1, assignedParent: 'Bob'),
      ]);
      // 2025-01-06 is a Monday → rotation says Alice, weekday rule says Bob.
      expect(e.baseOwner(DateTime(2025, 1, 6)), 'Bob');
      expect(e.dayOwner(DateTime(2025, 1, 6)), 'Bob');
    });

    test('accepted day transfer wins dayOwner', () {
      final d = DateTime(2025, 1, 8); // Alice's week
      final e = engine(anchor: monAnchor, custody: [
        custodyReq(date: d, to: 'Bob', pickup: '00:00'),
      ]);
      expect(e.dayOwner(d), 'Bob');
    });
  });

  group('day transfers and parentAtTime', () {
    final d = DateTime(2025, 1, 8); // Wed, Alice's week

    test('before pickup stays with the day owner, after flips', () {
      final e = engine(anchor: monAnchor, custody: [
        custodyReq(date: d, to: 'Bob', pickup: '17:30'),
      ]);
      expect(e.parentAtTime(d, const TimeOfDay(hour: 16, minute: 0)), 'Alice');
      expect(e.parentAtTime(d, const TimeOfDay(hour: 18, minute: 0)), 'Bob');
    });

    test('window only changes responsibility within pickup→return', () {
      final e = engine(anchor: monAnchor, custody: [
        custodyReq(date: d, to: 'Bob', pickup: '14:00', returnTime: '16:00'),
      ]);
      expect(e.parentAtTime(d, const TimeOfDay(hour: 13, minute: 0)), 'Alice');
      expect(e.parentAtTime(d, const TimeOfDay(hour: 15, minute: 0)), 'Bob');
      expect(e.parentAtTime(d, const TimeOfDay(hour: 16, minute: 0)), 'Alice');
      expect(e.custodyWindows(d).length, 1);
    });
  });

  group('recurring arrangement expansion', () {
    // target: a date safely in the future, on its own weekday.
    final target = daysFromToday(21);
    final wd = target.weekday;
    final start = DateTime(2025, 1, 1);

    test('fires when the OTHER parent owns the day', () {
      // anchor == target → daysSince 0 → even parent (Alice) owns the day.
      final e = engine(anchor: target, recurring: [
        recurring(dow: wd, to: 'Bob', start: start),
      ]);
      final transfer = e.dayTransferFor(target);
      expect(transfer, isNotNull);
      expect(transfer!.toParent, 'Bob');
      expect(transfer.fromParent, 'Alice'); // released by the day owner
      expect(e.dayOwner(target), 'Bob');
    });

    test('suppressed on weeks the recipient already owns the day', () {
      // anchor = target-7 → daysSince 7 → odd parent (Bob) owns the day.
      final e = engine(
          anchor: target.subtract(const Duration(days: 7)),
          recurring: [recurring(dow: wd, to: 'Bob', start: start)]);
      expect(e.effectiveCustodyFor(target), isEmpty);
    });

    test('not expanded for past dates (history comes from frozen rows)', () {
      final past = daysFromToday(-7);
      final e = engine(anchor: past, recurring: [
        recurring(dow: past.weekday, to: 'Bob', start: DateTime(2024, 1, 1)),
      ]);
      expect(e.effectiveCustodyFor(past), isEmpty);
    });

    test('not expanded before start_date', () {
      final e = engine(anchor: target, recurring: [
        recurring(
            dow: wd, to: 'Bob', start: target.add(const Duration(days: 7))),
      ]);
      expect(e.effectiveCustodyFor(target), isEmpty);
    });

    test('suppressed when a real request already covers the date', () {
      final e = engine(anchor: target, custody: [
        custodyReq(date: target, to: 'Bob', pickup: '17:30', id: 'real'),
      ], recurring: [
        recurring(dow: wd, to: 'Bob', start: start),
      ]);
      final all = e.effectiveCustodyFor(target);
      expect(all.length, 1);
      expect(all.single.id, 'real'); // not the virtual one
    });

    test('not expanded on a non-matching weekday', () {
      final otherDow = (wd % 7) + 1;
      final e = engine(anchor: target, recurring: [
        recurring(dow: otherDow, to: 'Bob', start: start),
      ]);
      expect(e.effectiveCustodyFor(target), isEmpty);
    });
  });

  group('shared mode', () {
    final d = DateTime(2025, 1, 8);
    test('no rotation — everyone is "Both"', () {
      final e = engine(anchor: monAnchor, mode: 'shared');
      expect(e.isSharedMode, true);
      expect(e.weekOwner(d), 'Both');
      expect(e.baseOwner(d), 'Both');
      expect(e.dayOwner(d), 'Both');
    });

    test('a day transfer still applies in shared mode', () {
      final e = engine(anchor: monAnchor, mode: 'shared', custody: [
        custodyReq(date: d, to: 'Bob', pickup: '00:00'),
      ]);
      expect(e.dayOwner(d), 'Bob');
    });
  });

  group('resolveDay', () {
    final target = daysFromToday(21);
    final wd = target.weekday;

    test('orders events by time with custody banner first at a tie', () {
      final e = engine(anchor: target, baseRules: [
        rule(wd, '16:00', activity: 'School', id: 'r16'),
        rule(wd, '17:30', activity: 'Clash', id: 'r1730'),
        rule(wd, '18:00', activity: 'Dinner', id: 'r18'),
      ], recurring: [
        recurring(dow: wd, to: 'Bob', pickup: '17:30', start: DateTime(2025, 1, 1)),
      ]);

      final events = e.resolveDay(target);
      // 16:00 School, 17:30 banner (custody), 17:30 Clash, 18:00 Dinner
      expect(events[0].activity, 'School');
      expect(events[1].recurringId, isNotNull); // banner sorts before same-time
      expect(events[2].activity, 'Clash');
      expect(events[3].activity, 'Dinner');
    });

    test('parent flips at the transfer pickup time', () {
      final e = engine(anchor: target, baseRules: [
        rule(wd, '16:00', id: 'r16'),
        rule(wd, '18:00', id: 'r18'),
      ], recurring: [
        recurring(dow: wd, to: 'Bob', pickup: '17:30', start: DateTime(2025, 1, 1)),
      ]);
      final events = e.resolveDay(target);
      final before = events.firstWhere((x) => x.ruleId == 'r16');
      final after = events.firstWhere((x) => x.ruleId == 'r18');
      expect(before.assignedParent, 'Alice'); // day owner before handover
      expect(after.assignedParent, 'Bob'); // recipient after handover
    });
  });

  group('manual overrides', () {
    final d = DateTime(2025, 1, 8); // Alice's week

    test('non-adhoc override changes parent and shows its reason', () {
      final e = engine(anchor: monAnchor, baseRules: [
        rule(d.weekday, '16:00', id: 'r16'),
      ], overrides: [
        override(date: d, assigned: 'Bob', reason: 'Dad swap'),
      ]);
      final ev = e.resolveDay(d).firstWhere((x) => x.ruleId == 'r16');
      expect(ev.assignedParent, 'Bob');
      expect(ev.overrideReason, 'Dad swap');
    });

    test('custody request beats override and drops the override reason (#3)', () {
      final e = engine(anchor: monAnchor, baseRules: [
        rule(d.weekday, '16:00', id: 'r16'),
      ], overrides: [
        override(date: d, assigned: 'Bob', reason: 'Dad swap'),
      ], custody: [
        custodyReq(date: d, to: 'Alice', from: 'Bob', pickup: '09:00'),
      ]);
      final ev = e.resolveDay(d).firstWhere((x) => x.ruleId == 'r16');
      expect(ev.assignedParent, 'Alice'); // transfer wins
      expect(ev.overrideReason, isNull); // mixed-provenance reason dropped
    });

    test('"All" override matches a child-specific rule and vice versa (#4)', () {
      // All override → Henri rule
      final e1 = engine(anchor: monAnchor, baseRules: [
        rule(d.weekday, '16:00', child: 'Henri', id: 'rH'),
      ], overrides: [
        override(date: d, assigned: 'Bob', child: 'All'),
      ]);
      expect(e1.resolveDay(d).firstWhere((x) => x.ruleId == 'rH').assignedParent,
          'Bob');

      // Henri override → All rule
      final e2 = engine(anchor: monAnchor, baseRules: [
        rule(d.weekday, '16:00', child: 'All', id: 'rA'),
      ], overrides: [
        override(date: d, assigned: 'Bob', child: 'Henri'),
      ]);
      expect(e2.resolveDay(d).firstWhere((x) => x.ruleId == 'rA').assignedParent,
          'Bob');
    });
  });

  group('rotation schemes', () {
    test('2-2-5-5 follows its pattern from the anchor', () {
      final e = engine(anchor: monAnchor, scheme: RotationScheme.twoTwoFiveFive());
      // pattern: [0,0,1,1,0,0,0,0,0,1,1,1,1,1]
      expect(e.weekOwner(DateTime(2025, 1, 6)), 'Alice'); // day 0
      expect(e.weekOwner(DateTime(2025, 1, 8)), 'Bob'); // day 2
      expect(e.weekOwner(DateTime(2025, 1, 10)), 'Alice'); // day 4
      expect(e.weekOwner(DateTime(2025, 1, 15)), 'Bob'); // day 9
    });
  });
}
