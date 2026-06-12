import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../providers/absence_provider.dart';
import '../providers/auth_provider.dart';
import 'common.dart';

/// Bottom sheet for marking an absence period.
///
/// The current user is automatically set as the absent parent (absences are
/// self-declared). Optionally accepts [initialStart] / [initialEnd] to
/// pre-fill the date range.
class MarkAbsenceSheet extends ConsumerStatefulWidget {
  final DateTime? initialStart;
  final DateTime? initialEnd;

  const MarkAbsenceSheet({super.key, this.initialStart, this.initialEnd});

  @override
  ConsumerState<MarkAbsenceSheet> createState() => _MarkAbsenceSheetState();
}

class _MarkAbsenceSheetState extends ConsumerState<MarkAbsenceSheet> {
  late DateTime? _start;
  late DateTime? _end;
  final _reasonCtrl = TextEditingController();
  final _noteCtrl   = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _start = widget.initialStart;
    _end   = widget.initialEnd;
  }

  @override
  void dispose() {
    _reasonCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final result = await showDateRangePicker(
      context:      context,
      firstDate:    DateTime(now.year, now.month, 1),
      lastDate:     DateTime(now.year + 2, 12, 31),
      initialDateRange: (_start != null && _end != null)
          ? DateTimeRange(start: _start!, end: _end!)
          : null,
      helpText:     'Select absence dates',
    );
    if (result != null) {
      setState(() {
        _start = result.start;
        _end   = result.end;
      });
    }
  }

  Future<void> _save() async {
    if (_start == null || _end == null) return;
    final reason = _reasonCtrl.text.trim();
    if (reason.isEmpty) return;

    setState(() => _saving = true);
    try {
      final myName = ref.read(authProvider).valueOrNull?.userName?.trim() ?? 'Parent';
      await ref.read(absencePeriodsProvider.notifier).create(
        absentParent: myName,
        startDate:    _start!,
        endDate:      _end!,
        reason:       reason,
        note:         _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) showErrorSnack(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme    = Theme.of(context);
    final fmt      = DateFormat('d MMM yyyy');
    final hasRange = _start != null && _end != null;

    return Padding(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Mark absence', style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Custody automatically shifts to the other parent for every day in this range.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 20),

          // ── Date range ────────────────────────────────────────────────────
          OutlinedButton.icon(
            onPressed: _pickRange,
            icon: const Icon(Icons.date_range),
            label: Text(
              hasRange
                  ? '${fmt.format(_start!)} – ${fmt.format(_end!)}'
                  : 'Select date range',
            ),
          ),

          const SizedBox(height: 16),

          // ── Reason ────────────────────────────────────────────────────────
          TextField(
            controller:  _reasonCtrl,
            decoration:  const InputDecoration(
              labelText:  'Reason *',
              hintText:   'e.g. Hiking trip',
              border:     OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
          ),

          const SizedBox(height: 12),

          // ── Optional note ─────────────────────────────────────────────────
          TextField(
            controller:  _noteCtrl,
            decoration:  const InputDecoration(
              labelText:  'Note (optional)',
              border:     OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.sentences,
            maxLines: 2,
          ),

          const SizedBox(height: 20),

          // ── Actions ───────────────────────────────────────────────────────
          BusyButton(
            busy: _saving,
            onPressed: (hasRange && _reasonCtrl.text.trim().isNotEmpty)
                ? _save
                : null,
            child: const Text('Save absence'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}
