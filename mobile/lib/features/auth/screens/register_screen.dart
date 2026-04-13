import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/providers/providers.dart';
import '../../../core/theme/app_theme.dart';

/// 3-step registration flow:
///   Step 0 — Credentials : email + password (with strength indicator)
///   Step 1 — Verify      : 6-digit OTP sent to email
///   Step 2 — Profile     : full name + phone
///
/// Navigates to /onboarding after step 2 completes.
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _pageController = PageController();
  int _step = 0;

  // Step 0 — Credentials
  final _email    = TextEditingController();
  final _password = TextEditingController();
  final _confirm  = TextEditingController();
  bool  _obscure  = true;
  bool  _obscureConfirm = true;
  final _step0Key = GlobalKey<FormState>();

  // Step 1 — OTP
  final _otpControllers = List.generate(6, (_) => TextEditingController());
  final _otpFocusNodes  = List.generate(6, (_) => FocusNode());
  String? _devOtp;
  Timer?  _resendTimer;
  int     _resendSeconds = 60;

  // Step 2 — Profile
  final _fullName = TextEditingController();
  final _phone    = TextEditingController();
  final _step2Key = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    // If returning mid-flow (partial session), jump to correct step
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = ref.read(authProvider);
      if (auth.isAuthenticated && auth.user != null) {
        _jumpTo(2);
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _email.dispose(); _password.dispose(); _confirm.dispose();
    _fullName.dispose(); _phone.dispose();
    for (final c in _otpControllers) c.dispose();
    for (final f in _otpFocusNodes)  f.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  void _jumpTo(int step) {
    _pageController.jumpToPage(step);
    setState(() => _step = step);
  }

  void _next() {
    _pageController.nextPage(
      duration: const Duration(milliseconds: 350),
      curve:    Curves.easeInOut,
    );
    setState(() => _step++);
  }

  // ── Step 0: register with email + password ─────────────────────────────────

  Future<void> _submitStep0() async {
    if (!_step0Key.currentState!.validate()) return;

    await ref.read(authProvider.notifier).register(
      email:    _email.text.trim(),
      password: _password.text,
    );

    if (!mounted) return;
    if (ref.read(authProvider).error != null) return;

    // Skip OTP and profile steps — go straight to onboarding
    context.go('/onboarding');
  }

  // ── Step 1: verify OTP ─────────────────────────────────────────────────────

  Future<void> _submitOtp() async {
    final otp = _otpControllers.map((c) => c.text).join();
    if (otp.length < 6) return;

    final ok = await ref.read(authProvider.notifier).verifyPhone(otp);
    if (!mounted) return;
    if (ok) _next();
  }

  Future<void> _resendOtp() async {
    final otp = await ref.read(authProvider.notifier).resendOtp();
    if (!mounted) return;
    setState(() { _devOtp = otp; _resendSeconds = 60; });
    _startResendTimer();
  }

  void _startResendTimer() {
    _resendTimer?.cancel();
    setState(() => _resendSeconds = 60);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      if (_resendSeconds <= 0) {
        t.cancel();
      } else {
        setState(() => _resendSeconds--);
      }
    });
  }

  void _onOtpChanged(int index, String value) {
    if (value.length == 1 && index < 5) {
      _otpFocusNodes[index + 1].requestFocus();
    }
    if (value.isEmpty && index > 0) {
      _otpFocusNodes[index - 1].requestFocus();
    }
    if (_otpControllers.every((c) => c.text.length == 1)) {
      _submitOtp();
    }
  }

  // ── Step 2: save profile ───────────────────────────────────────────────────

  Future<void> _submitProfile() async {
    if (!_step2Key.currentState!.validate()) return;

    final ok = await ref.read(authProvider.notifier).updateProfile(
      fullName: _fullName.text.trim(),
      phone:    _phone.text.trim(),
    );

    if (!mounted) return;
    if (ok) context.go('/onboarding');
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);

    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            // Progress bar
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 20, 28, 0),
              child: _StepProgressBar(current: _step, total: 3),
            ),

            // Back / sign-in button
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 0, 0),
                child: _step == 0
                    ? TextButton.icon(
                        onPressed: () {
                          ref.read(authProvider.notifier).logout();
                          context.go('/login');
                        },
                        icon:  const Icon(Icons.arrow_back, size: 18),
                        label: const Text('Sign in'),
                      )
                    : IconButton(
                        icon:      const Icon(Icons.arrow_back),
                        onPressed: () {
                          _pageController.previousPage(
                            duration: const Duration(milliseconds: 300),
                            curve:    Curves.easeInOut,
                          );
                          setState(() => _step--);
                        },
                      ),
              ),
            ),

            // Error banner
            if (auth.error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 6),
                child: _ErrorBanner(message: auth.error!, ctx: context),
              ),

            // Pages
            Expanded(
              child: PageView(
                controller: _pageController,
                physics:    const NeverScrollableScrollPhysics(),
                children:   [
                  _CredentialsStep(
                    formKey:        _step0Key,
                    email:          _email,
                    password:       _password,
                    confirm:        _confirm,
                    obscure:        _obscure,
                    obscureConfirm: _obscureConfirm,
                    onToggle:       () => setState(() => _obscure = !_obscure),
                    onToggleConfirm:() => setState(() => _obscureConfirm = !_obscureConfirm),
                    onSubmit:       _submitStep0,
                    isLoading:      auth.isLoading,
                  ),
                  _OtpStep(
                    email:         _email.text,
                    controllers:   _otpControllers,
                    focusNodes:    _otpFocusNodes,
                    onChanged:     _onOtpChanged,
                    onResend:      _resendOtp,
                    resendSeconds: _resendSeconds,
                    devOtp:        _devOtp,
                    isLoading:     auth.isLoading,
                    onSubmit:      _submitOtp,
                  ),
                  _ProfileStep(
                    formKey:   _step2Key,
                    fullName:  _fullName,
                    phone:     _phone,
                    onSubmit:  _submitProfile,
                    isLoading: auth.isLoading,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Step 0 — Credentials
// ══════════════════════════════════════════════════════════════════════════════

class _CredentialsStep extends StatefulWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController email, password, confirm;
  final bool obscure, obscureConfirm;
  final VoidCallback onToggle, onToggleConfirm;
  final Future<void> Function() onSubmit;
  final bool isLoading;

  const _CredentialsStep({
    required this.formKey,
    required this.email,
    required this.password,
    required this.confirm,
    required this.obscure,
    required this.obscureConfirm,
    required this.onToggle,
    required this.onToggleConfirm,
    required this.onSubmit,
    required this.isLoading,
  });

  @override
  State<_CredentialsStep> createState() => _CredentialsStepState();
}

class _CredentialsStepState extends State<_CredentialsStep> {
  // Re-render strength indicator on every keystroke
  @override
  void initState() {
    super.initState();
    widget.password.addListener(() => setState(() {}));
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(28, 8, 28, 32),
        child: Form(
          key: widget.formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              const _StepHeader(
                title:    'Create your account',
                subtitle: 'Enter your email and choose a strong password',
              ),
              const SizedBox(height: 28),

              // Email
              const _Label('Email address'),
              const SizedBox(height: 8),
              TextFormField(
                controller:      widget.email,
                keyboardType:    TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  hintText:   'you@example.com',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Email is required';
                  final emailRe = RegExp(r'^[^@]+@[^@]+\.[^@]+$');
                  if (!emailRe.hasMatch(v.trim())) return 'Enter a valid email';
                  return null;
                },
              ),
              const SizedBox(height: 20),

              // Password
              const _Label('Password'),
              const SizedBox(height: 8),
              TextFormField(
                controller:      widget.password,
                obscureText:     widget.obscure,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  hintText:   'Min 8 characters',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(widget.obscure
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined),
                    onPressed: widget.onToggle,
                  ),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Password is required';
                  final errs = _passwordErrors(v);
                  if (errs.isNotEmpty) return 'Password too weak';
                  return null;
                },
              ),

              // Strength indicator + checklist
              const SizedBox(height: 12),
              _PasswordStrength(password: widget.password.text),

              const SizedBox(height: 20),

              // Confirm password
              const _Label('Confirm password'),
              const SizedBox(height: 8),
              TextFormField(
                controller:       widget.confirm,
                obscureText:      widget.obscureConfirm,
                textInputAction:  TextInputAction.done,
                onFieldSubmitted: (_) => widget.onSubmit(),
                decoration: InputDecoration(
                  hintText:   'Re-enter your password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(widget.obscureConfirm
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined),
                    onPressed: widget.onToggleConfirm,
                  ),
                ),
                validator: (v) =>
                    v == widget.password.text ? null : 'Passwords do not match',
              ),
              const SizedBox(height: 32),

              _PrimaryButton(
                label:     'Continue',
                isLoading: widget.isLoading,
                onTap:     widget.onSubmit,
              ),

              const SizedBox(height: 20),
              Center(
                child: RichText(
                  text: TextSpan(
                    style: AppTheme.caption,
                    children: const [
                      TextSpan(text: 'By continuing you agree to our '),
                      TextSpan(
                        text:  'Terms of Service',
                        style: TextStyle(
                          color:      AppTheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}

// ── Password strength helpers ─────────────────────────────────────────────────

List<String> _passwordErrors(String pw) {
  final errors = <String>[];
  if (pw.length < 8)         errors.add('8 characters');
  if (!RegExp(r'[A-Z]').hasMatch(pw)) errors.add('uppercase');
  if (!RegExp(r'[a-z]').hasMatch(pw)) errors.add('lowercase');
  if (!RegExp(r'[0-9]').hasMatch(pw)) errors.add('number');
  return errors;
}

int _strengthScore(String pw) {
  int score = 0;
  if (pw.length >= 8)                      score++;
  if (RegExp(r'[A-Z]').hasMatch(pw))       score++;
  if (RegExp(r'[a-z]').hasMatch(pw))       score++;
  if (RegExp(r'[0-9]').hasMatch(pw))       score++;
  if (RegExp(r'[^A-Za-z0-9]').hasMatch(pw)) score++;
  return score;
}

class _PasswordStrength extends StatelessWidget {
  final String password;
  const _PasswordStrength({required this.password});

  @override
  Widget build(BuildContext context) {
    if (password.isEmpty) return const SizedBox.shrink();

    final score   = _strengthScore(password);
    final label   = score <= 1 ? 'Weak' : score <= 3 ? 'Medium' : 'Strong';
    final barColor = score <= 1
        ? const Color(0xFFEF4444)
        : score <= 3
            ? const Color(0xFFF59E0B)
            : AppTheme.primary;
    final fraction = score / 5;

    final rules = [
      ('8+ characters',      password.length >= 8),
      ('Uppercase letter',   RegExp(r'[A-Z]').hasMatch(password)),
      ('Lowercase letter',   RegExp(r'[a-z]').hasMatch(password)),
      ('Number',             RegExp(r'[0-9]').hasMatch(password)),
      ('Special character',  RegExp(r'[^A-Za-z0-9]').hasMatch(password)),
    ];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color:        AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border:       Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Bar + label
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value:           fraction,
                    backgroundColor: AppTheme.border,
                    valueColor:      AlwaysStoppedAnimation(barColor),
                    minHeight:       6,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(
                  fontSize:   12,
                  fontWeight: FontWeight.w700,
                  color:      barColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Checklist
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: rules.map((r) => _RuleChip(label: r.$1, met: r.$2)).toList(),
          ),
        ],
      ),
    );
  }
}

class _RuleChip extends StatelessWidget {
  final String label;
  final bool   met;
  const _RuleChip({required this.label, required this.met});

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding:  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color:        met ? AppTheme.primaryBg : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: met ? AppTheme.primary.withOpacity(0.4) : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Icon(
                met ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                key:   ValueKey(met),
                size:  13,
                color: met ? AppTheme.primary : AppTheme.inkMuted,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize:   11,
                fontWeight: FontWeight.w600,
                color:      met ? AppTheme.primary : AppTheme.inkMuted,
              ),
            ),
          ],
        ),
      );
}

