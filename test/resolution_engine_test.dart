import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';

import 'package:coplan/engine/resolution_engine.dart';
import 'package:coplan/models/absence_period.dart';
import 'package:coplan/models/base_rule.dart';
import 'package:coplan/models/custody_request.dart';
import 'package:coplan/models/holiday_block.dart';
import 'package:coplan/models/manual_override.dart';
import 'package:coplan/models/rotation_scheme.dart';

// ── Builders ──────────────────────────────────────────────────────────────────

ResolutionEngine engine({
  List<BaseRule> baseRules = const [],
  List<ManualOverride> overrides = const [],
  List<CustodyRequest> custody = const [],
  List<AbsencePeriod> absences = const [],
  List<HolidayBlock> holidays = const [],
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
      absencePeriods: absences,
      holidayBlocks: holidays,
      rotationAnchor: anchor,
      rotationParentEven: even,
      rotationParentOdd: odd,
      rotationScheme: scheme,
      householdMode: mode,
    );

AbsencePeriod absence({
  required String parent,
  required DateTime start,
  required DateTime end,
  String reason = 'Trip',
}) =>
    AbsencePeriod(
      id: 'abs',
      householdId: 'hh',
      absentParent: parent,
      startDate: start,
      endDate: end,
      reason: reason,
      createdBy: 'u1',
    );

HolidayBlock holiday({
  required String parent,
  required DateTime start,
  required DateTime end,
}) =>
    HolidayBlock(
      id: 'hol',
      householdId: 'hh',
      name: 'School holiday',
      assignedParent: parent,
      startDate: start,
      endDate: end,
      createdBy: 'u1',
    );

BaseRule rule(int dow, String time,
        {String child = 'All',
        String activity = 'Event',
        String id = 'r',
        DateTime? endDate,
        String? handoverFrom}) =>
    BaseRule(
        id: id,
        childName: child,
        dayOfWeek: dow,
        eventTime: time,
        location: '',
        activity: activity,
        endDate: endDate,
        handoverFrom: handoverFrom);

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
  String? swapGroup,
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
      swapGroup: swapGroup,
    );

