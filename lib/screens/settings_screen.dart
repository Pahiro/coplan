import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../models/app_colors.dart';
import '../models/rotation_scheme.dart';
import '../providers/auth_provider.dart';
import '../providers/colors_provider.dart';
import '../providers/household_provider.dart';
import '../providers/schedule_provider.dart';
import '../providers/theme_provider.dart';
import 'export_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorsAsync = ref.watch(colorsProvider);
    final themeMode   = ref.watch(themeProvider).valueOrNull ?? ThemeMode.system;
    final myName      = ref.watch(authProvider).valueOrNull?.userName ?? '';
    final household   = ref.watch(householdProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: colorsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (colors) => ListView(
          padding: EdgeInsets.fromLTRB(
            16, 16, 16,
            16 + MediaQuery.of(context).padding.bottom,
          ),
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
            // ── Household ──────────────────────────────────────────────────
            _SectionHeader('Household'),
            const _HouseholdSection(),
            const SizedBox(height: 24),

            _SectionHeader('Parent colours'),

            // Parent colour rows from household data
            ...(household?.parents ?? const []).map((m) => _ColorRow(
              label: m.displayName,
              description: "Shown on ${m.displayName}'s events and calendar blocks",
              current: colors.parentColor(m.displayName),
              isEditable: myName == m.displayName,
              onChanged: (c) =>
                  ref.read(colorsProvider.notifier).updateMyColor(c),
            )),

            // Helper colours (grandparents, nannies, …) — shown only if any
            if ((household?.helpers ?? const []).isNotEmpty) ...[
              const SizedBox(height: 24),
              _SectionHeader('Helper colours'),
              ...household!.helpers.map((m) => _ColorRow(
                label: m.displayName,
                description: "Shown when ${m.displayName} is covering a pickup",
                current: colors.parentColor(m.displayName),
                isEditable: myName == m.displayName,
                onChanged: (c) =>
                    ref.read(colorsProvider.notifier).updateMyColor(c),
              )),
            ],
            const SizedBox(height: 24),
            _SectionHeader('Children'),
            Text(
              'Children in this household. Colours show on event cards when a '
              'child has a solo event.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.grey),
            ),
            const SizedBox(height: 8),
            const _ChildrenSection(),
            const SizedBox(height: 24),
            _SectionHeader('Household mode'),
            Card(
              margin: const EdgeInsets.only(bottom: 16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                      selected: {ref.watch(householdProvider).valueOrNull?.mode ?? 'custody'},
                      onSelectionChanged: (s) =>
                          ref.read(householdProvider.notifier).updateMode(s.first),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      ref.watch(householdProvider).valueOrNull?.mode == 'shared'
                          ? 'Both parents are always responsible. '
                            'Use requests to coordinate who handles pickups.'
                          : 'Days rotate between parents by the scheme below. '
                            'Requests transfer custody for a day or time window.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
            // Only show rotation settings in custody mode
            if ((ref.watch(householdProvider).valueOrNull?.mode ?? 'custody') == 'custody') ...[
              _SectionHeader('Rotation start'),
              Text(
                'The date the cycle begins (Day 1) and which parent has the '
                'children that day.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.grey),
              ),
              const SizedBox(height: 8),
              const _RotationAnchorCard(),
              const SizedBox(height: 24),
              _SectionHeader('Rotation scheme'),
              Text(
                'How custody days rotate between parents from the start date above.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.grey),
              ),
              const SizedBox(height: 8),
              _RotationSchemePicker(ref: ref),
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
            ], // end custody-only section
            const SizedBox(height: 24),
            _SectionHeader('Data'),
            Card(
              child: ListTile(
                leading: const Icon(Icons.download),
                title: const Text('Export schedule'),
                subtitle: const Text('Download as CSV for Excel / Sheets'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ExportScreen()),
                ),
              ),
            ),
            const SizedBox(height: 24),
            // ── App version ─────────────────────────────────────────────────
            Center(
              child: FutureBuilder<PackageInfo>(
                future: PackageInfo.fromPlatform(),
                builder: (context, snap) {
                  final info = snap.data;
                  final version = info != null
                      ? 'v${info.version}+${info.buildNumber}'
                      : '...';
                  return Text(
                    'CoPlan $version',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant
                          .withOpacity(0.6),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

// ── Household management ──────────────────────────────────────────────────────

class _HouseholdSection extends ConsumerWidget {
  const _HouseholdSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(colorsProvider).valueOrNull ?? const AppColors();
    final household = ref.watch(householdProvider).valueOrNull;

    if (household == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('No active household.',
              style: TextStyle(color: Colors.grey)),
        ),
      );
    }

    final members = household.members;
    final myId = ref.watch(authProvider).valueOrNull?.userId ?? '';
    final iAmOwner = household.isOwnedBy(myId);

    return Card(
      child: Column(
        children: [
          // Name + rename
          ListTile(
            leading: const Icon(Icons.home_outlined),
            title: Text(household.name.isEmpty ? 'Household' : household.name,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('${household.parents.length} parent(s)'
                '${household.helpers.isNotEmpty ? ', ${household.helpers.length} helper(s)' : ''}'),
            trailing: TextButton(
              onPressed: () => _rename(context, ref, household.name),
              child: const Text('Rename'),
            ),
          ),
          const Divider(height: 1),

          // Members
          ...members.map((m) => ListTile(
                dense: true,
                leading: CircleAvatar(
                  radius: 16,
                  backgroundColor: m.isParent
                      ? colors.parentLightColor(m.displayName)
                      : Colors.grey.shade200,
                  child: Text(
                    m.displayName.isNotEmpty ? m.displayName[0] : '?',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: m.isParent
                          ? colors.parentColor(m.displayName)
                          : Colors.grey.shade700,
                    ),
                  ),
                ),
                title: Text(m.displayName),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Chip(
                      label: Text(
                        m.userId == household.ownerId
                            ? 'Owner'
                            : (m.isParent ? 'Parent' : 'Helper'),
                        style: const TextStyle(fontSize: 11),
                      ),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: EdgeInsets.zero,
                    ),
                    if (iAmOwner && m.userId != household.ownerId)
                      IconButton(
                        icon: const Icon(Icons.person_remove_outlined,
                            color: Colors.red),
                        tooltip: 'Remove ${m.displayName}',
                        onPressed: () =>
                            _removeMember(context, ref, m.id, m.displayName),
                      ),
                  ],
                ),
              )),
          // Transfer ownership — owner only, when another parent exists
          if (iAmOwner &&
              household.parents.any((p) => p.userId != household.ownerId)) ...[
            const Divider(height: 1),
            ListTile(
              dense: true,
              leading: const Icon(Icons.swap_horiz),
              title: const Text('Transfer ownership'),
              subtitle: const Text('Make another parent the household owner'),
              onTap: () {
                final candidates = household.parents
                    .where((p) => p.userId != household.ownerId)
                    .map((p) => MapEntry(p.userId, p.displayName))
                    .toList();
                _transferOwner(context, ref, candidates);
              },
            ),
          ],
          const Divider(height: 1),

          // Invite actions
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.person_add_outlined, size: 18),
                    label: const Text('Invite parent'),
                    onPressed: () => _invite(context, ref, 'parent'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.group_add_outlined, size: 18),
                    label: const Text('Invite helper'),
                    onPressed: () => _invite(context, ref, 'helper'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _rename(
      BuildContext context, WidgetRef ref, String current) async {
    final ctrl = TextEditingController(text: current);
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Rename household'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Household name',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, ctrl.text),
              child: const Text('Save')),
        ],
      ),
    );
    if (name != null && name.trim().isNotEmpty) {
      await ref.read(householdProvider.notifier).updateName(name.trim());
    }
  }

  Future<void> _transferOwner(BuildContext context, WidgetRef ref,
      List<MapEntry<String, String>> candidates) async {
    if (candidates.isEmpty) return;
    final chosen = await showDialog<MapEntry<String, String>>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Transfer ownership to'),
        children: candidates
            .map((c) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, c),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(c.value),
                  ),
                ))
            .toList(),
      ),
    );
    if (chosen == null || !context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Transfer ownership?'),
        content: Text(
            '${chosen.value} will become the household owner. You will no longer '
            'be able to manage members or remove people.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Transfer')),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(householdProvider.notifier).updateOwner(chosen.key);
    }
  }

  Future<void> _removeMember(
      BuildContext context, WidgetRef ref, String memberId, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Remove $name?'),
        content: Text(
            '$name will be removed from this household and will lose access to '
            'its schedule. This does not delete their account.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(householdProvider.notifier).removeMember(memberId);
    }
  }

  Future<void> _invite(
      BuildContext context, WidgetRef ref, String role) async {
    String code;
    try {
      code = await ref.read(householdProvider.notifier).createInvite(role: role);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not create invite: $e')));
      }
      return;
    }
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Invite ${role == 'parent' ? 'a parent' : 'a helper'}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Share this code. They sign up, then choose '
                '"Join with invite code" and enter it.'),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: SelectableText(
                code,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text('Expires in 72 hours.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.grey)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copy code'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: code));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Invite code copied')),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ── Children management ───────────────────────────────────────────────────────