// ══════════════════════════════════════════════════════════════════════════════
// Step 1 — Email OTP
// ══════════════════════════════════════════════════════════════════════════════

class _OtpStep extends StatelessWidget {
  final String email;
  final List<TextEditingController> controllers;
  final List<FocusNode> focusNodes;
  final void Function(int, String) onChanged;
  final VoidCallback onResend;
  final Future<void> Function() onSubmit;
  final int resendSeconds;
  final String? devOtp;
  final bool isLoading;

  const _OtpStep({
    required this.email,
    required this.controllers,
    required this.focusNodes,
    required this.onChanged,
    required this.onResend,
    required this.onSubmit,
    required this.resendSeconds,
    required this.isLoading,
    this.devOtp,
  });

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(28, 8, 28, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),

            // Icon
            Container(
              width: 60, height: 60,
              decoration: BoxDecoration(
                color:        AppTheme.primaryBg,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(Icons.mark_email_unread_outlined,
                  color: AppTheme.primary, size: 28),
            ),
            const SizedBox(height: 20),

            const _StepHeader(
              title:    'Check your email',
              subtitle: 'We sent a 6-digit verification code to',
            ),
            const SizedBox(height: 4),
            Text(
              email,
              style: const TextStyle(
                fontSize:   14,
                fontWeight: FontWeight.w700,
                color:      AppTheme.primary,
              ),
            ),
            const SizedBox(height: 32),

            // OTP boxes
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(6, (i) => _OtpBox(
                controller: controllers[i],
                focusNode:  focusNodes[i],
                onChanged:  (v) => onChanged(i, v),
              )),
            ),

