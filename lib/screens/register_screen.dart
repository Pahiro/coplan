import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/pb_client.dart';
import '../providers/auth_provider.dart';
import '../providers/household_provider.dart';
import '../providers/invite_provider.dart';
import '../widgets/server_url_field.dart';

/// Registration screen — creates a new PocketBase user account.
///
/// If [inviteCode] is provided (from a deep link or URL param), the account is
/// automatically joined to the invited household immediately after registration.
class RegisterScreen extends ConsumerStatefulWidget {
  final String? inviteCode;
  const RegisterScreen({super.key, this.inviteCode});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey  = GlobalKey<FormState>();
  final _nameCtrl  = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl  = TextEditingController();
  final _urlCtrl   = TextEditingController();
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _loadSavedUrl();
  }

  Future<void> _loadSavedUrl() async {
    final prefs = await SharedPreferences.getInstance();
    _urlCtrl.text = getSavedPbUrl(prefs);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    // Apply URL change if edited
    final prefs = await SharedPreferences.getInstance();
    final newUrl = _urlCtrl.text.trim();
    if (newUrl.isNotEmpty && newUrl != getSavedPbUrl(prefs)) {
      await setPocketBaseUrl(newUrl, prefs);
    }

    await ref.read(authProvider.notifier).register(
      email:    _emailCtrl.text.trim(),
      password: _passCtrl.text,
      name:     _nameCtrl.text.trim(),
    );

    if (!mounted) return;
    final auth = ref.read(authProvider);
    if (!auth.hasError && (auth.valueOrNull?.isLoggedIn ?? false)) {
      // If an invite code is present, auto-accept it now so the user lands
      // directly in the app without seeing the household setup wizard.
      final code = widget.inviteCode ?? ref.read(pendingInviteProvider);
      if (code != null) {
        try {
          await ref.read(householdProvider.notifier).acceptInvite(code);
          ref.read(pendingInviteProvider.notifier).state = null;
        } catch (e) {
          // Invite acceptance failed — user will land on household setup where
          // they can try the code again.
        }
      }
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final isLoading = auth.isLoading;
    final errorMsg = auth.hasError ? auth.error.toString() : null;
    final inviteCode = widget.inviteCode ?? ref.watch(pendingInviteProvider);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.family_restroom,
                      size: 80, color: Color(0xFF1565C0)),
                  const SizedBox(height: 16),
                  Text('Create Account',
                      style: Theme.of(context).textTheme.headlineLarge),
                  const SizedBox(height: 4),
                  Text(
                    inviteCode != null
                        ? "You'll be joined to your family after sign-up."
                        : 'Join CoPlan to coordinate your family schedule',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey,
                        ),
                    textAlign: TextAlign.center,
                  ),

                  // Invite badge
                  if (inviteCode != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.link,
                              size: 14,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onPrimaryContainer),
                          const SizedBox(width: 6),
                          Text(
                            'Invite: $inviteCode',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onPrimaryContainer,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 16),
                  ServerUrlField(controller: _urlCtrl),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _nameCtrl,
                    textInputAction: TextInputAction.next,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Your name',
                      prefixIcon: Icon(Icons.person_outline),
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Name required' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.email_outlined),
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        (v == null || !v.contains('@')) ? 'Valid email required' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passCtrl,
                    obscureText: _obscure,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(
                            _obscure ? Icons.visibility : Icons.visibility_off),
                        onPressed: () =>
                            setState(() => _obscure = !_obscure),
                      ),
                    ),
                    validator: (v) =>
                        (v == null || v.length < 8) ? 'Min 8 characters' : null,
                  ),
                  if (errorMsg != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Registration failed. Try a different email.',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: isLoading ? null : _submit,
                      child: isLoading
                          ? const SizedBox(
                              height: 18, width: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Text('Create Account'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Already have an account? Sign in'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
