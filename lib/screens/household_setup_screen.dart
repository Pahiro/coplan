import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';
import '../providers/household_provider.dart';

/// Post-registration wizard: create a new household or join an existing one
/// via invite code.
class HouseholdSetupScreen extends ConsumerStatefulWidget {
  const HouseholdSetupScreen({super.key});

  @override
  ConsumerState<HouseholdSetupScreen> createState() =>
      _HouseholdSetupScreenState();
}

class _HouseholdSetupScreenState extends ConsumerState<HouseholdSetupScreen> {
  _SetupMode _mode = _SetupMode.choose;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Set Up Your Family'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: () => ref.read(authProvider.notifier).logout(),
          ),
        ],
      ),
      body: SafeArea(
        child: switch (_mode) {
          _SetupMode.choose  => _ChoosePanel(
              onCreateNew: () => setState(() => _mode = _SetupMode.create),
              onJoin:      () => setState(() => _mode = _SetupMode.join),
            ),
          _SetupMode.create  => _CreateHouseholdPanel(
              onBack: () => setState(() => _mode = _SetupMode.choose),
            ),
          _SetupMode.join    => _JoinHouseholdPanel(
              onBack: () => setState(() => _mode = _SetupMode.choose),
            ),
        },
      ),
    );
  }
}

enum _SetupMode { choose, create, join }

// ── Choose: create or join ───────────────────────────────────────────────────

class _ChoosePanel extends StatelessWidget {
  final VoidCallback onCreateNew;
  final VoidCallback onJoin;

  const _ChoosePanel({required this.onCreateNew, required this.onJoin});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.family_restroom, size: 64, color: Color(0xFF1565C0)),
          const SizedBox(height: 24),
          Text('Welcome to CoPlan!',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            'Create a family to start scheduling, or join one '
            'if your co-parent has already set things up.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Create a family'),
              onPressed: onCreateNew,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.link),
              label: const Text('Join with invite code'),
              onPressed: onJoin,
            ),
          ),
        ],
      ),
    ),
  );
}

// ── Create household ─────────────────────────────────────────────────────────

class _CreateHouseholdPanel extends ConsumerStatefulWidget {
  final VoidCallback onBack;
  const _CreateHouseholdPanel({required this.onBack});

  @override
  ConsumerState<_CreateHouseholdPanel> createState() =>
      _CreateHouseholdPanelState();
}

class _CreateHouseholdPanelState
    extends ConsumerState<_CreateHouseholdPanel> {
  final _formKey   = GlobalKey<FormState>();
  final _nameCtrl  = TextEditingController();
  final _childCtrls = <TextEditingController>[TextEditingController()];
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    for (final c in _childCtrls) { c.dispose(); }
    super.dispose();
  }

  void _addChildField() {
    setState(() => _childCtrls.add(TextEditingController()));
  }

  void _removeChildField(int index) {
    if (_childCtrls.length <= 1) return;
    setState(() {
      _childCtrls[index].dispose();
      _childCtrls.removeAt(index);
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _saving = true; _error = null; });

    try {
      final auth = ref.read(authProvider).valueOrNull;
      final displayName = auth?.userName ?? 'Parent';

      // Create household + children atomically (passing child names through, so
      // they're created with the new household id rather than via addChild,
      // which would no-op while the provider state is still null).
      await ref.read(householdProvider.notifier).createHousehold(
            name: _nameCtrl.text.trim(),
            displayName: displayName,
            childNames: _childCtrls.map((c) => c.text).toList(),
          );

      // Refresh auth state so the app routes to the main shell
      if (mounted) {
        ref.invalidate(authProvider);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Create your family',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Family name',
                hintText: 'e.g. "Smith Family"',
                prefixIcon: Icon(Icons.home_outlined),
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 24),
            Text('Children',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...List.generate(_childCtrls.length, (i) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _childCtrls[i],
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        labelText: 'Child ${i + 1}',
                        prefixIcon: const Icon(Icons.child_care),
                        border: const OutlineInputBorder(),
                      ),
                      validator: (v) =>
                          i == 0 && (v == null || v.trim().isEmpty)
                              ? 'At least one child required'
                              : null,
                    ),
                  ),
                  if (_childCtrls.length > 1)
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: () => _removeChildField(i),
                    ),
                ],
              ),
            )),
            TextButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Add another child'),
              onPressed: _addChildField,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(
                  color: Theme.of(context).colorScheme.error, fontSize: 13)),
            ],
            const SizedBox(height: 24),
            Row(
              children: [
                TextButton(
                  onPressed: _saving ? null : widget.onBack,
                  child: const Text('Back'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: _saving ? null : _submit,
                  child: _saving
                      ? const SizedBox(height: 18, width: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Create Family'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Join household with invite code ──────────────────────────────────────────

class _JoinHouseholdPanel extends ConsumerStatefulWidget {
  final VoidCallback onBack;
  const _JoinHouseholdPanel({required this.onBack});

  @override
  ConsumerState<_JoinHouseholdPanel> createState() =>
      _JoinHouseholdPanelState();
}

class _JoinHouseholdPanelState extends ConsumerState<_JoinHouseholdPanel> {
  final _codeCtrl = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _codeCtrl.text.trim().toUpperCase();
    if (code.isEmpty) return;

    setState(() { _saving = true; _error = null; });
    try {
      await ref.read(householdProvider.notifier).acceptInvite(code);
      if (mounted) ref.invalidate(authProvider);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.link, size: 48, color: Color(0xFF1565C0)),
            const SizedBox(height: 16),
            Text('Join a family',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Enter the invite code your co-parent shared with you.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _codeCtrl,
              textCapitalization: TextCapitalization.characters,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 24, letterSpacing: 4, fontWeight: FontWeight.bold),
              decoration: const InputDecoration(
                hintText: 'ABCD-1234',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _submit(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(
                  color: Theme.of(context).colorScheme.error, fontSize: 13)),
            ],
            const SizedBox(height: 24),
            Row(
              children: [
                TextButton(
                  onPressed: _saving ? null : widget.onBack,
                  child: const Text('Back'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: _saving ? null : _submit,
                  child: _saving
                      ? const SizedBox(height: 18, width: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Join Family'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
