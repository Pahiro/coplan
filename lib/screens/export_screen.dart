import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../core/pb_client.dart';
import '../engine/engine_factory.dart';
import '../models/custody_request.dart';
import '../models/manual_override.dart';
import '../providers/absence_provider.dart';
import '../providers/holiday_provider.dart';
import '../providers/household_provider.dart';
import '../providers/schedule_provider.dart';
import '../utils/csv_export.dart';
import '../utils/dates.dart';
import '../widgets/common.dart';

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
      final path =
          await saveCsv(csv: csv, fileName: 'coplan_export_$dateStr.csv');
      setState(() => _resultPath = path);
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      setState(() => _exporting = false);
    }
  }

  Future<String> _generateCsv() async {
    final rules        = ref.read(baseRulesProvider).valueOrNull ?? const [];
    final weekdayRules = ref.read(weekdayRulesProvider).valueOrNull ?? const [];
    final recurring =
        ref.read(recurringArrangementsProvider).valueOrNull ?? const [];
    final allAbsences =
        ref.read(absencePeriodsProvider).valueOrNull ?? const [];
    final allHolidays =
        ref.read(holidayBlocksProvider).valueOrNull ?? const [];

    final start = _range!.start;
    final end = _range!.end;
    final startStr = isoDate(start);
    final endStr = isoDate(end);

    final overrideRecords = await pb.collection('manual_overrides').getFullList(
        filter: 'target_date >= "$startStr" && target_date <= "$endStr"');
    final allOverrides = overrideRecords
        .map((r) => ManualOverride.fromRecord(r.toJson()))
        .toList();

    final custodyRecords = await pb.collection('custody_requests').getFullList(
        filter:
            'date >= "$startStr" && date <= "$endStr" && status = "accepted"');
    final allCustody = custodyRecords
        .map((r) => CustodyRequest.fromRecord(r.toJson()))
        .toList();

    // One engine for the whole range — it filters by date internally.
    final engine = buildEngine(
      household:             ref.read(householdProvider).valueOrNull,
      baseRules:             rules,
      overrides:             allOverrides,
      custodyRequests:       allCustody,
      weekdayRules:          weekdayRules,
      recurringArrangements: recurring,
      absencePeriods:        allAbsences,
      holidayBlocks:         allHolidays,
    );

    final buf = StringBuffer();
    buf.writeln(
        'Date,Weekday,Day Owner,Time,Activity,Child,Location,Parent,Type,Shared');

    final days = end.difference(start).inDays + 1;
    final dayFmt = DateFormat('EEEE');

    for (int i = 0; i < days; i++) {
      final date = start.add(Duration(days: i));
      final dateStr = isoDate(date);
      final weekday = dayFmt.format(date);

      final dayOwner = engine.dayOwner(date);
      final events = engine.resolveDay(date);

      if (events.isEmpty) {
        // Still output day owner row even with no events
        buf.writeln('$dateStr,$weekday,$dayOwner,,,,,,');
      } else {
        for (final e in events) {
          final type = e.custodyRequestId != null
              ? 'transfer'
              : e.isAdhoc
                  ? 'adhoc'
                  : 'scheduled';
          buf.writeln(
            '$dateStr,$weekday,$dayOwner,${fmtTime(e.time)},'
            '${csvEscape(e.activity)},${csvEscape(e.childName)},'
            '${csvEscape(e.location)},${csvEscape(e.assignedParent)},'
            '$type,${e.isShared ? "Yes" : "No"}',
          );
        }
      }
    }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('d MMM yyyy');
    final cs = Theme.of(context).colorScheme;
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
                  ?.copyWith(color: cs.onSurfaceVariant),
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
            BusyButton(
              busy: _exporting,
              onPressed: _export,
              icon: const Icon(Icons.download),
              child: Text(_exporting ? 'Exporting…' : 'Export CSV'),
            ),
            if (_resultPath != null) ...[
              const SizedBox(height: 24),
              Card(
                color: cs.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.check_circle, color: Colors.green),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Export complete!',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: cs.onSurface,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _resultPath!,
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
