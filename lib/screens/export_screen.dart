import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../utils/csv_download_stub.dart'
    if (dart.library.html) '../utils/csv_download_web.dart';

import '../engine/resolution_engine.dart';
import '../providers/custody_provider.dart';
import '../providers/household_provider.dart';
import '../providers/schedule_provider.dart';

/// Export schedule data as CSV — supports both historical and future dates.
class ExportScreen extends ConsumerStatefulWidget {
  const ExportScreen({super.key});

  @override
  ConsumerState<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends ConsumerState<ExportScreen> {
  DateTimeRange? _range;
  bool _exporting = false;
  String? _resultPath;

  @override
  void initState() {
    super.initState();
    // Default: last 30 days to today
    final now = DateTime.now();
    _range = DateTimeRange(
      start: now.subtract(const Duration(days: 30)),
      end: now,
    );
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: _range,
      firstDate: DateTime(2020),
      lastDate: now.add(const Duration(days: 365)),
      helpText: 'Select date range to export',
    );
    if (picked != null) setState(() => _range = picked);
  }

  Future<void> _export() async {
    if (_range == null) return;
    setState(() {
      _exporting = true;
      _resultPath = null;
    });

    try {
      final csv = await _generateCsv();
      final dateStr = DateFormat('yyyyMMdd').format(DateTime.now());
      final fileName = 'coplan_export_$dateStr.csv';
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
    final anchor = household?.rotationAnchorDate ?? DateTime(2025, 1, 6);
    final evenName = household?.rotationParentEvenName ?? 'Parent A';
    final oddName = household?.rotationParentOddName ?? 'Parent B';
    final scheme = household?.rotationScheme;
    final mode = household?.mode ?? 'custody';

    final rules = ref.read(baseRulesProvider).valueOrNull ?? const [];
    final weekdayRules = ref.read(weekdayRulesProvider).valueOrNull ?? const [];
    final recurring =
        ref.read(recurringArrangementsProvider).valueOrNull ?? const [];
    final allCustody = ref.read(custodyRequestsProvider).valueOrNull ?? const [];
    final acceptedCustody =
        allCustody.where((r) => r.isAccepted).toList();

    final buf = StringBuffer();
    // CSV header
    buf.writeln(
        'Date,Weekday,Day Owner,Time,Activity,Child,Location,Parent,Type,Shared');

    final start = _range!.start;
    final end = _range!.end;
    final days = end.difference(start).inDays + 1;
    final fmt = DateFormat('yyyy-MM-dd');
    final dayFmt = DateFormat('EEEE');

    for (int i = 0; i < days; i++) {
      final date = start.add(Duration(days: i));
      final dateStr = fmt.format(date);
      final weekday = dayFmt.format(date);

      final engine = ResolutionEngine(
        baseRules: rules,
        overrides: const [],
        custodyRequests: acceptedCustody,
        weekdayRules: weekdayRules,
        recurringArrangements: recurring,
        rotationAnchor: anchor,
        rotationParentEven: evenName,
        rotationParentOdd: oddName,
        rotationScheme: scheme,
        householdMode: mode,
      );

      final dayOwner = engine.dayOwner(date);
      final events = engine.resolveDay(date);

      if (events.isEmpty) {
        // Still output day owner row even with no events
        buf.writeln('$dateStr,$weekday,$dayOwner,,,,,,');
      } else {
        for (final e in events) {
          final time = '${e.time.hour.toString().padLeft(2, '0')}:'
              '${e.time.minute.toString().padLeft(2, '0')}';
          final type = e.custodyRequestId != null
              ? 'transfer'
              : e.isAdhoc
                  ? 'adhoc'
                  : 'scheduled';
          buf.writeln(
            '$dateStr,$weekday,$dayOwner,$time,'
            '${_esc(e.activity)},${_esc(e.childName)},'
            '${_esc(e.location)},${_esc(e.assignedParent)},'
            '$type,${e.isShared ? "Yes" : "No"}',
          );
        }
      }
    }
    return buf.toString();
  }

  /// Escape a CSV field (wrap in quotes if it contains comma/newline/quote).
  String _esc(String s) {
    if (s.contains(',') || s.contains('"') || s.contains('\n')) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('d MMM yyyy');
    return Scaffold(
      appBar: AppBar(title: const Text('Export Schedule')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Export your schedule as a CSV file that can be opened in '
              'Excel, Google Sheets, or any spreadsheet app.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Select a date range — past dates export history, future dates '
              'export the planned schedule.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            // Date range picker
            Card(
              child: ListTile(
                leading: const Icon(Icons.date_range),
                title: Text(
                  _range != null
                      ? '${fmt.format(_range!.start)} — ${fmt.format(_range!.end)}'
                      : 'Select date range',
                ),
                subtitle: _range != null
                    ? Text('${_range!.end.difference(_range!.start).inDays + 1} days')
                    : null,
                trailing: const Icon(Icons.edit_calendar),
                onTap: _pickRange,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _exporting ? null : _export,
                icon: _exporting
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.download),
                label: Text(_exporting ? 'Exporting…' : 'Export CSV'),
              ),
            ),
            if (_resultPath != null) ...[
              const SizedBox(height: 24),
              Card(
                color: Colors.green[50],
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.check_circle, color: Colors.green[700]),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Export complete!',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.green[700],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        kIsWeb ? _resultPath! : _resultPath!,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (!kIsWeb) ...[
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () {
                            Clipboard.setData(
                                ClipboardData(text: _resultPath!));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Path copied to clipboard')),
                            );
                          },
                          icon: const Icon(Icons.copy, size: 16),
                          label: const Text('Copy path'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
