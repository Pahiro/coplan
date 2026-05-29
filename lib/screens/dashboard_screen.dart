import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../core/constants.dart';
import '../models/resolved_event.dart';
import '../providers/auth_provider.dart';
import '../providers/custody_provider.dart';
import '../providers/household_provider.dart';
import '../providers/schedule_provider.dart';
import '../providers/update_provider.dart';
import '../services/update_service.dart';
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
      body: Column(
        children: [
          const _UpdateBanner(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: dashboard.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) =>
                    Center(child: Text('Error loading schedule: $e')),
                data: (events) => _ScheduleList(events: events),
              ),
            ),
          ),
        ],
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
  /// Recipient of the request: '__parent__' = the co-parent (rotation flow),
  /// otherwise a helper's user id.
  String     _recipientKey     = '__parent__';
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
      // Resolve a helper recipient, if one was selected.
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
            childName:        _child,
            pickupTime:       _fmtTime(_pickupTime),
            returnTime:       (_hasReturnTime && !_returnTimeTbd)
                                  ? _fmtTime(_returnTime)
                                  : null,
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
    final myName    = auth?.userName?.trim() ?? 'Parent';
    final household = ref.read(householdProvider).valueOrNull;
    final otherName = household?.parents
        .where((m) => m.displayName != myName)
        .map((m) => m.displayName)
        .firstOrNull ?? 'Co-parent';

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
                ref.read(householdProvider).valueOrNull?.mode == 'shared'
                    ? 'New pickup request'
                    : 'New custody request',
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
    final household  = ref.read(householdProvider).valueOrNull;
    final helpers    = household?.helpers ?? const [];
    final isHelper   = _recipientKey != '__parent__';
    final helperName = isHelper
        ? (helpers
                .where((h) => h.userId == _recipientKey)
                .map((h) => h.displayName)
                .firstOrNull ??
            'Helper')
        : '';
    // Who ends up with the kids (toName) vs who releases them (fromName).
    final toName   = isHelper ? helperName : (_iAmTaking ? myName : otherName);
    final fromName = isHelper ? myName : (_iAmTaking ? otherName : myName);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Recipient: co-parent (rotation) or a helper
        if (helpers.isNotEmpty) ...[
          DropdownButtonFormField<String>(
            value: _recipientKey,
            decoration: const InputDecoration(
              labelText: 'Who has the kids?',
              border: OutlineInputBorder(),
            ),
            items: [
              DropdownMenuItem(
                  value: '__parent__', child: Text('$otherName (co-parent)')),
              ...helpers.map((h) => DropdownMenuItem(
                  value: h.userId, child: Text('${h.displayName} (helper)'))),
            ],
            onChanged: (v) => setState(() {
              _recipientKey = v ?? '__parent__';
              _toParentCollects = true;
              _toParentReturns  = false;
              if (_recipientKey != '__parent__') _repeatWeekly = false;
            }),
          ),
          const SizedBox(height: 16),
        ],

        // Direction: who ends up with the kids (co-parent requests only)
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
              _iAmTaking = s.first;
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
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ]),
          const SizedBox(height: 8),
        ] else if (!isHelper) ...[
          // Repeat weekly only makes sense for co-parent day transfers
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

class _ChildSelector extends ConsumerWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const _ChildSelector({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final children = ref.watch(householdChildNamesProvider);
    final items = ['All', ...children.map((c) => c.name)];
    return DropdownButtonFormField<String>(
      value: items.contains(value) ? value : 'All',
      decoration: const InputDecoration(
          labelText: 'Child', border: OutlineInputBorder()),
      items: items
          .map((name) => DropdownMenuItem(
                value: name,
                child: Text(name == 'All' ? 'All children' : name),
              ))
          .toList(),
      onChanged: (v) => onChanged(v ?? 'All'),
    );
  }
}

// ── In-app update banner ──────────────────────────────────────────────────────

class _UpdateBanner extends ConsumerStatefulWidget {
  const _UpdateBanner();

  @override
  ConsumerState<_UpdateBanner> createState() => _UpdateBannerState();
}

class _UpdateBannerState extends ConsumerState<_UpdateBanner> {
  bool _dismissed = false;

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();
    final info = ref.watch(updateProvider).valueOrNull;
    if (info == null) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
        child: Row(
          children: [
            Icon(Icons.system_update, color: scheme.onPrimaryContainer, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Update available',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: scheme.onPrimaryContainer)),
                  Text(
                    info.latestVersion.isEmpty
                        ? 'A newer version is ready to install'
                        : 'Version ${info.latestVersion} is ready to install',
                    style: TextStyle(
                        fontSize: 12,
                        color: scheme.onPrimaryContainer.withOpacity(0.8)),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                builder: (_) => _UpdateSheet(info: info),
              ),
              child: const Text('Update'),
            ),
            IconButton(
              icon: Icon(Icons.close, color: scheme.onPrimaryContainer, size: 20),
              tooltip: 'Dismiss',
              onPressed: () => setState(() => _dismissed = true),
            ),
          ],
        ),
      ),
    );
  }
}

class _UpdateSheet extends StatefulWidget {
  final UpdateInfo info;
  const _UpdateSheet({required this.info});

  @override
  State<_UpdateSheet> createState() => _UpdateSheetState();
}

class _UpdateSheetState extends State<_UpdateSheet> {
  double? _progress; // null = idle, 0..1 = downloading
  bool _installing = false;
  String? _error;

  bool get _busy => _progress != null || _installing;

  Future<void> _run() async {
    setState(() {
      _progress = 0;
      _error = null;
    });
    try {
      final file = await UpdateService.download(
        widget.info.apkUrl,
        (p) => setState(() => _progress = p),
      );
      setState(() => _installing = true);
      await UpdateService.install(file);
      // The system installer is now in the foreground; close the sheet.
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() {
        _error = '$e';
        _progress = null;
        _installing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24, right: 24, top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.system_update),
              const SizedBox(width: 10),
              Text(
                widget.info.latestVersion.isEmpty
                    ? 'Update CoPlan'
                    : 'Update to ${widget.info.latestVersion}',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          if (widget.info.notes != null) ...[
            const SizedBox(height: 12),
            Text(widget.info.notes!,
                style: Theme.of(context).textTheme.bodyMedium),
          ],
          const SizedBox(height: 20),
          if (_progress != null) ...[
            LinearProgressIndicator(value: _installing ? null : _progress),
            const SizedBox(height: 8),
            Text(
              _installing
                  ? 'Opening installer…'
                  : 'Downloading… ${((_progress ?? 0) * 100).toStringAsFixed(0)}%',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (_error != null) ...[
            Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _busy ? null : _run,
              icon: const Icon(Icons.download),
              label: Text(_error != null ? 'Retry' : 'Download & install'),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'CoPlan will ask permission to install. The app will close while the '
            'installer runs.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