class _ChildrenSection extends ConsumerWidget {
  const _ChildrenSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(colorsProvider).valueOrNull ?? const AppColors();
    final children = ref.watch(householdChildNamesProvider);

    return Column(
      children: [
        if (children.isEmpty)
          const Card(
            margin: EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('No children yet — add one below.',
                  style: TextStyle(color: Colors.grey)),
            ),
          ),
        ...children.map((child) => _ColorRow(
              label: child.name,
              description: "Shown on ${child.name}-specific events",
              current: colors.childColor(child.name),
              isEditable: true,
              onChanged: (c) => ref
                  .read(colorsProvider.notifier)
                  .updateChildColor(child.id, c),
              onDelete: () => _remove(context, ref, child.id, child.name),
            )),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add child'),
            onPressed: () => _add(context, ref),
          ),
        ),
      ],
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add child'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: "Child's name",
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, ctrl.text),
              child: const Text('Add')),
        ],
      ),
    );
    if (name != null && name.trim().isNotEmpty) {
      await ref.read(householdProvider.notifier).addChild(name: name.trim());
    }
  }

  Future<void> _remove(
      BuildContext context, WidgetRef ref, String id, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Remove $name?'),
        content: Text(
            "$name will be removed from the household. Existing events that "
            "reference $name stay in the record but won't match a child colour."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(householdProvider.notifier).removeChild(id);
    }
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
    final colors = ref.watch(colorsProvider).valueOrNull ?? const AppColors();
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

  /// When provided, a delete action is shown alongside the colour control.
  final VoidCallback? onDelete;

  const _ColorRow({
    required this.label,
    required this.description,
    required this.current,
    required this.isEditable,
    required this.onChanged,
    this.onDelete,
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
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            isEditable
                ? TextButton(
                    onPressed: () => _pickColor(context),
                    child: const Text('Change'),
                  )
                : Tooltip(
                    message: 'Only $label can change their own colour',
                    child: const Icon(Icons.lock_outline,
                        size: 18, color: Colors.grey),
                  ),
            if (onDelete != null)
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                tooltip: 'Remove',
                onPressed: onDelete,
              ),
          ],
        ),
      ),
    );
  }

  void _pickColor(BuildContext context) {
    // Grid of preset colours — avoids adding a colour-picker dependency.
    // Two tones per hue (deep + medium) plus neutrals for plenty of choice.
    final presets = <Color>[
      // Blues / indigos
      Colors.blue[900]!,
      Colors.blue[600]!,
      Colors.lightBlue[700]!,
      Colors.indigo[700]!,
      Colors.indigo[400]!,
      // Cyans / teals / greens
      Colors.cyan[700]!,
      Colors.teal[700]!,
      Colors.teal[400]!,
      Colors.green[700]!,
      Colors.green[500]!,
      Colors.lightGreen[700]!,
      // Yellows / ambers / oranges
      Colors.lime[800]!,
      Colors.amber[700]!,
      Colors.orange[800]!,
      Colors.deepOrange[600]!,
      // Reds / pinks / purples
      Colors.red[700]!,
      Colors.pink[600]!,
      Colors.pink[300]!,
      Colors.purple[700]!,
      Colors.purple[400]!,
      Colors.deepPurple[600]!,
      // Neutrals / browns
      Colors.brown[600]!,
      Colors.blueGrey[600]!,
      Colors.grey[700]!,
    ];

    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Choose colour for $label'),
        content: SizedBox(
          width: 300,
          child: SingleChildScrollView(
            child: Wrap(
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
                          ? Border.all(color: Colors.black, width: 3)
                          : null,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }
}

/// Dropdown to select a rotation scheme; persists choice to PocketBase.
/// Sets the rotation anchor (cycle Day 1) and which parent owns that day.
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
    // Resolve current even/odd ids, guarding against ids that aren't current
    // members (so SegmentedButton's selection always matches a segment).
    final evenId = (household.rotationParentEvenId != null &&
            ids.contains(household.rotationParentEvenId))
        ? household.rotationParentEvenId!
        : (parents.isNotEmpty ? parents.first.userId : '');
    final oddId = (household.rotationParentOddId != null &&
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
    final current = household?.rotationScheme ?? RotationScheme.weekly();

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
    final colors = ref.watch(colorsProvider).valueOrNull ?? const AppColors();
    final household = ref.watch(householdProvider).valueOrNull;
    final evenName = household?.rotationParentEvenName ?? 'A';
    final oddName  = household?.rotationParentOddName  ?? 'B';

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
            final name = isEven ? evenName : oddName;
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