            // Dev OTP hint
            if (devOtp != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color:        const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(10),
                  border:       Border.all(color: const Color(0xFFFDE68A)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.developer_mode,
                        size: 14, color: Color(0xFFD97706)),
                    const SizedBox(width: 8),
                    Text('Dev OTP: $devOtp',
                        style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize:   13,
                            color:      Color(0xFFD97706),
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 32),

            _PrimaryButton(
              label:     'Verify Code',
              isLoading: isLoading,
              onTap:     onSubmit,
            ),

            const SizedBox(height: 20),
            Center(
              child: resendSeconds > 0
                  ? Text(
                      'Resend code in ${resendSeconds}s',
                      style: AppTheme.body,
                    )
                  : TextButton.icon(
                      onPressed: onResend,
                      icon:  const Icon(Icons.refresh, size: 16),
                      label: const Text('Resend code'),
                    ),
            ),
          ],
        ),
      );
}

class _OtpBox extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;

  const _OtpBox({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 46, height: 56,
        child: TextFormField(
          controller:      controller,
          focusNode:       focusNode,
          textAlign:       TextAlign.center,
          keyboardType:    TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(1),
          ],
          style: const TextStyle(
            fontSize:   22,
            fontWeight: FontWeight.w800,
            color:      AppTheme.ink,
          ),
          decoration: InputDecoration(
            filled:      true,
            fillColor:   controller.text.isEmpty
                ? const Color(0xFFF3F4F6)
                : AppTheme.primaryBg,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:   BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:   const BorderSide(color: AppTheme.primary, width: 2),
            ),
            contentPadding: EdgeInsets.zero,
          ),
          onChanged: onChanged,
        ),
      );
}

