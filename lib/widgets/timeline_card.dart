import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_colors.dart';
import '../models/custody_request.dart';
import '../models/resolved_event.dart';
import '../providers/auth_provider.dart';
import '../providers/colors_provider.dart';
import '../providers/custody_provider.dart';
import '../providers/household_provider.dart';
import '../providers/schedule_provider.dart';
import '../utils/dates.dart';
import 'common.dart';
import 'event_edit_sheet.dart';

/// A single scheduled event rendered as a colour-coded card: the responsible
/// parent's colour on the left, child/exam chips, and — when the parent isn't
/// the usual one — why (override, absence, swap or handover).
class TimelineCard extends ConsumerWidget {
  final ResolvedEvent event;

  const TimelineCard({super.key, required this.event});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs        = Theme.of(context).colorScheme;
    final colors    = ref.watch(colorsProvider).valueOrNull ?? const AppColors();
    final household = ref.watch(householdProvider).valueOrNull;
    final myId      = ref.watch(authProvider).valueOrNull?.userId ?? '';
    final parent    = event.assignedParent;
    final isHelper  =
        household?.helpers.any((h) => h.displayName == parent) ?? false;

    final parentColor = colors.parentColor(parent);
    final parentLight = colors.parentLightColor(parent);

    // The agreement behind a custody banner — only its requester may cancel.
    RequestGroup? custodyGroup;
    if (event.isCustody) {
      final accepted = ref.watch(acceptedCustodyProvider).valueOrNull ?? const [];
      final legs = accepted
          .where((r) => event.swapGroup != null
              ? r.swapGroup == event.swapGroup
              : r.id == event.custodyRequestId)
          .toList()
        ..sort((a, b) => a.date.compareTo(b.date));
      if (legs.isNotEmpty && legs.first.createdBy == myId) {
        custodyGroup = RequestGroup(legs);
      }
    }
    final hasMenu =
        event.ruleId != null || event.overrideId != null || custodyGroup != null;

    final timeStr    = fmtTime(event.time);
    final endTimeStr = event.endTime != null ? fmtTime(event.endTime!) : null;
    final specificChild = colors.isChildSpecific(event.childName);

