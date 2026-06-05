import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_colors.dart';
import '../models/resolved_event.dart';
import '../providers/colors_provider.dart';
import '../providers/custody_provider.dart';
import '../providers/household_provider.dart';
import '../providers/schedule_provider.dart';
import 'custody_request_edit_sheet.dart';
import 'event_edit_sheet.dart';

/// A single scheduled event rendered as a colour-coded card.
/// Parent colour (blue = Bennet, pink = Jana) appears as a left border accent
/// and a name badge. When the event is for a single child (not "All"), a small
/// child-coloured chip is shown so split days are immediately identifiable.
class TimelineCard extends ConsumerWidget {
  final ResolvedEvent event;

  const TimelineCard({super.key, required this.event});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(colorsProvider).valueOrNull ?? const AppColors();
    final parent = event.assignedParent;
    final household = ref.watch(householdProvider).valueOrNull;
    final isHelper =
        household?.helpers.any((h) => h.displayName == parent) ?? false;

    // Dim events when a custody request has shifted responsibility for this slot.
    final isGreyed = event.custodyNote != null;
    final parentColor = colors.parentColor(parent);
    final parentLight = colors.parentLightColor(parent);

    final timeStr =
        '${event.time.hour.toString().padLeft(2, '0')}:${event.time.minute.toString().padLeft(2, '0')}';
    final endTimeStr = event.endTime != null
        ? '${event.endTime!.hour.toString().padLeft(2, '0')}:${event.endTime!.minute.toString().padLeft(2, '0')}'
        : null;

    return Opacity(
      opacity: isGreyed ? 0.45 : 1.0,
      child: Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Colour accent bar
            Container(width: 5, color: parentColor),
            // Time chip
            Container(
              width: 54,
              color: parentLight,
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      timeStr,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: parentColor,
                      ),
                    ),
                    if (endTimeStr != null) ...[
                      Text(
                        '–',
                        style: TextStyle(fontSize: 9, color: parentColor.withOpacity(0.6)),
                      ),
                      Text(
                        endTimeStr,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: parentColor,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            // Event details
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.activity,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                    const SizedBox(height: 2),
                    if (event.location.isNotEmpty)
                      Text(
                        event.location,
                        style: TextStyle(color: Colors.grey[600], fontSize: 13),
                      ),
                    if (event.custodyTransportNote != null) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(Icons.directions_car_outlined,
                              size: 12, color: Colors.grey[500]),
                          const SizedBox(width: 4),
                          Text(
                            event.custodyTransportNote!,
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    ],
                    if (event.recurringId != null) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(Icons.event_repeat_outlined,
                              size: 12, color: Colors.grey[500]),
                          const SizedBox(width: 4),
                          Text(
                            'Repeats weekly',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 6),
                    // Child chip row
                    _ChildChipRow(childName: event.childName, colors: colors),
                    if (event.overrideReason != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.info_outline,
                              size: 12, color: Colors.orange),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              event.overrideReason!,
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.orange),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (event.custodyNote != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.swap_horiz_rounded,
                              size: 12,
                              color: Colors.blue.shade600),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              event.custodyNote!,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.blue.shade700,
                                  fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (event.note != null && event.note!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.notes_outlined,
                              size: 12, color: Colors.grey[500]),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              event.note!,
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey[600]),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            // Parent badge, shared indicator, and event menu
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: parentLight,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      parent,
                      style: TextStyle(
                        color: parentColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  if (isHelper) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: parentLight,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: parentColor.withOpacity(0.4)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.volunteer_activism_outlined,
                              size: 11, color: parentColor),
                          const SizedBox(width: 3),
                          Text(
                            'Helper',
                            style: TextStyle(
                                fontSize: 10,
                                color: parentColor,
                                fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (event.isShared) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.teal.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.teal.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.people_outline,
                              size: 11, color: Colors.teal),
                          const SizedBox(width: 3),
                          Text(
                            'Both',
                            style: TextStyle(
                                fontSize: 10,
                                color: Colors.teal,
                                fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (event.ruleId != null ||
                      event.overrideId != null ||
                      event.custodyRequestId != null ||
                      event.recurringId != null) ...[
                    const SizedBox(height: 2),
                    _EventMenu(event: event),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    ));
  }
}

// ── Event context menu ────────────────────────────────────────────────────────

class _EventMenu extends ConsumerWidget {
  final ResolvedEvent event;
  const _EventMenu({required this.event});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isCustodyEvent  = event.custodyRequestId != null;
    final isAdhocOverride = event.overrideId != null && event.isAdhoc;
    final isNonAdhocOverride = event.overrideId != null && !event.isAdhoc;
    final isRule = event.ruleId != null && event.overrideId == null;
    final isRecurring = event.recurringId != null;

