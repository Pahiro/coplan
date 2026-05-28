import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/constants.dart';
import 'core/pb_client.dart';
import 'providers/queue_count_provider.dart';
import 'services/notification_service.dart';
import 'services/queue_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  await initPocketBase(prefs);
  await NotificationService.init();
  final initialQueueCount = await QueueService.pendingCount();

  if (!kIsWeb) {
    HomeWidget.registerBackgroundCallback(widgetBackgroundCallback);
    HomeWidget.setAppGroupId(AppConstants.widgetAppId);
  }

  runApp(ProviderScope(
    overrides: [
      // Seed the queue count from SharedPreferences before first frame
      pendingOpsCountProvider.overrideWith((ref) => initialQueueCount),
    ],
    child: const CoplanApp(),
  ));
}

/// Called when user interacts with the home-screen widget while app is stopped.
@pragma('vm:entry-point')
Future<void> widgetBackgroundCallback(Uri? uri) async {
  // Future: handle deep-link action URIs from widget taps
}
