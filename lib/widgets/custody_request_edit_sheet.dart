import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/custody_request.dart';
import '../providers/custody_provider.dart';
import '../providers/household_provider.dart';
import '../utils/dates.dart';
import 'common.dart';
import 'form_fields.dart';

/// Edit form for a pending one-way request (day handover or time window).
/// Answered requests and swaps can't be edited — withdraw and ask again.
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
  late TimeOfDay    _pickupTime;
  late bool         _hasReturnTime;
  late TimeOfDay?   _returnTime;
  late bool         _returnTimeTbd;
  late bool         _toParentCollects;
  late bool         _toParentReturns;
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
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final today = dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: _date.isBefore(today) ? _date : addDays(today, -1),
      lastDate: addDays(today, 365),
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
          ref.read(householdChildNamesProvider).map((c) => c.name).toList();
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
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
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

            PickerField.date(label: fmtDateLong(_date), onTap: _pickDate),
            const SizedBox(height: 12),

            ChildChips(
              selected: _selectedChildren,
              onChanged: (s) => setState(() => _selectedChildren = s),
            ),
            const SizedBox(height: 12),

            PickerField(
              label:
                  '${_toParentCollects ? 'Pickup' : 'Drop off'}: ${fmtTime(_pickupTime)}',
              onTap: () => _pickTime(_pickupTime, (t) => _pickupTime = t),
            ),
            const SizedBox(height: 8),

            CustodyEditTransportRow(
              label:      'Who brings the kids?',
              trueLabel:  '${widget.request.toParent} picks up',
              falseLabel: '${widget.request.fromParent} drops off',
              value:      _toParentCollects,
              onChanged:  (v) => setState(() => _toParentCollects = v),
            ),
            const SizedBox(height: 4),

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
              title: const Text('Kids come back the same day'),
              subtitle: Text(_hasReturnTime
                  ? 'A time window with a return time'
                  : 'Day handover — kids stay overnight'),
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
                    style: TextStyle(color: cs.onSurfaceVariant)),
              ]),
              const SizedBox(height: 8),
              CustodyEditTransportRow(
                label:      'Who handles the return?',
                trueLabel:  '${widget.request.toParent} drops back',
                falseLabel: '${widget.request.fromParent} picks up',
                value:      _toParentReturns,
                onChanged:  (v) => setState(() => _toParentReturns = v),
              ),
            ],
            const SizedBox(height: 12),

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
