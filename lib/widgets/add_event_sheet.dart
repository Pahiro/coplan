import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../engine/resolution_engine.dart';
import '../models/resolved_event.dart';
import '../providers/custody_provider.dart';
import '../providers/household_provider.dart';
import '../providers/schedule_provider.dart';

enum _AddMode { standing, oneoff }

/// Bottom sheet shown from the calendar screen "+" FAB.
///
/// "Standing event"  → creates a recurring base rule (same as old EventEditSheet
///                     create mode).
/// "One-off event"   → creates a one-time shared event visible to both parents
///                     (was previously the "Shared event" tab on the dashboard).
class AddEventSheet extends ConsumerStatefulWidget {
  /// Pre-selects the date / day-of-week for the selected calendar day.
  final DateTime initialDate;

  const AddEventSheet({super.key, required this.initialDate});

  @override
  ConsumerState<AddEventSheet> createState() => _AddEventSheetState();
}

class _AddEventSheetState extends ConsumerState<AddEventSheet> {
  _AddMode _mode = _AddMode.standing;

  // Shared fields
  late DateTime  _date;
  late int       _dayOfWeek;
  TimeOfDay      _time     = const TimeOfDay(hour: 14, minute: 30);
  String         _child    = 'All';
  bool           _isShared = false; // only used for standing events
  bool           _saving   = false;

  final _activityCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _date      = widget.initialDate;
    _dayOfWeek = widget.initialDate.weekday;
  }

  @override
  void dispose() {
    _activityCtrl.dispose();
    _locationCtrl.dispose();
    super.dispose();
  }

  String _fmtTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  String _fmtDate(DateTime d) => DateFormat('EEE, d MMM yyyy').format(d);

  Future<void> _pickTime() async {
    final picked =
        await showTimePicker(context: context, initialTime: _time);
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    if (_activityCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      if (_mode == _AddMode.standing) {
        await ref.read(baseRulesNotifierProvider.notifier).create(
              childName: _child,
              dayOfWeek: _dayOfWeek,
              eventTime: _fmtTime(_time),
              activity:  _activityCtrl.text.trim(),
              location:  _locationCtrl.text.trim(),
              isShared:  _isShared,
            );
      } else {
        // Use rotation to determine responsible parent for that date.
        final household = ref.read(householdProvider).valueOrNull;
        final anchor   = household?.rotationAnchorDate ?? DateTime(2025, 1, 6);
        final evenName = household?.rotationParentEvenName ?? 'Bennet';
        final oddName  = household?.rotationParentOddName  ?? 'Jana';
        final owner = ResolutionEngine(
          baseRules: const [], overrides: const [],
          rotationAnchor: anchor,
          rotationParentEven: evenName,
          rotationParentOdd: oddName,
        ).dayOwner(_date);
        await ref.read(custodyRequestsProvider.notifier).createSharedEvent(
              targetDate:     DateFormat('yyyy-MM-dd').format(_date),
              childName:      _child,
              time:           _fmtTime(_time),
              activity:       _activityCtrl.text.trim(),
              location:       _locationCtrl.text.trim(),
              assignedParent: owner,
            );
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24, right: 24, top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Add to schedule',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),

            // Mode selector
            SegmentedButton<_AddMode>(
              segments: const [
                ButtonSegment(
                  value: _AddMode.standing,
                  icon: Icon(Icons.repeat_outlined),
                  label: Text('Standing event'),
                ),
                ButtonSegment(
                  value: _AddMode.oneoff,
                  icon: Icon(Icons.event_outlined),
                  label: Text('One-off event'),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => setState(() => _mode = s.first),
            ),
            const SizedBox(height: 6),

            Text(
              _mode == _AddMode.standing
                  ? 'Repeats every week on the chosen day.'
                  : 'A one-time event both parents will see.',
              style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),

            // Date / day-of-week
            if (_mode == _AddMode.standing)
              _DayOfWeekField(
                value: _dayOfWeek,
                onChanged: (v) => setState(() => _dayOfWeek = v),
              )
            else
              _DateField(label: _fmtDate(_date), onTap: _pickDate),
            const SizedBox(height: 12),

            // Time
            _TimeField(label: _fmtTime(_time), onTap: _pickTime),
            const SizedBox(height: 12),

            // Event name
            TextField(
              controller: _activityCtrl,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Event name',
                prefixIcon: Icon(Icons.label_outline),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),

            // Location
            TextField(
              controller: _locationCtrl,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Location (optional)',
                prefixIcon: Icon(Icons.place_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),

            // Child
            DropdownButtonFormField<String>(
              value: _child,
              decoration: const InputDecoration(
                  labelText: 'Child', border: OutlineInputBorder()),
              items: (ref.watch(householdChildNamesProvider)
                  .map((c) => c.name)
                  .toList()
                ..insert(0, 'All'))
                  .map((name) => DropdownMenuItem(
                        value: name,
                        child: Text(name == 'All' ? 'All children' : name),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _child = v ?? 'All'),
            ),

            // Shared toggle — standing events only (one-off events are always shared)
            if (_mode == _AddMode.standing) ...[
              const SizedBox(height: 4),
              SwitchListTile(
                value: _isShared,
                onChanged: (v) => setState(() => _isShared = v),
                title: const Text('Both parents always see this'),
                subtitle: const Text('Marks it as a shared obligation'),
                contentPadding: EdgeInsets.zero,
              ),
            ] else
              const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving || _activityCtrl.text.trim().isEmpty
                    ? null
                    : _save,
                child: _saving
                    ? const SizedBox(
                        height: 18, width: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Text(_mode == _AddMode.standing
                        ? 'Add standing event'
                        : 'Add one-off event'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Reusable field widgets ────────────────────────────────────────────────────

class _DateField extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _DateField({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: InputDecorator(
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.calendar_today_outlined),
            border: OutlineInputBorder(),
            contentPadding:
                EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          ),
          child: Text(label, style: Theme.of(context).textTheme.bodyLarge),
        ),
      );
}

class _TimeField extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _TimeField({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: InputDecorator(
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.schedule_outlined),
            border: OutlineInputBorder(),
            contentPadding:
                EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          ),
          child: Text(label, style: Theme.of(context).textTheme.bodyLarge),
        ),
      );
}

const _kDays = [
  (1, 'Monday'),
  (2, 'Tuesday'),
  (3, 'Wednesday'),
  (4, 'Thursday'),
  (5, 'Friday'),
  (6, 'Saturday'),
  (7, 'Sunday'),
];

class _DayOfWeekField extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  const _DayOfWeekField({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<int>(
        value: value,
        decoration: const InputDecoration(
          labelText: 'Day of week',
          prefixIcon: Icon(Icons.repeat_outlined),
          border: OutlineInputBorder(),
        ),
        items: _kDays
            .map((d) => DropdownMenuItem(value: d.$1, child: Text(d.$2)))
            .toList(),
        onChanged: (v) => onChanged(v ?? DateTime.monday),
      );
}
