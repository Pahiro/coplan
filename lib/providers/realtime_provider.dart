import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/pb_client.dart';
import 'auth_provider.dart';
import 'custody_provider.dart';
import 'expense_provider.dart';
import 'schedule_provider.dart';

/// Watching this provider opens PocketBase SSE subscriptions for
/// [custody_requests] and [expense_splits] while the app is open.
///
/// OS / heads-up notifications are delivered server-side via FCM (see
/// [PushService] + pb_hooks), so they work even when the app is closed and
/// there are no duplicates. This subscription's only remaining job is to keep
/// the in-app data fresh in real time while the app is in the foreground —
/// it invalidates the relevant caches when records change.
final realtimeNotificationsProvider = Provider<void>((ref) {
  final auth = ref.watch(authProvider).valueOrNull;
  if (auth == null || !auth.isLoggedIn || auth.userId == null) return;

  pb
      .collection('custody_requests')
      .subscribe('*', (e) {
        if (e.record == null) return;
        ref.invalidate(custodyRequestsProvider);
        ref.invalidate(dashboardProvider);
      })
      .catchError((_) => () async {});

  pb
      .collection('expense_splits')
      .subscribe('*', (e) {
        if (e.record == null) return;
        ref.invalidate(expensesProvider);
        ref.invalidate(expenseSummaryProvider);
      })
      .catchError((_) => () async {});

  ref.onDispose(() {
    pb.collection('custody_requests').unsubscribe('*').catchError((_) => () async {});
    pb.collection('expense_splits').unsubscribe('*').catchError((_) => () async {});
  });
});
