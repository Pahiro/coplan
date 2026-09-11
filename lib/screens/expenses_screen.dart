import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/expense_categories.dart';
import '../models/shared_expense.dart';
import '../providers/expense_provider.dart';
import '../providers/household_provider.dart';
import '../providers/navigation_provider.dart';
import '../widgets/common.dart';
import '../widgets/need_sheet.dart';
import '../widgets/skeleton.dart';
import 'expense_detail_screen.dart';
import 'expense_form_screen.dart';
import 'needs_view.dart';

/// Settle up: the parent who is owed on balance confirms they've been paid,
/// which clears every outstanding split between the two of you. The parent
/// who owes is told how it works instead (they can't clear their own debt).
Future<void> showSettleUpDialog(BuildContext context, WidgetRef ref) async {
  final summary =
      ref.read(expenseSummaryProvider).valueOrNull ?? const ExpenseSummary();
  final other = ref.read(coParentProvider)?.displayName ?? 'your co-parent';
  final messenger = ScaffoldMessenger.of(context);

  if (summary.isEmpty) {
    messenger.showSnackBar(
        const SnackBar(content: Text('Nothing outstanding to settle.')));
    return;
  }

  if (!summary.canSettle) {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Settle up'),
        content: Text(
            'You owe ${summary.netFormatted} on balance. Once you\'ve paid, '
            '$other confirms it and everything between you is cleared.'),
        actions: [
          FilledButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
    return;
  }

  final refCtrl = TextEditingController();
  final noteCtrl = TextEditingController();
  final even = summary.netCents == 0;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Settle up'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(even
              ? 'You and $other owe each other the same. Settling clears '
                'everything outstanding.'
              : 'Confirm that $other has paid you ${summary.netFormatted}. '
                'This clears every outstanding expense between you, in both '
                'directions.'),
          const SizedBox(height: 12),
          TextField(
            controller: refCtrl,
            decoration: const InputDecoration(
              labelText: 'Payment reference (optional)',
              hintText: 'e.g. EFT ref',
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: noteCtrl,
            decoration: const InputDecoration(labelText: 'Note (optional)'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(even ? 'Settle' : 'Confirm received'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;

  try {
    final result = await ref.read(expensesProvider.notifier).settleUp(
          reference: refCtrl.text.trim(),
          note: noteCtrl.text.trim(),
        );
    messenger.showSnackBar(SnackBar(
        content: Text(
            'Settled ${result.count} split${result.count == 1 ? '' : 's'}')));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
  }
}

/// The money tab: the shared "to buy" list and the expenses it turns into.
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
    final view = ref.watch(expensesViewProvider);
    final toBuy = view == ExpensesView.toBuy;

    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<ExpensesView>(
                segments: const [
                  ButtonSegment(
                    value: ExpensesView.toBuy,
                    icon: Icon(Icons.shopping_bag_outlined),
                    label: Text('To buy'),
                  ),
                  ButtonSegment(
                    value: ExpensesView.expenses,
                    icon: Icon(Icons.receipt_long_outlined),
                    label: Text('Expenses'),
                  ),
                ],
                selected: {view},
                onSelectionChanged: (s) =>
                    ref.read(expensesViewProvider.notifier).state = s.first,
                style: SegmentedButton.styleFrom(
                    visualDensity: VisualDensity.compact),
              ),
            ),
          ),
          Expanded(child: toBuy ? const NeedsView() : _buildExpenses(context)),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'expense_fab',
        tooltip: toBuy ? 'Add to the list' : 'Add expense',
        onPressed: () => toBuy
            ? showAppSheet<void>(context, builder: (_) => const NeedSheet())
            : Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ExpenseFormScreen()),
              ),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildExpenses(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final expensesAsync = ref.watch(expensesProvider);
    final children = ref.watch(householdProvider).valueOrNull?.children ?? [];

    Future<void> refresh() async {
      ref.invalidate(expensesProvider);
      ref.invalidate(expenseSummaryProvider);
    }

    return Column(
      children: [
        _FilterBar(
          category: _categoryFilter,
          child: _childFilter,
          childNames: children.map((c) => c.name).toList(),
          onCategoryChanged: (v) => setState(() => _categoryFilter = v),
          onChildChanged: (v) => setState(() => _childFilter = v),
        ),
        Expanded(
          child: expensesAsync.when(
            skipLoadingOnReload: true,
            loading: () => const SkeletonList(count: 6, itemHeight: 72),
            error: (e, _) => Center(child: Text(friendlyError(e))),
            data: (expenses) {
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
                  onRefresh: refresh,
                  child: ListView(
                    children: [
                      const SizedBox(height: 120),
                      Icon(Icons.account_balance_wallet_outlined,
                          size: 48, color: cs.onSurfaceVariant),
                      const SizedBox(height: 12),
                      Text('No shared expenses yet.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: cs.onSurfaceVariant)),
                      const SizedBox(height: 4),
                      Text('Tap + to add one.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                    ],
                  ),
                );
              }

              return RefreshIndicator(
                onRefresh: refresh,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
                  children: [
                    if (active.isNotEmpty) ...[
                      _SectionHeader('Active (${active.length})'),
                      ...active.map((e) => _ExpenseTile(expense: e)),
                    ],
                    if (settled.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _SectionHeader('Ended (${settled.length})'),
                      ...settled.map((e) => _ExpenseTile(expense: e)),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ],
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

    // Container transform: the tile itself expands into the detail screen.
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: OpenContainer(
        transitionDuration: const Duration(milliseconds: 350),
        closedElevation: 1,
        closedColor: cs.surfaceContainerLow,
        closedShape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        openBuilder: (_, __) => ExpenseDetailScreen(expenseId: expense.id),
        closedBuilder: (_, open) => ListTile(
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
              : Icon(Icons.check_circle, color: cs.onSurfaceVariant, size: 20),
          onTap: open,
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
