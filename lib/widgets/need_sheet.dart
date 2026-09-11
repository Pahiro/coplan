import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/need.dart';
import '../providers/needs_provider.dart';
import 'common.dart';
import 'form_fields.dart';

/// Add or edit an item on the shared "to buy" list.
class NeedSheet extends ConsumerStatefulWidget {
  final Need? existing;
  const NeedSheet({super.key, this.existing});

  @override
  ConsumerState<NeedSheet> createState() => _NeedSheetState();
}

class _NeedSheetState extends ConsumerState<NeedSheet> {
  final _titleCtrl = TextEditingController();
  final _noteCtrl  = TextEditingController();
  String _child = 'All';
  DateTime? _neededBy;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final n = widget.existing;
    if (n != null) {
      _titleCtrl.text = n.title;
      _noteCtrl.text  = n.note ?? '';
      _child          = n.childName;
      _neededBy       = n.neededBy;
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) return;
    setState(() => _saving = true);
    try {
      final notifier = ref.read(needsProvider.notifier);
      final note = _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim();
      final existing = widget.existing;
      if (existing == null) {
        await notifier.add(
            title: title, childName: _child, note: note, neededBy: _neededBy);
      } else {
        await notifier.edit(existing,
            title: title, childName: _child, note: note, neededBy: _neededBy);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final adding = widget.existing == null;

    return Padding(
      padding: sheetPadding(context),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(adding ? 'Add to the list' : 'Edit item',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            if (adding) ...[
              const SizedBox(height: 4),
              Text(
                'Either parent can tap "I\'ll get it", so it\'s only bought once.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _titleCtrl,
              autofocus: adding,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'What\'s needed',
                hintText: 'e.g. School shoes',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            ChildDropdown(
              value: _child,
              onChanged: (v) => setState(() => _child = v),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _noteCtrl,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Size, brand or link (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            EndDateField(
              value: _neededBy,
              label: 'Needed by (optional)',
              setLabel: 'Needed by',
              onChanged: (d) => setState(() => _neededBy = d),
            ),
            const SizedBox(height: 20),
            BusyButton(
              busy: _saving,
              onPressed: _titleCtrl.text.trim().isEmpty ? null : _save,
              child: Text(adding ? 'Add to the list' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }
}
