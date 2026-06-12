import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/app_colors.dart';
import '../models/resolved_event.dart';
import '../providers/absence_provider.dart';
import '../providers/colors_provider.dart';
import '../providers/custody_provider.dart';
import '../providers/expense_provider.dart';
import '../providers/schedule_provider.dart';
import '../providers/update_provider.dart';
import '../services/notification_service.dart';
import '../services/update_service.dart';
import '../services/widget_cache_service.dart';
import '../utils/dates.dart';
import '../widgets/absence_banner.dart';
import '../widgets/motion.dart';
import '../widgets/new_action_sheet.dart';
import '../widgets/skeleton.dart';
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
                loading: () => const SkeletonList(count: 5, itemHeight: 84),
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

    final todayAbsence    = absences.where((a) => a.coversDate(today)).firstOrNull;
    final tomorrowAbsence = absences.where((a) => a.coversDate(tomorrow)).firstOrNull;

    final todayEvents    = events.where((e) => sameDay(e.date, today)).toList();
    final tomorrowEvents = events.where((e) => sameDay(e.date, tomorrow)).toList();

    // Staggered entrance: cards cascade in with a subtle fade + rise.
    var position = 0;
    Widget item(Widget child) =>
        staggeredItem(context, position: position++, child: child);

    return AnimationLimiter(
        child: ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
      children: [
        item(const _ExpenseSummaryCard()),
        item(_SectionLabel(
            'Today — ${DateFormat('EEEE, d MMMM').format(today)}',
            date: today)),
        if (todayAbsence != null) item(AbsenceBanner(absence: todayAbsence)),
        if (todayEvents.isEmpty)
          item(const _EmptySlot())
        else
          ...todayEvents.map((e) => item(TimelineCard(event: e))),
        const SizedBox(height: 20),
        item(_SectionLabel(
            'Tomorrow — ${DateFormat('EEEE, d MMMM').format(tomorrow)}',
            date: tomorrow)),
        if (tomorrowAbsence != null)
          item(AbsenceBanner(absence: tomorrowAbsence)),
        if (tomorrowEvents.isEmpty)
          item(const _EmptySlot())
        else
          ...tomorrowEvents.map((e) => item(TimelineCard(event: e))),
      ],
    ));
  }
}

/// Section header. When [date] is given (and the household runs in custody
/// mode) a colour-coded "X has the kids" chip answers the app's most basic
/// question at a glance.
class _SectionLabel extends ConsumerWidget {
  final String text;
  final DateTime? date;
  const _SectionLabel(this.text, {this.date});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final owner =
        date != null ? ref.watch(dayOwnerProvider(date!)) : null;
    final colors = ref.watch(colorsProvider).valueOrNull ?? const AppColors();

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(text,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
          ),
          CrossFadeSwitcher(
            child: owner == null
                ? const SizedBox.shrink(key: ValueKey('no-owner'))
                : Container(
                    key: ValueKey(owner),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: colors.parentLightColor(owner),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$owner has the kids',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colors.parentColor(owner),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
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

// ── Expense summary card ──────────────────────────────────────────────────────

class _ExpenseSummaryCard extends ConsumerWidget {
  const _ExpenseSummaryCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(expenseSummaryProvider).valueOrNull;
    if (summary == null || summary.isEmpty) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    final positive = Theme.of(context).brightness == Brightness.dark
        ? Colors.green.shade400
        : Colors.green.shade700;
    final net = summary.netCents;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(Icons.account_balance_wallet_outlined,
                size: 22, color: cs.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Net first — the number one actually settles. Counts
                  // up/down to its new value when the balance changes.
                  if (net != 0)
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: net.abs() / 100),
                      duration: const Duration(milliseconds: 600),
                      curve: Curves.easeOutCubic,
                      builder: (_, value, __) => Text(
                        net > 0
                            ? 'Net: you are owed R ${value.toStringAsFixed(2)}'
                            : 'Net: you owe R ${value.toStringAsFixed(2)}',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: net > 0 ? positive : cs.error),
                      ),
                    ),
                  if (summary.owedToYou > 0 && summary.youOwe > 0)
                    Text(
                      'Owed to you ${summary.owedToYouFormatted} · '
                      'you owe ${summary.youOweFormatted}',
                      style: TextStyle(
                          fontSize: 11, color: cs.onSurfaceVariant),
                    ),
                  if (summary.overdueCount > 0)
                    Text('${summary.overdueCount} overdue',
                        style: TextStyle(fontSize: 11, color: cs.error)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
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
                        color: scheme.onPrimaryContainer.withValues(alpha: 0.8)),
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

