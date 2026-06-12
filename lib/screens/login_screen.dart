import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/pb_client.dart';
import '../providers/auth_provider.dart';
import '../providers/invite_provider.dart';
import '../widgets/server_url_field.dart';
import 'register_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _urlCtrl = TextEditingController();
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _loadSavedUrl();
  }

  Future<void> _loadSavedUrl() async {
    final prefs = await SharedPreferences.getInstance();
    _urlCtrl.text = getSavedPbUrl(prefs);
    _emailCtrl.text = prefs.getString('last_email') ?? '';
  }

  @override
  void dispose() {
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

    final email = _emailCtrl.text.trim();
    await prefs.setString('last_email', email);
    await ref
        .read(authProvider.notifier)
        .login(email, _passCtrl.text);
  }

  Future<void> _forgotPassword(BuildContext context) async {
    final emailCtrl = TextEditingController(text: _emailCtrl.text.trim());
    final submitted = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Reset password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
                "Enter your email and we'll send you a link to reset your password."),
            const SizedBox(height: 16),
            TextField(
              controller: emailCtrl,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.email_outlined),
              ),
              onSubmitted: (v) => Navigator.pop(context, v.trim()),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, emailCtrl.text.trim()),
              child: const Text('Send link')),
        ],
      ),
    );
    if (submitted == null || submitted.isEmpty || !context.mounted) return;

    try {
      await ref.read(authProvider.notifier).requestPasswordReset(submitted);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Password reset email sent — check your inbox.'),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not send reset email: $e')),
        );
      }
    }
  }

  void _openRegister(String? inviteCode) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RegisterScreen(inviteCode: inviteCode),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final isLoading = auth.isLoading;
    final errorMsg = auth.hasError ? auth.error.toString() : null;
    final inviteCode = ref.watch(pendingInviteProvider);

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
                  Text('CoPlan',
                      style: Theme.of(context).textTheme.headlineLarge),
                  const SizedBox(height: 4),
                  Text('Co-parenting made simple',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.grey,
                          )),

                  // Invite banner
                  if (inviteCode != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.mail_outline,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onPrimaryContainer),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              "You've been invited! Sign in or create an account to join your family.",
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onPrimaryContainer,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),
                  ServerUrlField(controller: _urlCtrl),
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
                    // Login only checks presence — the registration policy
                    // (8+ chars) shouldn't lock out older accounts.
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'Password required' : null,
                  ),
                  if (errorMsg != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Sign-in failed. Check your email and password.',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: isLoading ? null : () => _forgotPassword(context),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('Forgot password?',
                          style: TextStyle(fontSize: 13)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: isLoading ? null : _submit,
                      child: isLoading
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white),
                            )
                          : const Text('Sign in'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => _openRegister(inviteCode),
                    child: Text(inviteCode != null
                        ? 'New here? Create an account to join'
                        : 'New here? Create an account'),
                  ),

                  // APK download link on web
                  if (kIsWeb) ...[
                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.android, size: 16, color: Colors.grey),
                        const SizedBox(width: 6),
                        TextButton(
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(0, 28),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: () => launchUrl(
                            Uri.parse(
                                'https://coplan.vdgryp.co.za/coplan-latest.apk'),
                            mode: LaunchMode.externalApplication,
                          ),
                          child: const Text('Download Android app',
                              style: TextStyle(fontSize: 13, color: Colors.grey)),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
