import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_colors.dart';
import '../models/need.dart';
import '../providers/auth_provider.dart';
import '../providers/colors_provider.dart';
import '../providers/household_provider.dart';
import '../providers/needs_provider.dart';
import '../utils/dates.dart';
import '../widgets/common.dart';
import '../widgets/need_sheet.dart';
import '../widgets/skeleton.dart';
import 'expense_form_screen.dart';

/// The shared "to buy" list: things the kids need that either parent can pick
/// up. Claiming an item ("I'll get it") stops both parents buying it; marking
/// it bought offers to share the cost as an expense.
class NeedsView extends ConsumerWidget {
  const NeedsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final needsAsync = ref.watch(needsProvider);

    Future<void> refresh() async {
      ref.invalidate(needsProvider);
      await ref.read(needsProvider.future).catchError((_) => const <Need>[]);
    }

    return needsAsync.when(
      skipLoadingOnReload: true,
      loading: () => const SkeletonList(count: 4, itemHeight: 64),
      error: (e, _) => Center(child: Text(friendlyError(e))),
      data: (needs) {
        final cutoff = addDays(dateOnly(DateTime.now()), -30);
        final open = needs.where((n) => !n.isBought).toList()
          ..sort((a, b) {
            final ad = a.neededBy, bd = b.neededBy;
            if (ad != null && bd != null) return ad.compareTo(bd);
            if (ad != null) return -1;
            if (bd != null) return 1;
            return b.created.compareTo(a.created);
          });
        final bought = needs
            .where((n) =>
                n.isBought && (n.boughtAt == null || !n.boughtAt!.isBefore(cutoff)))
            .toList()
          ..sort((a, b) =>
              (b.boughtAt ?? b.created).compareTo(a.boughtAt ?? a.created));

        return RefreshIndicator(
          onRefresh: refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
            children: [
              if (open.isEmpty && bought.isEmpty) ...[
                const SizedBox(height: 96),
                Icon(Icons.shopping_bag_outlined,
                    size: 48, color: cs.onSurfaceVariant),
                const SizedBox(height: 12),
                Text('Nothing on the list',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: cs.onSurfaceVariant)),
                const SizedBox(height: 4),
                Text(
                  'Add things the kids need — new shoes, a racket — and either '
                  'parent can pick them up.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                ),
              ],
              ...open.map((n) => _NeedTile(need: n)),
              if (bought.isNotEmpty) ...[
                Padding(
                  padding: EdgeInsets.only(top: open.isEmpty ? 0 : 16, bottom: 8),
                  child: Text('Recently bought',
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold)),
                ),
                ...bought.map((n) => _NeedTile(need: n)),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _NeedTile extends ConsumerWidget {
  final Need need;
  const _NeedTile({required this.need});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs        = Theme.of(context).colorScheme;
    final myId      = ref.watch(authProvider).valueOrNull?.userId ?? '';
    final household = ref.watch(householdProvider).valueOrNull;
    final colors    = ref.watch(colorsProvider).valueOrNull ?? const AppColors();
    String nameOf(String? id) =>
        household?.memberByUserId(id ?? '')?.displayName ?? 'Someone';

    final details = [
      if (need.childName != 'All') need.childName,
      if (need.note != null) need.note!,
      if (!need.isBought && need.neededBy != null)
        'by ${fmtDateShort(need.neededBy!)}',
      if (need.isBought)
        'Bought by ${need.boughtBy == myId ? 'you' : nameOf(need.boughtBy)}'
            '${need.expenseId != null ? ' · cost shared' : ''}',
    ];

    Widget? trailing;
    if (!need.isBought) {
      if (need.isClaimed) {
        final who = nameOf(need.claimedBy);
        trailing = Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: colors.parentLightColor(who),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            need.claimedBy == myId ? 'You\'re getting it' : '$who is getting it',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: colors.parentColor(who)),
          ),
        );
      } else {
        trailing = TextButton(
          onPressed: () =>
              _run(context, () => ref.read(needsProvider.notifier).claim(need)),
          child: const Text('I\'ll get it'),
        );
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.only(left: 4, right: 8),
        leading: IconButton(
          tooltip: need.isBought ? 'Bought' : 'Mark bought',
          icon: Icon(
            need.isBought ? Icons.check_circle : Icons.radio_button_unchecked,
            color: need.isBought ? cs.primary : cs.onSurfaceVariant,
          ),
          onPressed: need.isBought ? null : () => markNeedBought(context, ref, need),
        ),
        title: Text(
          need.title,
          style: need.isBought
              ? TextStyle(
                  decoration: TextDecoration.lineThrough,
                  color: cs.onSurfaceVariant)
              : null,
        ),
        subtitle: details.isEmpty
            ? null
            : Text(details.join(' · '), style: const TextStyle(fontSize: 12)),
        trailing: trailing,
        onTap: () => _showActions(context, ref, myId),
      ),
    );
  }

  Future<void> _showActions(
      BuildContext context, WidgetRef ref, String myId) async {
    final notifier = ref.read(needsProvider.notifier);
    final cs = Theme.of(context).colorScheme;

    Widget action(BuildContext ctx, String value, IconData icon, String label,
            {bool destructive = false}) =>
        ListTile(
          leading: Icon(icon, color: destructive ? cs.error : null),
          title: Text(label,
              style: destructive ? TextStyle(color: cs.error) : null),
          onTap: () => Navigator.pop(ctx, value),
        );

    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(need.title,
                  style: Theme.of(ctx)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
            ),
            if (!need.isBought && !need.isClaimed)
              action(ctx, 'claim', Icons.front_hand_outlined, 'I\'ll get it'),
            if (need.isClaimed && need.claimedBy == myId)
              action(ctx, 'release', Icons.undo, 'I can\'t get it after all'),
            if (!need.isBought)
              action(ctx, 'bought', Icons.check_circle_outline, 'Mark bought'),
            if (need.isBought && need.expenseId == null)
              action(ctx, 'expense', Icons.receipt_long_outlined, 'Share the cost'),
            if (need.isBought)
              action(ctx, 'reopen', Icons.replay, 'Put back on the list'),
            action(ctx, 'edit', Icons.edit_outlined, 'Edit'),
            action(ctx, 'delete', Icons.delete_outline, 'Delete', destructive: true),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == null || !context.mounted) return;

    switch (choice) {
      case 'claim':
        await _run(context, () => notifier.claim(need));
      case 'release':
        await _run(context, () => notifier.release(need));
      case 'bought':
        await markNeedBought(context, ref, need);
      case 'expense':
        await shareNeedCost(context, ref, need);
      case 'reopen':
        await _run(context, () => notifier.reopen(need));
      case 'edit':
        await showAppSheet<void>(context, builder: (_) => NeedSheet(existing: need));
      case 'delete':
        final ok = await confirmDialog(
          context,
          title: 'Delete item?',
          body: 'Remove "${need.title}" from the list?',
          action: 'Delete',
          destructive: true,
        );
        if (ok && context.mounted) {
          await _run(context, () => notifier.delete(need));
        }
    }
  }
}

