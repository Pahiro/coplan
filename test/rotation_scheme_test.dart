import 'package:flutter_test/flutter_test.dart';
import 'package:coplan/models/rotation_scheme.dart';

void main() {
  group('RotationScheme.ownerIndex', () {
    test('weekly: first 7 days are even, next 7 are odd', () {
      final s = RotationScheme.weekly();
      for (var d = 0; d < 7; d++) {
        expect(s.ownerIndex(d), 0, reason: 'day $d should be parentEven');
      }
      for (var d = 7; d < 14; d++) {
        expect(s.ownerIndex(d), 1, reason: 'day $d should be parentOdd');
      }
      // Wraps after the 14-day cycle.
      expect(s.ownerIndex(14), 0);
      expect(s.ownerIndex(21), 1);
    });

    test('handles negative offsets (dates before the anchor)', () {
      final s = RotationScheme.weekly();
      // -7 → index 7 → parentOdd; -1 → index 13 → parentOdd; -14 → index 0.
      expect(s.ownerIndex(-7), 1);
      expect(s.ownerIndex(-1), 1);
      expect(s.ownerIndex(-14), 0);
      expect(s.ownerIndex(-8), 0); // index 6
    });

    test('ownerAtDay maps index to the right display name', () {
      final s = RotationScheme.weekly();
      expect(s.ownerAtDay(0, 'Alice', 'Bob'), 'Alice');
      expect(s.ownerAtDay(7, 'Alice', 'Bob'), 'Bob');
    });
  });

  group('preset patterns', () {
    test('2-2-5-5 sums to a balanced 14-day cycle', () {
      final s = RotationScheme.twoTwoFiveFive();
      expect(s.cycleLength, 14);
      final even = s.pattern.where((v) => v == 0).length;
      final odd = s.pattern.where((v) => v == 1).length;
      expect(even, 7);
      expect(odd, 7);
    });

    test('2-2-3 is a 14-day cycle', () {
      final s = RotationScheme.twoTwoThree();
      expect(s.cycleLength, 14);
      expect(s.type, '2-2-3');
    });

    test('alternating weekends only differs on the second weekend', () {
      final s = RotationScheme.alternatingWeekends();
      // Indices 12,13 (second weekend) are the only odd days.
      expect(s.pattern[12], 1);
      expect(s.pattern[13], 1);
      expect(s.pattern.where((v) => v == 1).length, 2);
    });
  });

  group('fromJson', () {
    test('reconstructs known types', () {
      expect(RotationScheme.fromJson('weekly', null).type, 'weekly');
      expect(RotationScheme.fromJson('2-2-5-5', null).type, '2-2-5-5');
      expect(RotationScheme.fromJson('2-2-3', null).type, '2-2-3');
      expect(RotationScheme.fromJson('alternating_weekends', null).type,
          'alternating_weekends');
    });

    test('custom uses the supplied pattern', () {
      final s = RotationScheme.fromJson('custom', [0, 1, 0]);
      expect(s.type, 'custom');
      expect(s.pattern, [0, 1, 0]);
    });

    test('custom with empty pattern falls back to weekly pattern', () {
      final s = RotationScheme.custom([]);
      expect(s.pattern.length, 14);
    });

    test('unknown type falls back to weekly', () {
      expect(RotationScheme.fromJson('nonsense', null).type, 'weekly');
    });
  });
}
