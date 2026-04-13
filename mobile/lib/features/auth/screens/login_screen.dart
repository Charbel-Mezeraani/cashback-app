import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/providers/providers.dart';
import '../../../core/theme/app_theme.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey  = GlobalKey<FormState>();
  final _email    = TextEditingController();
  final _password = TextEditingController();
  bool _obscure   = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    await ref.read(authProvider.notifier).login(
          _email.text.trim(),
          _password.text,
        );
    // Router auto-redirects when auth state changes
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);

    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 64),

                // ── Brand mark ──────────────────────────────────────────
                Container(
                  width:  56,
                  height: 56,
                  decoration: BoxDecoration(
                    color:        AppTheme.primaryBg,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(Icons.savings_rounded,
                      size: 30, color: AppTheme.primary),
                ),
                const SizedBox(height: 28),

                Text('Welcome back', style: AppTheme.display.copyWith(fontSize: 28)),
                const SizedBox(height: 8),
                const Text('Sign in to view your cashback rewards',
                    style: AppTheme.body),
                const SizedBox(height: 40),

                // ── Error banner ────────────────────────────────────────
                if (auth.error != null) ...[
                  _ErrorBanner(message: auth.error!),
                  const SizedBox(height: 20),
                ],

                // ── Email ───────────────────────────────────────────────
                _Label('Email address'),
                const SizedBox(height: 8),
                TextFormField(
                  controller:   _email,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    hintText:   'you@example.com',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                  validator: (v) =>
                      v != null && v.contains('@') ? null : 'Enter a valid email',
                ),
                const SizedBox(height: 20),

                // ── Password ────────────────────────────────────────────
                _Label('Password'),
                const SizedBox(height: 8),
                TextFormField(
                  controller:      _password,
                  obscureText:     _obscure,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    hintText:   'Min 8 characters',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(_obscure
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  validator: (v) =>
                      v != null && v.length >= 8 ? null : 'Min 8 characters',
                ),
                const SizedBox(height: 36),

                // ── Submit ──────────────────────────────────────────────
                ElevatedButton(
                  onPressed: auth.isLoading ? null : _submit,
                  child: auth.isLoading
                      ? const SizedBox(
                          height: 20, width: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2.5))
                      : const Text('Sign In'),
                ),
                const SizedBox(height: 24),

                // ── Register link ───────────────────────────────────────
                Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text("Don't have an account? ", style: AppTheme.body),
                      GestureDetector(
                        onTap: () => context.go('/register'),
                        child: Text('Sign up',
                            style: AppTheme.body.copyWith(
                              color:      AppTheme.primary,
                              fontWeight: FontWeight.w700,
                            )),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 40),

                // ── Benefits strip ──────────────────────────────────────
                const _BenefitsStrip(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          fontSize:   13,
          fontWeight: FontWeight.w600,
          color:      AppTheme.ink,
          letterSpacing: 0.1,
        ),
      );
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color:        const Color(0xFFFEF2F2),
          borderRadius: BorderRadius.circular(12),
          border:       Border.all(color: const Color(0xFFFCA5A5)),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: AppTheme.error, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(message,
                  style: const TextStyle(color: AppTheme.error, fontSize: 13)),
            ),
          ],
        ),
      );
}

class _BenefitsStrip extends StatelessWidget {
  const _BenefitsStrip();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color:        AppTheme.primaryBg,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Column(
          children: [
            _Benefit(icon: Icons.verified_outlined,        text: 'Verified purchases only'),
            SizedBox(height: 10),
            _Benefit(icon: Icons.account_balance_outlined, text: 'Real cash to your wallet'),
            SizedBox(height: 10),
            _Benefit(icon: Icons.shield_outlined,          text: 'Secure & fraud-protected'),
          ],
        ),
      );
}

class _Benefit extends StatelessWidget {
  final IconData icon;
  final String   text;
  const _Benefit({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, color: AppTheme.primary, size: 18),
          const SizedBox(width: 10),
          Text(text, style: AppTheme.body.copyWith(color: AppTheme.primaryDark)),
        ],
      );
}