    return SizedBox(
      height: 24,
      width: 24,
      child: PopupMenuButton<_MenuAction>(
        padding: EdgeInsets.zero,
        iconSize: 16,
        icon: Icon(Icons.more_vert,
            size: 16,
            color: Theme.of(context).colorScheme.onSurfaceVariant),
        onSelected: (action) => _handle(context, ref, action),
        itemBuilder: (_) => [
          // Recurring (virtual) occurrences only offer "Stop repeating" — the
          // pattern is edited from the source request's repeat toggle, and a
          // single week is changed by adding a one-off request for that date.
          if (isRecurring)
            const PopupMenuItem(
              value: _MenuAction.stopRepeating,
              child: ListTile(
                leading: Icon(Icons.event_repeat_outlined, color: Colors.red),
                title: Text('Stop repeating',
                    style: TextStyle(color: Colors.red)),
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
            ),
          if (!isRecurring && (isRule || isAdhocOverride || isCustodyEvent))
            const PopupMenuItem(
              value: _MenuAction.edit,
              child: ListTile(
                leading: Icon(Icons.edit_outlined),
                title: Text('Edit'),
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
            ),
          if (!isRecurring && isNonAdhocOverride)
            const PopupMenuItem(
              value: _MenuAction.removeOverride,
              child: ListTile(
                leading: Icon(Icons.undo_outlined),
                title: Text('Remove override'),
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
            ),
          if (!isRecurring)
            const PopupMenuItem(
              value: _MenuAction.delete,
              child: ListTile(
                leading: Icon(Icons.delete_outline, color: Colors.red),
                title: Text('Delete', style: TextStyle(color: Colors.red)),
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _handle(
      BuildContext context, WidgetRef ref, _MenuAction action) async {
    // ── Recurring (virtual) occurrences ───────────────────────────────────────
    if (event.recurringId != null) {
      if (action == _MenuAction.stopRepeating) {
        final confirm = await _confirmDialog(
          context,
          title: 'Stop repeating?',
          body: 'Removes this standing arrangement from all future weeks. '
              'Past occurrences already recorded are kept.',
          action: 'Stop',
        );
        if (confirm && context.mounted) {
          await ref
              .read(recurringArrangementsNotifierProvider.notifier)
              .delete(event.recurringId!);
        }
      }
      return;
    }

    // ── Custody request events ────────────────────────────────────────────────
    if (event.custodyRequestId != null) {
      final requests = ref.read(custodyRequestsProvider).valueOrNull ?? [];
      final request = requests
          .where((r) => r.id == event.custodyRequestId)
          .firstOrNull;
      if (request == null) return;

      if (action == _MenuAction.edit) {
        if (!context.mounted) return;
        await showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          builder: (_) => CustodyRequestEditSheet(request: request),
        );
        return;
      }
      if (action == _MenuAction.delete) {
        final confirm = await _confirmDialog(
          context,
          title: 'Delete request?',
          body: 'This removes the custody request and restores the original schedule.',
          action: 'Delete',
        );
        if (confirm && context.mounted) {
          await ref
              .read(custodyRequestsProvider.notifier)
              .deleteRequest(event.custodyRequestId!);
        }
        return;
      }
    }

    switch (action) {
      case _MenuAction.stopRepeating:
        // Handled above for recurring events; unreachable here.
        return;

      case _MenuAction.edit:
        await showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          builder: (_) => EventEditSheet(event: event),
        );

      case _MenuAction.removeOverride:
        final confirm = await _confirmDialog(
          context,
          title: 'Remove override?',
          body: 'This will revert the event to the base schedule for this day.',
          action: 'Remove',
        );
        if (confirm && context.mounted) {
          await ref
              .read(manualOverridesNotifierProvider.notifier)
              .delete(event.overrideId!);
        }

      case _MenuAction.delete:
        final label = event.ruleId != null && event.overrideId == null
            ? 'Delete standing event?\n\nThis removes it from every future week.'
            : 'Delete this event?';
        final confirm = await _confirmDialog(
          context,
          title: 'Delete event?',
          body: label,
          action: 'Delete',
        );
        if (!confirm || !context.mounted) return;
        if (event.overrideId != null) {
          await ref
              .read(manualOverridesNotifierProvider.notifier)
              .delete(event.overrideId!);
        } else if (event.ruleId != null) {
          await ref
              .read(baseRulesNotifierProvider.notifier)
              .delete(event.ruleId!);
        }
    }
  }

  Future<bool> _confirmDialog(
    BuildContext context, {
    required String title,
    required String body,
    required String action,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(title),
            content: Text(body),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel')),
              TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  child: Text(action)),
            ],
          ),
        ) ??
        false;
  }
}

enum _MenuAction { edit, delete, removeOverride, stopRepeating }

class _ChildChipRow extends StatelessWidget {
  final String childName;
  final AppColors colors;
  const _ChildChipRow({required this.childName, required this.colors});

  @override
  Widget build(BuildContext context) {
    if (childName == 'All') {
      // Don't show individual child chips for "All" — the parent colour
      // already indicates ownership. Specific children are shown only when
      // the event is for a single child.
      return const SizedBox.shrink();
    }
    if (colors.isChildSpecific(childName)) {
      return _chip(childName, colors.childColor(childName));
    }
    return const SizedBox.shrink();
  }

  Widget _chip(String name, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Text(
          name,
          style: TextStyle(
              fontSize: 10, color: color, fontWeight: FontWeight.w600),
        ),
      );
}
