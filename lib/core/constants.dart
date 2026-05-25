class AppConstants {
  AppConstants._();

  // ── Server ──────────────────────────────────────────────────────────────────
  /// Override at build/run time with --dart-define=PB_URL=https://…
  /// Defaults to localhost for local development.
  static const String pbUrl = String.fromEnvironment(
    'PB_URL',
    defaultValue: 'http://localhost:8090',
  );

  /// Base URL of your ntfy instance.
  static const String ntfyBaseUrl = String.fromEnvironment(
    'NTFY_URL',
    defaultValue: 'https://ntfy.yourserver.com',
  );

  // ── People ──────────────────────────────────────────────────────────────────
  static const String parentBennet = 'Bennet';
  static const String parentJana = 'Jana';

  // ── Rotation anchor ─────────────────────────────────────────────────────────
  /// The Monday of a known *Bennet's week*, as "YYYY-MM-DD".
  /// Set at build time: --dart-define=ROTATION_ANCHOR=2026-05-18
  /// Default is 2026-05-18 — update to any Monday Bennet had the kids.
  static final DateTime rotationAnchor = _parseAnchor(
    const String.fromEnvironment(
      'ROTATION_ANCHOR',
      defaultValue: '2026-05-18',
    ),
  );

  static DateTime _parseAnchor(String s) {
    final p = s.split('-');
    return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
  }

  // ── Android widget ──────────────────────────────────────────────────────────
  static const String widgetCacheKey = 'coplan_widget_events';
  static const String widgetAppId = 'com.coplan.app';
  static const String widgetName = 'CoplanWidget';
}
