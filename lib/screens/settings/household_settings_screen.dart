import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../providers/colors_provider.dart';
import '../../providers/household_provider.dart';
import '../../widgets/color_setting_row.dart';

class HouseholdSettingsScreen extends ConsumerWidget {
  const HouseholdSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final household     = ref.watch(householdProvider).valueOrNull;
    final householdMode = household?.mode ?? 'custody';

    return Scaffold(
      appBar: AppBar(title: const Text('Household')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16, 16, 16,
          16 + MediaQuery.of(context).padding.bottom,
        ),
        children: [
          // Household management card
          const _HouseholdCard(),
          const SizedBox(height: 16),

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

          // Children section
          Text(
            'Children — colours show on event cards for solo events.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Colors.grey),
          ),
          const SizedBox(height: 8),
          const _ChildrenCard(),
        ],
      ),
    );
  }
}

// ── Household management card ─────────────────────────────────────────────────

class _HouseholdCard extends ConsumerWidget {
  const _HouseholdCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors    = ref.watch(colorsProvider).valueOrNull ?? const AppColors();
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

    final members  = household.members;
    final myId     = ref.watch(authProvider).valueOrNull?.userId ?? '';
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

// ── Children management card ──────────────────────────────────────────────────

class _ChildrenCard extends ConsumerWidget {
  const _ChildrenCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors   = ref.watch(colorsProvider).valueOrNull ?? const AppColors();
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
        ...children.map((child) => ColorSettingRow(
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
