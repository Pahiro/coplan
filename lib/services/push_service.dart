import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../core/pb_client.dart';
import 'notification_service.dart';

/// Background isolate handler. Required by firebase_messaging to be a top-level
/// (or static) function annotated with @pragma('vm:entry-point').
///
/// Our pushes are "notification" messages, so the Android system displays them
/// automatically when the app is backgrounded/killed — there's nothing to do
/// here. It exists so data-only messages (future use) don't get dropped.
@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  // Intentionally empty — system handles notification display.
}

/// True background push via FCM. FCM is the single source of OS notifications:
///   • App foreground → the system doesn't auto-display, so [onMessage] renders
///     the notification (banner + heads-up) itself.
///   • App background/killed → the FCM "notification" message is shown by the
///     Android system automatically.
///
/// The SSE path ([realtimeNotificationsProvider]) no longer shows notifications
/// (avoids duplicates); it only refreshes in-app data while the app is open.
///
/// The server (pb_hooks/main.pb.js) is what actually sends these, looking up
/// the tokens this service registers in the `device_tokens` collection.
class PushService {
  PushService._();

  static bool _initialised = false;

  /// Call once at startup (after Firebase is available). No-op on web/desktop.
  static Future<void> init() async {
    if (kIsWeb || _initialised) return;
    _initialised = true;
    try {
      await Firebase.initializeApp();
      await FirebaseMessaging.instance.requestPermission();

      FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);

      // Foreground: the system only auto-displays notification messages when
      // the app is backgrounded, so render foreground ones ourselves. FCM is
      // the single source of OS notifications (no SSE duplication), which also
      // means foreground delivery no longer depends on the SSE connection.
      FirebaseMessaging.onMessage.listen((message) {
        final n = message.notification;
        if (n == null) return;
        NotificationService.show(
          title: n.title ?? 'CoPlan',
          body: n.body ?? '',
          id: (message.messageId ?? n.title ?? '').hashCode.abs() % 100000,
        );
      });

      // Token rotation → re-register against the currently logged-in user.
      FirebaseMessaging.instance.onTokenRefresh.listen((token) {
        final uid = pb.authStore.record?.id;
        if (uid != null && uid.isNotEmpty) _upsert(uid, token);
      });
    } catch (e) {
      if (kDebugMode) debugPrint('PushService.init failed: $e');
    }
  }

  /// Register (or refresh) this device's FCM token for [userId]. Safe to call
  /// repeatedly — it upserts on the unique token.
  static Future<void> registerForUser(String userId) async {
    if (kIsWeb || userId.isEmpty) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) return;
      await _upsert(userId, token);
    } catch (e) {
      if (kDebugMode) debugPrint('PushService.registerForUser failed: $e');
    }
  }

  /// Remove this device's token (call on logout) so a signed-out phone stops
  /// receiving the previous user's pushes.
  static Future<void> unregister() async {
    if (kIsWeb) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && token.isNotEmpty) {
        try {
          final existing = await pb
              .collection('device_tokens')
              .getFirstListItem('token = "$token"');
          await pb.collection('device_tokens').delete(existing.id);
        } catch (_) {/* no row — fine */}
      }
      await FirebaseMessaging.instance.deleteToken();
    } catch (e) {
      if (kDebugMode) debugPrint('PushService.unregister failed: $e');
    }
  }

  static Future<void> _upsert(String userId, String token) async {
    final body = {
      'user': userId,
      'token': token,
      'platform': 'android',
      'last_seen': DateTime.now().toUtc().toIso8601String(),
    };
    try {
      // Update the existing row for this token if present (unique index).
      final existing = await pb
          .collection('device_tokens')
          .getFirstListItem('token = "$token"');
      await pb.collection('device_tokens').update(existing.id, body: body);
    } catch (_) {
      // No row yet — create one.
      try {
        await pb.collection('device_tokens').create(body: body);
      } catch (e) {
        if (kDebugMode) debugPrint('PushService._upsert create failed: $e');
      }
    }
  }
}
