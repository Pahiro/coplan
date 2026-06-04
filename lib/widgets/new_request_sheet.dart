import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../providers/auth_provider.dart';
import '../providers/custody_provider.dart';
import '../providers/household_provider.dart';

class NewRequestSheet extends ConsumerStatefulWidget {
  const NewRequestSheet({super.key});

  @override
  ConsumerState<NewRequestSheet> createState() => _NewRequestSheetState();
}

class _NewRequestSheetState extends ConsumerState<NewRequestSheet> {
  // ── State ───────────────────────────────────────────────────────────────────
  DateTime _date    = DateTime.now();
  Set<String> _selectedChildren = {}; // empty = All
  bool     _sending = false;

  String     _recipientKey     = '__parent__';
  bool       _iAmTaking        = true;
  bool       _hasReturnTime    = false;
  TimeOfDay? _pickupTime;
  TimeOfDay? _returnTime;
  bool       _returnTimeTbd    = false;
  bool       _toParentCollects = true;
  bool       _toParentReturns  = false;
  bool       _repeatWeekly     = false;
  final _noteCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _pickupTime = _defaultPickupTime(_date);
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  TimeOfDay _defaultPickupTime(DateTime d) =>
      d.weekday <= DateTime.friday
          ? const TimeOfDay(hour: 16, minute: 0)
          : const TimeOfDay(hour: 9, minute: 0);

