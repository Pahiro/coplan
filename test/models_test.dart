import 'package:flutter/material.dart' show Color;
import 'package:flutter_test/flutter_test.dart';

import 'package:coplan/models/app_colors.dart';
import 'package:coplan/models/base_rule.dart';
import 'package:coplan/models/custody_request.dart';
import 'package:coplan/models/household.dart';
import 'package:coplan/models/manual_override.dart';
import 'package:coplan/models/recurring_arrangement.dart';
import 'package:coplan/models/weekday_rule.dart';

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
      expect(r.timeWindowLabel, '17:30 onwards');
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

  group('RecurringArrangement', () {
    test('toVirtualRequest builds an accepted day transfer with synthetic id', () {
      final a = RecurringArrangement(
        id: 'arr1',
        dayOfWeek: 2,
        toParent: 'Bennet',
        childName: 'All',
        pickupTime: '17:30',
        startDate: DateTime(2026, 5, 26),
      );
      final v = a.toVirtualRequest(DateTime(2026, 6, 9), fromParent: 'Jana');
      expect(v.id, 'recurring:arr1:2026-06-09');
      expect(v.fromParent, 'Jana');
      expect(v.toParent, 'Bennet');
      expect(v.isAccepted, true);
      expect(v.isDayTransfer, true);
    });

    test('recurringIdFrom extracts the arrangement id', () {
      expect(RecurringArrangement.recurringIdFrom('recurring:arr1:2026-06-09'),
          'arr1');
      expect(RecurringArrangement.recurringIdFrom('abc123'), isNull);
    });
  });

  group('ManualOverride.fromRecord adhoc inference', () {
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
      expect(o.adhocActivity, 'Birthday');
      expect(o.adhocLocation, 'Park');
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

  group('WeekdayRule.fromRecord', () {
    test('parses and defaults active', () {
      final w = WeekdayRule.fromRecord({
        'id': 'w1',
        'day_of_week': 3,
        'assigned_parent': 'Jana',
      });
      expect(w.dayOfWeek, 3);
      expect(w.assignedParent, 'Jana');
      expect(w.active, true);
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
