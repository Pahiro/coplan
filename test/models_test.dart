import 'package:flutter/material.dart' show Color;
import 'package:flutter_test/flutter_test.dart';

import 'package:coplan/models/app_colors.dart';
import 'package:coplan/models/base_rule.dart';
import 'package:coplan/models/custody_request.dart';
import 'package:coplan/models/household.dart';
import 'package:coplan/models/manual_override.dart';
import 'package:coplan/models/need.dart';

Map<String, dynamic> requestRecord(String id, String date,
        {String to = 'Bennet', String status = 'pending', String swapGroup = ''}) =>
    {
      'id': id,
      'from_parent': 'Jana',
      'to_parent': to,
      'date': date,
      'child_name': 'All',
      'pickup_time': '00:00',
      'return_time': '',
      'status': status,
      'swap_group': swapGroup,
    };

void main() {
  group('BaseRule.fromRecord', () {
    test('parses fields and defaults isShared', () {
      final r = BaseRule.fromRecord({
        'id': 'r1',
        'child_name': 'All',
        'day_of_week': 2,
        'event_time': '16:00',
        'location': 'School',
        'activity': 'Pickup',
      });
      expect(r.id, 'r1');
      expect(r.dayOfWeek, 2);
      expect(r.isShared, false);
    });
  });

  group('CustodyRequest', () {
    test('day transfer: no return time', () {
      final r = CustodyRequest.fromRecord({
        'id': 'c1',
        'from_parent': 'Jana',
        'to_parent': 'Bennet',
        'date': '2026-05-26',
        'child_name': 'All',
        'pickup_time': '17:30',
        'return_time': '',
        'status': 'accepted',
      });
      expect(r.isDayTransfer, true);
      expect(r.isAccepted, true);
      expect(r.isSwapLeg, false);
      expect(r.timeWindowLabel, '17:30 onwards');
    });

    test('whole-day transfer reads as "All day"', () {
      final r = CustodyRequest.fromRecord(requestRecord('c0', '2026-05-26'));
      expect(r.timeWindowLabel, 'All day');
    });

    test('window: has return time', () {
      final r = CustodyRequest.fromRecord({
        'id': 'c2',
        'from_parent': 'Jana',
        'to_parent': 'Bennet',
        'date': '2026-05-25',
        'child_name': 'All',
        'pickup_time': '16:00',
        'return_time': '19:00',
        'status': 'pending',
      });
      expect(r.isDayTransfer, false);
      expect(r.isAccepted, false);
      expect(r.timeWindowLabel, '16:00–19:00');
      expect(r.statusLabel, 'Pending');
    });

    test('TBD return time is not a day transfer', () {
      final r = CustodyRequest.fromRecord({
        'id': 'c3',
        'from_parent': 'Jana',
        'to_parent': 'Bennet',
        'date': '2026-05-25',
        'child_name': 'All',
        'pickup_time': '16:00',
        'return_time': '',
        'return_time_tbd': true,
        'status': 'accepted',
      });
      expect(r.isDayTransfer, false);
      expect(r.timeWindowLabel, '16:00–TBD');
    });
  });

  group('groupRequests', () {
    test('collapses swap legs into one group sorted by date', () {
      final requests = [
        CustodyRequest.fromRecord(requestRecord('solo', '2026-10-01')),
        CustodyRequest.fromRecord(requestRecord('leg2', '2026-10-11', to: 'Jana', swapGroup: 'g1')),
        CustodyRequest.fromRecord(requestRecord('leg1', '2026-10-04', swapGroup: 'g1')),
      ];
      final groups = groupRequests(requests);
      expect(groups.length, 2);
      expect(groups[0].isSwap, isFalse);
      expect(groups[1].isSwap, isTrue);
      expect(groups[1].key, 'g1');
      expect(groups[1].legs.map((r) => r.id), ['leg1', 'leg2']);
      expect(groups[1].legTo('Jana')?.id, 'leg2');
    });

    test('a swap stays pending until every leg is answered', () {
      final groups = groupRequests([
        CustodyRequest.fromRecord(requestRecord('a', '2026-10-04', status: 'accepted', swapGroup: 'g')),
        CustodyRequest.fromRecord(requestRecord('b', '2026-10-11', swapGroup: 'g')),
      ]);
      expect(groups.single.status, CustodyStatus.pending);
    });
  });

  group('ManualOverride.fromRecord', () {
    test('explicit is_adhoc true', () {
      final o = ManualOverride.fromRecord({
        'id': 'o1',
        'target_date': '2026-06-01',
        'child_name': 'All',
        'assigned_parent': 'Bennet',
        'is_adhoc': true,
        'activity': 'Birthday',
        'location': 'Park',
        'reason': 'Birthday',
      });
      expect(o.isAdhoc, true);
      expect(o.isExam, false);
      expect(o.adhocActivity, 'Birthday');
      expect(o.adhocLocation, 'Park');
    });

    test('exam kind', () {
      final o = ManualOverride.fromRecord({
        'id': 'o4',
        'target_date': '2026-10-20',
        'child_name': 'Henri',
        'assigned_parent': 'Bennet',
        'is_adhoc': true,
        'activity': 'Maths P1',
        'reason': 'Maths P1',
        'kind': 'exam',
      });
      expect(o.isExam, true);
    });

    test('missing is_adhoc but non-empty reason → treated as adhoc', () {
      final o = ManualOverride.fromRecord({
        'id': 'o2',
        'target_date': '2026-06-01',
        'child_name': 'All',
        'assigned_parent': 'Bennet',
        'reason': 'Koor',
      });
      expect(o.isAdhoc, true);
    });

    test('missing is_adhoc and empty reason → parent substitution', () {
      final o = ManualOverride.fromRecord({
        'id': 'o3',
        'target_date': '2026-06-01',
        'child_name': 'All',
        'assigned_parent': 'Bennet',
        'reason': '',
      });
      expect(o.isAdhoc, false);
    });
  });

  group('Need.fromRecord', () {
    test('parses a claimed item with defaults', () {
      final n = Need.fromRecord({
        'id': 'n1',
        'household': 'h1',
        'title': 'Tennis racket',
        'child_name': '',
        'note': '',
        'needed_by': '2026-10-01',
        'status': 'claimed',
        'claimed_by': 'uJana',
        'expense': '',
        'created_by': 'uBennet',
        'created': '2026-09-11 08:00:00.000Z',
      });
      expect(n.childName, 'All');
      expect(n.note, isNull);
      expect(n.isClaimed, isTrue);
      expect(n.isBought, isFalse);
      expect(n.neededBy, DateTime(2026, 10, 1));
      expect(n.expenseId, isNull);
    });
  });

  group('HouseholdConfig', () {
    final config = HouseholdConfig.fromRecord(
      {
        'id': 'h1',
        'name': 'Test Home',
        'rotation_anchor': '2026-05-18',
        'rotation_parent_even': 'uBennet',
        'rotation_parent_odd': 'uJana',
        'mode': 'custody',
        'rotation_scheme_type': '2-2-5-5',
      },
      members: [
        const HouseholdMember(
            id: 'm1',
            householdId: 'h1',
            userId: 'uBennet',
            role: 'parent',
            displayName: 'Bennet'),
        const HouseholdMember(
            id: 'm2',
            householdId: 'h1',
            userId: 'uJana',
            role: 'parent',
            displayName: 'Jana'),
        const HouseholdMember(
            id: 'm3',
            householdId: 'h1',
            userId: 'uGran',
            role: 'helper',
            displayName: 'Gran'),
      ],
      children: [
        const HouseholdChild(id: 'k1', householdId: 'h1', name: 'Henri'),
        const HouseholdChild(id: 'k2', householdId: 'h1', name: 'Chris'),
      ],
    );

    test('resolves rotation parent display names from member user ids', () {
      expect(config.rotationParentEvenName, 'Bennet');
      expect(config.rotationParentOddName, 'Jana');
    });

    test('separates parents and helpers', () {
      expect(config.parents.map((m) => m.displayName), ['Bennet', 'Jana']);
      expect(config.helpers.map((m) => m.displayName), ['Gran']);
    });

    test('childDropdownItems lists children then All', () {
      expect(config.childDropdownItems, ['Henri', 'Chris', 'All']);
    });

    test('parses rotation scheme type and anchor date', () {
      expect(config.rotationScheme.type, '2-2-5-5');
      expect(config.rotationAnchorDate, DateTime(2026, 5, 18));
    });

    test('memberByName / memberByUserId lookups', () {
      expect(config.memberByName('Jana')?.userId, 'uJana');
      expect(config.memberByUserId('uGran')?.displayName, 'Gran');
      expect(config.memberByName('Nobody'), isNull);
    });
  });

  group('AppColors', () {
    const colors = AppColors(
      parentColors: {'Bennet': Color(0xFF1565C0), 'Jana': Color(0xFFD81B60)},
      childColors: {'Henri': Color(0xFFE65100)},
    );

    test('parent colour lookup with Both and unknown fallback', () {
      expect(colors.parentColor('Bennet'), const Color(0xFF1565C0));
      expect(colors.parentColor('Both'), const Color(0xFF7E57C2));
      expect(colors.parentColor('Ghost'), isNotNull); // falls back, no throw
    });

    test('child colour and specificity', () {
      expect(colors.isChildSpecific('Henri'), true);
      expect(colors.isChildSpecific('All'), false);
      expect(colors.childColor('Henri'), const Color(0xFFE65100));
    });
  });
}
