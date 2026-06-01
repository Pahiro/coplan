import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Wraps flutter_local_notifications (mobile) and in-app SnackBar (all platforms).
///
/// Usage:
///   1. Call [init] once at startup (before runApp).
///   2. Set [messengerKey] on [MaterialApp.scaffoldMessengerKey].
///   3. Call [show] from anywhere to display a notification.
class NotificationService {
  NotificationService._();

  static final GlobalKey<ScaffoldMessengerState> messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  static final _plugin = FlutterLocalNotificationsPlugin();

  static const _systemChannel = MethodChannel('com.coplan.app/system');

  static const _channel = AndroidNotificationChannel(
    'coplan_requests',
    'Pickup Requests',
    description: 'CoPlan pickup request notifications',
    importance: Importance.high,
  );

  static Future<void> init() async {
    if (kIsWeb) return;

    const androidInit =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    await _plugin.initialize(initSettings);

    // Create the notification channel (Android 8+)
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);

    // Request POST_NOTIFICATIONS permission (Android 13+)
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  /// Show an in-app SnackBar banner (all platforms) and, on Android,
  /// a heads-up OS notification that appears even when the app is backgrounded.
  ///
  /// [id] identifies the notification slot — two calls with the same [id]
  /// replace each other. Derive it from the record id so simultaneous
  /// notifications for different records don't collide.
  static Future<void> show({
    required String title,
    required String body,
    int id = 0,
  }) async {
    // In-app banner — visible when the app is in the foreground
    messengerKey.currentState?.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, color: Colors.white)),
            Text(body, style: const TextStyle(color: Colors.white70)),
          ],
        ),
      ),
    );

    if (kIsWeb) return;

    // OS notification — visible even when backgrounded
    await _plugin.show(
      id,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );
  }

  /// Returns true when Android is still optimising the app's battery (i.e.
  /// the app is NOT exempt, so background notifications may be suppressed).
  static Future<bool> isBatteryOptimized() async {
    if (kIsWeb) return false;
    try {
      return await _systemChannel.invokeMethod<bool>('isBatteryOptimized') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Opens the system dialog that lets the user exempt CoPlan from battery
  /// optimisation, enabling reliable background notifications.
  static Future<void> requestBatteryExemption() async {
    if (kIsWeb) return;
    try {
      await _systemChannel.invokeMethod('requestBatteryExemption');
    } catch (_) {}
  }
}
