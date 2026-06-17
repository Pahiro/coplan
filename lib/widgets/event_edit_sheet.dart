import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/resolved_event.dart';
import '../providers/schedule_provider.dart';
import '../utils/dates.dart';
import 'common.dart';
import 'form_fields.dart';

/// Bottom sheet for creating a new standing rule or editing an existing
/// event (BaseRule or adhoc ManualOverride).
///
/// Pass [event] to edit; omit it (or pass null) to create a new rule.
class EventEditSheet extends ConsumerStatefulWidget {
  final ResolvedEvent? event;
  const EventEditSheet({super.key, this.event});

  @override
  ConsumerState<EventEditSheet> createState() => _EventEditSheetState();
}

class _EventEditSheetState extends ConsumerState<EventEditSheet> {
  late final TextEditingController _activityCtrl;
  late final TextEditingController _locationCtrl;
  late final TextEditingController _noteCtrl;
  late String   _child;
  late TimeOfDay _time;
  TimeOfDay?    _endTime;
  DateTime?     _endDate;   // only for standing rules (optional "repeats until")
  late bool     _isShared;
  late DateTime _date;      // only for adhoc/create-rule (date picker)
  late int      _dayOfWeek; // only for base rules (day picker)
  bool _saving = false;

  bool get _isCreateRule  => widget.event == null;
  bool get _isEditRule     => widget.event?.ruleId != null && widget.event?.overrideId == null;
  bool get _isEditOverride => widget.event?.overrideId != null && (widget.event?.isAdhoc ?? false);

  @override
  void initState() {
    super.initState();
    final e = widget.event;
    _activityCtrl = TextEditingController(text: e?.activity ?? '');
    _locationCtrl = TextEditingController(text: e?.location ?? '');
    _noteCtrl     = TextEditingController(text: e?.note ?? '');
    _child        = e?.childName ?? 'All';
    _time         = e?.time ?? const TimeOfDay(hour: 14, minute: 30);
    _endTime      = e?.endTime;
    _isShared     = e?.isShared ?? false;
    _date         = e?.date ?? DateTime.now().add(const Duration(days: 1));
    _dayOfWeek    = e?.date.weekday ?? DateTime.monday;
    // Pre-populate the standing rule's existing end date (ResolvedEvent doesn't
    // carry it, so look it up from the loaded base rules).
    final rid = e?.ruleId;
    if (rid != null && e?.overrideId == null) {
      for (final r in ref.read(baseRulesProvider).valueOrNull ?? const []) {
        if (r.id == rid) {
          _endDate = r.endDate;
          break;
        }
      }
    }
  }

  @override
  void dispose() {
    _activityCtrl.dispose();
    _locationCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
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
      if (_isEditOverride) {
        await ref.read(manualOverridesNotifierProvider.notifier).updateOverride(
              widget.event!.overrideId!,
              childName:    _child,
              targetDate:   isoDate(_date),
              overrideTime: fmtTime(_time),
              activity:     _activityCtrl.text.trim(),
              location:     _locationCtrl.text.trim(),
              isShared:     _isShared,
              endTime:      _endTime != null ? fmtTime(_endTime!) : null,
              note:         _noteCtrl.text.trim(),
            );
      } else if (_isEditRule) {
        await ref.read(baseRulesNotifierProvider.notifier).updateRule(
              widget.event!.ruleId!,
              childName:   _child,
              dayOfWeek:   _dayOfWeek,
              eventTime:   fmtTime(_time),
              activity:    _activityCtrl.text.trim(),
              location:    _locationCtrl.text.trim(),
              isShared:    _isShared,
              endDate:     _endDate != null ? isoDate(_endDate!) : null,
            );
      } else {
        // Create new standing rule
        await ref.read(baseRulesNotifierProvider.notifier).create(
              childName:   _child,
              dayOfWeek:   _dayOfWeek,
              eventTime:   fmtTime(_time),
              activity:    _activityCtrl.text.trim(),
              location:    _locationCtrl.text.trim(),
              isShared:    _isShared,
              endDate:     _endDate != null ? isoDate(_endDate!) : null,
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
    final String title;
    if (_isCreateRule) {
      title = 'New standing event';
    } else if (_isEditRule) {
      title = 'Edit standing event';
    } else {
      title = 'Edit event';
    }

    return Padding(
      padding: sheetPadding(context),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            if (_isEditRule) ...[
              const SizedBox(height: 4),
              Text(
                'Changes affect every future occurrence of this event.',
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 20),

            // Date or day-of-week picker
            if (_isEditOverride) ...[
              PickerField.date(label: fmtDateLong(_date), onTap: _pickDate),
              const SizedBox(height: 12),
            ] else ...[
              DayOfWeekField(
                value: _dayOfWeek,
                onChanged: (v) => setState(() => _dayOfWeek = v),
              ),
              const SizedBox(height: 12),
            ],

            // Time
            PickerField(label: fmtTime(_time), onTap: _pickTime),
            const SizedBox(height: 12),

            // Activity
            TextField(
              controller: _activityCtrl,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Event name',
                prefixIcon: Icon(Icons.event_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),

            // Location
            TextField(
              controller: _locationCtrl,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Location',
                prefixIcon: Icon(Icons.place_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),

            // End time — adhoc overrides only
            if (_isEditOverride) ...[
              PickerField(
                label: _endTime != null
                    ? 'Ends: ${fmtTime(_endTime!)}'
                    : 'End time (optional)',
                onTap: _pickEndTime,
                icon: Icons.timer_off_outlined,
              ),
              const SizedBox(height: 12),
            ],

            // Notes — adhoc overrides only
            if (_isEditOverride) ...[
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

            // Optional end date — standing rules only
            if (!_isEditOverride) ...[
              EndDateField(
                value: _endDate,
                label: 'Repeats forever (set an end date)',
                onChanged: (d) => setState(() => _endDate = d),
              ),
              const SizedBox(height: 12),
            ],

            // Child
            ChildDropdown(
              value: _child,
              onChanged: (v) => setState(() => _child = v),
            ),
            const SizedBox(height: 4),

            // Shared toggle
            SwitchListTile(
              value: _isShared,
              onChanged: (v) => setState(() => _isShared = v),
              title: const Text('Shared event'),
              subtitle: const Text('Both parents always see this event'),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 16),

            BusyButton(
              busy: _saving,
              onPressed: _activityCtrl.text.trim().isEmpty ? null : _save,
              child: Text(_isCreateRule ? 'Add Event' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }
}
