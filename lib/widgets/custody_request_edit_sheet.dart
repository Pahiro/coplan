import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/custody_request.dart';
import '../models/weekday_rule.dart';
import '../providers/custody_provider.dart';
import '../providers/schedule_provider.dart';

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
  late DateTime  _date;
  late String    _child;
  late TimeOfDay _pickupTime;
  late bool      _hasReturnTime;
  late TimeOfDay? _returnTime;
  late bool      _returnTimeTbd;
  late bool      _toParentCollects;
  late bool      _toParentReturns;
  late bool      _repeatWeekly;
  final _noteCtrl = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final r = widget.request;
    _date             = r.date;
    _child            = r.childName;
    _pickupTime       = _parseTime(r.pickupTime);
    _hasReturnTime    = !r.isDayTransfer;
    _returnTimeTbd    = r.returnTimeTbd;
    _returnTime       = r.returnTime != null ? _parseTime(r.returnTime!) : null;
    _toParentCollects = r.toParentCollects;
    _toParentReturns  = r.toParentReturns;
    _noteCtrl.text    = r.note ?? '';
    // Reflect whether a weekday rule already exists for this day.
    final rules = ref.read(weekdayRulesProvider).valueOrNull ?? <WeekdayRule>[];
    _repeatWeekly = rules.any((wr) => wr.active && wr.dayOfWeek == r.date.weekday);
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  TimeOfDay _parseTime(String hhmm) {
    final p = hhmm.split(':');
    return TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1]));
  }

  String _fmtTime(TimeOfDay? t) => t != null
      ? '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}'
      : '—';

  String _fmtDate(DateTime d) => DateFormat('EEE, d MMM yyyy').format(d);
  String _isoDate(DateTime d)  => DateFormat('yyyy-MM-dd').format(d);

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
      await ref.read(custodyRequestsProvider.notifier).updateRequest(
            widget.request.id,
            date:             _isoDate(_date),
            childName:        _child,
            pickupTime:       _fmtTime(_pickupTime),
            returnTime:       (_hasReturnTime && !_returnTimeTbd)
                ? _fmtTime(_returnTime)
                : null,
            returnTimeTbd:    _hasReturnTime && _returnTimeTbd,
            note:             _noteCtrl.text.isEmpty ? null : _noteCtrl.text,
            toParentCollects: _toParentCollects,
            toParentReturns:  _toParentReturns,
          );

      // Sync the weekday rule to match the toggle state.
      if (!_hasReturnTime) {
        final rules = ref.read(weekdayRulesProvider).valueOrNull ?? <WeekdayRule>[];
        final existing = rules.firstWhereOrNull(
            (wr) => wr.active && wr.dayOfWeek == _date.weekday);
        if (_repeatWeekly && existing == null) {
          await ref.read(weekdayRulesNotifierProvider.notifier).create(
                dayOfWeek:      _date.weekday,
                assignedParent: widget.request.toParent,
                reason:         _noteCtrl.text,
              );
        } else if (!_repeatWeekly && existing != null) {
          await ref.read(weekdayRulesNotifierProvider.notifier)
              .delete(existing.id);
        }
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
            Text('Edit request',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),

            // Date
            InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(4),
              child: InputDecorator(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.calendar_today_outlined),
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                ),
                child: Text(_fmtDate(_date),
                    style: Theme.of(context).textTheme.bodyLarge),
              ),
            ),
            const SizedBox(height: 12),

            // Child
            DropdownButtonFormField<String>(
              value: _child,
              decoration: const InputDecoration(
                  labelText: 'Child', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'All',   child: Text('Both — Henri & Chris')),
                DropdownMenuItem(value: 'Henri', child: Text('Henri')),
                DropdownMenuItem(value: 'Chris', child: Text('Chris')),
              ],
              onChanged: (v) => setState(() => _child = v ?? 'All'),
            ),
            const SizedBox(height: 12),

            // Pickup time
            InkWell(
              onTap: () => _pickTime(_pickupTime, (t) => _pickupTime = t),
              borderRadius: BorderRadius.circular(4),
              child: InputDecorator(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.schedule_outlined),
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                ),
                child: Text('${_toParentCollects ? 'Pickup' : 'Drop off'}: ${_fmtTime(_pickupTime)}',
                    style: Theme.of(context).textTheme.bodyLarge),
              ),
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
                InkWell(
                  onTap: () => _pickTime(_returnTime, (t) => _returnTime = t),
                  borderRadius: BorderRadius.circular(4),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.schedule_outlined),
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    ),
                    child: Text('Return: ${_fmtTime(_returnTime)}',
                        style: Theme.of(context).textTheme.bodyLarge),
                  ),
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

            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
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
              style: const TextStyle(fontSize: 12, color: Colors.grey)),
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
