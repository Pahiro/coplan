import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/resolved_event.dart';
import '../providers/household_provider.dart';
import '../providers/schedule_provider.dart';

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
  }

  @override
  void dispose() {
    _activityCtrl.dispose();
    _locationCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  String _fmtTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  String _fmtDate(DateTime d) => DateFormat('EEE, d MMM yyyy').format(d);

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
              targetDate:   DateFormat('yyyy-MM-dd').format(_date),
              overrideTime: _fmtTime(_time),
              activity:     _activityCtrl.text.trim(),
              location:     _locationCtrl.text.trim(),
              isShared:     _isShared,
              endTime:      _endTime != null ? _fmtTime(_endTime!) : null,
              note:         _noteCtrl.text.trim(),
            );
      } else if (_isEditRule) {
        await ref.read(baseRulesNotifierProvider.notifier).updateRule(
              widget.event!.ruleId!,
              childName:   _child,
              dayOfWeek:   _dayOfWeek,
              eventTime:   _fmtTime(_time),
              activity:    _activityCtrl.text.trim(),
              location:    _locationCtrl.text.trim(),
              isShared:    _isShared,
            );
      } else {
        // Create new standing rule
        await ref.read(baseRulesNotifierProvider.notifier).create(
              childName:   _child,
              dayOfWeek:   _dayOfWeek,
              eventTime:   _fmtTime(_time),
              activity:    _activityCtrl.text.trim(),
              location:    _locationCtrl.text.trim(),
              isShared:    _isShared,
            );
      }
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

  @override
  Widget build(BuildContext context) {
    final String title;
    if (_isCreateRule)   title = 'New standing event';
    else if (_isEditRule) title = 'Edit standing event';
    else                  title = 'Edit event';

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
              _DateField(label: _fmtDate(_date), onTap: _pickDate),
              const SizedBox(height: 12),
            ] else ...[
              _DayOfWeekField(
                value: _dayOfWeek,
                onChanged: (v) => setState(() => _dayOfWeek = v),
              ),
              const SizedBox(height: 12),
            ],

            // Time
            _TimeField(
              label: _fmtTime(_time),
              onTap: _pickTime,
            ),
            const SizedBox(height: 12),

            // Activity
            TextField(
              controller: _activityCtrl,
              textCapitalization: TextCapitalization.sentences,
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
              _TimeField(
                label: _endTime != null ? 'Ends: ${_fmtTime(_endTime!)}' : 'End time (optional)',
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

            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 18, width: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Text(_isCreateRule ? 'Add Event' : 'Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Helper sub-widgets ────────────────────────────────────────────────────────

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
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          ),
          child: Text(label, style: Theme.of(context).textTheme.bodyLarge),
        ),
      );
}

class _TimeField extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final IconData icon;
  const _TimeField({required this.label, required this.onTap, this.icon = Icons.schedule_outlined});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: InputDecorator(
          decoration: InputDecoration(
            prefixIcon: Icon(icon),
            border: const OutlineInputBorder(),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
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
