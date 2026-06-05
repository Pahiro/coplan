import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../providers/absence_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/holiday_provider.dart';
import '../../providers/household_provider.dart';
import '../../widgets/mark_absence_sheet.dart';

class CustodySettingsScreen extends ConsumerWidget {
  const CustodySettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Custody')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16, 16, 16,
          16 + MediaQuery.of(context).padding.bottom,
        ),
        children: [
          Text(
            'Override the rotation for school holidays or trips. '
            'Each block assigns one parent for a date range.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Colors.grey),
          ),
          const SizedBox(height: 8),
          const _HolidayPeriodsSection(),
          const SizedBox(height: 24),
          const _AbsenceSection(),
        ],
      ),
    );
  }
}

// ── Holiday periods section ───────────────────────────────────────────────────

class _HolidayPeriodsSection extends ConsumerStatefulWidget {
  const _HolidayPeriodsSection();

  @override
  ConsumerState<_HolidayPeriodsSection> createState() =>
      _HolidayPeriodsSectionState();
}

class _HolidayPeriodsSectionState
    extends ConsumerState<_HolidayPeriodsSection> {
  @override
  Widget build(BuildContext context) {
    final blocksAsync = ref.watch(holidayBlocksProvider);
    final household   = ref.watch(householdProvider).valueOrNull;
    final parentA     = household?.rotationParentEvenName ?? 'Parent A';
    final parentB     = household?.rotationParentOddName  ?? 'Parent B';

    return blocksAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error:   (e, _) => Text('Error: $e'),
      data: (blocks) => Column(
        children: [
          if (blocks.isEmpty)
            Card(
              margin: EdgeInsets.zero,
              child: const ListTile(
                leading: Icon(Icons.beach_access_outlined),
                title: Text('No holiday periods yet'),
                subtitle: Text('Add one to override the rotation for school holidays or trips'),
              ),
            )
          else
            ...blocks.map((b) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: const Icon(Icons.beach_access_outlined),
                title: Text(b.name),
                subtitle: Text(
                  '${b.assignedParent}  ·  '
                  '${_fmtDisplay(b.startDate)} – ${_fmtDisplay(b.endDate)}'
                  '${b.notes != null ? '\n${b.notes}' : ''}',
                ),
                isThreeLine: b.notes != null,
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('Delete holiday block?'),
                        content: Text(
                            'Remove "${b.name}" (${b.assignedParent}) from '
                            '${_fmtDisplay(b.startDate)} to ${_fmtDisplay(b.endDate)}?'),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Cancel')),
                          FilledButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('Delete')),
                        ],
                      ),
                    );
                    if (confirmed == true) {
                      await ref
                          .read(holidayBlocksProvider.notifier)
                          .delete(b.id);
                    }
                  },
                ),
              ),
            )),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Add holiday block'),
              onPressed: () => _showAddSheet(context, parentA, parentB),
            ),
          ),
        ],
      ),
    );
  }

  String _fmtDisplay(DateTime d) =>
      '${d.day} ${_monthAbbr(d.month)} ${d.year}';

  String _monthAbbr(int m) => const [
    '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ][m];

  Future<void> _showAddSheet(
      BuildContext context, String parentA, String parentB) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AddHolidayBlockSheet(parentA: parentA, parentB: parentB),
    );
  }
}

class _AddHolidayBlockSheet extends ConsumerStatefulWidget {
  final String parentA;
  final String parentB;
  const _AddHolidayBlockSheet({required this.parentA, required this.parentB});

  @override
  ConsumerState<_AddHolidayBlockSheet> createState() =>
      _AddHolidayBlockSheetState();
}