  String _fmtDate(DateTime d) => DateFormat('EEE, d MMM yyyy').format(d);
  String _fmtTime(TimeOfDay? t) => t != null
      ? '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}'
      : '—';
  String _isoDate(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() {
      _date         = picked;
      _pickupTime   = _defaultPickupTime(picked);
      _repeatWeekly = false;
    });
  }

  Future<void> _pickTime(
      TimeOfDay? current, ValueChanged<TimeOfDay> onPicked) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: current ?? const TimeOfDay(hour: 16, minute: 0),
    );
    if (picked != null) setState(() => onPicked(picked));
  }

  Future<void> _send() async {
    setState(() => _sending = true);
    try {
      String? recipientUserId;
      String? recipientName;
      if (_recipientKey != '__parent__') {
        final household = ref.read(householdProvider).valueOrNull;
        final helper = household?.helpers
            .where((h) => h.userId == _recipientKey)
            .firstOrNull;
        recipientUserId = helper?.userId;
        recipientName   = helper?.displayName;
      }
      final isHelper = recipientUserId != null;

      await ref.read(custodyRequestsProvider.notifier).createRequest(
            iAmTaking:        _iAmTaking,
            date:             _isoDate(_date),
            childName:        _encodeChildName(_selectedChildren),
            pickupTime:       _fmtTime(_pickupTime),
            returnTime:       (_hasReturnTime && !_returnTimeTbd)
                                  ? _fmtTime(_returnTime) : null,
            returnTimeTbd:    _hasReturnTime && _returnTimeTbd,
            note:             _noteCtrl.text.isEmpty ? null : _noteCtrl.text,
            repeatWeekly:     !isHelper && _repeatWeekly && !_hasReturnTime,
            repeatReason:     _noteCtrl.text.isNotEmpty ? _noteCtrl.text : null,
            toParentCollects: _toParentCollects,
            toParentReturns:  _toParentReturns,
            recipientUserId:  recipientUserId,
            recipientName:    recipientName,
          );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Something went wrong'),
            content: Text('$e'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK')),
            ],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth      = ref.read(authProvider).valueOrNull;
    final myName    = auth?.userName?.trim() ?? 'Parent';
    final household = ref.read(householdProvider).valueOrNull;
    final otherName = household?.parents
            .where((m) => m.displayName != myName)
            .map((m) => m.displayName)
            .firstOrNull ??
        'Co-parent';
    final helpers  = household?.helpers ?? const [];
    final isHelper = _recipientKey != '__parent__';
    final helperName = isHelper
        ? (helpers
                .where((h) => h.userId == _recipientKey)
                .map((h) => h.displayName)
                .firstOrNull ??
            'Helper')
        : '';
    final toName   = isHelper ? helperName : (_iAmTaking ? myName : otherName);
    final fromName = isHelper ? myName     : (_iAmTaking ? otherName : myName);

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
            Text(
              household?.mode == 'shared'
                  ? 'New pickup request'
                  : 'New custody request',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),

            // Recipient
            if (helpers.isNotEmpty) ...[
              DropdownButtonFormField<String>(
                value: _recipientKey,
                decoration: const InputDecoration(
                  labelText: 'Who has the kids?',
                  border: OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem(
                      value: '__parent__',
                      child: Text('$otherName (co-parent)')),
                  ...helpers.map((h) => DropdownMenuItem(
                      value: h.userId,
                      child: Text('${h.displayName} (helper)'))),
                ],
                onChanged: (v) => setState(() {
                  _recipientKey    = v ?? '__parent__';
                  _toParentCollects = true;
                  _toParentReturns  = false;
                  if (_recipientKey != '__parent__') _repeatWeekly = false;
                }),
              ),
              const SizedBox(height: 16),
            ],

            // Direction
            if (!isHelper) ...[
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(
                      value: true,
                      icon: const Icon(Icons.arrow_forward, size: 16),
                      label: Text('$myName takes them')),
                  ButtonSegment(
                      value: false,
                      icon: const Icon(Icons.arrow_back, size: 16),
                      label: Text('$otherName takes them')),
                ],
                selected: {_iAmTaking},
                onSelectionChanged: (s) => setState(() {
                  _iAmTaking       = s.first;
                  _toParentCollects = true;
                  _toParentReturns  = false;
                }),
              ),
              const SizedBox(height: 16),
            ],

            // Date
            _DatePickerField(label: _fmtDate(_date), onTap: _pickDate),
            const SizedBox(height: 12),

            // Child
            _ChildChips(
                selected: _selectedChildren,
                onChanged: (s) => setState(() => _selectedChildren = s)),
            const SizedBox(height: 12),

            // Pickup time
            _TimePickerField(
              label:
                  '${_toParentCollects ? "Pickup" : "Drop off"}: ${_fmtTime(_pickupTime)}',
              onTap: () => _pickTime(_pickupTime, (t) => _pickupTime = t),
            ),
            const SizedBox(height: 6),

            // Transport at pickup
            _transportLabel('Who brings the kids?'),
            const SizedBox(height: 6),
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(
                    value: true,
                    icon: const Icon(Icons.directions_walk, size: 14),
                    label: Text('$toName picks up')),
                ButtonSegment(
                    value: false,
                    icon: const Icon(Icons.drive_eta, size: 14),
                    label: Text('$fromName drops off')),
              ],
              selected: {_toParentCollects},
              onSelectionChanged: (s) =>
                  setState(() => _toParentCollects = s.first),
              style: SegmentedButton.styleFrom(
                  visualDensity: VisualDensity.compact),
            ),
            const SizedBox(height: 4),

            // Has return time switch
            SwitchListTile(
              value: _hasReturnTime,
              onChanged: (v) => setState(() {
                _hasReturnTime = v;
                if (!v) {
                  _returnTimeTbd   = false;
                  _returnTime      = null;
                  _toParentReturns = false;
                }
              }),
              title: const Text('Has a return time'),
              subtitle: Text(_hasReturnTime
                  ? 'Kids are returned at a set time'
                  : 'Day transfer — kids stay overnight'),
              contentPadding: EdgeInsets.zero,
            ),

            if (_hasReturnTime) ...[
              if (!_returnTimeTbd) ...[
                _TimePickerField(
                  label: 'Return: ${_fmtTime(_returnTime)}',
                  onTap: () => _pickTime(_returnTime, (t) => _returnTime = t),
                ),
                const SizedBox(height: 4),
              ],
              Row(children: [
                Switch(
                  value: _returnTimeTbd,
                  onChanged: (v) => setState(() => _returnTimeTbd = v),
                ),
                const SizedBox(width: 8),
                Text('Return time TBD',
                    style: TextStyle(
                        color:
                            Theme.of(context).colorScheme.onSurfaceVariant)),
              ]),
              const SizedBox(height: 8),
            ] else if (!isHelper) ...[
              SwitchListTile(
                value: _repeatWeekly,
                onChanged: (v) => setState(() => _repeatWeekly = v),
                title: Text(
                    'Repeat every ${DateFormat('EEEE').format(_date)}'),
                subtitle: Text(_repeatWeekly
                    ? 'Creates a standing rule — manage in Settings'
                    : 'One-time request only'),
                contentPadding: EdgeInsets.zero,
              ),
            ],

            if (_hasReturnTime) ...[
              const SizedBox(height: 8),
              _transportLabel('Who handles the return?'),
              const SizedBox(height: 6),
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(
                      value: false,
                      icon: const Icon(Icons.directions_walk, size: 14),
                      label: Text('$fromName picks up')),
                  ButtonSegment(
                      value: true,
                      icon: const Icon(Icons.drive_eta, size: 14),
                      label: Text('$toName drops back')),
                ],
                selected: {_toParentReturns},
                onSelectionChanged: (s) =>
                    setState(() => _toParentReturns = s.first),
                style: SegmentedButton.styleFrom(
                    visualDensity: VisualDensity.compact),
              ),
              const SizedBox(height: 4),
            ],

            // Note
            TextField(
              controller: _noteCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),

            // Submit
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _sending ? null : _send,
                child: _sending
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Text(_hasReturnTime
                        ? 'Send Handover Request'
                        : 'Send Custody Request'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Shared sub-widgets ────────────────────────────────────────────────────────

Widget _transportLabel(String text) => Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Text(text,
          style: const TextStyle(fontSize: 12, color: Colors.grey)),
    );

class _DatePickerField extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _DatePickerField({required this.label, required this.onTap});

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

class _TimePickerField extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _TimePickerField({required this.label, required this.onTap});

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

String _encodeChildName(Set<String> s) =>
    s.isEmpty ? 'All' : s.toList().join(',');

class _ChildChips extends ConsumerWidget {
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;
  const _ChildChips({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final children = ref.watch(householdChildNamesProvider);
    if (children.isEmpty) return const SizedBox.shrink();

    final allSelected = selected.isEmpty || selected.length == children.length;
    return InputDecorator(
      decoration: const InputDecoration(
        labelText: 'Children',
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      child: Wrap(
        spacing: 8,
        children: [
          FilterChip(
            label: const Text('All'),
            selected: allSelected,
            onSelected: (_) => onChanged({}),
          ),
          ...children.map((c) => FilterChip(
                label: Text(c.name),
                selected: !allSelected && selected.contains(c.name),
                onSelected: (on) {
                  final next = Set<String>.from(selected);
                  if (on) {
                    next.add(c.name);
                  } else {
                    next.remove(c.name);
                  }
                  onChanged(next.length == children.length ? {} : next);
                },
              )),
        ],
      ),
    );
  }
}
