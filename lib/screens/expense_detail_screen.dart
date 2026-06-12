import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../core/expense_categories.dart';
import '../core/pb_client.dart';
import '../models/expense_split.dart';
import '../models/shared_expense.dart';
import '../providers/auth_provider.dart';
import '../providers/expense_provider.dart';
import '../providers/household_provider.dart';
import '../providers/payment_details_provider.dart';
import '../widgets/common.dart';
import 'expense_form_screen.dart';

/// Detail view for one expense. Watches the expenses provider (rather than
/// holding a snapshot) so edits made from the pencil icon show immediately.
class ExpenseDetailScreen extends ConsumerWidget {
  final String expenseId;
  const ExpenseDetailScreen({super.key, required this.expenseId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expensesAsync = ref.watch(expensesProvider);
    final household     = ref.watch(householdProvider).valueOrNull;
    final myId          = ref.watch(authProvider).valueOrNull?.userId ?? '';
    final cs            = Theme.of(context).colorScheme;

    final expense = expensesAsync.valueOrNull
        ?.firstWhereOrNull((e) => e.id == expenseId);

    if (expense == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Expense Details')),
        body: expensesAsync.isLoading
            ? const Center(child: CircularProgressIndicator())
            : const Center(
                child: Text('This expense no longer exists.',
                    style: TextStyle(color: Colors.grey))),
      );
    }

    final splitsAsync = ref.watch(expenseSplitsProvider(expense.id));

    String userName(String userId) {
      final member = household?.members
          .where((m) => m.userId == userId)
          .firstOrNull;
      return member?.displayName ?? 'Unknown';
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Expense Details'),
        actions: [
          if (expense.createdBy == myId)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => ExpenseFormScreen(existing: expense)),
              ),
            ),
          if (expense.createdBy == myId)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete',
              onPressed: () => _confirmDelete(context, ref, expense),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Header card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(expense.title,
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text(expense.formattedAmount,
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            color: cs.primary,
                            fontWeight: FontWeight.bold,
                          )),
                  const SizedBox(height: 12),
                  _DetailRow(
                      ExpenseCategory.iconFor(expense.category),
                      expense.category ?? 'Other'),
                  if (expense.childName != 'All')
                    _DetailRow(Icons.child_care, expense.childName),
                  if (expense.isRecurring)
                    _DetailRow(Icons.repeat,
                        '${expense.recurrence ?? "Recurring"} · Day ${expense.dueDay ?? "-"}'),
                  if (expense.description?.isNotEmpty == true)
                    _DetailRow(Icons.notes, expense.description!),
                  _DetailRow(Icons.person, 'Paid by ${userName(expense.paidBy ?? '')}'),
                  _DetailRow(Icons.calendar_today,
                      'Created ${DateFormat.yMMMd().format(expense.created)}'),
                ],
              ),
            ),
          ),

          // Receipt photo
          if (expense.receipt != null) _ReceiptCard(expense: expense),

          const SizedBox(height: 16),
          Text('Splits',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),

          // Splits
          splitsAsync.when(
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('Error loading splits: $e'),
            data: (splits) {
              if (splits.isEmpty) {
                return const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No splits found.',
                        style: TextStyle(color: Colors.grey)),
                  ),
                );
              }
              return Column(
                children: splits.map((s) => _SplitCard(
                  split: s,
                  userName: userName(s.user),
                  canMarkPaid: expense.paidBy == myId && !s.isPaid,
                  onMarkPaid: () => _markPaid(context, ref, s),
                )).toList(),
              );
            },
          ),

          // Payee banking details (shown to the owing parent)
          if (expense.paidBy != null && expense.paidBy != myId)
            _PayeeDetailsCard(userId: expense.paidBy!),
        ],
      ),
    );
  }

  void _markPaid(BuildContext context, WidgetRef ref, ExpenseSplit split) {
    showDialog(
      context: context,
      builder: (ctx) {
        final refCtrl = TextEditingController();
        final noteCtrl = TextEditingController();
        return AlertDialog(
          title: const Text('Mark as Paid'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: refCtrl,
                decoration: const InputDecoration(
                    labelText: 'Reference (optional)',
                    hintText: 'e.g. EFT ref'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: noteCtrl,
                decoration: const InputDecoration(
                    labelText: 'Note (optional)'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                ref.read(expensesProvider.notifier).markSplitPaid(
                      split.id,
                      reference: refCtrl.text.trim(),
                      note: noteCtrl.text.trim(),
                    );
              },
              child: const Text('Confirm'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, SharedExpense expense) async {
    final ok = await confirmDialog(
      context,
      title: 'Delete Expense',
      body: 'Delete "${expense.title}" and all its splits?',
      action: 'Delete',
      destructive: true,
    );
    if (ok && context.mounted) {
      await ref.read(expensesProvider.notifier).deleteExpense(expense.id);
      if (context.mounted) Navigator.pop(context);
    }
  }
}

// ── Receipt photo card ───────────────────────────────────────────────────────

class _ReceiptCard extends StatelessWidget {
  final SharedExpense expense;
  const _ReceiptCard({required this.expense});

  String get _url =>
      '${pb.baseURL}/api/files/shared_expenses/${expense.id}/${expense.receipt}';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => showDialog<void>(
            context: context,
            builder: (_) => Dialog(
              child: InteractiveViewer(
                child: Image.network(_url, fit: BoxFit.contain),
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Image.network(
                '$_url?thumb=600x0',
                height: 160,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
              const Padding(
                padding: EdgeInsets.all(10),
                child: Row(
                  children: [
                    Icon(Icons.receipt_long, size: 16, color: Colors.grey),
                    SizedBox(width: 6),
                    Text('Receipt — tap to view',
                        style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Helper widgets ───────────────────────────────────────────────────────────

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _DetailRow(this.icon, this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Icon(icon, size: 16, color: Colors.grey),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
          ],
        ),
      );
}

class _SplitCard extends StatelessWidget {
  final ExpenseSplit split;
  final String userName;
  final bool canMarkPaid;
  final VoidCallback onMarkPaid;

  const _SplitCard({
    required this.split,
    required this.userName,
    required this.canMarkPaid,
    required this.onMarkPaid,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Color statusColor;
    IconData statusIcon;
    switch (split.status) {
      case SplitStatus.paid:
        statusColor = Colors.green;
        statusIcon  = Icons.check_circle;
      case SplitStatus.overdue:
        statusColor = cs.error;
        statusIcon  = Icons.warning;
      case SplitStatus.pending:
        statusColor = Colors.orange;
        statusIcon  = Icons.schedule;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(statusIcon, color: statusColor, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(userName,
                      style: const TextStyle(fontWeight: FontWeight.w500)),
                  Text(
                    '${split.formattedAmount} · ${split.status.name}',
                    style: TextStyle(fontSize: 12, color: statusColor),
                  ),
                  if (split.paymentReference?.isNotEmpty == true)
                    Text('Ref: ${split.paymentReference}',
                        style: const TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ),
            ),
            if (canMarkPaid)
              TextButton(
                onPressed: onMarkPaid,
                child: const Text('Mark paid'),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Payee banking details card ───────────────────────────────────────────────

class _PayeeDetailsCard extends ConsumerWidget {
  final String userId;
  const _PayeeDetailsCard({required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailsAsync = ref.watch(userPaymentDetailsProvider(userId));

    return detailsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (details) {
        if (details == null || !details.hasDetails) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Payment Info',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (details.bankName?.isNotEmpty == true) ...[
                        _DetailRow(Icons.account_balance, details.bankName!),
                        if (details.accountHolder?.isNotEmpty == true)
                          _DetailRow(Icons.person, details.accountHolder!),
                        if (details.accountNumber?.isNotEmpty == true)
                          _DetailRow(Icons.numbers, details.maskedAccountNumber),
                        if (details.branchCode?.isNotEmpty == true)
                          _DetailRow(Icons.tag, 'Branch: ${details.branchCode}'),
                      ],
                      if (details.paymentLink?.isNotEmpty == true)
                        _DetailRow(Icons.link, details.paymentLink!),
                      if (details.paymentReference?.isNotEmpty == true)
                        _DetailRow(Icons.receipt, 'Ref: ${details.paymentReference}'),
                      if (details.notes?.isNotEmpty == true)
                        _DetailRow(Icons.notes, details.notes!),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