    Widget infoRow(IconData icon, String text, Color color,
            {FontWeight? weight}) =>
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(icon, size: 12, color: color),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(text,
                    style: TextStyle(fontSize: 11.5, color: color, fontWeight: weight)),
              ),
            ],
          ),
        );

    final chips = <Widget>[
      if (event.isExam)
        _Chip(
          label: 'Exam',
          icon: Icons.school_outlined,
          color: specificChild ? colors.childColor(event.childName) : cs.tertiary,
        ),
      if (specificChild)
        _Chip(label: event.childName, color: colors.childColor(event.childName)),
    ];

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 5, color: parentColor),
            Container(
              width: 54,
              color: parentLight,
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(timeStr,
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: parentColor)),
                    if (endTimeStr != null) ...[
                      Text('–',
                          style: TextStyle(
                              fontSize: 9,
                              color: parentColor.withValues(alpha: 0.6))),
                      Text(endTimeStr,
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: parentColor)),
                    ],
                  ],
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(event.activity,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 15)),
                    if (event.location.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(event.location,
                            style: TextStyle(
                                color: cs.onSurfaceVariant, fontSize: 13)),
                      ),
                    if (event.custodyTransportNote != null)
                      infoRow(Icons.directions_car_outlined,
                          event.custodyTransportNote!, cs.onSurfaceVariant),
                    if (chips.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Wrap(spacing: 4, runSpacing: 4, children: chips),
                      ),
                    if (event.overrideReason != null)
                      infoRow(Icons.info_outline, event.overrideReason!, cs.tertiary),
                    if (event.custodyNote != null)
                      infoRow(Icons.swap_horiz_rounded, event.custodyNote!,
                          cs.primary, weight: FontWeight.w500),
                    if (event.note != null && event.note!.isNotEmpty)
                      infoRow(Icons.notes_outlined, event.note!, cs.onSurfaceVariant),
                  ],
                ),
              ),
            ),
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
                    child: Text(parent,
                        style: TextStyle(
                            color: parentColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 12)),
                  ),
                  if (isHelper) ...[
                    const SizedBox(height: 4),
                    _Chip(
                        label: 'Helper',
                        icon: Icons.volunteer_activism_outlined,
                        color: parentColor),
                  ],
                  if (event.isShared) ...[
                    const SizedBox(height: 4),
                    _Chip(label: 'Both', icon: Icons.people_outline, color: cs.secondary),
                  ],
                  if (hasMenu) ...[
                    const SizedBox(height: 2),
                    _EventMenu(event: event, custodyGroup: custodyGroup),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Event context menu ────────────────────────────────────────────────────────

enum _MenuAction { edit, delete, removeOverride, cancelCustody }

class _EventMenu extends ConsumerWidget {
  final ResolvedEvent event;
  final RequestGroup? custodyGroup;

  const _EventMenu({required this.event, this.custodyGroup});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final isRule     = event.ruleId != null && event.overrideId == null;
    final isOneOff   = event.overrideId != null && event.isAdhoc;
    final isOverride = event.overrideId != null && !event.isAdhoc;

    ListTile item(IconData icon, String label, {bool destructive = false}) =>
        ListTile(
          leading: Icon(icon, color: destructive ? cs.error : null),
          title: Text(label,
              style: destructive ? TextStyle(color: cs.error) : null),
          contentPadding: EdgeInsets.zero,
          dense: true,
        );

    return SizedBox(
      height: 24,
      width: 24,
      child: PopupMenuButton<_MenuAction>(
        padding: EdgeInsets.zero,
        iconSize: 16,
        tooltip: 'More',
        icon: Icon(Icons.more_vert, size: 16, color: cs.onSurfaceVariant),
        onSelected: (action) => _handle(context, ref, action),
        itemBuilder: (_) => [
          if (custodyGroup != null)
            PopupMenuItem(
              value: _MenuAction.cancelCustody,
              child: item(Icons.event_busy_outlined,
                  custodyGroup!.isSwap ? 'Cancel swap' : 'Cancel agreement',
                  destructive: true),
            ),
          if (isRule || isOneOff)
            PopupMenuItem(
                value: _MenuAction.edit, child: item(Icons.edit_outlined, 'Edit')),
          if (isOverride)
            PopupMenuItem(
                value: _MenuAction.removeOverride,
                child: item(Icons.undo_outlined, 'Remove override')),
          if (isRule || isOneOff)
            PopupMenuItem(
                value: _MenuAction.delete,
                child: item(Icons.delete_outline, 'Delete', destructive: true)),
        ],
      ),
    );
  }

  Future<void> _handle(
      BuildContext context, WidgetRef ref, _MenuAction action) async {
    try {
      switch (action) {
        case _MenuAction.cancelCustody:
          final group = custodyGroup!;
          final other = ref
                  .read(householdProvider)
                  .valueOrNull
                  ?.memberByUserId(group.requestedFrom)
                  ?.displayName ??
              'The other parent';
          final ok = await confirmDialog(
            context,
            title: group.isSwap ? 'Cancel this swap?' : 'Cancel this agreement?',
            body: '${group.isSwap ? 'Both days go' : 'The day goes'} back to '
                'the normal schedule. $other will be notified.',
            action: 'Cancel it',
            cancel: 'Keep',
            destructive: true,
          );
          if (ok) {
            await ref.read(custodyRequestsProvider.notifier).deleteGroup(group);
          }

        case _MenuAction.edit:
          await showAppSheet<void>(context,
              builder: (_) => EventEditSheet(event: event));

        case _MenuAction.removeOverride:
          final ok = await confirmDialog(
            context,
            title: 'Remove override?',
            body: 'This will revert the event to the base schedule for this day.',
            action: 'Remove',
            destructive: true,
          );
          if (ok) {
            await ref
                .read(manualOverridesNotifierProvider.notifier)
                .delete(event.overrideId!);
          }

        case _MenuAction.delete:
          final standing = event.ruleId != null && event.overrideId == null;
          final ok = await confirmDialog(
            context,
            title: event.isExam ? 'Delete exam?' : 'Delete event?',
            body: standing
                ? 'This removes it from every week.'
                : 'This removes it for everyone.',
            action: 'Delete',
            destructive: true,
          );
          if (!ok) return;
          if (standing) {
            await ref.read(baseRulesNotifierProvider.notifier).delete(event.ruleId!);
          } else {
            await ref
                .read(manualOverridesNotifierProvider.notifier)
                .delete(event.overrideId!);
          }
      }
    } catch (e) {
      if (context.mounted) showErrorSnack(context, e);
    }
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color color;

  const _Chip({required this.label, required this.color, this.icon});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 11, color: color),
              const SizedBox(width: 3),
            ],
            Text(label,
                style: TextStyle(
                    fontSize: 10, color: color, fontWeight: FontWeight.w600)),
          ],
        ),
      );
}