ManualOverride override({
  required DateTime date,
  required String assigned,
  String child = 'All',
  String reason = '',
  String? time,
  String id = 'o',
  bool adhoc = false,
  String kind = '',
  String? activity,
}) =>
    ManualOverride(
      id: id,
      targetDate: date,
      childName: child,
      assignedParent: assigned,
      overrideTime: time,
      reason: reason,
      createdBy: 'u1',
      isAdhoc: adhoc,
      adhocActivity: activity,
      kind: kind,
    );

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
    test('baseOwner follows rotation without holidays', () {
      final e = engine(anchor: monAnchor);
      expect(e.baseOwner(DateTime(2025, 1, 13)), 'Bob');
    });

    test('holiday block overrides rotation', () {
      final d = DateTime(2025, 1, 8); // Alice's week
      final e = engine(anchor: monAnchor, holidays: [
        holiday(parent: 'Bob', start: d, end: d),
      ]);
      expect(e.baseOwner(d), 'Bob');
      expect(e.dayOwner(d), 'Bob');
    });

    test('accepted day transfer wins dayOwner', () {
      final d = DateTime(2025, 1, 8); // Alice's week
      final e = engine(anchor: monAnchor, custody: [
        custodyReq(date: d, to: 'Bob', pickup: '00:00'),
      ]);
      expect(e.dayOwner(d), 'Bob');
    });

    test('pending requests are ignored', () {
      final d = DateTime(2025, 1, 8);
      final e = engine(anchor: monAnchor, custody: [
        custodyReq(date: d, to: 'Bob', pickup: '00:00', status: CustodyStatus.pending),
      ]);
      expect(e.dayOwner(d), 'Alice');
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

    test('a per-child transfer does not move siblings', () {
      final e = engine(anchor: monAnchor, custody: [
        custodyReq(date: d, to: 'Bob', pickup: '00:00', child: 'Henri'),
      ]);
      expect(e.parentAtTime(d, const TimeOfDay(hour: 9, minute: 0), child: 'Henri'), 'Bob');
      expect(e.parentAtTime(d, const TimeOfDay(hour: 9, minute: 0), child: 'Chris'), 'Alice');
    });
  });

  group('day swaps', () {
    // Alice gives Bob her Wednesday and takes his Wednesday a week later.
    final aliceWed = DateTime(2025, 1, 8);
    final bobWed = DateTime(2025, 1, 15);
    final e = engine(anchor: monAnchor, baseRules: [
      rule(DateTime.wednesday, '16:00', activity: 'Swimming', id: 'swim'),
    ], custody: [
      custodyReq(date: aliceWed, from: 'Alice', to: 'Bob', pickup: '00:00', id: 'leg1', swapGroup: 'g'),
      custodyReq(date: bobWed, from: 'Bob', to: 'Alice', pickup: '00:00', id: 'leg2', swapGroup: 'g'),
    ]);

    test('both days change hands', () {
      expect(e.dayOwner(aliceWed), 'Bob');
      expect(e.dayOwner(bobWed), 'Alice');
    });

    test('events follow the swap and the banner is labelled', () {
      final first = e.resolveDay(aliceWed);
      expect(first.firstWhere((x) => x.ruleId == 'swim').assignedParent, 'Bob');
      final banner = first.firstWhere((x) => x.isCustody);
      expect(banner.activity, 'All in Bob\'s care · swap');
      expect(banner.swapGroup, 'g');
      expect(e.resolveDay(bobWed).firstWhere((x) => x.ruleId == 'swim').assignedParent,
          'Alice');
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
    final d = DateTime(2025, 1, 8); // Wed, Alice's week
    final wd = d.weekday;

    test('orders events by time with custody banner first at a tie', () {
      final e = engine(anchor: monAnchor, baseRules: [
        rule(wd, '16:00', activity: 'School', id: 'r16'),
        rule(wd, '17:30', activity: 'Clash', id: 'r1730'),
        rule(wd, '18:00', activity: 'Dinner', id: 'r18'),
      ], custody: [
        custodyReq(date: d, to: 'Bob', pickup: '17:30'),
      ]);

      final events = e.resolveDay(d);
      // 16:00 School, 17:30 banner (custody), 17:30 Clash, 18:00 Dinner
      expect(events[0].activity, 'School');
      expect(events[1].isCustody, isTrue);
      expect(events[2].activity, 'Clash');
      expect(events[3].activity, 'Dinner');
    });

    test('parent flips at the transfer pickup time', () {
      final e = engine(anchor: monAnchor, baseRules: [
        rule(wd, '16:00', id: 'r16'),
        rule(wd, '18:00', id: 'r18'),
      ], custody: [
        custodyReq(date: d, to: 'Bob', pickup: '17:30'),
      ]);
      final events = e.resolveDay(d);
      expect(events.firstWhere((x) => x.ruleId == 'r16').assignedParent, 'Alice');
      expect(events.firstWhere((x) => x.ruleId == 'r18').assignedParent, 'Bob');
    });

    test('directional handover rule renders only for the outgoing parent', () {
      final e = engine(anchor: monAnchor, baseRules: [
        rule(wd, '10:00', id: 'fromAlice', handoverFrom: 'Alice'),
        rule(wd, '12:00', id: 'fromBob', handoverFrom: 'Bob'),
      ]);
      final ids = e.resolveDay(d).map((x) => x.ruleId).toList();
      expect(ids, ['fromAlice']);
    });
  });

  group('one-off events', () {
    final d = DateTime(2025, 1, 8); // Alice's week

    test('responsible parent is resolved live, not the stored value', () {
      // Stored when Alice owned the day; a holiday block added later gives
      // the day to Bob, and the event must follow.
      final e = engine(anchor: monAnchor, overrides: [
        override(date: d, assigned: 'Alice', adhoc: true, time: '15:00',
            activity: 'Party', id: 'party'),
      ], holidays: [
        holiday(parent: 'Bob', start: d, end: d),
      ]);
      final ev = e.resolveDay(d).single;
      expect(ev.assignedParent, 'Bob');
      expect(ev.custodyNote, isNull);
    });

    test('exam kind passes through', () {
      final e = engine(anchor: monAnchor, overrides: [
        override(date: d, assigned: 'Alice', adhoc: true, time: '09:00',
            activity: 'Maths P1', child: 'Henri', kind: 'exam', id: 'exam'),
      ]);
      final ev = e.resolveDay(d).single;
      expect(ev.isExam, isTrue);
      expect(ev.activity, 'Maths P1');
      expect(ev.childName, 'Henri');
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

    test('custody request beats override and drops the override reason', () {
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

    test('"All" override matches a child-specific rule and vice versa', () {
      final e1 = engine(anchor: monAnchor, baseRules: [
        rule(d.weekday, '16:00', child: 'Henri', id: 'rH'),
      ], overrides: [
        override(date: d, assigned: 'Bob', child: 'All'),
      ]);
      expect(e1.resolveDay(d).firstWhere((x) => x.ruleId == 'rH').assignedParent,
          'Bob');

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

  group('absence periods', () {
    final aliceDay = DateTime(2025, 1, 6); // Monday, Alice's week
    final bobDay   = DateTime(2025, 1, 13); // Monday, Bob's week

    test('dayOwner flips to Bob when Alice is absent', () {
      final e = engine(
        anchor: monAnchor,
        absences: [absence(parent: 'Alice', start: aliceDay, end: aliceDay)],
      );
      expect(e.dayOwner(aliceDay), 'Bob');
    });

    test('dayOwner flips to Alice when Bob is absent', () {
      final e = engine(
        anchor: monAnchor,
        absences: [absence(parent: 'Bob', start: bobDay, end: bobDay)],
      );
      expect(e.dayOwner(bobDay), 'Alice');
    });

    test('dayOwner unchanged outside absence range', () {
      final e = engine(
        anchor: monAnchor,
        absences: [absence(parent: 'Alice', start: aliceDay, end: aliceDay)],
      );
      expect(e.dayOwner(aliceDay.add(const Duration(days: 1))), 'Alice');
    });

    test('before a transfer pickup the absence still applies', () {
      final e = engine(
        anchor: monAnchor,
        absences: [absence(parent: 'Alice', start: aliceDay, end: aliceDay)],
        custody: [custodyReq(date: aliceDay, to: 'Gran', pickup: '17:00')],
      );
      expect(e.parentAtTime(aliceDay, const TimeOfDay(hour: 8, minute: 0)), 'Bob');
      expect(e.parentAtTime(aliceDay, const TimeOfDay(hour: 18, minute: 0)), 'Gran');
    });

    test('manual override beats absence — override parent is respected', () {
      final d = aliceDay;
      final e = engine(
        anchor: monAnchor,
        baseRules: [rule(d.weekday, '08:00')],
        overrides: [
          ManualOverride(
            id: 'ov1', targetDate: d, childName: 'All',
            assignedParent: 'Alice', reason: 'explicit', createdBy: 'u',
          ),
        ],
        absences: [absence(parent: 'Alice', start: d, end: d)],
      );
      expect(e.resolveDay(d).first.assignedParent, 'Alice');
    });

    test('resolveDay shows absence reason on affected events', () {
      final d = aliceDay;
      final e = engine(
        anchor: monAnchor,
        baseRules: [rule(d.weekday, '08:00')],
        absences: [absence(parent: 'Alice', start: d, end: d, reason: 'Hiking trip')],
      );
      final event = e.resolveDay(d).first;
      expect(event.assignedParent, 'Bob');
      expect(event.overrideReason, 'Hiking trip');
    });

    test('absenceFor returns matching absence', () {
      final e = engine(
        anchor: monAnchor,
        absences: [absence(parent: 'Alice', start: aliceDay, end: aliceDay.add(const Duration(days: 2)))],
      );
      expect(e.absenceFor(aliceDay)?.absentParent, 'Alice');
      expect(e.absenceFor(aliceDay.add(const Duration(days: 3))), isNull);
    });
  });

  group('standing event end dates (inclusive)', () {
    final d = DateTime(2025, 1, 8);
    final wd = d.weekday;

    test('renders on its end date, gone the next week', () {
      final e = engine(anchor: monAnchor, baseRules: [
        rule(wd, '16:00', activity: 'Swimming', id: 'rs', endDate: d),
      ]);
      expect(e.resolveDay(d).where((x) => x.ruleId == 'rs'), isNotEmpty);
      final nextWeek = d.add(const Duration(days: 7));
      expect(e.resolveDay(nextWeek).where((x) => x.ruleId == 'rs'), isEmpty);
    });

    test('a time-of-day on the date does not end it early', () {
      final e = engine(anchor: monAnchor, baseRules: [
        rule(wd, '16:00', id: 'rs', endDate: d),
      ]);
      final afternoon = DateTime(d.year, d.month, d.day, 14, 30);
      expect(e.resolveDay(afternoon).where((x) => x.ruleId == 'rs'), isNotEmpty);
    });

    test('without an end date it repeats forever', () {
      final e = engine(anchor: monAnchor, baseRules: [rule(wd, '16:00', id: 'rs')]);
      final later = d.add(const Duration(days: 700));
      expect(e.resolveDay(later).where((x) => x.ruleId == 'rs'), isNotEmpty);
    });
  });
}
