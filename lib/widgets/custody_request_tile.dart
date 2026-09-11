import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/custody_request.dart';
import '../providers/auth_provider.dart';
import '../providers/custody_provider.dart';
import '../providers/household_provider.dart';
import '../utils/dates.dart';
import 'common.dart';
import 'custody_request_edit_sheet.dart';

/// A request — or both days of a swap — with the actions the current user may
/// take: accept/decline when it's addressed to them; edit, withdraw or cancel
/// when they made it.
class CustodyRequestTile extends ConsumerWidget {
  final RequestGroup group;

  const CustodyRequestTile({super.key, required this.group});

  Future<void> _respond(BuildContext context, WidgetRef ref,
      {required bool accept}) async {
    String? note;
    if (!accept) {
      // Declining without context invites a phone call — offer a reason.
      final noteCtrl = TextEditingController();
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(group.isSwap ? 'Decline swap?' : 'Decline request?'),
          content: TextField(
            controller: noteCtrl,
            autofocus: true,
            maxLines: 2,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Reason (optional)',
              hintText: 'e.g. We have a family lunch that day',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Decline'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      note = noteCtrl.text;
    }
    try {
      await ref
          .read(custodyRequestsProvider.notifier)
          .respond(group, accept: accept, note: note);
    } catch (e) {
      if (context.mounted) showErrorSnack(context, e);
    }
  }

  Future<void> _cancel(
      BuildContext context, WidgetRef ref, String otherName) async {
    final accepted = group.status == CustodyStatus.accepted;
    final ok = await confirmDialog(
      context,
      title: accepted
          ? (group.isSwap ? 'Cancel this swap?' : 'Cancel this agreement?')
          : 'Withdraw request?',
      body: accepted
          ? '${group.isSwap ? 'Both days go' : 'The day goes'} back to the '
            'normal schedule. $otherName will be notified.'
          : '$otherName will be told you withdrew it.',
      action: accepted ? 'Cancel it' : 'Withdraw',
      cancel: 'Keep',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    try {
      await ref.read(custodyRequestsProvider.notifier).deleteGroup(group);
    } catch (e) {
      if (context.mounted) showErrorSnack(context, e);
    }
  }

  String _pickupLabel(CustodyRequest r, String myName) {
    final amIToParent = myName == r.toParent;
    if (r.toParentCollects) {
      return amIToParent
          ? 'You collect at ${r.pickupTime}'
          : '${r.toParent} collects at ${r.pickupTime}';
    }
    return amIToParent
        ? '${r.fromParent} drops off at ${r.pickupTime}'
        : 'You drop off at ${r.pickupTime}';
  }

  String? _returnLabel(CustodyRequest r, String myName) {
    if (r.isDayTransfer) return null;
    final amIToParent = myName == r.toParent;
    final t = r.returnTimeTbd ? 'TBD' : (r.returnTime ?? '?');
    if (r.toParentReturns) {
      return amIToParent
          ? 'You drop back at $t'
          : '${r.toParent} drops back at $t';
    }
    return amIToParent
        ? '${r.fromParent} picks up at $t'
        : 'You pick up at $t';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs        = Theme.of(context).colorScheme;
    final myId      = ref.watch(authProvider).valueOrNull?.userId ?? '';
    final myName    = ref.watch(myDisplayNameProvider);
    final household = ref.watch(householdProvider).valueOrNull;
    final r         = group.first;
    final status    = group.status;

    final isCreator   = group.createdBy == myId;
    final isRecipient = group.requestedFrom == myId;
    final otherName = household
            ?.memberByUserId(isCreator ? group.requestedFrom : group.createdBy)
            ?.displayName ??
        'The other parent';
    final isUpcoming = !group.lastDate.isBefore(dateOnly(DateTime.now()));

    final canAct    = isRecipient && status == CustodyStatus.pending;
    final canEdit   = isCreator && isUpcoming && !group.isSwap &&
        status == CustodyStatus.pending;
    final canCancel = isCreator && isUpcoming &&
        (status == CustodyStatus.pending || status == CustodyStatus.accepted);

    final (statusColor, statusBg) = switch (status) {
      CustodyStatus.accepted  => (Colors.green,  Colors.green.withValues(alpha: 0.15)),
      CustodyStatus.declined  => (cs.error,      cs.error.withValues(alpha: 0.12)),
      CustodyStatus.completed => (cs.onSurfaceVariant, cs.onSurfaceVariant.withValues(alpha: 0.12)),
      CustodyStatus.pending   => (Colors.orange, Colors.orange.withValues(alpha: 0.15)),
    };

    final kindLabel = group.isSwap
        ? 'Day swap'
        : r.isDayTransfer ? 'Day handover' : 'Time window';
    final icon = group.isSwap
        ? Icons.sync_alt
        : r.isDayTransfer ? Icons.swap_horiz : Icons.schedule;
    final kidsLabel =
        r.childName == 'All' ? 'All children' : r.childName.split(',').join(' & ');
    final dateLabel = group.isSwap
        ? group.legs.map((l) => fmtDateShort(l.date)).join('  ⇄  ')
        : DateFormat('EEE, d MMM').format(r.date);

    final lines = <String>[
      if (group.isSwap)
        for (final leg in group.legs)
          '${leg.toParent == myName ? 'You take' : '${leg.toParent} takes'} '
              'them ${fmtDateShort(leg.date)}'
              '${leg.pickupTime == '00:00' ? '' : ' from ${leg.pickupTime}'}'
      else ...[
        _pickupLabel(r, myName),
        if (_returnLabel(r, myName) != null) _returnLabel(r, myName)!,
      ],
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: cs.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '$kindLabel · $kidsLabel',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    r.statusLabel == 'Pending' || status == CustodyStatus.pending
                        ? 'Pending'
                        : r.statusLabel,
                    style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 12),
                  ),
                ),
                if (canEdit || canCancel)
                  PopupMenuButton<String>(
                    iconSize: 18,
                    padding: EdgeInsets.zero,
                    tooltip: 'More',
                    onSelected: (action) async {
                      if (action == 'edit') {
                        await showAppSheet<void>(context,
                            builder: (_) => CustodyRequestEditSheet(request: r));
                      } else {
                        await _cancel(context, ref, otherName);
                      }
                    },
                    itemBuilder: (_) => [
                      if (canEdit)
                        const PopupMenuItem(
                          value: 'edit',
                          child: ListTile(
                            leading: Icon(Icons.edit_outlined),
                            title: Text('Edit'),
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                          ),
                        ),
                      if (canCancel)
                        PopupMenuItem(
                          value: 'cancel',
                          child: ListTile(
                            leading: Icon(Icons.event_busy_outlined, color: cs.error),
                            title: Text(
                              status == CustodyStatus.pending ? 'Withdraw' : 'Cancel',
                              style: TextStyle(color: cs.error),
                            ),
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                          ),
                        ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(dateLabel,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurfaceVariant)),
            const SizedBox(height: 6),
            for (final line in lines)
              Text(line,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
            if (!group.isSwap) ...[
              const SizedBox(height: 2),
              Text('${r.fromParent} → ${r.toParent}',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
            ],
            if (r.note != null) ...[
              const SizedBox(height: 6),
              Text('"${r.note}"',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
            ],
            if (canAct) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                          foregroundColor: cs.error,
                          side: BorderSide(color: cs.error)),
                      onPressed: () => _respond(context, ref, accept: false),
                      icon: const Icon(Icons.close, size: 16),
                      label: const Text('Decline'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _respond(context, ref, accept: true),
                      icon: const Icon(Icons.check, size: 16),
                      label: Text(group.isSwap ? 'Accept swap' : 'Accept'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