class _AddHolidayBlockSheetState
    extends ConsumerState<_AddHolidayBlockSheet> {
  final _nameCtrl  = TextEditingController();
  final _notesCtrl = TextEditingController();
  late String   _parent;
  DateTime?     _startDate;
  DateTime?     _endDate;
  bool          _saving = false;

  @override
  void initState() {
    super.initState();
    _parent = widget.parentA;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  String _fmtDisplay(DateTime d) =>
      '${d.day} ${const ['','Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][d.month]} ${d.year}';

  Future<void> _pickStart() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) setState(() => _startDate = picked);
  }

  Future<void> _pickEnd() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? (_startDate ?? DateTime.now()),
      firstDate: _startDate ?? DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) setState(() => _endDate = picked);
  }

  bool get _valid =>
      _nameCtrl.text.trim().isNotEmpty &&
      _startDate != null &&
      _endDate != null &&
      !_endDate!.isBefore(_startDate!);

  Future<void> _save() async {
    if (!_valid) return;
    setState(() => _saving = true);
    try {
      await ref.read(holidayBlocksProvider.notifier).create(
            name:           _nameCtrl.text.trim(),
            assignedParent: _parent,
            startDate:      _startDate!,
            endDate:        _endDate!,
            notes:          _notesCtrl.text.trim().isNotEmpty
                                ? _notesCtrl.text.trim() : null,
          );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Add holiday block',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Name (e.g. Easter 2026)',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _parent,
            decoration: const InputDecoration(
              labelText: 'Who has the kids',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: [widget.parentA, widget.parentB]
                .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                .toList(),
            onChanged: (v) => setState(() => _parent = v!),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _pickStart,
                  child: Text(_startDate != null
                      ? _fmtDisplay(_startDate!)
                      : 'Start date'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: _pickEnd,
                  child: Text(_endDate != null
                      ? _fmtDisplay(_endDate!)
                      : 'End date'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notesCtrl,
            decoration: const InputDecoration(
              labelText: 'Notes (optional)',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _valid && !_saving ? _save : null,
              child: _saving
                  ? const SizedBox(
                      height: 18, width: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Save'),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Absence section ───────────────────────────────────────────────────────────

class _AbsenceSection extends ConsumerWidget {
  const _AbsenceSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final absencesAsync = ref.watch(absencePeriodsProvider);
    final myName = ref.watch(authProvider).valueOrNull?.userName?.trim() ?? '';
    final fmt    = DateFormat('d MMM yyyy');

    void openSheet() => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => const MarkAbsenceSheet(),
    );

    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.hiking),
            title: const Text('Mark absence'),
            subtitle: const Text('Custody shifts to the other parent while you\'re away'),
            trailing: const Icon(Icons.add),
            onTap: openSheet,
          ),
          absencesAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            ),
            error: (e, _) => const SizedBox.shrink(),
            data: (absences) {
              final mine = absences
                  .where((a) => a.absentParent == myName ||
                      a.createdBy == (ref.read(authProvider).valueOrNull?.userId ?? ''))
                  .toList();
              if (mine.isEmpty) return const SizedBox.shrink();
              return Column(
                children: [
                  const Divider(height: 1),
                  ...mine.map((a) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.event_busy, size: 20),
                    title: Text(a.reason.isNotEmpty ? a.reason : 'Absence'),
                    subtitle: Text(
                      '${fmt.format(a.startDate)} – ${fmt.format(a.endDate)}'
                      ' · ${a.durationDays} ${a.durationDays == 1 ? "day" : "days"}',
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, size: 20),
                      tooltip: 'Remove absence',
                      onPressed: () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: const Text('Remove absence?'),
                            content: Text(
                              'Remove "${a.reason.isNotEmpty ? a.reason : "absence"}" '
                              '(${fmt.format(a.startDate)} – ${fmt.format(a.endDate)})? '
                              'Custody will revert to the normal schedule.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('Cancel'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('Remove'),
                              ),
                            ],
                          ),
                        );
                        if (confirmed == true) {
                          await ref
                              .read(absencePeriodsProvider.notifier)
                              .delete(a.id);
                        }
                      },
                    ),
                  )),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
