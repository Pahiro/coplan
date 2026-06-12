import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/pb_client.dart';
import '../services/notification_service.dart';
import 'auth_provider.dart';
import 'custody_provider.dart';
import 'expense_provider.dart';
import 'schedule_provider.dart';

/// Watching this provider opens PocketBase SSE subscriptions for
/// [custody_requests] and [expense_splits]. Fires in-app notifications and
/// invalidates caches when events arrive.
final realtimeNotificationsProvider = Provider<void>((ref) {
  final auth = ref.watch(authProvider).valueOrNull;
  if (auth == null || !auth.isLoggedIn || auth.userId == null) return;

  final myId = auth.userId!;

  pb
      .collection('custody_requests')
      .subscribe('*', (e) {
        final record = e.record;
        if (record == null) return;

        // Use the record id to give each notification its own slot so
        // simultaneous notifications don't overwrite each other.
        final notifId = record.id.hashCode.abs() % 10000;

        if (e.action == 'create') {
          final requestedFrom = record.data['requested_from'] as String?;
          if (requestedFrom != myId) return;

          final fromParent       = record.data['from_parent']      as String? ?? '';
          final toParent         = record.data['to_parent']        as String? ?? '';
          final child            = record.data['child_name']       as String? ?? 'the children';
          final date             = record.data['date']             as String? ?? 'an upcoming date';
          final rtEmpty          = (record.data['return_time']     as String? ?? '').isEmpty;
          final rtTbd            = (record.data['return_time_tbd'] as bool?) ?? false;
          final isDayXfer        = rtEmpty && !rtTbd;
          final toParentCollects = (record.data['to_parent_collects'] as bool?) ?? true;
          final childStr         = child == 'All' ? 'the kids' : child;

          final pickupAction = toParentCollects
              ? '$toParent collects $childStr'
              : '$fromParent drops off $childStr';

          NotificationService.show(
            title: isDayXfer ? 'Custody Request' : 'Handover Requested',
            body:  '$pickupAction on $date${isDayXfer ? '' : ' (return expected)'}',
            id:    notifId,
          );
          ref.invalidate(custodyRequestsProvider);
        } else if (e.action == 'update') {
          final createdBy = record.data['created_by'] as String?;
          if (createdBy != myId) return;

          final status = record.data['status'] as String?;
          if (status == null || status == 'pending') return;

          final child = record.data['child_name'] as String? ?? 'the children';
          final date  = record.data['date']       as String? ?? 'an upcoming date';
          final whom  = child == 'All' ? 'the kids' : child;

          final msg = switch (status) {
            'accepted'  => 'Your $whom request for $date was accepted',
            'declined'  => 'Your $whom request for $date was declined',
            'completed' => 'Handover for $whom on $date marked complete',
            _           => null,
          };
          if (msg == null) return;

          NotificationService.show(
            title: 'Request ${status[0].toUpperCase()}${status.substring(1)}',
            body:  msg,
            id:    notifId,
          );
          ref.invalidate(custodyRequestsProvider);
          ref.invalidate(dashboardProvider);
        }
      })
      .catchError((_) => () async {});

  // ── Expense activity ────────────────────────────────────────────────────────
  // Created split directed at me → "you owe"; my split marked paid → receipt.
  pb
      .collection('expense_splits')
      .subscribe('*', (e) async {
        final record = e.record;
        if (record == null) return;

        // Any expense change is worth refreshing the lists for.
        ref.invalidate(expensesProvider);
        ref.invalidate(expenseSummaryProvider);

        final splitUser = record.data['user'] as String?;
        if (splitUser != myId) return;

        final amountDue = (record.data['amount_due'] as num?)?.toInt() ?? 0;
        final amountStr = 'R ${(amountDue / 100).toStringAsFixed(2)}';
        final notifId = record.id.hashCode.abs() % 10000 + 10000;

        String title = 'a shared expense';
        try {
          final expenseId = record.data['expense'] as String? ?? '';
          if (expenseId.isNotEmpty) {
            final expense =
                await pb.collection('shared_expenses').getOne(expenseId);
            title = expense.data['title'] as String? ?? title;
          }
        } catch (_) {}

        if (e.action == 'create') {
          NotificationService.show(
            title: 'New shared expense',
            body:  '$title — your share is $amountStr',
            id:    notifId,
          );
        } else if (e.action == 'update' &&
            record.data['status'] == 'paid') {
          NotificationService.show(
            title: 'Payment recorded',
            body:  'Your $amountStr share of $title was marked paid',
            id:    notifId,
          );
        }
      })
      .catchError((_) => () async {});

  ref.onDispose(() {
    pb.collection('custody_requests').unsubscribe('*').catchError((_) => () async {});
    pb.collection('expense_splits').unsubscribe('*').catchError((_) => () async {});
  });
});
