import 'package:flutter/material.dart';

import 'household.dart';

/// Runtime colours for the app — data-driven from household members and
/// children. Falls back to defaults for unknown names.
class AppColors {
  /// Map of parent display name → colour.
  final Map<String, Color> _parentColors;
  /// Map of child name → colour.
  final Map<String, Color> _childColors;

  const AppColors({
    Map<String, Color> parentColors = const {},
    Map<String, Color> childColors  = const {},
  }) : _parentColors = parentColors,
       _childColors  = childColors;

  /// Default member colours: blue, pink, teal, amber.
  static const palette = [
    Color(0xFF1565C0),
    Color(0xFFD81B60),
    Color(0xFF00897B),
    Color(0xFFFF8F00),
  ];

  /// Colours for [household]: each member's preferred colour, else blue for the
  /// even rotation parent, pink for the odd one, else the palette in member
  /// order. The Kotlin widget worker mirrors this.
  factory AppColors.forHousehold(HouseholdConfig? household) {
    if (household == null) return const AppColors();
    final parents = <String, Color>{};
    for (final m in household.members) {
      parents[m.displayName] = _parseHex(m.preferredColor) ??
          (m.userId == household.rotationParentEvenId
              ? palette[0]
              : m.userId == household.rotationParentOddId
                  ? palette[1]
                  : palette[parents.length % palette.length]);
    }
    return AppColors(
      parentColors: parents,
      childColors: {
        for (final c in household.children)
          c.name: _parseHex(c.color) ?? Colors.grey,
      },
    );
  }

  /// Accent colour for a parent by display name.
  /// "Both" returns a neutral purple for shared-mode days.
  Color parentColor(String parentName) {
    if (parentName == 'Both') return const Color(0xFF7E57C2); // purple 400
    return _parentColors[parentName] ?? Colors.blueGrey;
  }

  /// Soft background tint for a parent.
  Color parentLightColor(String parentName) =>
      parentColor(parentName).withValues(alpha: 0.15);

  /// Colour for a named child. Returns grey for 'All' / unknown.
  Color childColor(String childName) =>
      _childColors[childName] ?? Colors.grey;

  Color childLightColor(String childName) =>
      childColor(childName).withValues(alpha: 0.18);

  /// True when the child name is a known specific child (not 'All').
  bool isChildSpecific(String childName) =>
      _childColors.containsKey(childName);

  /// All known parent display names.
  Iterable<String> get parentNames => _parentColors.keys;

  static Color? _parseHex(String? s) {
    if (s == null || !s.startsWith('#') || s.length != 7) return null;
    final value = int.tryParse('FF${s.substring(1)}', radix: 16);
    return value == null ? null : Color(value);
  }
}
