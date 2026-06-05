import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/app_colors.dart';
import '../../models/rotation_scheme.dart';
import '../../providers/colors_provider.dart';
import '../../providers/household_provider.dart';
import '../../providers/schedule_provider.dart';

class ScheduleSettingsScreen extends ConsumerWidget {
  const ScheduleSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final household     = ref.watch(householdProvider).valueOrNull;
    final householdMode = household?.mode ?? 'custody';

    return Scaffold(
      appBar: AppBar(title: const Text('Schedule')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16, 16, 16,
          16 + MediaQuery.of(context).padding.bottom,
        ),
        children: [
          // Mode picker
          Card(
            margin: const EdgeInsets.only(bottom: 16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Mode',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 10),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'custody',
                        icon: Icon(Icons.swap_horiz, size: 18),
                        label: Text('Custody'),
                      ),
                      ButtonSegment(
                        value: 'shared',
                        icon: Icon(Icons.people_outline, size: 18),
                        label: Text('Shared'),
                      ),
                    ],
                    selected: {householdMode},
                    onSelectionChanged: (s) =>
                        ref.read(householdProvider.notifier).updateMode(s.first),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    householdMode == 'shared'
                        ? 'Both parents are always responsible. '
                          'Use requests to coordinate who handles pickups.'
                        : 'Days rotate between parents by the scheme below. '
                          'Requests transfer custody for a day or time window.',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),

          if (householdMode != 'custody') ...[
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Rotation settings apply to custody mode only.',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ),
          ] else ...[
            Text(
              'Rotation cycle start, pattern, and standing weekday rules.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.grey),
            ),
            const SizedBox(height: 8),
            const _RotationAnchorCard(),
            const SizedBox(height: 8),
            _RotationSchemePicker(ref: ref),
            const SizedBox(height: 8),
            const _HandoverSetupCard(),
            const SizedBox(height: 16),
            Text(
              'Recurring arrangements — weekly pickups and transfers.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.grey),
            ),
            const SizedBox(height: 8),
            const _RecurringArrangementsSection(),
            const SizedBox(height: 16),
            Text(
              'Weekday rules — standing day-of-week custody overrides created '
              'via the "Repeat every …" toggle on a request.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.grey),
            ),
            const SizedBox(height: 8),
            const _RecurringRulesSection(),
          ],
        ],
      ),
    );
  }
}

// ── Rotation anchor card ──────────────────────────────────────────────────────

