import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/app_colors.dart';
import '../models/household.dart';
import '../providers/auth_provider.dart';
import '../providers/colors_provider.dart';
import '../providers/household_provider.dart';
import '../providers/schedule_provider.dart';
import '../providers/theme_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorsAsync = ref.watch(colorsProvider);
    final themeMode   = ref.watch(themeProvider).valueOrNull ?? ThemeMode.system;
    final myName      = ref.watch(authProvider).valueOrNull?.userName ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: colorsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (colors) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Theme ──────────────────────────────────────────────────────
            _SectionHeader('Appearance'),
            Card(
              margin: const EdgeInsets.only(bottom: 16),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Theme',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 10),
                    SegmentedButton<ThemeMode>(
                      segments: const [
                        ButtonSegment(
                          value: ThemeMode.light,
                          icon: Icon(Icons.light_mode_outlined),
                          label: Text('Light'),
                        ),
                        ButtonSegment(
                          value: ThemeMode.system,
                          icon: Icon(Icons.brightness_auto_outlined),
                          label: Text('System'),
                        ),
                        ButtonSegment(
                          value: ThemeMode.dark,
                          icon: Icon(Icons.dark_mode_outlined),
                          label: Text('Dark'),
                        ),
                      ],
                      selected: {themeMode},
                      onSelectionChanged: (s) =>
                          ref.read(themeProvider.notifier).setMode(s.first),
                    ),
                  ],
                ),
              ),
            ),
            _SectionHeader('Parent colours'),

            // Dynamic parent colour rows from household data
            ...colors.parentNames.map((name) => _ColorRow(
              label: name,
              description: "Shown on $name's events and calendar blocks",
              current: colors.parentColor(name),
              isEditable: myName == name,
              onChanged: (c) =>
                  ref.read(colorsProvider.notifier).updateMyColor(c),
            )),
            const SizedBox(height: 24),
            _SectionHeader('Child colours'),
            Text(
              'Used on event cards when a child has a solo event.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.grey),
            ),
            const SizedBox(height: 8),
            // Dynamic child colour rows — provided by household children
            ...ref.watch(householdChildNamesProvider).map((child) => _ColorRow(
              label: child.name,
              description: "Shown on ${child.name}-specific events",
              current: colors.childColor(child.name),
              isEditable: true,
              onChanged: (c) => ref
                  .read(colorsProvider.notifier)
                  .updateChildColor(child.id, c),
            )),
            const SizedBox(height: 24),
            _SectionHeader('Recurring schedule'),
            Text(
              'Standing weekday custody rules — these override the week rotation '
              'every week for that day. Created via the "Repeat every …" toggle '
              'on a pickup or drop-off request.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.grey),
            ),
            const SizedBox(height: 8),
            const _RecurringRulesSection(),
          ],
        ),
      ),
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

// ─────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

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

class _ColorRow extends StatelessWidget {
  final String label;
  final String description;
  final Color current;
  final bool isEditable;
  final ValueChanged<Color> onChanged;

  const _ColorRow({
    required this.label,
    required this.description,
    required this.current,
    required this.isEditable,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: current,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        title: Text(label,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(description,
            style: const TextStyle(fontSize: 12)),
        trailing: isEditable
            ? TextButton(
                onPressed: () => _pickColor(context),
                child: const Text('Change'),
              )
            : Tooltip(
                message: 'Only $label can change their own colour',
                child: const Icon(Icons.lock_outline,
                    size: 18, color: Colors.grey),
              ),
      ),
    );
  }

  void _pickColor(BuildContext context) {
    // Simple grid of preset colours — avoids adding a colour-picker dependency
    final presets = [
      Colors.blue[800]!,
      Colors.indigo[700]!,
      Colors.purple[700]!,
      Colors.pink[700]!,
      Colors.red[700]!,
      Colors.orange[800]!,
      Colors.amber[700]!,
      Colors.green[700]!,
      Colors.teal[700]!,
      Colors.cyan[700]!,
      Colors.brown[600]!,
      Colors.blueGrey[600]!,
    ];

    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Choose colour for $label'),
        content: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: presets.map((c) {
            final isSelected = c.value == current.value;
            return GestureDetector(
              onTap: () {
                onChanged(c);
                Navigator.pop(context);
              },
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: c,
                  borderRadius: BorderRadius.circular(8),
                  border: isSelected
                      ? Border.all(
                          color: Colors.black, width: 3)
                      : null,
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