Future<void> _run(BuildContext context, Future<void> Function() action) async {
  try {
    await action();
  } catch (e) {
    if (context.mounted) showErrorSnack(context, e);
  }
}

/// Marks [need] bought, then offers to share its cost as an expense.
Future<void> markNeedBought(BuildContext context, WidgetRef ref, Need need) async {
  try {
    await ref.read(needsProvider.notifier).markBought(need);
  } catch (e) {
    if (context.mounted) showErrorSnack(context, e);
    return;
  }
  if (!context.mounted) return;
  final share = await confirmDialog(
    context,
    title: 'Bought — share the cost?',
    body: 'Add "${need.title}" as a shared expense so the cost is split.',
    action: 'Add expense',
    cancel: 'Not now',
  );
  if (share && context.mounted) await shareNeedCost(context, ref, need);
}

/// Opens the expense form pre-filled from [need] and links the result.
Future<void> shareNeedCost(BuildContext context, WidgetRef ref, Need need) async {
  final expenseId = await Navigator.push<String?>(
    context,
    MaterialPageRoute(
      builder: (_) => ExpenseFormScreen(
        prefillTitle: need.title,
        prefillChild: need.childName,
      ),
    ),
  );
  if (expenseId == null) return;
  try {
    await ref.read(needsProvider.notifier).linkExpense(need, expenseId);
  } catch (_) {
    // The expense exists either way; the link is only a convenience.
  }
}
