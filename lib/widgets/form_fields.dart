import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/household_provider.dart';

/// Shared form fields used by the event / request bottom sheets.
/// Previously each sheet carried its own private copies of these.

/// Tappable read-only field styled like an outlined input — used for
/// date and time pickers.
class PickerField extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final IconData icon;

  const PickerField({
    super.key,
    required this.label,
    required this.onTap,
    this.icon = Icons.schedule_outlined,
  });

  /// Convenience constructor with the calendar icon.
  const PickerField.date({
    super.key,
    required this.label,
    required this.onTap,
  }) : icon = Icons.calendar_today_outlined;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: InputDecorator(
          decoration: InputDecoration(
            prefixIcon: Icon(icon),
            border: const OutlineInputBorder(),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          ),
          child: Text(label, style: Theme.of(context).textTheme.bodyLarge),
        ),
      );
}

/// (isoWeekday, display name) pairs, Monday first.
const kWeekdays = [
  (1, 'Monday'),
  (2, 'Tuesday'),
  (3, 'Wednesday'),
  (4, 'Thursday'),
  (5, 'Friday'),
  (6, 'Saturday'),
  (7, 'Sunday'),
];

class DayOfWeekField extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  const DayOfWeekField({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<int>(
        initialValue: value,
        decoration: const InputDecoration(
          labelText: 'Day of week',
          prefixIcon: Icon(Icons.repeat_outlined),
          border: OutlineInputBorder(),
        ),
        items: kWeekdays
            .map((d) => DropdownMenuItem(value: d.$1, child: Text(d.$2)))
            .toList(),
        onChanged: (v) => onChanged(v ?? DateTime.monday),
      );
}

/// Dropdown of the household's children plus "All children".
class ChildDropdown extends ConsumerWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const ChildDropdown({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final names = ref
        .watch(householdChildNamesProvider)
        .map((c) => c.name)
        .toList()
      ..insert(0, 'All');
    return DropdownButtonFormField<String>(
      initialValue: names.contains(value) ? value : 'All',
      decoration: const InputDecoration(
          labelText: 'Child', border: OutlineInputBorder()),
      items: names
          .map((name) => DropdownMenuItem(
                value: name,
                child: Text(name == 'All' ? 'All children' : name),
              ))
          .toList(),
      onChanged: (v) => onChanged(v ?? 'All'),
    );
  }
}

/// Multi-select chip row for choosing which children a request covers.
/// An empty [selected] set means "All children".
class ChildChips extends ConsumerWidget {
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;
  const ChildChips({super.key, required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final children = ref.watch(householdChildNamesProvider);
    if (children.isEmpty) return const SizedBox.shrink();

    final allSelected = selected.isEmpty || selected.length == children.length;
    return InputDecorator(
      decoration: const InputDecoration(
        labelText: 'Children',
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      child: Wrap(
        spacing: 8,
        children: [
          FilterChip(
            label: const Text('All'),
            selected: allSelected,
            onSelected: (_) => onChanged({}),
          ),
          ...children.map((c) => FilterChip(
                label: Text(c.name),
                selected: !allSelected && selected.contains(c.name),
                onSelected: (on) {
                  final next = Set<String>.from(selected);
                  if (on) {
                    next.add(c.name);
                  } else {
                    next.remove(c.name);
                  }
                  // If all individually selected, collapse back to "All".
                  onChanged(next.length == children.length ? {} : next);
                },
              )),
        ],
      ),
    );
  }
}

/// "All" or empty → empty set; "Henri,Chris" → {"Henri","Chris"}.
Set<String> parseChildSelection(String v) =>
    (v == 'All' || v.isEmpty) ? {} : v.split(',').map((s) => s.trim()).toSet();

/// Empty set (or every child selected) → "All"; otherwise comma-joined names.
String encodeChildSelection(Set<String> s, [List<String>? allNames]) =>
    s.isEmpty || (allNames != null && s.length == allNames.length)
        ? 'All'
        : s.toList().join(',');
