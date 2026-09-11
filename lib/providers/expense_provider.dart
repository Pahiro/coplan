import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:pocketbase/pocketbase.dart';

import '../core/pb_client.dart';
import '../models/expense_split.dart';
import '../models/shared_expense.dart';
import '../services/queue_service.dart';
import '../utils/dates.dart';
import '../utils/ids.dart';
import 'auth_provider.dart';
import 'household_provider.dart';
import 'queue_count_provider.dart';

// ── Summary (dashboard card) ─────────────────────────────────────────────────

/// Quick summary of what the current user owes and is owed.
class ExpenseSummary {
  final int youOwe;       // cents
  final int owedToYou;    // cents
  final int overdueCount;

  const ExpenseSummary({
    this.youOwe = 0,
    this.owedToYou = 0,
    this.overdueCount = 0,
  });

  /// Positive: the other parent owes you on balance. Negative: you owe.
  int get netCents => owedToYou - youOwe;

  String get youOweFormatted => _rand(youOwe);
  String get owedToYouFormatted => _rand(owedToYou);
  String get netFormatted => _rand(netCents.abs());
  bool get isEmpty => youOwe == 0 && owedToYou == 0;

  /// Only the parent who is owed on balance confirms a settle-up.
  bool get canSettle => !isEmpty && netCents >= 0;

  static String _rand(int cents) => 'R ${(cents / 100).toStringAsFixed(2)}';
}

final expenseSummaryProvider = FutureProvider<ExpenseSummary>((ref) async {
  final auth = ref.watch(authProvider).valueOrNull;
  if (auth == null || !auth.isLoggedIn) return const ExpenseSummary();
  final myId = auth.userId ?? '';
  if (myId.isEmpty) return const ExpenseSummary();

  try {
    final splitRecords = await pb.collection('expense_splits').getFullList(
      filter: 'status != "paid"',
    );
    final expenseRecords =
        await pb.collection('shared_expenses').getFullList();
    final paidByByExpense = {
      for (final r in expenseRecords) r.id: r.data['paid_by'] as String? ?? '',
    };

    int youOwe = 0;
    int owedToYou = 0;
    int overdueCount = 0;

    for (final r in splitRecords) {
      final split = ExpenseSplit.fromRecord(r.toJson());
      if (split.user == myId) {
        youOwe += split.amountDue;
        if (split.isOverdue) overdueCount++;
      } else if (paidByByExpense[split.expense] == myId) {
        owedToYou += split.amountDue;
      }
    }

    return ExpenseSummary(
      youOwe: youOwe,
      owedToYou: owedToYou,
      overdueCount: overdueCount,
    );
  } catch (_) {
    return const ExpenseSummary();
  }
});

// ── Expenses list ────────────────────────────────────────────────────────────

final expensesProvider =
    AsyncNotifierProvider<ExpensesNotifier, List<SharedExpense>>(
  ExpensesNotifier.new,
);

class ExpensesNotifier extends AsyncNotifier<List<SharedExpense>> {
  @override
  Future<List<SharedExpense>> build() async {
    ref.watch(authProvider);
    // Overdue marking runs server-side in the daily cron.
    final records = await pb.collection('shared_expenses').getFullList(
      sort: '-created',
    );
    return records
        .map((r) => SharedExpense.fromRecord(r.toJson()))
        .toList();
  }

  /// Create a new expense with a single split to the other parent. Returns the
  /// new expense id, or null when it was queued offline.
  ///
  /// Offline, the expense+split is queued as one logical op (client-generated
  /// ids make the replay safe). The receipt photo is only attached online.
  Future<String?> createExpense({
    required String title,
    String? description,
    required int amount,
    String childName = 'All',
    String? category,
    String? beneficiary,
    bool isRecurring = false,
    String? recurrence,
    int? dueDay,
    DateTime? nextDueDate,
    DateTime? startDate,
    DateTime? endDate,
    required String splitToUserId,
    int splitPercent = 100,
    http.MultipartFile? receipt,
  }) async {
    final auth = ref.read(authProvider).valueOrNull;
    final household = ref.read(householdProvider).valueOrNull;
    if (auth == null || household == null) {
      throw Exception('No active household yet — please try again in a moment.');
    }

    final myId = auth.userId ?? '';
    final expenseId = newRecordId();

    final expenseBody = {
      'id':           expenseId,
      'household':    household.id,
      'title':        title,
      'description':  description ?? '',
      'child_name':   childName,
      'amount':       amount,
      'currency':     'ZAR',
      'category':     category ?? 'other',
      'beneficiary':  beneficiary ?? '',
      'is_recurring': isRecurring,
      'recurrence':   recurrence ?? '',
      'due_day':      dueDay,
      'next_due_date': nextDueDate != null ? isoDate(nextDueDate) : '',
      'start_date':   startDate != null ? isoDate(startDate) : '',
      'end_date':     endDate != null ? isoDate(endDate) : '',
      'paid_by':      myId,
      'active':       true,
      'created_by':   myId,
    };
    final splitBody = {
      'id':          newRecordId(),
      'household':   household.id,
      'user':        splitToUserId,
      'split_type':  'percentage',
      'split_value': splitPercent,
      'amount_due':  (amount * splitPercent / 100).round(),
      'status':      'pending',
      'due_date':    nextDueDate != null ? isoDate(nextDueDate) : '',
    };

    var expenseCreated = false;
    try {
      await pb.collection('shared_expenses').create(
        body: expenseBody,
        files: receipt != null ? [receipt] : const [],
      );
      expenseCreated = true;
      await pb.collection('expense_splits').create(
          body: {...splitBody, 'expense': expenseId});
    } catch (e) {
      if (isNetworkError(e)) {
        await QueueService.enqueue(PendingOp(
          id:         QueueService.newOpId(),
          collection: 'shared_expenses',
          method:     'create',
          body:       expenseBody,
          splitBody:  splitBody,
        ));
        ref.read(pendingOpsCountProvider.notifier).state =
            await QueueService.pendingCount();
        return null;
      }
      // Never leave an expense without its split.
      if (expenseCreated) {
        try {
          await pb.collection('shared_expenses').delete(expenseId);
        } catch (_) {}
      }
      rethrow;
    }

    ref.invalidateSelf();
    ref.invalidate(expenseSummaryProvider);
    return expenseId;
  }

