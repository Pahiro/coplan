import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/custody_request.dart';
import '../models/recurring_arrangement.dart';
import '../models/weekday_rule.dart';
import '../providers/custody_provider.dart';
import '../providers/household_provider.dart';
import '../providers/schedule_provider.dart';
import '../utils/dates.dart';
import 'common.dart';
import 'form_fields.dart';

/// Full edit form for an existing [CustodyRequest].
/// Extracted so it can be shown from both [CustodyRequestTile]
/// and [TimelineCard].
class CustodyRequestEditSheet extends ConsumerStatefulWidget {
  final CustodyRequest request;
  const CustodyRequestEditSheet({super.key, required this.request});

  @override
  ConsumerState<CustodyRequestEditSheet> createState() =>
      _CustodyRequestEditSheetState();
}

class _CustodyRequestEditSheetState
    extends ConsumerState<CustodyRequestEditSheet> {
  late DateTime     _date;
  late Set<String>  _selectedChildren; // empty = "All"
  late TimeOfDay _pickupTime;
  late bool      _hasReturnTime;
  late TimeOfDay? _returnTime;
  late bool      _returnTimeTbd;
  late bool      _toParentCollects;
  late bool      _toParentReturns;
  late bool      _repeatWeekly;
  DateTime?      _repeatEndDate; // optional "repeats until" for the standing rule
  final _noteCtrl = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final r = widget.request;
    _date             = r.date;
    _selectedChildren = parseChildSelection(r.childName);
    _pickupTime       = parseHHmm(r.pickupTime);
    _hasReturnTime    = !r.isDayTransfer;
    _returnTimeTbd    = r.returnTimeTbd;
    _returnTime       = r.returnTime != null ? parseHHmm(r.returnTime!) : null;
    _toParentCollects = r.toParentCollects;
    _toParentReturns  = r.toParentReturns;
    _noteCtrl.text    = r.note ?? '';
    // Reflect whether a recurring arrangement (or a stale weekday rule) already
    // covers this weekday for this recipient.
    final rules        = ref.read(weekdayRulesProvider).valueOrNull ?? <WeekdayRule>[];
    final arrangements = ref.read(recurringArrangementsProvider).valueOrNull
        ?? <RecurringArrangement>[];
    final existingArr = arrangements.firstWhereOrNull((a) =>
        a.active && a.dayOfWeek == r.date.weekday && a.toParent == r.toParent);
    _repeatWeekly = existingArr != null ||
        rules.any((wr) => wr.active && wr.dayOfWeek == r.date.weekday);
    _repeatEndDate = existingArr?.endDate;
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime(TimeOfDay? cur, ValueChanged<TimeOfDay> cb) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: cur ?? const TimeOfDay(hour: 16, minute: 0),
    );
    if (picked != null) setState(() => cb(picked));
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final allChildNames =
          (ref.read(householdChildNamesProvider)).map((c) => c.name).toList();
      await ref.read(custodyRequestsProvider.notifier).updateRequest(
            widget.request.id,
            date:             isoDate(_date),
            childName:        encodeChildSelection(_selectedChildren, allChildNames),
            pickupTime:       fmtTime(_pickupTime),
            returnTime:       (_hasReturnTime && !_returnTimeTbd)
                ? fmtTimeOr(_returnTime)
                : null,
            returnTimeTbd:    _hasReturnTime && _returnTimeTbd,
            note:             _noteCtrl.text.isEmpty ? null : _noteCtrl.text,
            toParentCollects: _toParentCollects,
            toParentReturns:  _toParentReturns,
          );

      // Sync the repeat setting via a logic-based recurring arrangement.  A
      // single rule is expanded by the engine for future weeks (only where the
      // other parent owns the day) and frozen into history as days pass.
      if (!_hasReturnTime) {
        // Clean up any stale full-day weekday rule from the legacy approach.
        final rules     = ref.read(weekdayRulesProvider).valueOrNull ?? <WeekdayRule>[];
        final staleRule = rules.firstWhereOrNull(
            (wr) => wr.active && wr.dayOfWeek == _date.weekday);
        if (staleRule != null) {
          await ref.read(weekdayRulesNotifierProvider.notifier).delete(staleRule.id);
        }

        final recurring = ref.read(recurringArrangementsNotifierProvider.notifier);
        if (_repeatWeekly) {
          await recurring.upsert(
            dayOfWeek:        _date.weekday,
            toParent:         widget.request.toParent,
            childName:        encodeChildSelection(_selectedChildren, allChildNames),
            pickupTime:       fmtTime(_pickupTime),
            returnTime:       null,
            returnTimeTbd:    false,
            toParentCollects: _toParentCollects,
            toParentReturns:  false,
            startDate:        isoDate(_date),
            endDate:          _repeatEndDate != null ? isoDate(_repeatEndDate!) : null,
            note:             _noteCtrl.text.isEmpty ? null : _noteCtrl.text,
          );
        } else {
          await recurring.deleteForDay(_date.weekday, toParent: widget.request.toParent);
        }
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
            Text('Edit request',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),

            // Date
            PickerField.date(label: fmtDateLong(_date), onTap: _pickDate),
            const SizedBox(height: 12),

            // Child — multi-select chips; none selected = All
            ChildChips(
              selected: _selectedChildren,
              onChanged: (s) => setState(() => _selectedChildren = s),
            ),
            const SizedBox(height: 12),

            // Pickup time
            PickerField(
              label:
                  '${_toParentCollects ? 'Pickup' : 'Drop off'}: ${fmtTime(_pickupTime)}',
              onTap: () => _pickTime(_pickupTime, (t) => _pickupTime = t),
            ),
            const SizedBox(height: 8),

            // Transport at pickup — directly below so the label updates in context
            CustodyEditTransportRow(
              label:      'Who brings the kids?',
              trueLabel:  '${widget.request.toParent} picks up',
              falseLabel: '${widget.request.fromParent} drops off',
              value:      _toParentCollects,
              onChanged:  (v) => setState(() => _toParentCollects = v),
            ),
            const SizedBox(height: 4),

            // Has return time — shown immediately after pickup so it's always visible
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
                  ? 'Kids return to the other parent'
                  : 'Day transfer — kids stay overnight'),
              contentPadding: EdgeInsets.zero,
            ),

            if (_hasReturnTime) ...[
              if (!_returnTimeTbd)
                PickerField(
                  label: 'Return: ${fmtTimeOr(_returnTime)}',
                  onTap: () => _pickTime(_returnTime, (t) => _returnTime = t),
                ),
              Row(children: [
                Switch(
                  value: _returnTimeTbd,
                  onChanged: (v) => setState(() => _returnTimeTbd = v),
                ),
                const SizedBox(width: 8),
                Text('Return time TBD',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ]),
              const SizedBox(height: 8),
            ],

            // Repeat weekly — only for day transfers
            if (!_hasReturnTime) ...[
              SwitchListTile(
                value: _repeatWeekly,
                onChanged: (v) => setState(() => _repeatWeekly = v),
                title: Text(
                    'Repeat every ${DateFormat('EEEE').format(_date)}'),
                subtitle: Text(_repeatWeekly
                    ? 'Standing rule active — toggle off to remove'
                    : 'One-time request only'),
                contentPadding: EdgeInsets.zero,
              ),
              if (_repeatWeekly) ...[
                const SizedBox(height: 8),
                EndDateField(
                  value: _repeatEndDate,
                  firstDate: _date,
                  label: 'Repeats forever (set an end date)',
                  onChanged: (d) => setState(() => _repeatEndDate = d),
                ),
              ],
            ],

            if (_hasReturnTime) ...[
              const SizedBox(height: 8),
              CustodyEditTransportRow(
                label:      'Who handles the return?',
                trueLabel:  '${widget.request.toParent} drops back',
                falseLabel: '${widget.request.fromParent} picks up',
                value:      _toParentReturns,
                onChanged:  (v) => setState(() => _toParentReturns = v),
              ),
            ],
            const SizedBox(height: 8),

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

            BusyButton(
              busy: _saving,
              onPressed: _save,
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Segmented button row for choosing pickup/return transport direction.
class CustodyEditTransportRow extends StatelessWidget {
  final String label;
  final String trueLabel;
  final String falseLabel;
  final bool value;
  final ValueChanged<bool> onChanged;

  const CustodyEditTransportRow({
    super.key,
    required this.label,
    required this.trueLabel,
    required this.falseLabel,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 6),
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(value: true,  label: Text(trueLabel)),
              ButtonSegment(value: false, label: Text(falseLabel)),
            ],
            selected: {value},
            onSelectionChanged: (s) => onChanged(s.first),
            style: SegmentedButton.styleFrom(
                visualDensity: VisualDensity.compact),
          ),
        ],
      );
}
