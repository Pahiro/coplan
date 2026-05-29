import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/pb_client.dart';
import '../providers/auth_provider.dart';

/// Registration screen — creates a new PocketBase user account.
/// After successful registration the user is logged in automatically
/// and routed to the household setup wizard.
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

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
  bool _showUrl = false;

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

    // On success the app's home rebuilds to the household setup wizard, but this
    // RegisterScreen is pushed on top of the login screen — pop it so the new
    // home is revealed instead of leaving the user staring at the form.
    if (!mounted) return;
    final auth = ref.read(authProvider);
    if (!auth.hasError && (auth.valueOrNull?.isLoggedIn ?? false)) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final isLoading = auth.isLoading;
    final errorMsg = auth.hasError ? auth.error.toString() : null;

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
                  Text('Join CoPlan to coordinate your family schedule',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.grey,
                          )),
                  const SizedBox(height: 16),
                  // Server URL (collapsible)
                  GestureDetector(
                    onTap: () => setState(() => _showUrl = !_showUrl),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.dns_outlined, size: 14, color: Colors.grey[600]),
                        const SizedBox(width: 4),
                        Text(
                          _showUrl ? 'Hide server URL' : 'Server URL',
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                        Icon(
                          _showUrl ? Icons.expand_less : Icons.expand_more,
                          size: 16, color: Colors.grey[600],
                        ),
                      ],
                    ),
                  ),
                  if (_showUrl) ...[
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _urlCtrl,
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'PocketBase URL',
                        hintText: 'http://192.168.1.100:8090',
                        prefixIcon: Icon(Icons.link),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Server URL required';
                        final uri = Uri.tryParse(v);
                        if (uri == null || !uri.hasScheme) return 'Enter a valid URL';
                        return null;
                      },
                    ),
                  ],
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
