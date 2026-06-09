import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/pb_client.dart';
import '../models/expense_split.dart';
import '../models/shared_expense.dart';
import 'auth_provider.dart';
import 'household_provider.dart';

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

  String get youOweFormatted => 'R ${(youOwe / 100).toStringAsFixed(2)}';
  String get owedToYouFormatted => 'R ${(owedToYou / 100).toStringAsFixed(2)}';
  bool get isEmpty => youOwe == 0 && owedToYou == 0;
}

final expenseSummaryProvider = FutureProvider<ExpenseSummary>((ref) async {
  final auth = ref.watch(authProvider).valueOrNull;
  if (auth == null || !auth.isLoggedIn) return const ExpenseSummary();
  final myId = auth.userId ?? '';
  if (myId.isEmpty) return const ExpenseSummary();

  try {
    // Fetch all pending/overdue splits in this household
    final splits = await pb.collection('expense_splits').getFullList(
      filter: 'status != "paid"',
    );

    int youOwe = 0;
    int owedToYou = 0;
    int overdueCount = 0;

    for (final r in splits) {
      final json = r.toJson();
      final split = ExpenseSplit.fromRecord(json);
      if (split.user == myId) {
        // I owe this
        youOwe += split.amountDue;
        if (split.isOverdue) overdueCount++;
      } else {
        // Fetch the expense to check if I'm the payer
        // (owedToYou = splits where I paid the vendor and someone else owes)
        try {
          final expense = await pb.collection('shared_expenses').getOne(split.expense);
          if (expense.data['paid_by'] == myId) {
            owedToYou += split.amountDue;
          }
        } catch (_) {}
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
      final now = DateTime.now();
      final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
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

  /// Create a new expense with a single split (100% to the other parent).
  Future<void> createExpense({
    required String title,
    String? description,
    required int amount,
    String childName = 'All',
    String? category,
    bool isRecurring = false,
    String? recurrence,
    int? dueDay,
    DateTime? nextDueDate,
    DateTime? startDate,
    DateTime? endDate,
    required String splitToUserId,
  }) async {
    final auth = ref.read(authProvider).valueOrNull;
    final household = ref.read(householdProvider).valueOrNull;
    if (auth == null || household == null) return;

    final myId = auth.userId ?? '';
    final householdId = household.id;

    // Create the expense
    final expenseRecord = await pb.collection('shared_expenses').create(body: {
      'household':    householdId,
      'title':        title,
      'description':  description ?? '',
      'child_name':   childName,
      'amount':       amount,
      'currency':     'ZAR',
      'category':     category ?? 'other',
      'is_recurring': isRecurring,
      'recurrence':   recurrence ?? '',
      'due_day':      dueDay,
      'next_due_date': nextDueDate != null ? _isoDate(nextDueDate) : '',
      'start_date':   startDate != null ? _isoDate(startDate) : '',
      'end_date':     endDate != null ? _isoDate(endDate) : '',
      'paid_by':      myId,
      'active':       true,
      'created_by':   myId,
    });

    // Create split — 100% to the other parent
    await pb.collection('expense_splits').create(body: {
      'expense':     expenseRecord.id,
      'household':   householdId,
      'user':        splitToUserId,
      'split_type':  'percentage',
      'split_value': 100,
      'amount_due':  amount,
      'status':      'pending',
      'due_date':    nextDueDate != null ? _isoDate(nextDueDate) : '',
    });

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
    bool isRecurring = false,
    String? recurrence,
    int? dueDay,
    DateTime? nextDueDate,
  }) async {
    // Get old amount to check if splits need recalculating
    final old = await pb.collection('shared_expenses').getOne(expenseId);
    final oldAmount = (old.data['amount'] as num?)?.toInt() ?? 0;

    await pb.collection('shared_expenses').update(expenseId, body: {
      'title':        title,
      'description':  description ?? '',
      'child_name':   childName,
      'amount':       amount,
      'category':     category ?? 'other',
      'is_recurring': isRecurring,
      'recurrence':   recurrence ?? '',
      'due_day':      dueDay,
      'next_due_date': nextDueDate != null ? _isoDate(nextDueDate) : '',
    });

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
      'paid_date':         _isoDate(DateTime.now()),
      'payment_reference': reference ?? '',
      'payment_note':      note ?? '',
    });
    ref.invalidateSelf();
    ref.invalidate(expenseSummaryProvider);
  }

  /// Settle up: mark all pending/overdue splits for a given user as paid.
  /// Returns the number of splits settled and total amount.
  Future<({int count, int totalCents})> settleUp({
    required String userId,
    String? reference,
    String? note,
  }) async {
    final splits = await pb.collection('expense_splits').getFullList(
      filter: 'user = "$userId" && status != "paid"',
    );
    int total = 0;
    for (final s in splits) {
      total += (s.data['amount_due'] as num?)?.toInt() ?? 0;
      await pb.collection('expense_splits').update(s.id, body: {
        'status':            'paid',
        'paid_date':         _isoDate(DateTime.now()),
        'payment_reference': reference ?? '',
        'payment_note':      note ?? '',
      });
    }
    ref.invalidateSelf();
    ref.invalidate(expenseSummaryProvider);
    return (count: splits.length, totalCents: total);
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

  static String _isoDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
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
