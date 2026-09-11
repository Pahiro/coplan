import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/pb_client.dart';
import '../services/widget_cache_service.dart';
import 'absence_provider.dart';
import 'auth_provider.dart';
import 'custody_provider.dart';
import 'expense_provider.dart';
import 'holiday_provider.dart';
import 'household_provider.dart';
import 'needs_provider.dart';
import 'schedule_provider.dart';

/// Watching this provider opens PocketBase realtime (SSE) subscriptions for
/// every collection the app shows, so changes made by the other parent appear
/// while the app is open.
///
/// OS notifications are delivered server-side via FCM (see PushService and
/// pb_hooks); this subscription only keeps in-app data fresh. Anything missed
/// while the connection was down is picked up by the refresh on app resume.
final realtimeNotificationsProvider = Provider<void>((ref) {
  final auth = ref.watch(authProvider).valueOrNull;
  if (auth == null || !auth.isLoggedIn || auth.userId == null) return;

  final watched = <String, List<ProviderOrFamily>>{
    'custody_requests': [custodyRequestsProvider, acceptedCustodyProvider],
    'manual_overrides': [manualOverridesProvider],
    'rules_base':       [baseRulesProvider],
    'holiday_blocks':   [holidayBlocksProvider],
    'absence_periods':  [absencePeriodsProvider],
    'households':       [householdProvider],
    'household_members': [householdProvider],
    'children':         [householdProvider],
    'expense_splits':   [expensesProvider, expenseSummaryProvider, expenseSplitsProvider],
    'shared_expenses':  [expensesProvider, expenseSummaryProvider],
    'needs':            [needsProvider],
  };
  const affectsWidget = {
    'custody_requests', 'manual_overrides', 'rules_base', 'holiday_blocks',
    'absence_periods', 'households', 'household_members',
  };

  for (final entry in watched.entries) {
    pb.collection(entry.key).subscribe('*', (e) {
      for (final p in entry.value) {
        ref.invalidate(p);
      }
      if (affectsWidget.contains(entry.key)) WidgetCacheService.updateSoon();
    }).catchError((_) => () async {});
  }

  ref.onDispose(() {
    for (final name in watched.keys) {
      pb.collection(name).unsubscribe('*').catchError((_) {});
    }
  });
});
