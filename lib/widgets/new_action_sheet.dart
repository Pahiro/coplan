import 'package:flutter/material.dart';

import 'add_event_sheet.dart';
import 'common.dart';
import 'mark_absence_sheet.dart';
import 'new_request_sheet.dart';

/// Opens the unified "New…" chooser sheet.
/// Pass [initialDate] so the event/request sheets pre-fill the selected
/// calendar day.
Future<void> showNewActionSheet(BuildContext context,
    {DateTime? initialDate}) {
  return showModalBottomSheet<void>(
    context: context,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _NewActionSheet(initialDate: initialDate),
  );
}

class _NewActionSheet extends StatelessWidget {
  final DateTime? initialDate;
  const _NewActionSheet({this.initialDate});

  void _open(BuildContext context, Widget sheet) {
    Navigator.pop(context);
    showAppSheet<void>(context, builder: (_) => sheet);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('New…',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            ListTile(
              leading: const Icon(Icons.swap_horiz),
              title: const Text('Custody request'),
              subtitle: const Text('Swap a day or arrange a time window'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () =>
                  _open(context, NewRequestSheet(initialDate: initialDate)),
            ),
            ListTile(
              leading: const Icon(Icons.event_outlined),
              title: const Text('One-off event'),
              subtitle: const Text('Activity, outing or adhoc pickup'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _open(context,
                  AddEventSheet(initialDate: initialDate ?? DateTime.now())),
            ),
            ListTile(
              leading: const Icon(Icons.hiking),
              title: const Text('Absence'),
              subtitle: const Text('Mark yourself away — custody shifts automatically'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _open(context, const MarkAbsenceSheet()),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
