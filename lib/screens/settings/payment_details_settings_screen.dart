import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/payment_details_provider.dart';

class PaymentDetailsSettingsScreen extends ConsumerStatefulWidget {
  const PaymentDetailsSettingsScreen({super.key});

  @override
  ConsumerState<PaymentDetailsSettingsScreen> createState() =>
      _PaymentDetailsSettingsScreenState();
}

class _PaymentDetailsSettingsScreenState
    extends ConsumerState<PaymentDetailsSettingsScreen> {
  final _formKey     = GlobalKey<FormState>();
  final _bankCtrl    = TextEditingController();
  final _holderCtrl  = TextEditingController();
  final _accountCtrl = TextEditingController();
  final _branchCtrl  = TextEditingController();
  final _linkCtrl    = TextEditingController();
  final _refCtrl     = TextEditingController();
  final _notesCtrl   = TextEditingController();

  bool _loaded = false;
  bool _saving = false;

  @override
  void dispose() {
    _bankCtrl.dispose();
    _holderCtrl.dispose();
    _accountCtrl.dispose();
    _branchCtrl.dispose();
    _linkCtrl.dispose();
    _refCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _populateFromExisting() {
    final details = ref.read(myPaymentDetailsProvider).valueOrNull;
    if (details != null && !_loaded) {
      _bankCtrl.text    = details.bankName ?? '';
      _holderCtrl.text  = details.accountHolder ?? '';
      _accountCtrl.text = details.accountNumber ?? '';
      _branchCtrl.text  = details.branchCode ?? '';
      _linkCtrl.text    = details.paymentLink ?? '';
      _refCtrl.text     = details.paymentReference ?? '';
      _notesCtrl.text   = details.notes ?? '';
      _loaded = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final detailsAsync = ref.watch(myPaymentDetailsProvider);

    // Populate fields once data loads
    detailsAsync.whenData((_) => _populateFromExisting());

    return Scaffold(
      appBar: AppBar(title: const Text('Payment Details')),
      body: detailsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (_) => Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Your banking details are visible to other household members '
                'so they know where to send payments.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey,
                    ),
              ),
              const SizedBox(height: 16),

              // Bank details section
              Text('Bank Details',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextFormField(
                controller: _bankCtrl,
                decoration: const InputDecoration(
                  labelText: 'Bank name',
                  hintText: 'e.g. FNB, Capitec',
                  prefixIcon: Icon(Icons.account_balance),
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _holderCtrl,
                decoration: const InputDecoration(
                  labelText: 'Account holder',
                  prefixIcon: Icon(Icons.person),
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _accountCtrl,
                decoration: const InputDecoration(
                  labelText: 'Account number',
                  prefixIcon: Icon(Icons.numbers),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _branchCtrl,
                decoration: const InputDecoration(
                  labelText: 'Branch code',
                  hintText: 'Universal branch code',
                  prefixIcon: Icon(Icons.tag),
                ),
                keyboardType: TextInputType.number,
              ),

              const SizedBox(height: 24),

              // Payment link section
              Text('Payment Link',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextFormField(
                controller: _linkCtrl,
                decoration: const InputDecoration(
                  labelText: 'Payment link',
                  hintText: 'Snapscan, PayFast, Zapper URL',
                  prefixIcon: Icon(Icons.link),
                ),
                keyboardType: TextInputType.url,
              ),

              const SizedBox(height: 24),

              // Reference & notes
              Text('Reference',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextFormField(
                controller: _refCtrl,
                decoration: const InputDecoration(
                  labelText: 'Default payment reference',
                  hintText: 'e.g. KIDS-<month>',
                  prefixIcon: Icon(Icons.receipt),
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _notesCtrl,
                decoration: const InputDecoration(
                  labelText: 'Notes',
                  hintText: 'Any extra instructions',
                  prefixIcon: Icon(Icons.notes),
                ),
                maxLines: 2,
              ),

              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save),
                label: Text(_saving ? 'Saving…' : 'Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(myPaymentDetailsProvider.notifier).save(
            bankName:         _bankCtrl.text.trim(),
            accountHolder:    _holderCtrl.text.trim(),
            accountNumber:    _accountCtrl.text.trim(),
            branchCode:       _branchCtrl.text.trim(),
            paymentLink:      _linkCtrl.text.trim(),
            paymentReference: _refCtrl.text.trim(),
            notes:            _notesCtrl.text.trim(),
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment details saved')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
