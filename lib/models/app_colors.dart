import 'package:flutter/material.dart';

import '../models/resolved_event.dart';

/// Holds the four runtime colours for the app.
/// Defaults are applied when PocketBase hasn't been reached yet.
class AppColors {
  final Color bennetColor;
  final Color janaColor;
  final Color henriColor;
  final Color chrisColor;

  const AppColors({
    this.bennetColor = const Color(0xFF1565C0), // blue
    this.janaColor   = const Color(0xFFD81B60), // pink
    this.henriColor  = const Color(0xFFE65100), // deep orange
    this.chrisColor  = const Color(0xFF00695C), // teal
  });

  Color parentColor(Parent p) =>
      p == Parent.bennet ? bennetColor : janaColor;

  Color parentLightColor(Parent p) =>
      parentColor(p).withOpacity(0.15);

  /// Colour for a named child. Returns grey for 'All' / unknown.
  Color childColor(String childName) => switch (childName) {
        'Henri' => henriColor,
        'Chris' => chrisColor,
        _       => Colors.grey,
      };

  Color childLightColor(String childName) =>
      childColor(childName).withOpacity(0.18);

  /// True when the event is for a single known child (not shared).
  bool isChildSpecific(String childName) =>
      childName == 'Henri' || childName == 'Chris';
}
