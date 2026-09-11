import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/resolution_engine.dart';
import '../models/household.dart';
import '../models/manual_override.dart';
import '../providers/custody_provider.dart';
import '../providers/household_provider.dart';
import '../providers/schedule_provider.dart';
import '../utils/dates.dart';
import 'common.dart';
import 'form_fields.dart';

/// The three things a parent can ask for.
enum RequestKind {
  /// One parent has the kids for the rest of a day (and overnight).
  day,

  /// Trade days: the other parent takes one of yours, you take one of theirs.
  swap,

  /// The kids go to someone for a few hours and come back.
  window,
}

class NewRequestSheet extends ConsumerStatefulWidget {
  /// Pre-selects the date (e.g. the day selected on the calendar).
  final DateTime? initialDate;
  final RequestKind initialKind;

  const NewRequestSheet({
    super.key,
    this.initialDate,
    this.initialKind = RequestKind.day,
  });

  @override
  ConsumerState<NewRequestSheet> createState() => _NewRequestSheetState();
}

class _NewRequestSheetState extends ConsumerState<NewRequestSheet> {
  late RequestKind _kind;
  late DateTime _date;      // day/window date; for a swap, the day you give
  late DateTime _takeDate;  // swap: the day you take
  Set<String> _children = {}; // empty = All
  bool _sending = false;

  // Day / window
  String     _recipientKey     = '__parent__';
  bool       _iAmTaking        = true;
  late TimeOfDay _pickupTime;
  TimeOfDay? _returnTime;
  bool       _returnTimeTbd    = false;
  bool       _toParentCollects = true;
  bool       _toParentReturns  = false;

  // Swap
  bool      _swapTimes = false;
  TimeOfDay _giveTime  = const TimeOfDay(hour: 17, minute: 0);
  TimeOfDay _takeTime  = const TimeOfDay(hour: 17, minute: 0);

  final _noteCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _kind       = widget.initialKind;
    _date       = dateOnly(widget.initialDate ?? DateTime.now());
    _pickupTime = _defaultPickupTime(_date);
    _takeDate   = _suggestTakeDate(_date);
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

  /// The next day the co-parent has the kids — the same weekday when possible
  /// (a Saturday for a Saturday), otherwise the nearest of their days.
  DateTime _suggestTakeDate(DateTime give) {
    final engine = ref.read(scheduleEngineProvider);
    final me = ref.read(myDisplayNameProvider);
    DateTime? nearest;
    for (var i = 1; i <= 35; i++) {
      final d = addDays(give, i);
      if (engine.dayOwner(d) == me) continue;
      if (d.weekday == give.weekday) return d;
      nearest ??= d;
    }
    return nearest ?? addDays(give, 7);
  }

  bool _canSwap() {
    final household = ref.read(householdProvider).valueOrNull;
    return household?.mode != 'shared' && ref.read(coParentProvider) != null;
  }

  RequestKind _effectiveKind(bool canSwap) =>
      !canSwap && _kind == RequestKind.swap ? RequestKind.day : _kind;

