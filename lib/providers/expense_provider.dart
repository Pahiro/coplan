import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../core/pb_client.dart';
import '../models/expense_split.dart';
import '../models/shared_expense.dart';
import '../services/queue_service.dart';
import '../utils/dates.dart';
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

  static String _rand(int cents) => 'R ${(cents / 100).toStringAsFixed(2)}';
}

final expenseSummaryProvider = FutureProvider<ExpenseSummary>((ref) async {
  final auth = ref.watch(authProvider).valueOrNull;
  if (auth == null || !auth.isLoggedIn) return const ExpenseSummary();
  final myId = auth.userId ?? '';
  if (myId.isEmpty) return const ExpenseSummary();

  try {
    // One fetch each — previously this did a getOne per split (N+1).
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
  Future<List<SharedExpense>> build() => _fetch();

  Future<List<SharedExpense>> _fetch() async {
    final records = await pb.collection('shared_expenses').getFullList(
      sort: '-created',
    );

    // Auto-detect overdue splits: if due_date < today and still pending, mark overdue
    await _markOverdueSplits();

    return records
        .map((r) => SharedExpense.fromRecord(r.toJson()))
        .toList();
  }

  /// Check all pending splits and mark as overdue if past due date.
  Future<void> _markOverdueSplits() async {
    try {
      final todayStr = isoDate(DateTime.now());
      final pendingSplits = await pb.collection('expense_splits').getFullList(
        filter: 'status = "pending" && due_date != "" && due_date < "$todayStr"',
      );
      for (final s in pendingSplits) {
        await pb.collection('expense_splits').update(s.id, body: {
          'status': 'overdue',
        });
      }
    } catch (_) {
      // Non-critical — silently ignore
    }
  }

  /// Create a new expense with a single split to the other parent.
  /// Works offline: on a network error the expense+split is queued as one
  /// logical op and synced when the connection returns. (The receipt photo
  /// is only attached when online — files can't be queued.)
  Future<void> createExpense({
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
    final householdId = household.id;

    final expenseBody = {
      'household':    householdId,
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
      'household':   householdId,
      'user':        splitToUserId,
      'split_type':  'percentage',
      'split_value': splitPercent,
      'amount_due':  (amount * splitPercent / 100).round(),
      'status':      'pending',
      'due_date':    nextDueDate != null ? isoDate(nextDueDate) : '',
    };

    try {
      final expenseRecord = await pb.collection('shared_expenses').create(
        body: expenseBody,
        files: receipt != null ? [receipt] : const [],
      );
      await pb.collection('expense_splits').create(
          body: {...splitBody, 'expense': expenseRecord.id});
    } catch (e) {
      if (!isNetworkError(e)) rethrow;
      await QueueService.enqueue(PendingOp(
        id:         QueueService.newOpId(),
        collection: 'shared_expenses',
        method:     'create',
        body:       expenseBody,
        splitBody:  splitBody,
      ));
      final count = await QueueService.pendingCount();
      ref.read(pendingOpsCountProvider.notifier).state = count;
      return;
    }

    ref.invalidateSelf();
    ref.invalidate(expenseSummaryProvider);
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
    // Get old amount to check if splits need recalculating
    final old = await pb.collection('shared_expenses').getOne(expenseId);
    final oldAmount = (old.data['amount'] as num?)?.toInt() ?? 0;

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
        'next_due_date': nextDueDate != null ? isoDate(nextDueDate) : '',
        'end_date':     endDate != null ? isoDate(endDate) : '',
      },
      files: receipt != null ? [receipt] : const [],
    );

    // Recalculate unpaid splits if amount changed
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

  /// Mark a split as paid.
  Future<void> markSplitPaid(String splitId, {String? reference, String? note}) async {
    await pb.collection('expense_splits').update(splitId, body: {
      'status':            'paid',
      'paid_date':         isoDate(DateTime.now()),
      'payment_reference': reference ?? '',
      'payment_note':      note ?? '',
    });
    ref.invalidateSelf();
    ref.invalidate(expenseSummaryProvider);
  }

  /// Settle up in both directions: marks every unpaid split in the household
  /// as paid, so a single net payment clears the slate.
  /// Returns the number of splits settled and the net amount (positive =
  /// the other side owed the current user more than vice versa).
  Future<({int count, int netCents})> settleUpAll({
    String? reference,
    String? note,
  }) async {
    final myId = ref.read(authProvider).valueOrNull?.userId ?? '';
    final splits = await pb.collection('expense_splits').getFullList(
      filter: 'status != "paid"',
    );
    int net = 0;
    for (final s in splits) {
      final due = (s.data['amount_due'] as num?)?.toInt() ?? 0;
      final user = s.data['user'] as String? ?? '';
      // Splits owed by me reduce the net in my favour; splits owed by the
      // other side increase it.
      net += user == myId ? -due : due;
      await pb.collection('expense_splits').update(s.id, body: {
        'status':            'paid',
        'paid_date':         isoDate(DateTime.now()),
        'payment_reference': reference ?? '',
        'payment_note':      note ?? '',
      });
    }
    ref.invalidateSelf();
    ref.invalidate(expenseSummaryProvider);
    return (count: splits.length, netCents: net);
  }

  /// Delete an expense and its splits.
  Future<void> deleteExpense(String expenseId) async {
    // Delete associated splits first
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