  /// Update an existing expense. Recalculates unpaid splits if amount changed.
  Future<void> updateExpense({
    required String expenseId,
    required String title,
    String? description,
    required int amount,
    String childName = 'All',
    String? category,
    String? beneficiary,
    bool isRecurring = false,
    String? recurrence,
    int? dueDay,
    DateTime? nextDueDate,
    DateTime? endDate,
    http.MultipartFile? receipt,
  }) async {
    final old = await pb.collection('shared_expenses').getOne(expenseId);
    final oldAmount = (old.data['amount'] as num?)?.toInt() ?? 0;
    final oldDueDay = (old.data['due_day'] as num?)?.toInt();
    final oldRecurrence = old.data['recurrence'] as String? ?? '';

    // Only move next_due_date when the schedule itself changed; recomputing it
    // on every edit could re-create a split the cron already generated.
    final scheduleChanged = isRecurring &&
        (dueDay != oldDueDay || (recurrence ?? '') != oldRecurrence ||
            (old.data['next_due_date'] as String? ?? '').isEmpty);

    await pb.collection('shared_expenses').update(
      expenseId,
      body: {
        'title':        title,
        'description':  description ?? '',
        'child_name':   childName,
        'amount':       amount,
        'category':     category ?? 'other',
        'beneficiary':  beneficiary ?? '',
        'is_recurring': isRecurring,
        'recurrence':   recurrence ?? '',
        'due_day':      dueDay,
        if (!isRecurring) 'next_due_date': '',
        if (scheduleChanged)
          'next_due_date': nextDueDate != null ? isoDate(nextDueDate) : '',
        'end_date':     endDate != null ? isoDate(endDate) : '',
      },
      files: receipt != null ? [receipt] : const [],
    );

    if (amount != oldAmount) {
      final splits = await pb.collection('expense_splits').getFullList(
        filter: 'expense = "$expenseId" && status != "paid"',
      );
      for (final s in splits) {
        final splitType  = s.data['split_type'] as String? ?? 'percentage';
        final splitValue = (s.data['split_value'] as num?)?.toDouble() ?? 100;
        final newDue = splitType == 'percentage'
            ? (amount * splitValue / 100).round()
            : splitValue.toInt();
        await pb.collection('expense_splits').update(s.id, body: {
          'amount_due': newDue,
        });
      }
    }

    ref.invalidateSelf();
    ref.invalidate(expenseSummaryProvider);
  }

  /// Confirm a split was paid (payer only — the server enforces it).
  Future<void> markSplitPaid(String splitId, {String? reference, String? note}) async {
    await pb.collection('expense_splits').update(splitId, body: {
      'status':            'paid',
      'paid_date':         isoDate(DateTime.now()),
      'payment_reference': reference ?? '',
      'payment_note':      note ?? '',
    });
    ref.invalidateSelf();
    ref.invalidate(expenseSummaryProvider);
    ref.invalidate(expenseSplitsProvider);
  }

  /// Clears every unpaid split between the current user and the other parent
  /// in both directions. Only the parent who is owed on balance may confirm
  /// it; the server checks and notifies the other parent.
  Future<({int count, int netCents})> settleUp({
    String? reference,
    String? note,
  }) async {
    final hid = ref.read(householdProvider).valueOrNull?.id;
    if (hid == null) throw Exception('No active household.');
    try {
      final res = await pb.send(
        '/api/coplan/settle-up',
        method: 'POST',
        body: {'household': hid, 'reference': reference ?? '', 'note': note ?? ''},
      );
      ref.invalidateSelf();
      ref.invalidate(expenseSummaryProvider);
      return (
        count: (res['count'] as num?)?.toInt() ?? 0,
        netCents: (res['netCents'] as num?)?.toInt() ?? 0,
      );
    } on ClientException catch (e) {
      final message = e.response['message'];
      if (e.statusCode == 403 && message is String && message.isNotEmpty) {
        throw Exception(message);
      }
      rethrow;
    }
  }

  /// Delete an expense and its splits.
  Future<void> deleteExpense(String expenseId) async {
    final splits = await pb.collection('expense_splits').getFullList(
      filter: 'expense = "$expenseId"',
    );
    for (final s in splits) {
      await pb.collection('expense_splits').delete(s.id);
    }
    await pb.collection('shared_expenses').delete(expenseId);
    ref.invalidateSelf();
    ref.invalidate(expenseSummaryProvider);
  }
}

// ── Splits for a specific expense ────────────────────────────────────────────

final expenseSplitsProvider =
    FutureProvider.family<List<ExpenseSplit>, String>((ref, expenseId) async {
  final records = await pb.collection('expense_splits').getFullList(
    filter: 'expense = "$expenseId"',
    sort: '-created',
  );
  return records
      .map((r) => ExpenseSplit.fromRecord(r.toJson()))
      .toList();
});
