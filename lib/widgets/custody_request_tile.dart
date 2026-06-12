import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/custody_request.dart';
import '../providers/auth_provider.dart';
import '../providers/custody_provider.dart';
import 'common.dart';
import 'custody_request_edit_sheet.dart';

class CustodyRequestTile extends ConsumerWidget {
  final CustodyRequest request;
  final String myId;

  const CustodyRequestTile({
    super.key,
    required this.request,
    required this.myId,
  });

  /// Declining without context invites a phone call — offer an optional note
  /// so the reason travels with the request.
  Future<void> _decline(BuildContext context, WidgetRef ref) async {
    final noteCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Decline request?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
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
          ],
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
    if (confirmed == true) {
      await ref
          .read(custodyRequestsProvider.notifier)
          .respond(request.id, accept: false, note: noteCtrl.text);
    }
  }

  String _pickupLabel(String myName) {
    final amIToParent = myName == request.toParent;
    if (request.toParentCollects) {
      return amIToParent
          ? 'You collect at ${request.pickupTime}'
          : '${request.toParent} collects at ${request.pickupTime}';
    } else {
      return amIToParent
          ? '${request.fromParent} drops off at ${request.pickupTime}'
          : 'You drop off at ${request.pickupTime}';
    }
  }

  String? _returnLabel(String myName) {
    if (request.isDayTransfer) return null;
    final amIToParent = myName == request.toParent;
    final t = request.returnTimeTbd ? 'TBD' : (request.returnTime ?? '?');
    if (request.toParentReturns) {
      return amIToParent
          ? 'You drop back at $t'
          : '${request.toParent} drops back at $t';
    } else {
      return amIToParent
          ? '${request.fromParent} picks up at $t'
          : 'You pick up at $t';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth        = ref.watch(authProvider).valueOrNull;
    final myName      = auth?.userName?.trim() ?? '';
    final isCreator   = request.createdBy == myId;
    final isRecipient = request.requestedFrom == myId;
    final canAct      = isRecipient && request.status == CustodyStatus.pending;
    // Only window requests (with a return time) have a "completed" state.
    final canComplete = isCreator &&
        request.status == CustodyStatus.accepted &&
        !request.isDayTransfer;

    final (statusColor, statusBg) = switch (request.status) {
      CustodyStatus.accepted  => (Colors.green,  Colors.green.withValues(alpha: 0.15)),
      CustodyStatus.declined  => (Colors.red,    Colors.red.withValues(alpha: 0.15)),
      CustodyStatus.completed => (Colors.grey,   Colors.grey.withValues(alpha: 0.15)),
      CustodyStatus.pending   => (Colors.orange, Colors.orange.withValues(alpha: 0.15)),
    };

    final kindLabel = request.isDayTransfer ? 'Day transfer' : 'Handover';
    final icon      = request.isDayTransfer ? Icons.swap_horiz : Icons.swap_vert;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ────────────────────────────────────────────────────
            Row(
              children: [
                Icon(icon, size: 18,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '$kindLabel · ${request.childName} · '
                    '${DateFormat('EEE, d MMM').format(request.date)}',
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
                    request.statusLabel,
                    style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 12),
                  ),
                ),
                if (isCreator && request.status == CustodyStatus.pending)
                  PopupMenuButton<_TileAction>(
                    iconSize: 18,
                    padding: EdgeInsets.zero,
                    onSelected: (action) async {
                      if (action == _TileAction.edit) {
                        await showAppSheet<void>(context,
                            builder: (_) =>
                                CustodyRequestEditSheet(request: request));
                      } else {
                        final ok = await confirmDialog(context,
                            title: 'Delete request?',
                            body: 'This cannot be undone.',
                            action: 'Delete',
                            destructive: true);
                        if (ok && context.mounted) {
                          await ref
                              .read(custodyRequestsProvider.notifier)
                              .deleteRequest(request.id);
                        }
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: _TileAction.edit,
                        child: ListTile(
                          leading: Icon(Icons.edit_outlined),
                          title: Text('Edit'),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                        ),
                      ),
                      PopupMenuItem(
                        value: _TileAction.delete,
                        child: ListTile(
                          leading: Icon(Icons.delete_outline, color: Colors.red),
                          title: Text('Delete',
                              style: TextStyle(color: Colors.red)),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 4),
            // ── Transport labels ───────────────────────────────────────────
            Text(
              _pickupLabel(myName),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
            if (_returnLabel(myName) != null) ...[
              const SizedBox(height: 2),
              Text(
                _returnLabel(myName)!,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ],
            const SizedBox(height: 2),
            Text(
              '${request.fromParent} → ${request.toParent}',
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
            if (request.note != null) ...[
              const SizedBox(height: 6),
              Text('"${request.note}"',
                  style: TextStyle(color: Colors.grey[700], fontSize: 13)),
            ],
            // ── Accept / Decline — recipient of a pending request ──────────
            if (canAct) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red)),
                      onPressed: () => _decline(context, ref),
                      icon: const Icon(Icons.close, size: 16),
                      label: const Text('Decline'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => ref
                          .read(custodyRequestsProvider.notifier)
                          .respond(request.id, accept: true),
                      icon: const Icon(Icons.check, size: 16),
                      label: const Text('Accept'),
                    ),
                  ),
                ],
              ),
            ],
            // ── Mark complete — creator of an accepted window request ───────
            if (canComplete) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => ref
                      .read(custodyRequestsProvider.notifier)
                      .complete(request.id),
                  icon: const Icon(Icons.done_all, size: 16),
                  label: const Text('Mark completed (kids returned)'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

enum _TileAction { edit, delete }
