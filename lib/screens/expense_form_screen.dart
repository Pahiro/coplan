import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../core/expense_categories.dart';
import '../models/shared_expense.dart';
import '../providers/auth_provider.dart';
import '../providers/expense_provider.dart';
import '../providers/household_provider.dart';
import '../widgets/common.dart';

class ExpenseFormScreen extends ConsumerStatefulWidget {
  /// Pass an existing expense to edit; null = create new.
  final SharedExpense? existing;
  const ExpenseFormScreen({super.key, this.existing});

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
  int _splitPercent = 100;
  bool _saving = false;
  XFile? _receipt;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _titleCtrl.text  = e.title;
      _descCtrl.text   = e.description ?? '';
      _amountCtrl.text = e.amountInRands.toStringAsFixed(2);
      _category    = e.category ?? 'other';
      _childName   = e.childName;
      _isRecurring = e.isRecurring;
      _recurrence  = e.recurrence ?? 'monthly';
      _dueDay      = e.dueDay;
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickReceipt() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (picked != null) setState(() => _receipt = picked);
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
      appBar: AppBar(title: Text(_isEditing ? 'Edit Expense' : 'New Expense')),
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
              initialValue: _category,
              decoration: const InputDecoration(labelText: 'Category'),
              items: ExpenseCategory.all
                  .map((c) =>
                      DropdownMenuItem(value: c.id, child: Text(c.label)))
                  .toList(),
              onChanged: (v) => setState(() => _category = v ?? 'other'),
            ),
            const SizedBox(height: 12),

            // Child
            DropdownButtonFormField<String>(
              initialValue: _childName,
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
            const SizedBox(height: 12),

            // Receipt photo
            OutlinedButton.icon(
              onPressed: _pickReceipt,
              icon: const Icon(Icons.receipt_long, size: 18),
              label: Text(_receipt != null
                  ? 'Receipt attached — tap to replace'
                  : widget.existing?.receipt != null
                      ? 'Replace receipt photo'
                      : 'Attach receipt photo (optional)'),
            ),
            const SizedBox(height: 4),

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
                initialValue: _recurrence,
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
                initialValue: _dueDay?.toString(),
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

            // Split percentage
            if (otherParent != null) ...[
              Text(
                'Split: ${otherParent.displayName} owes $_splitPercent%',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              Slider(
                value: _splitPercent.toDouble(),
                min: 0,
                max: 100,
                divisions: 20,
                label: '$_splitPercent%',
                onChanged: (v) => setState(() => _splitPercent = v.round()),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('0%', style: Theme.of(context).textTheme.bodySmall),
                  Text('50%', style: Theme.of(context).textTheme.bodySmall),
                  Text('100%', style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ],

            const SizedBox(height: 24),

            // Save button
            BusyButton(
              busy: _saving,
              onPressed: () => _save(otherParent?.userId),
              icon: const Icon(Icons.check),
              child: Text(_isEditing ? 'Update Expense' : 'Create Expense'),
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

    http.MultipartFile? receiptFile;
    if (_receipt != null) {
      receiptFile = http.MultipartFile.fromBytes(
        'receipt',
        await _receipt!.readAsBytes(),
        filename: _receipt!.name,
      );
    }

    try {
      if (_isEditing) {
        await ref.read(expensesProvider.notifier).updateExpense(
              expenseId: widget.existing!.id,
              title: _titleCtrl.text.trim(),
              description: _descCtrl.text.trim(),
              amount: amountCents,
              childName: _childName,
              category: _category,
              isRecurring: _isRecurring,
              recurrence: _isRecurring ? _recurrence : null,
              dueDay: _isRecurring ? _dueDay : null,
              nextDueDate: nextDue,
              receipt: receiptFile,
            );
      } else {
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
              splitPercent: _splitPercent,
              receipt: receiptFile,
            );
      }

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
