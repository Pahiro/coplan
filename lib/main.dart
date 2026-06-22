import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/constants.dart';
import 'core/pb_client.dart';
import 'providers/invite_provider.dart';
import 'providers/queue_count_provider.dart';
import 'services/notification_service.dart';
import 'services/offline_cache.dart';
import 'services/push_service.dart';
import 'services/queue_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  await initPocketBase(prefs);
  await OfflineCache.init();
  await NotificationService.init();
  await PushService.init();
  final initialQueueCount = await QueueService.pendingCount();

  if (!kIsWeb) {
    HomeWidget.registerInteractivityCallback(widgetBackgroundCallback);
    HomeWidget.setAppGroupId(AppConstants.widgetAppId);
  }

  // Read invite code from URL (web) or initial deep link (Android).
  final initialInviteCode = _extractInviteCode(
    kIsWeb ? Uri.base : await _initialAndroidLink(),
  );

  final container = ProviderContainer(
    overrides: [
      pendingOpsCountProvider.overrideWith((ref) => initialQueueCount),
      if (initialInviteCode != null)
        pendingInviteProvider.overrideWith((ref) => initialInviteCode),
    ],
  );

  // On Android, also listen for links that arrive while the app is running.
  if (!kIsWeb) {
    AppLinks().uriLinkStream.listen((uri) {
      final code = _extractInviteCode(uri);
      if (code != null) {
        container.read(pendingInviteProvider.notifier).state = code;
      }
    });
  }

  runApp(UncontrolledProviderScope(
    container: container,
    child: const CoplanApp(),
  ));
}

/// Returns the invite code from `?invite=` query param, or null.
String? _extractInviteCode(Uri? uri) {
  if (uri == null) return null;
  final code = uri.queryParameters['invite'];
  return (code != null && code.isNotEmpty) ? code.toUpperCase() : null;
}

/// Returns the URI that launched the app on Android, or null.
Future<Uri?> _initialAndroidLink() async {
  try {
    return await AppLinks().getInitialLink();
  } catch (_) {
    return null;
  }
}

/// Called when user interacts with the home-screen widget while app is stopped.
@pragma('vm:entry-point')
Future<void> widgetBackgroundCallback(Uri? uri) async {
  // Future: handle deep-link action URIs from widget taps
}
