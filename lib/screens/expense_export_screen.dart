import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../utils/csv_download_stub.dart'
    if (dart.library.html) '../utils/csv_download_web.dart';

import '../core/pb_client.dart';
import '../models/expense_split.dart';
import '../models/shared_expense.dart';
import '../providers/household_provider.dart';

class ExpenseExportScreen extends ConsumerStatefulWidget {
  const ExpenseExportScreen({super.key});

  @override
  ConsumerState<ExpenseExportScreen> createState() =>
      _ExpenseExportScreenState();
}

class _ExpenseExportScreenState extends ConsumerState<ExpenseExportScreen> {
  bool _exporting = false;
  String? _resultPath;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Export Expenses')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Export all expenses and splits as a CSV file, suitable for '
              'spreadsheets or tax records.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _exporting ? null : _export,
                icon: _exporting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.download),
                label: Text(_exporting ? 'Exporting…' : 'Export CSV'),
              ),
            ),
            if (_resultPath != null) ...[
              const SizedBox(height: 16),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.check_circle, color: Colors.green),
                  title: const Text('Export complete'),
                  subtitle: Text(_resultPath!,
                      style: const TextStyle(fontSize: 12)),
                  trailing: IconButton(
                    icon: const Icon(Icons.copy, size: 18),
                    tooltip: 'Copy path',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _resultPath!));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Path copied')),
                      );
                    },
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _export() async {
    setState(() {
      _exporting = true;
      _resultPath = null;
    });

    try {
      final csv = await _generateCsv();
      final dateStr = DateFormat('yyyyMMdd').format(DateTime.now());
      final fileName = 'coplan_expenses_$dateStr.csv';
      if (kIsWeb) {
        downloadCsvOnWeb(csv, fileName);
        setState(() => _resultPath = fileName);
      } else {
        final dir = await getApplicationDocumentsDirectory();
        final file = File('${dir.path}/$fileName');
        await file.writeAsString(csv);
        setState(() => _resultPath = file.path);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    } finally {
      setState(() => _exporting = false);
    }
  }

  Future<String> _generateCsv() async {
    final household = ref.read(householdProvider).valueOrNull;

    // Fetch all expenses
    final expenseRecords =
        await pb.collection('shared_expenses').getFullList(sort: '-created');
    final expenses = expenseRecords
        .map((r) => SharedExpense.fromRecord(r.toJson()))
        .toList();

    // Fetch all splits
    final splitRecords =
        await pb.collection('expense_splits').getFullList(sort: '-created');
    final splits = splitRecords
        .map((r) => ExpenseSplit.fromRecord(r.toJson()))
        .toList();

    // Build user name lookup
    String userName(String userId) {
      final member = household?.members
          .where((m) => m.userId == userId)
          .firstOrNull;
      return member?.displayName ?? userId;
    }

    final buf = StringBuffer();
    buf.writeln(
        'Expense,Child,Category,Amount (R),Recurring,Assigned To,Split Amount (R),Status,Due Date,Paid Date,Reference');

    for (final exp in expenses) {
      final expSplits = splits.where((s) => s.expense == exp.id).toList();
      if (expSplits.isEmpty) {
        // Expense with no splits
        buf.writeln([
          _csvEscape(exp.title),
          _csvEscape(exp.childName),
          exp.category ?? '',
          exp.amountInRands.toStringAsFixed(2),
          exp.isRecurring ? exp.recurrence ?? 'yes' : 'no',
          '', '', '', '', '', '',
        ].join(','));
      } else {
        for (final split in expSplits) {
          buf.writeln([
            _csvEscape(exp.title),
            _csvEscape(exp.childName),
            exp.category ?? '',
            exp.amountInRands.toStringAsFixed(2),
            exp.isRecurring ? exp.recurrence ?? 'yes' : 'no',
            _csvEscape(userName(split.user)),
            split.amountInRands.toStringAsFixed(2),
            split.status.name,
            split.dueDate != null
                ? DateFormat('yyyy-MM-dd').format(split.dueDate!)
                : '',
            split.paidDate != null
                ? DateFormat('yyyy-MM-dd').format(split.paidDate!)
                : '',
            _csvEscape(split.paymentReference ?? ''),
          ].join(','));
        }
      }
    }

    return buf.toString();
  }

  String _csvEscape(String s) {
    if (s.contains(',') || s.contains('"') || s.contains('\n')) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }
}
