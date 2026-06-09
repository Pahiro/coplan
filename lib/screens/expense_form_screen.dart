import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';
import '../providers/expense_provider.dart';
import '../providers/household_provider.dart';

class ExpenseFormScreen extends ConsumerStatefulWidget {
  const ExpenseFormScreen({super.key});

  @override
  ConsumerState<ExpenseFormScreen> createState() => _ExpenseFormScreenState();
}

class _ExpenseFormScreenState extends ConsumerState<ExpenseFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descCtrl  = TextEditingController();
  final _amountCtrl = TextEditingController();

  String _category = 'other';
  String _childName = 'All';
  bool _isRecurring = false;
  String _recurrence = 'monthly';
  int? _dueDay;
  bool _saving = false;

  static const _categories = [
    ('education', 'Education'),
    ('sport',     'Sport'),
    ('medical',   'Medical'),
    ('clothing',  'Clothing'),
    ('other',     'Other'),
  ];

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final household = ref.watch(householdProvider).valueOrNull;
    final myId = ref.watch(authProvider).valueOrNull?.userId ?? '';
    final children = household?.children ?? [];

    // Find the other parent (not me)
    final otherParent = household?.members
        .where((m) => m.isParent && m.userId != myId)
        .firstOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('New Expense')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Title
            TextFormField(
              controller: _titleCtrl,
              decoration: const InputDecoration(
                labelText: 'Title *',
                hintText: 'e.g. Swimming lessons',
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 12),

            // Amount (in rands, converted to cents on save)
            TextFormField(
              controller: _amountCtrl,
              decoration: const InputDecoration(
                labelText: 'Amount (R) *',
                prefixText: 'R ',
                hintText: '450.00',
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
              ],
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Required';
                final parsed = double.tryParse(v);
                if (parsed == null || parsed <= 0) return 'Enter a valid amount';
                return null;
              },
            ),
            const SizedBox(height: 12),

            // Category
            DropdownButtonFormField<String>(
              value: _category,
              decoration: const InputDecoration(labelText: 'Category'),
              items: _categories
                  .map((c) => DropdownMenuItem(value: c.$1, child: Text(c.$2)))
                  .toList(),
              onChanged: (v) => setState(() => _category = v ?? 'other'),
            ),
            const SizedBox(height: 12),

            // Child
            DropdownButtonFormField<String>(
              value: _childName,
              decoration: const InputDecoration(labelText: 'For child'),
              items: [
                const DropdownMenuItem(value: 'All', child: Text('All children')),
                ...children.map((c) =>
                    DropdownMenuItem(value: c.name, child: Text(c.name))),
              ],
              onChanged: (v) => setState(() => _childName = v ?? 'All'),
            ),
            const SizedBox(height: 12),

            // Description
            TextFormField(
              controller: _descCtrl,
              decoration: const InputDecoration(
                labelText: 'Notes',
                hintText: 'Optional details',
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 16),

            // Recurring toggle
            SwitchListTile(
              title: const Text('Recurring expense'),
              subtitle: const Text('Repeats on a schedule'),
              value: _isRecurring,
              onChanged: (v) => setState(() => _isRecurring = v),
            ),

            if (_isRecurring) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _recurrence,
                decoration: const InputDecoration(labelText: 'Frequency'),
                items: const [
                  DropdownMenuItem(value: 'monthly',   child: Text('Monthly')),
                  DropdownMenuItem(value: 'quarterly', child: Text('Quarterly')),
                  DropdownMenuItem(value: 'annually',  child: Text('Annually')),
                ],
                onChanged: (v) =>
                    setState(() => _recurrence = v ?? 'monthly'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                decoration: const InputDecoration(
                  labelText: 'Due day of month',
                  hintText: '1–28',
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (v) => _dueDay = int.tryParse(v),
                validator: (v) {
                  if (!_isRecurring) return null;
                  final d = int.tryParse(v ?? '');
                  if (d == null || d < 1 || d > 28) return '1–28';
                  return null;
                },
              ),
            ],

            const SizedBox(height: 24),

            // Info about split
            if (otherParent != null)
              Card(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '100% assigned to ${otherParent.displayName}',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 24),

            // Save button
            FilledButton.icon(
              onPressed: _saving ? null : () => _save(otherParent?.userId),
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check),
              label: Text(_saving ? 'Saving…' : 'Create Expense'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save(String? otherParentId) async {
    if (!_formKey.currentState!.validate()) return;
    if (otherParentId == null || otherParentId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No other parent found in household')),
      );
      return;
    }

    setState(() => _saving = true);

    final amountCents =
        (double.parse(_amountCtrl.text) * 100).round();

    DateTime? nextDue;
    if (_isRecurring && _dueDay != null) {
      final now = DateTime.now();
      nextDue = DateTime(now.year, now.month, _dueDay!);
      if (nextDue.isBefore(now)) {
        nextDue = DateTime(now.year, now.month + 1, _dueDay!);
      }
    }

    try {
      await ref.read(expensesProvider.notifier).createExpense(
            title: _titleCtrl.text.trim(),
            description: _descCtrl.text.trim(),
            amount: amountCents,
            childName: _childName,
            category: _category,
            isRecurring: _isRecurring,
            recurrence: _isRecurring ? _recurrence : null,
            dueDay: _isRecurring ? _dueDay : null,
            nextDueDate: nextDue,
            startDate: DateTime.now(),
            splitToUserId: otherParentId,
          );

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
