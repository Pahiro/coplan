/// Defines rotation custody patterns.
///
/// A rotation scheme is a repeating day-pattern relative to an anchor date.
/// Given a date, compute `daysSinceAnchor % pattern.length` → index → owner.
/// Pattern values: 0 = parentEven, 1 = parentOdd.
class RotationScheme {
  final String type;
  final List<int> pattern;

  const RotationScheme({required this.type, required this.pattern});

  /// Returns the owner index (0 or 1) for a given number of days since anchor.
  /// Handles negative offsets (dates before anchor) correctly.
  int ownerIndex(int daysSinceAnchor) {
    final len = pattern.length;
    final idx = ((daysSinceAnchor % len) + len) % len;
    return pattern[idx];
  }

  /// Resolves to the parent display name.
  String ownerAtDay(int daysSinceAnchor, String parentEven, String parentOdd) =>
      ownerIndex(daysSinceAnchor) == 0 ? parentEven : parentOdd;

  /// Standard weekly alternating (current default): 7 days A, 7 days B.
  factory RotationScheme.weekly() => const RotationScheme(
        type: 'weekly',
        pattern: [0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1],
      );

  /// 2-2-5-5: 2 days A, 2 days B, 5 days A, 5 days B (14-day cycle).
  /// Common in many jurisdictions as a balanced schedule.
  factory RotationScheme.twoTwoFiveFive() => const RotationScheme(
        type: '2-2-5-5',
        pattern: [0, 0, 1, 1, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1],
      );

  /// 2-2-3: Alternates 2-2-3 then swaps. 14-day total cycle.
  /// Week 1: A(2) B(2) A(3), Week 2: B(2) A(2) B(3).
  factory RotationScheme.twoTwoThree() => const RotationScheme(
        type: '2-2-3',
        pattern: [0, 0, 1, 1, 0, 0, 0, 1, 1, 0, 0, 1, 1, 1],
      );

  /// Alternating weekends: Mon-Fri follow weekday rules (engine skips rotation
  /// for those), Sat-Sun alternate every week. 14-day cycle for weekends.
  /// Pattern encodes ONLY the weekend days for a 2-week block.
  /// Usage: engine uses weekday rules Mon-Fri; only calls rotation for Sat/Sun.
  factory RotationScheme.alternatingWeekends() => const RotationScheme(
        type: 'alternating_weekends',
        // Full 14-day pattern: Mon-Sun week1, Mon-Sun week2.
        // Weekdays are "neutral" (0) — the engine uses weekday rules for them.
        // Only Sat(idx 5) and Sun(idx 6) matter: week1=A, week2=B.
        pattern: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1],
      );

  /// User-defined custom pattern.
  factory RotationScheme.custom(List<int> pattern) => RotationScheme(
        type: 'custom',
        pattern: pattern.isEmpty ? [0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1] : pattern,
      );

  /// Reconstruct from stored type + pattern.
  factory RotationScheme.fromJson(String type, List<int>? pattern) {
    switch (type) {
      case 'weekly':
        return RotationScheme.weekly();
      case '2-2-5-5':
        return RotationScheme.twoTwoFiveFive();
      case '2-2-3':
        return RotationScheme.twoTwoThree();
      case 'alternating_weekends':
        return RotationScheme.alternatingWeekends();
      case 'custom':
        return RotationScheme.custom(pattern ?? []);
      default:
        return RotationScheme.weekly();
    }
  }

  /// Cycle length in days.
  int get cycleLength => pattern.length;

  /// Human-readable label.
  String get label => switch (type) {
        'weekly'               => 'Weekly (7/7)',
        '2-2-5-5'             => '2-2-5-5',
        '2-2-3'               => '2-2-3',
        'alternating_weekends' => 'Alternating weekends',
        'custom'               => 'Custom',
        _                      => type,
      };

  /// Short description of the pattern.
  String get description => switch (type) {
        'weekly'               => 'One full week each, alternating',
        '2-2-5-5'             => '2 days, 2 days, 5 days — then swap',
        '2-2-3'               => '2 days, 2 days, 3 days — then swap',
        'alternating_weekends' => 'Weekdays by rules, weekends alternate',
        'custom'               => '${pattern.length}-day custom cycle',
        _                      => '',
      };
}
