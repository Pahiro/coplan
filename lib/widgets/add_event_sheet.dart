import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/engine_factory.dart';
import '../providers/custody_provider.dart';
import '../providers/holiday_provider.dart';
import '../providers/household_provider.dart';
import '../providers/schedule_provider.dart';
import '../utils/dates.dart';
import 'common.dart';
import 'form_fields.dart';

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
  TimeOfDay?     _endTime;
  String         _child    = 'All';
  bool           _isShared = false; // only used for standing events
  bool           _saving   = false;

  final _activityCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _noteCtrl     = TextEditingController();

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
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final picked =
        await showTimePicker(context: context, initialTime: _time);
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _pickEndTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _endTime ?? _time.replacing(hour: (_time.hour + 1) % 24),
    );
    if (picked != null) setState(() => _endTime = picked);
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
              eventTime: fmtTime(_time),
              activity:  _activityCtrl.text.trim(),
              location:  _locationCtrl.text.trim(),
              isShared:  _isShared,
            );
      } else {
        // Use rotation to determine responsible parent for that date.
        final owner = buildEngine(
          household: ref.read(householdProvider).valueOrNull,
          holidayBlocks: ref.read(holidayBlocksProvider).valueOrNull ?? const [],
        ).dayOwner(_date);
        await ref.read(custodyRequestsProvider.notifier).createSharedEvent(
              targetDate:     isoDate(_date),
              childName:      _child,
              time:           fmtTime(_time),
              activity:       _activityCtrl.text.trim(),
              location:       _locationCtrl.text.trim(),
              assignedParent: owner,
              endTime:        _endTime != null ? fmtTime(_endTime!) : null,
              note:           _noteCtrl.text.trim(),
            );
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: sheetPadding(context),
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
              DayOfWeekField(
                value: _dayOfWeek,
                onChanged: (v) => setState(() => _dayOfWeek = v),
              )
            else
              PickerField.date(label: fmtDateLong(_date), onTap: _pickDate),
            const SizedBox(height: 12),

            // Time
            PickerField(label: fmtTime(_time), onTap: _pickTime),
            const SizedBox(height: 12),

            // Event name
            TextField(
              controller: _activityCtrl,
              textCapitalization: TextCapitalization.sentences,
              // Rebuild so the save button enables as soon as a name exists.
              onChanged: (_) => setState(() {}),
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

            // End time — one-off events only
            if (_mode == _AddMode.oneoff) ...[
              PickerField(
                label: _endTime != null
                    ? 'Ends: ${fmtTime(_endTime!)}'
                    : 'End time (optional)',
                onTap: _pickEndTime,
                icon: Icons.timer_off_outlined,
              ),
              const SizedBox(height: 12),
            ],

            // Notes — one-off events only
            if (_mode == _AddMode.oneoff) ...[
              TextField(
                controller: _noteCtrl,
                textCapitalization: TextCapitalization.sentences,
                maxLines: 3,
                minLines: 1,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                  prefixIcon: Icon(Icons.notes_outlined),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Child
            ChildDropdown(
              value: _child,
              onChanged: (v) => setState(() => _child = v),
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
            ],

            BusyButton(
              busy: _saving,
              onPressed: _activityCtrl.text.trim().isEmpty ? null : _save,
              child: Text(_mode == _AddMode.standing
                  ? 'Add standing event'
                  : 'Add one-off event'),
            ),
          ],
        ),
      ),
    );
  }
}
