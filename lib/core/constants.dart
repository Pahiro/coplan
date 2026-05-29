class AppConstants {
  AppConstants._();

  // ── Server ──────────────────────────────────────────────────────────────────
  /// Build-time default for PocketBase URL.  At runtime, the user-configured
  /// URL from SharedPreferences is used instead (see pb_client.dart).
  static const String pbUrl = String.fromEnvironment(
    'PB_URL',
    defaultValue: 'http://localhost:8090',
  );

  /// Base URL of your ntfy instance.
  static const String ntfyBaseUrl = String.fromEnvironment(
    'NTFY_URL',
    defaultValue: 'https://ntfy.yourserver.com',
  );

  // ── People (legacy fallback only) ──────────────────────────────────────────
  static const String parentBennet = 'Bennet';
  static const String parentJana = 'Jana';

  // ── Android widget ──────────────────────────────────────────────────────────
  static const String widgetCacheKey = 'coplan_widget_events';
  static const String widgetAppId = 'com.coplan.app';
  static const String widgetName = 'CoplanWidget';

  /// AppWidget provider (Glance receiver) class names for all three widget
  /// styles. Updating the cache must redraw every placed style, so we broadcast
  /// an update to each — not just style 1.
  static const List<String> widgetReceivers = [
    'CoplanWidgetReceiver',
    'CoplanWidget2Receiver',
    'CoplanWidget3Receiver',
  ];
}
