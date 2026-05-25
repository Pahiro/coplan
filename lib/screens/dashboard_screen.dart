import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../core/constants.dart';
import '../models/resolved_event.dart';
import '../providers/auth_provider.dart';
import '../providers/custody_provider.dart';
import '../providers/schedule_provider.dart';
import '../services/widget_cache_service.dart';
import '../widgets/timeline_card.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetCacheService.updateCache();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) WidgetCacheService.updateCache();
  }

  Future<void> _refresh() async {
    ref.invalidate(dashboardProvider);
    ref.invalidate(custodyRequestsProvider);
    await WidgetCacheService.updateCache();
  }

  @override
  Widget build(BuildContext context) {
    final dashboard = ref.watch(dashboardProvider);

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: dashboard.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error loading schedule: $e')),
          data: (events) => _ScheduleList(events: events),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          builder: (_) => const _RequestSheet(),
        ),
        icon: const Icon(Icons.swap_horiz),
        label: const Text('New request'),
      ),
    );
  }
}

// ── Schedule list ─────────────────────────────────────────────────────────────

class _ScheduleList extends StatelessWidget {
  final List<ResolvedEvent> events;
  const _ScheduleList({required this.events});

  @override
  Widget build(BuildContext context) {
    final today    = DateTime.now();
    final tomorrow = today.add(const Duration(days: 1));

    bool sameDay(DateTime a, DateTime b) =>
        a.year == b.year && a.month == b.month && a.day == b.day;

    final todayEvents    = events.where((e) => sameDay(e.date, today)).toList();
    final tomorrowEvents = events.where((e) => sameDay(e.date, tomorrow)).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
      children: [
        _SectionLabel('Today — ${DateFormat('EEEE, d MMMM').format(today)}'),
        if (todayEvents.isEmpty)
          const _EmptySlot()
        else
          ...todayEvents.map((e) => TimelineCard(event: e)),
        const SizedBox(height: 20),
        _SectionLabel('Tomorrow — ${DateFormat('EEEE, d MMMM').format(tomorrow)}'),
        if (tomorrowEvents.isEmpty)
          const _EmptySlot()
        else
          ...tomorrowEvents.map((e) => TimelineCard(event: e)),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold)),
      );
}

class _EmptySlot extends StatelessWidget {
  const _EmptySlot();

  @override
  Widget build(BuildContext context) => const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('No events scheduled',
              style: TextStyle(color: Colors.grey)),
        ),
      );
}

// ── Bottom sheet ──────────────────────────────────────────────────────────────

class _RequestSheet extends ConsumerStatefulWidget {
  const _RequestSheet();

  @override
  ConsumerState<_RequestSheet> createState() => _RequestSheetState();
}

class _RequestSheetState extends ConsumerState<_RequestSheet> {
  // ── State ─────────────────────────────────────────────────────────────────
  DateTime _date     = DateTime.now();
  String   _child    = 'All';
  bool     _sending  = false;

  // ── Custody fields ────────────────────────────────────────────────────────
  bool       _iAmTaking        = true;  // direction: I take / they take
  bool       _hasReturnTime    = false; // false = day transfer, true = window
  TimeOfDay? _pickupTime;
  TimeOfDay? _returnTime;
  bool       _returnTimeTbd    = false;
  bool       _toParentCollects = true;  // true = to_parent picks up
  bool       _toParentReturns  = false; // true = to_parent drops back
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

  // ── Helpers ───────────────────────────────────────────────────────────────

  TimeOfDay _defaultPickupTime(DateTime d) =>
      d.weekday <= DateTime.friday
          ? const TimeOfDay(hour: 16, minute: 0)
          : const TimeOfDay(hour: 9, minute: 0);

  String _fmtDate(DateTime d)   => DateFormat('EEE, d MMM yyyy').format(d);
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

  // ── Submit handlers ───────────────────────────────────────────────────────