class _RotationAnchorCard extends ConsumerWidget {
  const _RotationAnchorCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final household = ref.watch(householdProvider).valueOrNull;
    if (household == null) {
      return const Card(
        margin: EdgeInsets.only(bottom: 8),
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('No active household.',
              style: TextStyle(color: Colors.grey)),
        ),
      );
    }

    final parents = household.parents;
    final ids     = parents.map((p) => p.userId).toSet();
    final anchor  = household.rotationAnchorDate;
    final evenId  = (household.rotationParentEvenId != null &&
            ids.contains(household.rotationParentEvenId))
        ? household.rotationParentEvenId!
        : (parents.isNotEmpty ? parents.first.userId : '');
    final oddId   = (household.rotationParentOddId != null &&
            ids.contains(household.rotationParentOddId))
        ? household.rotationParentOddId!
        : (parents.length > 1 ? parents[1].userId : evenId);

    final fmt = DateFormat('EEE, d MMM yyyy');

    Future<void> save(String anchorIso, String even, String odd) =>
        ref.read(householdProvider.notifier).updateRotation(
              anchor: anchorIso,
              evenParentUserId: even,
              oddParentUserId: odd,
            );

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: anchor,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2100),
                  helpText: 'Cycle start date (Day 1)',
                );
                if (picked != null) {
                  await save(DateFormat('yyyy-MM-dd').format(picked), evenId, oddId);
                }
              },
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Cycle start (Day 1)',
                  prefixIcon: Icon(Icons.event_outlined),
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                ),
                child: Text(fmt.format(anchor)),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Who has the children on Day 1?',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 6),
            if (parents.length < 2)
              Text(
                parents.isEmpty
                    ? 'Add a parent first.'
                    : '${parents.first.displayName} — invite the co-parent to alternate weeks.',
                style: const TextStyle(fontSize: 13),
              )
            else
              SegmentedButton<String>(
                segments: parents
                    .map((p) => ButtonSegment(
                        value: p.userId, label: Text(p.displayName)))
                    .toList(),
                selected: {evenId},
                onSelectionChanged: (s) async {
                  final newEven = s.first;
                  final newOdd = parents
                      .firstWhere((p) => p.userId != newEven,
                          orElse: () => parents.first)
                      .userId;
                  await save(
                      DateFormat('yyyy-MM-dd').format(anchor), newEven, newOdd);
                },
                style: SegmentedButton.styleFrom(
                    visualDensity: VisualDensity.compact),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Rotation scheme picker ────────────────────────────────────────────────────

class _RotationSchemePicker extends StatelessWidget {
  final WidgetRef ref;
  const _RotationSchemePicker({required this.ref});

  static final _presets = [
    RotationScheme.weekly(),
    RotationScheme.twoTwoFiveFive(),
    RotationScheme.twoTwoThree(),
    RotationScheme.alternatingWeekends(),
  ];

  @override
  Widget build(BuildContext context) {
    final household = ref.watch(householdProvider).valueOrNull;
    final current   = household?.rotationScheme ?? RotationScheme.weekly();

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<String>(
              value: _presets.any((p) => p.type == current.type)
                  ? current.type
                  : 'weekly',
              decoration: const InputDecoration(
                labelText: 'Rotation pattern',
                border: OutlineInputBorder(),
              ),
              items: _presets
                  .map((s) => DropdownMenuItem(
                        value: s.type,
                        child: Text(s.label),
                      ))
                  .toList(),
              onChanged: (type) {
                if (type == null) return;
                final scheme = RotationScheme.fromJson(type, null);
                ref.read(householdProvider.notifier).updateRotationScheme(scheme);
              },
            ),
            const SizedBox(height: 12),
            Text(
              current.description,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[600],
                  ),
            ),
            const SizedBox(height: 12),
            _CyclePreview(scheme: current, ref: ref),
          ],
        ),
      ),
    );
  }
}

/// Visual row showing the rotation cycle with coloured day dots.
class _CyclePreview extends StatelessWidget {
  final RotationScheme scheme;
  final WidgetRef ref;
  const _CyclePreview({required this.scheme, required this.ref});

  @override
  Widget build(BuildContext context) {
    final colors    = ref.watch(colorsProvider).valueOrNull ?? const AppColors();
    final household = ref.watch(householdProvider).valueOrNull;
    final evenName  = household?.rotationParentEvenName ?? 'A';
    final oddName   = household?.rotationParentOddName  ?? 'B';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${scheme.cycleLength}-day cycle',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 3,
          runSpacing: 3,
          children: List.generate(scheme.cycleLength, (i) {
            final isEven = scheme.pattern[i] == 0;
            final name   = isEven ? evenName : oddName;
            return Tooltip(
              message: 'Day ${i + 1}: $name',
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: colors.parentColor(name),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            _legendDot(colors.parentColor(evenName)),
            const SizedBox(width: 4),
            Text(evenName, style: const TextStyle(fontSize: 11)),
            const SizedBox(width: 12),
            _legendDot(colors.parentColor(oddName)),
            const SizedBox(width: 4),
            Text(oddName, style: const TextStyle(fontSize: 11)),
          ],
        ),
      ],
    );
  }

  Widget _legendDot(Color color) => Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

// ── Handover setup card ───────────────────────────────────────────────────────

class _HandoverSetupCard extends ConsumerStatefulWidget {
  const _HandoverSetupCard();

  @override
  ConsumerState<_HandoverSetupCard> createState() => _HandoverSetupCardState();
}

class _HandoverSetupCardState extends ConsumerState<_HandoverSetupCard> {
  bool _expanded = false;

