import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/expense_categories.dart';
import '../models/shared_expense.dart';
import '../providers/expense_provider.dart';
import '../providers/household_provider.dart';
import 'expense_detail_screen.dart';
import 'expense_form_screen.dart';

/// Settle-up dialog: clears every unpaid split in both directions so one net
/// payment settles the slate. Exposed so the app bar (shell) can offer it.
void showSettleUpDialog(BuildContext context, WidgetRef ref) {
  final summary =
      ref.read(expenseSummaryProvider).valueOrNull ?? const ExpenseSummary();

  if (summary.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Nothing outstanding to settle.')),
    );
    return;
  }

  final net = summary.netCents;
  final netLine = net == 0
      ? 'Both sides owe the same — settling clears everything.'
      : net > 0
          ? 'Net: you are owed ${summary.netFormatted}.'
          : 'Net: you owe ${summary.netFormatted}.';

  final refCtrl = TextEditingController();
  final noteCtrl = TextEditingController();

  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Settle Up'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Marks every outstanding split — in both directions — as paid. '
            '$netLine',
            style: const TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: refCtrl,
            decoration: const InputDecoration(
              labelText: 'Payment reference',
              hintText: 'e.g. EFT ref',
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: noteCtrl,
            decoration: const InputDecoration(
              labelText: 'Note (optional)',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () async {
            Navigator.pop(ctx);
            final result = await ref.read(expensesProvider.notifier).settleUpAll(
                  reference: refCtrl.text.trim(),
                  note: noteCtrl.text.trim(),
                );
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                      'Settled ${result.count} split${result.count == 1 ? '' : 's'}'),
                ),
              );
            }
          },
          child: const Text('Settle All'),
        ),
      ],
    ),
  );
}

class ExpensesScreen extends ConsumerStatefulWidget {
  const ExpensesScreen({super.key});

  @override
  ConsumerState<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends ConsumerState<ExpensesScreen> {
  String? _categoryFilter;
  String? _childFilter;

  @override
  Widget build(BuildContext context) {
    final expensesAsync = ref.watch(expensesProvider);
    final children = ref.watch(householdProvider).valueOrNull?.children ?? [];

    return Scaffold(
      body: Column(
        children: [
          // Filter chips
          _FilterBar(
            category: _categoryFilter,
            child: _childFilter,
            childNames: children.map((c) => c.name).toList(),
            onCategoryChanged: (v) => setState(() => _categoryFilter = v),
            onChildChanged: (v) => setState(() => _childFilter = v),
          ),
          Expanded(
            child: expensesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error loading expenses: $e')),
              data: (expenses) {
                // Apply filters
                var filtered = expenses.toList();
                if (_categoryFilter != null) {
                  filtered = filtered.where((e) => e.category == _categoryFilter).toList();
                }
                if (_childFilter != null) {
                  filtered = filtered.where((e) => e.childName == _childFilter).toList();
                }

                final active  = filtered.where((e) => e.active).toList();
                final settled = filtered.where((e) => !e.active).toList();

                if (filtered.isEmpty) {
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
          ),
        ],
      ),
      // Export and settle-up live in the app bar (see _MainShell) — a single
      // FAB keeps the primary action obvious.
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: cs.primaryContainer,
          child: Icon(ExpenseCategory.iconFor(expense.category),
              color: cs.onPrimaryContainer, size: 20),
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
              builder: (_) => ExpenseDetailScreen(expenseId: expense.id)),
        ),
      ),
    );
  }
}

// ── Filter bar ───────────────────────────────────────────────────────────────

class _FilterBar extends StatelessWidget {
  final String? category;
  final String? child;
  final List<String> childNames;
  final ValueChanged<String?> onCategoryChanged;
  final ValueChanged<String?> onChildChanged;

  const _FilterBar({
    required this.category,
    required this.child,
    required this.childNames,
    required this.onCategoryChanged,
    required this.onChildChanged,
  });

  @override
  Widget build(BuildContext context) {
    final hasFilters = category != null || child != null;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          if (hasFilters)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ActionChip(
                avatar: const Icon(Icons.clear, size: 16),
                label: const Text('Clear'),
                onPressed: () {
                  onCategoryChanged(null);
                  onChildChanged(null);
                },
              ),
            ),
          ...ExpenseCategory.all.map((c) => Padding(
                padding: const EdgeInsets.only(right: 6),
                child: FilterChip(
                  label: Text(c.label),
                  selected: category == c.id,
                  onSelected: (sel) => onCategoryChanged(sel ? c.id : null),
                ),
              )),
          ...childNames.map((name) => Padding(
                padding: const EdgeInsets.only(right: 6),
                child: FilterChip(
                  avatar: const Icon(Icons.child_care, size: 16),
                  label: Text(name),
                  selected: child == name,
                  onSelected: (sel) => onChildChanged(sel ? name : null),
                ),
              )),
        ],
      ),
    );
  }
}
