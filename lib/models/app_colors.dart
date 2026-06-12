import 'package:flutter/material.dart';

/// Runtime colours for the app — now data-driven from household members
/// and children. Falls back to defaults for unknown names.
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
}
