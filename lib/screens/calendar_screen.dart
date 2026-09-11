import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/resolved_event.dart';
import '../providers/absence_provider.dart';
import '../providers/refresh.dart';
import '../providers/schedule_provider.dart';
import '../utils/dates.dart';
import '../widgets/absence_banner.dart';
import '../widgets/common.dart';
import '../widgets/month_grid.dart';
import '../widgets/motion.dart';
import '../widgets/new_action_sheet.dart';
import '../widgets/timeline_card.dart';
import '../widgets/week_strip.dart';

enum _ViewMode { week, month }

class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  late DateTime _selectedDay;
  _ViewMode _viewMode = _ViewMode.week;
  // Drives the slide direction of the strip/grid transition.
  bool _navReverse = false;

  @override
  void initState() {
    super.initState();
    _selectedDay = dateOnly(DateTime.now());
  }

  // ── Navigation ────────────────────────────────────────────────────────────

  void _prev() => setState(() {
        _navReverse = true;
        _selectedDay = _viewMode == _ViewMode.week
            ? addDays(_selectedDay, -7)
            : DateTime(_selectedDay.year, _selectedDay.month - 1, 1);
      });

  void _next() => setState(() {
        _navReverse = false;
        _selectedDay = _viewMode == _ViewMode.week
            ? addDays(_selectedDay, 7)
            : DateTime(_selectedDay.year, _selectedDay.month + 1, 1);
      });

  void _goToToday() => setState(() {
        final today = dateOnly(DateTime.now());
        _navReverse = today.isBefore(_selectedDay);
        _selectedDay = today;
      });

  Future<void> _refresh(DateTime monday) async {
    refreshAppData(ref.invalidate);
    await ref
        .read(weekEventsProvider(monday).future)
        .catchError((_) => const <String, List<ResolvedEvent>>{});
  }

  // ── Labels ───────────────────────────────────────────────────────────────

  String get _navLabel {
    if (_viewMode == _ViewMode.month) {
      return DateFormat('MMMM yyyy').format(_selectedDay);
    }
    final monday = weekMonday(_selectedDay);
    final sunday = addDays(monday, 6);
    return '${DateFormat('d MMM').format(monday)} – '
        '${DateFormat('d MMM yyyy').format(sunday)}';
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  /// Swipe left/right anywhere on the strip/grid to change week or month.
  void _onSwipe(DragEndDetails details) {
    final vx = details.primaryVelocity ?? 0;
    if (vx.abs() < 200) return;
    if (vx < 0) {
      _next();
    } else {
      _prev();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs         = Theme.of(context).colorScheme;
    final monday     = weekMonday(_selectedDay);
    final weekEvents = ref.watch(weekEventsProvider(monday));
    final selectedEvents = weekEvents.valueOrNull?[isoDate(_selectedDay)] ?? [];

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        tooltip: 'New…',
        onPressed: () =>
            showNewActionSheet(context, initialDate: _selectedDay),
        child: const Icon(Icons.add),
      ),
      body: Column(
      children: [
        // ── View-mode toggle ───────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: SegmentedButton<_ViewMode>(
            segments: const [
              ButtonSegment(
                value: _ViewMode.week,
                icon: Icon(Icons.view_week_outlined),
                label: Text('Week'),
              ),
              ButtonSegment(
                value: _ViewMode.month,
                icon: Icon(Icons.calendar_month_outlined),
                label: Text('Month'),
              ),
            ],
            selected: {_viewMode},
            onSelectionChanged: (s) => setState(() => _viewMode = s.first),
            style: SegmentedButton.styleFrom(
              visualDensity: VisualDensity.compact,
            ),
          ),
        ),
        // ── Navigation header ──────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                tooltip: 'Previous',
                onPressed: _prev,
              ),
              Expanded(
                child: GestureDetector(
                  onTap: _goToToday,
                  child: Text(
                    _navLabel,
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                tooltip: 'Next',
                onPressed: _next,
              ),
            ],
          ),
        ),
        // ── Strip / grid (horizontal swipe changes week/month) ─────────────
        GestureDetector(
          onHorizontalDragEnd: _onSwipe,
          child: PageTransitionSwitcher(
            duration: const Duration(milliseconds: 300),
            reverse: _navReverse,
            transitionBuilder: (child, animation, secondaryAnimation) =>
                SharedAxisTransition(
              animation: animation,
              secondaryAnimation: secondaryAnimation,
              transitionType: SharedAxisTransitionType.horizontal,
              fillColor: Colors.transparent,
              child: child,
            ),
            child: KeyedSubtree(
              key: ValueKey(_viewMode == _ViewMode.week
                  ? 'week-${isoDate(monday)}'
                  : 'month-${_selectedDay.year}-${_selectedDay.month}'),
              child: _viewMode == _ViewMode.week
                  ? WeekStrip(
                      weekStart: monday,
                      selectedDay: _selectedDay,
                      onDaySelected: (d) => setState(() => _selectedDay = d),
                    )
                  : Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: MonthGrid(
                        month: DateTime(_selectedDay.year, _selectedDay.month),
                        selectedDay: _selectedDay,
                        onDaySelected: (d) =>
                            setState(() => _selectedDay = d),
                      ),
                    ),
            ),
          ),
        ),
        const Divider(height: 1),
        // ── Selected day label ─────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              DateFormat('EEEE, d MMMM').format(_selectedDay),
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
        ),
        // ── Absence banner for selected day ───────────────────────────────
        Builder(builder: (context) {
          final absences = ref.watch(absencePeriodsProvider).valueOrNull ?? [];
          final absence  = absences.where((a) => a.coversDate(_selectedDay)).firstOrNull;
          if (absence == null) return const SizedBox.shrink();
          return AbsenceBanner(absence: absence);
        }),
        // ── Day events (cross-fades when a different day is selected) ──────
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: KeyedSubtree(
              key: ValueKey(isoDate(_selectedDay)),
              child: weekEvents.when(
                skipLoadingOnReload: true,
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text(friendlyError(e))),
                data: (_) => RefreshIndicator(
                  onRefresh: () => _refresh(monday),
                  child: selectedEvents.isEmpty
                      ? ListView(children: [
                          const SizedBox(height: 48),
                          Center(
                            child: Text('No events this day',
                                style: TextStyle(color: cs.onSurfaceVariant)),
                          ),
                        ])
                      : AnimationLimiter(
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
                            itemCount: selectedEvents.length,
                            itemBuilder: (ctx, i) => staggeredItem(ctx,
                                position: i,
                                child: TimelineCard(event: selectedEvents[i])),
                          ),
                        ),
                ),
              ),
            ),
          ),
        ),
      ],
      ),
    );
  }
}