  Future<void> _sendCustody() async {
    setState(() => _sending = true);
    try {
      await ref.read(custodyRequestsProvider.notifier).createRequest(
            iAmTaking:        _iAmTaking,
            date:             _isoDate(_date),
            childName:        _child,
            pickupTime:       _fmtTime(_pickupTime),
            returnTime:       (_hasReturnTime && !_returnTimeTbd)
                                  ? _fmtTime(_returnTime)
                                  : null,
            returnTimeTbd:    _hasReturnTime && _returnTimeTbd,
            note:             _noteCtrl.text.isEmpty ? null : _noteCtrl.text,
            repeatWeekly:     _repeatWeekly && !_hasReturnTime,
            repeatReason:     _noteCtrl.text.isNotEmpty ? _noteCtrl.text : null,
            toParentCollects: _toParentCollects,
            toParentReturns:  _toParentReturns,
          );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) _showError(e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _showError(Object e) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Something went wrong'),
        content: Text('$e'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Widget _spinner() => const SizedBox(
      height: 18, width: 18,
      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white));

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final auth      = ref.read(authProvider).valueOrNull;
    final myName    = auth?.userName?.trim() ?? AppConstants.parentBennet;
    final otherName = myName == AppConstants.parentBennet
        ? AppConstants.parentJana
        : AppConstants.parentBennet;

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
            Text('New custody request',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            _buildCustodyForm(myName, otherName),
          ],
        ),
      ),
    );
  }

  // ── Custody form ──────────────────────────────────────────────────────────

  Widget _buildCustodyForm(String myName, String otherName) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Direction: who ends up with the kids
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
            _iAmTaking = s.first;
            _toParentCollects = true;
            _toParentReturns  = false;
          }),
        ),
        const SizedBox(height: 16),

        // Date
        _DatePickerField(label: _fmtDate(_date), onTap: _pickDate),
        const SizedBox(height: 12),

        // Child
        _ChildSelector(
            value: _child, onChanged: (v) => setState(() => _child = v)),
        const SizedBox(height: 12),

        // Pickup time
        _TimePickerField(
          label: '${_toParentCollects ? 'Pickup' : 'Drop off'}: ${_fmtTime(_pickupTime)}',
          onTap: () => _pickTime(_pickupTime, (t) => _pickupTime = t),
        ),
        const SizedBox(height: 6),

        // Transport direction at pickup
        _transportLabel('Who brings the kids?'),
        const SizedBox(height: 6),
        SegmentedButton<bool>(
          segments: [
            ButtonSegment(
                value: true,
                icon: const Icon(Icons.directions_walk, size: 14),
                label: Text('${_iAmTaking ? myName : otherName} picks up')),
            ButtonSegment(
                value: false,
                icon: const Icon(Icons.drive_eta, size: 14),
                label: Text('${_iAmTaking ? otherName : myName} drops off')),
          ],
          selected: {_toParentCollects},
          onSelectionChanged: (s) =>
              setState(() => _toParentCollects = s.first),
          style: SegmentedButton.styleFrom(
              visualDensity: VisualDensity.compact),
        ),
        const SizedBox(height: 4),

        // Duration: day transfer vs timed window — shown early so it's always visible
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
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ]),
          const SizedBox(height: 8),
        ] else ...[
          // Repeat weekly only makes sense for day transfers
          SwitchListTile(
            value: _repeatWeekly,
            onChanged: (v) => setState(() => _repeatWeekly = v),
            title: Text('Repeat every ${DateFormat('EEEE').format(_date)}'),
            subtitle: Text(_repeatWeekly
                ? 'Creates a standing rule — manage in Settings'
                : 'One-time request only'),
            contentPadding: EdgeInsets.zero,
          ),
        ],

        if (_hasReturnTime) ...[
          const SizedBox(height: 8),
          // Transport direction at return
          _transportLabel('Who handles the return?'),
          const SizedBox(height: 6),
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(
                  value: false,
                  icon: const Icon(Icons.directions_walk, size: 14),
                  label: Text(
                      '${_iAmTaking ? otherName : myName} picks up')),
              ButtonSegment(
                  value: true,
                  icon: const Icon(Icons.drive_eta, size: 14),
                  label: Text(
                      '${_iAmTaking ? myName : otherName} drops back')),
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
            onPressed: _sending ? null : _sendCustody,
            child: _sending
                ? _spinner()
                : Text(_hasReturnTime
                    ? 'Send Handover Request'
                    : 'Send Custody Request'),
          ),
        ),
      ],
    );
  }

  // ── Shared event form ─────────────────────────────────────────────────────

}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

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
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          ),
          child:
              Text(label, style: Theme.of(context).textTheme.bodyLarge),
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
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          ),
          child:
              Text(label, style: Theme.of(context).textTheme.bodyLarge),
        ),
      );
}

class _ChildSelector extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const _ChildSelector({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
        value: value,
        decoration: const InputDecoration(
            labelText: 'Child', border: OutlineInputBorder()),
        items: const [
          DropdownMenuItem(value: 'All',   child: Text('Both — Henri & Chris')),
          DropdownMenuItem(value: 'Henri', child: Text('Henri')),
          DropdownMenuItem(value: 'Chris', child: Text('Chris')),
        ],
        onChanged: (v) => onChanged(v ?? 'All'),
      );
}