  // Form state
  int       _dayOfWeek = DateTime.sunday;
  TimeOfDay _timeA     = const TimeOfDay(hour: 10, minute: 0);
  TimeOfDay _timeB     = const TimeOfDay(hour: 12, minute: 0);
  bool      _saving    = false;

  String _fmtTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  String _dayName(int d) => const {
    1: 'Monday', 2: 'Tuesday', 3: 'Wednesday', 4: 'Thursday',
    5: 'Friday',  6: 'Saturday', 7: 'Sunday',
  }[d]!;

  Future<void> _save(String parentA, String parentB) async {
    setState(() => _saving = true);
    try {
      final notifier = ref.read(baseRulesNotifierProvider.notifier);
      final existing = (await ref.read(baseRulesProvider.future))
          .where((r) => r.handoverFrom != null)
          .toList();

      // Delete any old directional handover rules before recreating.
      for (final r in existing) {
        await notifier.delete(r.id);
      }

      await notifier.create(
        childName:    'All',
        dayOfWeek:    _dayOfWeek,
        eventTime:    _fmtTime(_timeA),
        activity:     'Weekly handover',
        location:     '',
        isShared:     false,
        isLogistics:  true,
        handoverFrom: parentA,
      );
      await notifier.create(
        childName:    'All',
        dayOfWeek:    _dayOfWeek,
        eventTime:    _fmtTime(_timeB),
        activity:     'Weekly handover',
        location:     '',
        isShared:     false,
        isLogistics:  true,
        handoverFrom: parentB,
      );

      if (mounted) setState(() { _expanded = false; _saving = false; });
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final household     = ref.watch(householdProvider).valueOrNull;
    final parentA       = household?.rotationParentEvenName ?? 'Parent A';
    final parentB       = household?.rotationParentOddName  ?? 'Parent B';

    final rulesAsync    = ref.watch(baseRulesProvider);
    final handoverRules = rulesAsync.valueOrNull
        ?.where((r) => r.handoverFrom != null)
        .toList() ?? [];

    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.swap_horiz_outlined),
            title: const Text('Weekly handover'),
            subtitle: handoverRules.isEmpty
                ? const Text('Not configured')
                : Text(handoverRules
                    .map((r) => '${r.handoverFrom} → ${r.eventTime}')
                    .join('  ·  ')),
            trailing: IconButton(
              icon: Icon(_expanded ? Icons.expand_less : Icons.edit_outlined),
              onPressed: () => setState(() => _expanded = !_expanded),
            ),
          ),
          if (_expanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<int>(
                    value: _dayOfWeek,
                    decoration: const InputDecoration(
                      labelText: 'Handover day',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: List.generate(7, (i) => i + 1).map((d) =>
                      DropdownMenuItem(value: d, child: Text(_dayName(d))),
                    ).toList(),
                    onChanged: (v) => setState(() => _dayOfWeek = v!),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('$parentA drops at'),
                    trailing: TextButton(
                      child: Text(_fmtTime(_timeA),
                          style: const TextStyle(fontSize: 16)),
                      onPressed: () async {
                        final t = await showTimePicker(
                          context: context, initialTime: _timeA);
                        if (t != null) setState(() => _timeA = t);
                      },
                    ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('$parentB drops at'),
                    trailing: TextButton(
                      child: Text(_fmtTime(_timeB),
                          style: const TextStyle(fontSize: 16)),
                      onPressed: () async {
                        final t = await showTimePicker(
                          context: context, initialTime: _timeB);
                        if (t != null) setState(() => _timeB = t);
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _saving ? null : () => _save(parentA, parentB),
                      child: _saving
                          ? const SizedBox(
                              height: 18, width: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Text('Save handover times'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Recurring arrangements (weekly pickups / transfers) ───────────────────────

class _RecurringArrangementsSection extends ConsumerWidget {
  const _RecurringArrangementsSection();

  static String _dayName(int dow) {
    final date = DateTime(2024, 1, 1).add(Duration(days: dow - 1));
    return DateFormat('EEEE').format(date);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(colorsProvider).valueOrNull ?? const AppColors();
    final async  = ref.watch(recurringArrangementsProvider);
    return async.when(
      loading: () => const LinearProgressIndicator(),
      error: (e, _) =>
          Text('Could not load arrangements: $e',
              style: const TextStyle(color: Colors.red)),
      data: (all) {
        final active = all.where((r) => r.active).toList()
          ..sort((a, b) => a.dayOfWeek == b.dayOfWeek
              ? a.pickupTime.compareTo(b.pickupTime)
              : a.dayOfWeek.compareTo(b.dayOfWeek));

        if (active.isEmpty) {
          return Card(
            margin: const EdgeInsets.only(bottom: 16),
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'No recurring arrangements.',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          );
        }

        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          child: Column(
            children: active.map((r) {
              final time = r.pickupTime;
              final returnLabel = r.returnTimeTbd
                  ? 'return TBD'
                  : r.returnTime != null
                      ? 'until ${r.returnTime}'
                      : null;
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: colors.parentLightColor(r.toParent),
                  child: Text(
                    r.toParent[0],
                    style: TextStyle(
                      color: colors.parentColor(r.toParent),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                title: Text('${_dayName(r.dayOfWeek)} · $time'),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${r.childName} → ${r.toParent}'
                        '${returnLabel != null ? ' ($returnLabel)' : ''}'),
                    if (r.note != null && r.note!.isNotEmpty)
                      Text(r.note!,
                          style: const TextStyle(
                              fontSize: 11, color: Colors.grey)),
                  ],
                ),
                isThreeLine:
                    r.note != null && r.note!.isNotEmpty,
              );
            }).toList(),
          ),
        );
      },
    );
  }
}

// ── Recurring weekday rules ───────────────────────────────────────────────────

class _RecurringRulesSection extends ConsumerWidget {
  const _RecurringRulesSection();

  static String _dayName(int dow) {
    // dow: 1=Monday … 7=Sunday (ISO); Jan 1 2024 was a Monday.
    final date = DateTime(2024, 1, 1).add(Duration(days: dow - 1));
    return DateFormat('EEEE').format(date);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors     = ref.watch(colorsProvider).valueOrNull ?? const AppColors();
    final rulesAsync = ref.watch(weekdayRulesProvider);
    return rulesAsync.when(
      loading: () => const LinearProgressIndicator(),
      error: (e, _) =>
          Text('Could not load rules: $e', style: const TextStyle(color: Colors.red)),
      data: (rules) {
        final active = rules.where((r) => r.active).toList()
          ..sort((a, b) => a.dayOfWeek.compareTo(b.dayOfWeek));

        if (active.isEmpty) {
          return Card(
            margin: const EdgeInsets.only(bottom: 16),
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No recurring rules — use the "Repeat every …" toggle '
                  'when creating a pickup or drop-off request.',
                  style: TextStyle(color: Colors.grey)),
            ),
          );
        }

        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          child: Column(
            children: active.map((rule) {
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: colors.parentLightColor(rule.assignedParent),
                  child: Text(
                    rule.assignedParent[0],
                    style: TextStyle(
                      color: colors.parentColor(rule.assignedParent),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                title: Text(_dayName(rule.dayOfWeek)),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${rule.assignedParent} has the kids'),
                    if (rule.reason.isNotEmpty)
                      Text(rule.reason,
                          style: const TextStyle(
                              fontSize: 11, color: Colors.grey)),
                  ],
                ),
                isThreeLine: rule.reason.isNotEmpty,
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  tooltip: 'Remove standing rule',
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: Text(
                            'Remove ${_dayName(rule.dayOfWeek)} rule?'),
                        content: Text(
                            '${rule.assignedParent} will no longer automatically '
                            'have the kids every ${_dayName(rule.dayOfWeek)}. '
                            'The week rotation will apply instead.'),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Cancel')),
                          FilledButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('Remove')),
                        ],
                      ),
                    );
                    if (confirmed == true) {
                      await ref
                          .read(weekdayRulesNotifierProvider.notifier)
                          .delete(rule.id);
                    }
                  },
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }
}