  Future<DateTime?> _pickDate(DateTime initial) {
    final today = dateOnly(DateTime.now());
    final last = addDays(today, 365);
    return showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: initial.isBefore(today) ? initial : addDays(today, -1),
      lastDate: initial.isAfter(last) ? initial : last,
    );
  }

  Future<void> _pickTime(TimeOfDay? current, ValueChanged<TimeOfDay> onPicked) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: current ?? const TimeOfDay(hour: 16, minute: 0),
    );
    if (picked != null) setState(() => onPicked(picked));
  }

  Future<void> _send() async {
    final kind = _effectiveKind(_canSwap());
    if (kind == RequestKind.swap && sameDay(_date, _takeDate)) {
      showErrorSnack(context, Exception('Pick two different days to swap.'));
      return;
    }
    if (kind == RequestKind.window && !_returnTimeTbd && _returnTime == null) {
      showErrorSnack(context, Exception('Set a return time, or mark it TBD.'));
      return;
    }

    setState(() => _sending = true);
    try {
      final notifier  = ref.read(custodyRequestsProvider.notifier);
      final allNames  = ref.read(householdChildNamesProvider).map((c) => c.name).toList();
      final childName = encodeChildSelection(_children, allNames);
      final note      = _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim();

      if (kind == RequestKind.swap) {
        await notifier.createSwap(
          giveDate:   isoDate(_date),
          takeDate:   isoDate(_takeDate),
          childName:  childName,
          givePickup: _swapTimes ? fmtTime(_giveTime) : '00:00',
          takePickup: _swapTimes ? fmtTime(_takeTime) : '00:00',
          note:       note,
        );
      } else {
        String? recipientUserId;
        String? recipientName;
        if (_recipientKey != '__parent__') {
          final helper = ref
              .read(householdProvider)
              .valueOrNull
              ?.helpers
              .where((h) => h.userId == _recipientKey)
              .firstOrNull;
          recipientUserId = helper?.userId;
          recipientName   = helper?.displayName;
        }
        final window = kind == RequestKind.window;
        await notifier.createRequest(
          iAmTaking:        _iAmTaking,
          date:             isoDate(_date),
          childName:        childName,
          pickupTime:       fmtTime(_pickupTime),
          returnTime:       window && !_returnTimeTbd ? fmtTimeOr(_returnTime) : null,
          returnTimeTbd:    window && _returnTimeTbd,
          note:             note,
          toParentCollects: _toParentCollects,
          toParentReturns:  window && _toParentReturns,
          recipientUserId:  recipientUserId,
          recipientName:    recipientName,
        );
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme     = Theme.of(context);
    final cs        = theme.colorScheme;
    final household = ref.watch(householdProvider).valueOrNull;
    final engine    = ref.watch(scheduleEngineProvider);
    final myName    = ref.watch(myDisplayNameProvider);
    final coParent  = ref.watch(coParentProvider);
    final otherName = coParent?.displayName ?? 'Co-parent';
    final helpers   = household?.helpers ?? const <HouseholdMember>[];
    final shared    = household?.mode == 'shared';
    final canSwap   = !shared && coParent != null;
    final kind      = _effectiveKind(canSwap);

    final isHelper   = _recipientKey != '__parent__';
    final helperName = helpers
            .where((h) => h.userId == _recipientKey)
            .map((h) => h.displayName)
            .firstOrNull ??
        'Helper';
    final toName   = isHelper ? helperName : (_iAmTaking ? myName : otherName);
    final fromName = isHelper ? myName     : (_iAmTaking ? otherName : myName);

    return Padding(
      padding: sheetPadding(context),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(shared ? 'New pickup request' : 'New request',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              child: SegmentedButton<RequestKind>(
                segments: [
                  const ButtonSegment(
                      value: RequestKind.day,
                      icon: Icon(Icons.swap_horiz),
                      label: Text('Day')),
                  if (canSwap)
                    const ButtonSegment(
                        value: RequestKind.swap,
                        icon: Icon(Icons.sync_alt),
                        label: Text('Swap')),
                  const ButtonSegment(
                      value: RequestKind.window,
                      icon: Icon(Icons.schedule),
                      label: Text('Window')),
                ],
                selected: {kind},
                onSelectionChanged: (s) => setState(() => _kind = s.first),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              switch (kind) {
                RequestKind.day =>
                  'Someone has the kids for the rest of the day and overnight.',
                RequestKind.swap =>
                  'Trade days: $otherName takes one of your days, you take one of theirs.',
                RequestKind.window =>
                  'The kids go for a few hours and come back the same day.',
              },
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 16),

            if (kind == RequestKind.swap) ...[
              _label(context, '$otherName takes the kids'),
              const SizedBox(height: 6),
              PickerField.date(
                label: fmtDateLong(_date),
                onTap: () async {
                  final d = await _pickDate(_date);
                  if (d != null) {
                    setState(() {
                      _date = d;
                      _takeDate = _suggestTakeDate(d);
                    });
                  }
                },
              ),
              _ownerHint(context, engine, _date, myName, expectMine: true),
              const SizedBox(height: 12),
              _label(context, 'You take the kids'),
              const SizedBox(height: 6),
              PickerField.date(
                label: fmtDateLong(_takeDate),
                onTap: () async {
                  final d = await _pickDate(_takeDate);
                  if (d != null) setState(() => _takeDate = d);
                },
              ),
              _ownerHint(context, engine, _takeDate, myName, expectMine: false),
              const SizedBox(height: 12),
              ChildChips(
                  selected: _children,
                  onChanged: (s) => setState(() => _children = s)),
              ..._examHints(context, [_date, _takeDate]),
              SwitchListTile(
                value: _swapTimes,
                onChanged: (v) => setState(() => _swapTimes = v),
                title: const Text('Set handover times'),
                subtitle: Text(_swapTimes
                    ? 'Each swapped day starts at its handover time'
                    : 'Whole days'),
                contentPadding: EdgeInsets.zero,
              ),
              if (_swapTimes) ...[
                PickerField(
                  label: '${fmtDateShort(_date)}: from ${fmtTime(_giveTime)}',
                  onTap: () => _pickTime(_giveTime, (t) => _giveTime = t),
                ),
                const SizedBox(height: 8),
                PickerField(
                  label: '${fmtDateShort(_takeDate)}: from ${fmtTime(_takeTime)}',
                  onTap: () => _pickTime(_takeTime, (t) => _takeTime = t),
                ),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 8),
            ] else ...[
              // Recipient
              if (helpers.isNotEmpty) ...[
                DropdownButtonFormField<String>(
                  initialValue: _recipientKey,
                  decoration: const InputDecoration(
                    labelText: 'With',
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
                    _recipientKey     = v ?? '__parent__';
                    _toParentCollects = true;
                    _toParentReturns  = false;
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
                    _iAmTaking        = s.first;
                    _toParentCollects = true;
                    _toParentReturns  = false;
                  }),
                ),
                const SizedBox(height: 16),
              ],

              PickerField.date(
                label: fmtDateLong(_date),
                onTap: () async {
                  final d = await _pickDate(_date);
                  if (d != null) {
                    setState(() {
                      _date       = d;
                      _pickupTime = _defaultPickupTime(d);
                    });
                  }
                },
              ),
              const SizedBox(height: 12),
              ChildChips(
                  selected: _children,
                  onChanged: (s) => setState(() => _children = s)),
              ..._examHints(context, [_date]),
              const SizedBox(height: 12),

              PickerField(
                label:
                    '${_toParentCollects ? "Pickup" : "Drop off"}: ${fmtTime(_pickupTime)}',
                onTap: () => _pickTime(_pickupTime, (t) => _pickupTime = t),
              ),
              const SizedBox(height: 6),
              _label(context, 'Who brings the kids?'),
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

              if (kind == RequestKind.window) ...[
                const SizedBox(height: 12),
                if (!_returnTimeTbd) ...[
                  PickerField(
                    label: 'Return: ${fmtTimeOr(_returnTime, 'set a time')}',
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
                      style: TextStyle(color: cs.onSurfaceVariant)),
                ]),
                const SizedBox(height: 8),
                _label(context, 'Who handles the return?'),
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
              ],
              const SizedBox(height: 16),
            ],

            TextField(
              controller: _noteCtrl,
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),

            BusyButton(
              busy: _sending,
              onPressed: _send,
              child: Text(kind == RequestKind.swap
                  ? 'Send swap request'
                  : 'Send request'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(left: 2),
        child: Text(text,
            style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );

  /// "You have the kids that day" / "Jana has the kids that day", in the error
  /// colour when it doesn't fit the swap (e.g. giving away a day that isn't
  /// yours).
  Widget _ownerHint(BuildContext context, ResolutionEngine engine,
      DateTime date, String myName, {required bool expectMine}) {
    final cs = Theme.of(context).colorScheme;
    final owner = engine.dayOwner(date);
    if (owner == 'Both') return const SizedBox.shrink();
    final mine = owner == myName;
    final fits = mine == expectMine;
    final color = fits ? cs.onSurfaceVariant : cs.error;
    return Padding(
      padding: const EdgeInsets.only(top: 4, left: 4),
      child: Row(
        children: [
          Icon(fits ? Icons.info_outline : Icons.warning_amber_rounded,
              size: 14, color: color),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              mine ? 'You have the kids that day' : '$owner has the kids that day',
              style: TextStyle(fontSize: 12, color: color),
            ),
          ),
        ],
      ),
    );
  }

  /// Exams on the chosen date(s) for the selected children — the kind of
  /// thing worth knowing before moving the kids around.
  List<Widget> _examHints(BuildContext context, List<DateTime> dates) {
    final cs = Theme.of(context).colorScheme;
    final exams = (ref.watch(manualOverridesProvider).valueOrNull ??
            const <ManualOverride>[])
        .where((o) =>
            o.isExam &&
            dates.any((d) => sameDay(d, o.targetDate)) &&
            (_children.isEmpty ||
                o.childName == 'All' ||
                _children.contains(o.childName)))
        .toList()
      ..sort((a, b) => a.targetDate.compareTo(b.targetDate));
    if (exams.isEmpty) return const [];

    return [
      const SizedBox(height: 8),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: cs.tertiaryContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final o in exams)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Icon(Icons.school_outlined,
                        size: 16, color: cs.onTertiaryContainer),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${o.childName == 'All' ? '' : '${o.childName}: '}'
                        '${o.adhocActivity ?? 'Exam'} · ${fmtDateShort(o.targetDate)}'
                        '${o.overrideTime != null ? ' at ${o.overrideTime}' : ''}',
                        style: TextStyle(
                            fontSize: 12, color: cs.onTertiaryContainer),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ];
  }
}
