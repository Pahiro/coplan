import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/shared_expense.dart';
import '../providers/expense_provider.dart';
import 'expense_form_screen.dart';
import 'expense_detail_screen.dart';

class ExpensesScreen extends ConsumerWidget {
  const ExpensesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expensesAsync = ref.watch(expensesProvider);

    return Scaffold(
      body: expensesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error loading expenses: $e')),
        data: (expenses) {
          final active  = expenses.where((e) => e.active).toList();
          final settled = expenses.where((e) => !e.active).toList();

          if (expenses.isEmpty) {
            return RefreshIndicator(
              onRefresh: () async => ref.invalidate(expensesProvider),
              child: ListView(
                children: const [
                  SizedBox(height: 120),
                  Center(
                    child: Column(
                      children: [
                        Icon(Icons.account_balance_wallet_outlined,
                            size: 48, color: Colors.grey),
                        SizedBox(height: 12),
                        Text('No shared expenses yet.',
                            style: TextStyle(color: Colors.grey)),
                        SizedBox(height: 4),
                        Text('Tap + to add one.',
                            style: TextStyle(color: Colors.grey, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(expensesProvider),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
              children: [
                if (active.isNotEmpty) ...[
                  _SectionHeader('Active (${active.length})'),
                  ...active.map((e) => _ExpenseTile(expense: e)),
                ],
                if (settled.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _SectionHeader('Settled (${settled.length})'),
                  ...settled.map((e) => _ExpenseTile(expense: e)),
                ],
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'expense_fab',
        tooltip: 'Add expense',
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ExpenseFormScreen()),
        ),
        child: const Icon(Icons.add),
      ),
    );
  }
}

// ── Section header ───────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader(this.label);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(label,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.bold)),
      );
}

// ── Expense tile ─────────────────────────────────────────────────────────────

class _ExpenseTile extends StatelessWidget {
  final SharedExpense expense;
  const _ExpenseTile({required this.expense});

  static const _categoryIcons = {
    'education': Icons.school,
    'sport':     Icons.sports_soccer,
    'medical':   Icons.local_hospital,
    'clothing':  Icons.checkroom,
    'other':     Icons.receipt_long,
  };

  @override
  Widget build(BuildContext context) {
    final icon = _categoryIcons[expense.category] ?? Icons.receipt_long;
    final cs = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: cs.primaryContainer,
          child: Icon(icon, color: cs.onPrimaryContainer, size: 20),
        ),
        title: Text(expense.title),
        subtitle: Text(
          [
            expense.formattedAmount,
            if (expense.isRecurring) expense.recurrence ?? 'recurring',
            if (expense.childName != 'All') expense.childName,
          ].join(' · '),
          style: const TextStyle(fontSize: 12),
        ),
        trailing: expense.active
            ? null
            : const Icon(Icons.check_circle, color: Colors.green, size: 20),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => ExpenseDetailScreen(expense: expense)),
        ),
      ),
    );
  }
}
