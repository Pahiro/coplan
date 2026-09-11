import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/household_provider.dart';
import '../providers/schedule_provider.dart';
import '../utils/dates.dart';
import 'common.dart';

/// Adds a child's exam papers in one go. Each paper becomes a one-off event of
/// kind "exam": it appears on Today and the calendar (with a dot in month
/// view), and as a hint when someone plans a swap or handover for that day.
class ExamTimetableSheet extends ConsumerStatefulWidget {
  final DateTime? initialDate;
  const ExamTimetableSheet({super.key, this.initialDate});

  @override
  ConsumerState<ExamTimetableSheet> createState() => _ExamTimetableSheetState();
}

class _Paper {
  DateTime date;
  TimeOfDay start;
  TimeOfDay? end;
  final TextEditingController subject = TextEditingController();

  _Paper({required this.date, required this.start, this.end});
}

class _ExamTimetableSheetState extends ConsumerState<ExamTimetableSheet> {
  String? _child;
  late final List<_Paper> _papers;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _papers = [
      _Paper(
        date: _schoolDay(dateOnly(widget.initialDate ?? DateTime.now())),
        start: const TimeOfDay(hour: 9, minute: 0),
      ),
    ];
  }

  @override
  void dispose() {
    for (final p in _papers) {
      p.subject.dispose();
    }
    super.dispose();
  }

  /// [d], or the Monday after if it falls on a weekend.
  static DateTime _schoolDay(DateTime d) {
    var day = d;
    while (day.weekday > DateTime.friday) {
      day = addDays(day, 1);
    }
    return day;
  }

  void _addPaper() {
    final last = _papers.last;
    setState(() => _papers.add(_Paper(
          date: _schoolDay(addDays(last.date, 1)),
          start: last.start,
          end: last.end,
        )));
  }

  void _removePaper(int index) {
    final removed = _papers[index];
    setState(() => _papers.removeAt(index));
    WidgetsBinding.instance
        .addPostFrameCallback((_) => removed.subject.dispose());
  }

  Future<void> _pickDate(_Paper p) async {
    final today = dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: p.date,
      firstDate: p.date.isBefore(today) ? p.date : addDays(today, -30),
      lastDate: addDays(today, 365),
    );
    if (picked != null) setState(() => p.date = picked);
  }

  Future<void> _pickTime(_Paper p, {required bool end}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: end
          ? (p.end ?? p.start.replacing(hour: (p.start.hour + 2) % 24))
          : p.start,
    );
    if (picked == null) return;
    setState(() {
      if (end) {
        p.end = picked;
      } else {
        p.start = picked;
      }
    });
  }

  Future<void> _save(String child) async {
    setState(() => _saving = true);
    try {
      await ref.read(manualOverridesNotifierProvider.notifier).createEvents([
        for (final p in _papers)
          NewEvent(
            date:      p.date,
            time:      fmtTime(p.start),
            endTime:   p.end != null ? fmtTime(p.end!) : null,
            activity:  p.subject.text.trim(),
            childName: child,
            isShared:  false,
            kind:      'exam',
          ),
      ]);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme    = Theme.of(context);
    final cs       = theme.colorScheme;
    final children = ref.watch(householdChildNamesProvider);
    final selected = _child ?? (children.length == 1 ? children.first.name : null);
    final valid    = selected != null &&
        _papers.every((p) => p.subject.text.trim().isNotEmpty);

    return Padding(
      padding: sheetPadding(context),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Exam timetable',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
              'Add each paper once — both parents see them on Today and the calendar.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 16),

            if (children.isEmpty)
              Text('Add your children in Settings → Household first.',
                  style: TextStyle(color: cs.error))
            else
              Wrap(
                spacing: 8,
                children: [
                  for (final c in children)
                    ChoiceChip(
                      label: Text(c.name),
                      selected: selected == c.name,
                      onSelected: (_) => setState(() => _child = c.name),
                    ),
                ],
              ),
            const SizedBox(height: 12),

            for (var i = 0; i < _papers.length; i++) _paperCard(context, i),

            TextButton.icon(
              onPressed: _addPaper,
              icon: const Icon(Icons.add),
              label: const Text('Add another paper'),
            ),
            const SizedBox(height: 12),

            BusyButton(
              busy: _saving,
              onPressed: valid ? () => _save(selected) : null,
              child: Text(_papers.length == 1
                  ? 'Add exam'
                  : 'Add ${_papers.length} exams'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _paperCard(BuildContext context, int index) {
    final cs = Theme.of(context).colorScheme;
    final p = _papers[index];

    Widget picker(IconData icon, String label, VoidCallback onTap) =>
        OutlinedButton.icon(
          onPressed: onTap,
          icon: Icon(icon, size: 16),
          label: Text(label, overflow: TextOverflow.ellipsis),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            visualDensity: VisualDensity.compact,
          ),
        );

    return Card(
      key: ObjectKey(p),
      margin: const EdgeInsets.only(bottom: 10),
      color: cs.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 4, 12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: p.subject,
                    autofocus: index > 0,
                    textCapitalization: TextCapitalization.sentences,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Subject / paper',
                      hintText: 'e.g. Maths P1',
                      isDense: true,
                    ),
                  ),
                ),
                if (_papers.length > 1)
                  IconButton(
                    tooltip: 'Remove paper',
                    icon: const Icon(Icons.close),
                    onPressed: () => _removePaper(index),
                  )
                else
                  const SizedBox(width: 8),
              ],
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: picker(Icons.calendar_today_outlined,
                        fmtDateShort(p.date), () => _pickDate(p)),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    flex: 3,
                    child: picker(Icons.schedule, fmtTime(p.start),
                        () => _pickTime(p, end: false)),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    flex: 3,
                    child: picker(Icons.timer_off_outlined,
                        p.end != null ? fmtTime(p.end!) : 'End',
                        () => _pickTime(p, end: true)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
