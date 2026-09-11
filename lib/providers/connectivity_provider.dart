import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/pb_client.dart';
import '../services/queue_service.dart';
import 'queue_count_provider.dart';
import 'refresh.dart';

export 'queue_count_provider.dart' show pendingOpsCountProvider;

/// Watch this provider at the root shell to keep the watcher alive.
/// Flushes queued ops automatically when connectivity is restored and
/// re-fetches app data so the UI reflects the synced state.
final connectivityWatcherProvider = Provider<void>((ref) {
  bool? lastOnline;

  final sub = Connectivity().onConnectivityChanged.listen((results) async {
    final isOnline = results.any((r) => r != ConnectivityResult.none);

    if (lastOnline == false && isOnline) {
      await QueueService.flush(pb);
      refreshAppData(ref.invalidate);
    }

    lastOnline = isOnline;

    final count = await QueueService.pendingCount();
    ref.read(pendingOpsCountProvider.notifier).state = count;
  });

  ref.onDispose(sub.cancel);
});
