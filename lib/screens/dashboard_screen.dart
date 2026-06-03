import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/resolved_event.dart';
import '../providers/absence_provider.dart';
import '../providers/custody_provider.dart';
import '../providers/schedule_provider.dart';
import '../providers/update_provider.dart';
import '../services/notification_service.dart';
import '../services/update_service.dart';
import '../services/widget_cache_service.dart';
import '../widgets/absence_banner.dart';
import '../widgets/new_action_sheet.dart';
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
    ref.invalidate(updateProvider); // re-check for a newer build
    await WidgetCacheService.updateCache();
  }

  @override
  Widget build(BuildContext context) {
    final dashboard = ref.watch(dashboardProvider);

    return Scaffold(
      body: Column(
        children: [
          const _UpdateBanner(),
          const _BatteryBanner(),
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
      floatingActionButton: FloatingActionButton(
        tooltip: 'New…',
        onPressed: () => showNewActionSheet(context),
        child: const Icon(Icons.add),
      ),
    );
  }
}

// ── Schedule list ─────────────────────────────────────────────────────────────

class _ScheduleList extends ConsumerWidget {
  final List<ResolvedEvent> events;
  const _ScheduleList({required this.events});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today    = DateTime.now();
    final tomorrow = today.add(const Duration(days: 1));
    final absences = ref.watch(absencePeriodsProvider).valueOrNull ?? [];

    bool sameDay(DateTime a, DateTime b) =>
        a.year == b.year && a.month == b.month && a.day == b.day;

    final todayAbsence    = absences.where((a) => a.coversDate(today)).firstOrNull;
    final tomorrowAbsence = absences.where((a) => a.coversDate(tomorrow)).firstOrNull;

    final todayEvents    = events.where((e) => sameDay(e.date, today)).toList();
    final tomorrowEvents = events.where((e) => sameDay(e.date, tomorrow)).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
      children: [
        _SectionLabel('Today — ${DateFormat('EEEE, d MMMM').format(today)}'),
        if (todayAbsence != null) AbsenceBanner(absence: todayAbsence),
        if (todayEvents.isEmpty)
          const _EmptySlot()
        else
          ...todayEvents.map((e) => TimelineCard(event: e)),
        const SizedBox(height: 20),
        _SectionLabel('Tomorrow — ${DateFormat('EEEE, d MMMM').format(tomorrow)}'),
        if (tomorrowAbsence != null) AbsenceBanner(absence: tomorrowAbsence),
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


// ── Battery optimisation banner ───────────────────────────────────────────────
//
// Shown when Android still has CoPlan under battery optimisation, which
// suppresses background notifications. Dismissed for the session once the user
// taps "Fix" (the system dialog may grant the exemption).

class _BatteryBanner extends StatefulWidget {
  const _BatteryBanner();

  @override
  State<_BatteryBanner> createState() => _BatteryBannerState();
}

class _BatteryBannerState extends State<_BatteryBanner>
    with WidgetsBindingObserver {
  bool? _optimized;   // null = not checked yet
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-check when returning from the system settings dialog.
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    final v = await NotificationService.isBatteryOptimized();
    if (mounted) setState(() => _optimized = v);
  }

  @override
  Widget build(BuildContext context) {
    // Show only when battery optimisation is confirmed ON and not dismissed.
    if (_optimized != true || _dismissed) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.errorContainer,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(Icons.notifications_paused_outlined,
                  size: 20, color: theme.colorScheme.onErrorContainer),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Background notifications may be blocked — tap Fix to allow them.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.onErrorContainer,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                onPressed: () async {
                  await NotificationService.requestBatteryExemption();
                  // The system dialog will resume the app — didChangeAppLifecycleState
                  // will re-check. Dismiss immediately so the banner goes away if
                  // the user granted the exemption or chose to ignore it.
                  setState(() => _dismissed = true);
                },
                child: const Text('Fix', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              IconButton(
                icon: Icon(Icons.close, size: 18,
                    color: theme.colorScheme.onErrorContainer),
                visualDensity: VisualDensity.compact,
                tooltip: 'Dismiss',
                onPressed: () => setState(() => _dismissed = true),
              ),
            ],
          ),
        ),
      ),
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