// ══════════════════════════════════════════════════════════════════════════════
// Step 2 — Profile (name + phone)
// ══════════════════════════════════════════════════════════════════════════════

class _ProfileStep extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController fullName, phone;
  final Future<void> Function() onSubmit;
  final bool isLoading;

  const _ProfileStep({
    required this.formKey,
    required this.fullName,
    required this.phone,
    required this.onSubmit,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(28, 8, 28, 32),
        child: Form(
          key: formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              const _StepHeader(
                title:    'Complete your profile',
                subtitle: 'Almost done! Just a few more details.',
              ),
              const SizedBox(height: 28),

              const _Label('Full name'),
              const SizedBox(height: 8),
              TextFormField(
                controller:            fullName,
                textCapitalization:    TextCapitalization.words,
                textInputAction:       TextInputAction.next,
                decoration: const InputDecoration(
                  hintText:   'First and last name',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (v) =>
                    v != null && v.trim().length >= 2 ? null : 'Enter your full name',
              ),
              const SizedBox(height: 20),

              const _Label('Phone number'),
              const SizedBox(height: 8),
              TextFormField(
                controller:       phone,
                keyboardType:     TextInputType.phone,
                textInputAction:  TextInputAction.done,
                onFieldSubmitted: (_) => onSubmit(),
                decoration: const InputDecoration(
                  hintText:   '+961 70 000 000',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
                validator: (v) =>
                    v != null && v.trim().length >= 7 ? null : 'Enter a valid phone number',
              ),

              const SizedBox(height: 10),
              Row(children: [
                const Icon(Icons.info_outline, size: 13, color: AppTheme.inkMuted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Used for account recovery only. Never shared.',
                    style: AppTheme.caption,
                  ),
                ),
              ]),

              const SizedBox(height: 32),

              _PrimaryButton(
                label:     'Start Earning',
                icon:      Icons.rocket_launch_outlined,
                isLoading: isLoading,
                onTap:     onSubmit,
              ),
            ],
          ),
        ),
      );
}

