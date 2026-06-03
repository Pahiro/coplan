import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../providers/absence_provider.dart';
import '../providers/schedule_provider.dart';
import '../widgets/absence_banner.dart';
import '../widgets/add_event_sheet.dart';
import '../widgets/month_grid.dart';
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

  @override
  void initState() {
    super.initState();
    _selectedDay = DateTime.now();
  }

  // ── Navigation ────────────────────────────────────────────────────────────

  void _prev() => setState(() {
        if (_viewMode == _ViewMode.week) {
          _selectedDay = _selectedDay.subtract(const Duration(days: 7));
        } else {
          _selectedDay =
              DateTime(_selectedDay.year, _selectedDay.month - 1, 1);
        }
      });

  void _next() => setState(() {
        if (_viewMode == _ViewMode.week) {
          _selectedDay = _selectedDay.add(const Duration(days: 7));
        } else {
          _selectedDay =
              DateTime(_selectedDay.year, _selectedDay.month + 1, 1);
        }
      });

  void _goToToday() => setState(() => _selectedDay = DateTime.now());

  // ── Labels ───────────────────────────────────────────────────────────────

  String get _navLabel {
    if (_viewMode == _ViewMode.month) {
      return DateFormat('MMMM yyyy').format(_selectedDay);
    }
    final monday = weekMonday(_selectedDay);
    final sunday = monday.add(const Duration(days: 6));
    return '${DateFormat('d MMM').format(monday)} – '
        '${DateFormat('d MMM yyyy').format(sunday)}';
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final monday     = weekMonday(_selectedDay);
    final weekEvents = ref.watch(weekEventsProvider(monday));
    final selectedKey =
        '${_selectedDay.year}-'
        '${_selectedDay.month.toString().padLeft(2, '0')}-'
        '${_selectedDay.day.toString().padLeft(2, '0')}';
    final selectedEvents = weekEvents.valueOrNull?[selectedKey] ?? [];

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add to schedule',
        onPressed: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          builder: (_) => AddEventSheet(initialDate: _selectedDay),
        ),
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
                onPressed: _next,
              ),
            ],
          ),
        ),
        // ── Strip / grid ───────────────────────────────────────────────────
        if (_viewMode == _ViewMode.week)
          WeekStrip(
            weekStart: monday,
            selectedDay: _selectedDay,
            onDaySelected: (d) => setState(() => _selectedDay = d),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: MonthGrid(
              month: DateTime(_selectedDay.year, _selectedDay.month),
              selectedDay: _selectedDay,
              onDaySelected: (d) => setState(() => _selectedDay = d),
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
        // ── Day events ─────────────────────────────────────────────────────
        Expanded(
          child: weekEvents.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (_) {
              if (selectedEvents.isEmpty) {
                return const Center(
                  child: Text('No events this day',
                      style: TextStyle(color: Colors.grey)),
                );
              }
              return RefreshIndicator(
                onRefresh: () async =>
                    ref.invalidate(weekEventsProvider(monday)),
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
                  itemCount: selectedEvents.length,
                  separatorBuilder: (_, __) => const SizedBox.shrink(),
                  itemBuilder: (_, i) =>
                      TimelineCard(event: selectedEvents[i]),
                ),
              );
            },
          ),
        ),
      ],
      ),
    );
  }
}