// ══════════════════════════════════════════════════════════════════════════════
// Shared widgets
// ══════════════════════════════════════════════════════════════════════════════

class _PrimaryButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final bool isLoading;
  final Future<void> Function() onTap;

  const _PrimaryButton({
    required this.label,
    required this.isLoading,
    required this.onTap,
    this.icon,
  });

  @override
  State<_PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<_PrimaryButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync:      this,
    duration:   const Duration(milliseconds: 80),
    lowerBound: 0.96,
    upperBound: 1.0,
    value:      1.0,
  );

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTapDown:   (_) { if (!widget.isLoading) _ctrl.reverse(); },
        onTapUp:     (_) { _ctrl.forward(); if (!widget.isLoading) widget.onTap(); },
        onTapCancel: () => _ctrl.forward(),
        child: ScaleTransition(
          scale: _ctrl,
          child: Container(
            height: 54,
            decoration: BoxDecoration(
              gradient:     widget.isLoading
                  ? LinearGradient(colors: [Colors.grey.shade300, Colors.grey.shade300])
                  : AppTheme.primaryGradient,
              borderRadius: BorderRadius.circular(14),
              boxShadow:    widget.isLoading ? [] : AppTheme.cardShadow,
            ),
            child: Center(
              child: widget.isLoading
                  ? const SizedBox(
                      width: 22, height: 22,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5))
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.icon != null) ...[
                          Icon(widget.icon, color: Colors.white, size: 18),
                          const SizedBox(width: 8),
                        ],
                        Text(widget.label,
                            style: const TextStyle(
                              color:      Colors.white,
                              fontSize:   16,
                              fontWeight: FontWeight.w700,
                            )),
                      ],
                    ),
            ),
          ),
        ),
      );
}

class _StepProgressBar extends StatelessWidget {
  final int current, total;
  const _StepProgressBar({required this.current, required this.total});

  @override
  Widget build(BuildContext context) => Row(
        children: List.generate(total, (i) {
          final done   = i < current;
          final active = i == current;
          return Expanded(
            child: AnimatedContainer(
              duration:    const Duration(milliseconds: 300),
              height:      4,
              margin:      EdgeInsets.only(right: i < total - 1 ? 6 : 0),
              decoration:  BoxDecoration(
                color: done || active ? AppTheme.primary : AppTheme.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        }),
      );
}

class _StepHeader extends StatelessWidget {
  final String title, subtitle;
  const _StepHeader({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTheme.heading),
          const SizedBox(height: 6),
          Text(subtitle, style: AppTheme.body),
        ],
      );
}

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
        ),
      );
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  final BuildContext ctx;
  const _ErrorBanner({required this.message, required this.ctx});

  bool get _isEmailTaken =>
      message.toLowerCase().contains('already') ||
      message.toLowerCase().contains('registered');

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color:        const Color(0xFFFEF2F2),
          borderRadius: BorderRadius.circular(12),
          border:       Border.all(color: const Color(0xFFFCA5A5)),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: AppTheme.error, size: 17),
            const SizedBox(width: 10),
            Expanded(
              child: Text(message,
                  style: const TextStyle(color: AppTheme.error, fontSize: 13)),
            ),
            if (_isEmailTaken) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => ctx.go('/login'),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color:        AppTheme.error,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('Sign in',
                      style: TextStyle(
                          color:      Colors.white,
                          fontSize:   12,
                          fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ],
        ),
      );
}
