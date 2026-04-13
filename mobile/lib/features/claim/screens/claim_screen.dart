import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/api/api_client.dart';
import '../../../core/models/models.dart';
import '../../../core/providers/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/widgets.dart';

/// Entry point: receives receipt + product from ProductDetailScreen via GoRouter extra.
class ClaimScreen extends ConsumerStatefulWidget {
  final Receipt receipt;
  final Product product;

  const ClaimScreen({
    super.key,
    required this.receipt,
    required this.product,
  });

  @override
  ConsumerState<ClaimScreen> createState() => _ClaimScreenState();
}

class _ClaimScreenState extends ConsumerState<ClaimScreen>
    with SingleTickerProviderStateMixin {
  // Step 1: poll OCR   → Step 2: submit claim   → Step 3: result
  int _step = 1;

  late Receipt _receipt;
  Claim? _claim;
  String? _error;
  bool _isSubmitting = false;

  Timer? _pollTimer;
  int _pollCount = 0;
  static const _maxPolls = 30;

  late final AnimationController _stepCtrl = AnimationController(
    vsync: this, duration: const Duration(milliseconds: 400),
  )..forward();

  @override
  void initState() {
    super.initState();
    _receipt = widget.receipt;
    _startPolling();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _stepCtrl.dispose();
    super.dispose();
  }

  void _advanceStep(int step) {
    setState(() => _step = step);
    _stepCtrl.forward(from: 0);
  }

  // ── Step 1: Poll OCR status (exponential backoff) ────────────────────────

  void _startPolling() {
    if (_receipt.isDone) {
      _onOcrDone();
      return;
    }
    _scheduleNextPoll(const Duration(seconds: 1));
  }

  void _scheduleNextPoll(Duration delay) {
    _pollTimer = Timer(delay, () async {
      if (!mounted) return;
      _pollCount++;

      if (_pollCount > _maxPolls) {
        setState(() => _error = 'Receipt processing timed out. Please try again.');
        return;
      }

      try {
        final updated =
            await ref.read(apiServiceProvider).getReceipt(_receipt.id);
        if (!mounted) return;

        setState(() => _receipt = updated);

        if (updated.isDone) {
          _onOcrDone();
        } else if (updated.isFailed) {
          setState(() =>
              _error = updated.ocrError ?? 'Could not read receipt. Try a clearer photo.');
        } else {
          final next = delay * 2;
          _scheduleNextPoll(next > const Duration(seconds: 8)
              ? const Duration(seconds: 8)
              : next);
        }
      } catch (_) {
        _scheduleNextPoll(delay);
      }
    });
  }

  void _onOcrDone() {
    final matched =
        _receipt.items.any((i) => i.productId == widget.product.id);
    if (!matched) {
      setState(() {
        _error = 'Product "${widget.product.name}" was not found on this receipt.';
        _step  = 1;
      });
      return;
    }
    _advanceStep(2);
  }

  // ── Step 2: Submit claim ──────────────────────────────────────────────────

  Future<void> _submitClaim() async {
    HapticFeedback.mediumImpact();
    setState(() { _isSubmitting = true; _error = null; });

    try {
      final claim = await ref.read(apiServiceProvider).submitClaim(
            receiptId: _receipt.id,
            productId: widget.product.id,
          );

      ref.invalidate(walletProvider);

      setState(() {
        _claim        = claim;
        _isSubmitting = false;
      });
      _advanceStep(3);
    } on ApiException catch (e) {
      setState(() { _error = e.userMessage; _isSubmitting = false; });
    }
  }

  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: _step < 3
          ? AppBar(
              backgroundColor:  AppTheme.surface,
              surfaceTintColor: Colors.transparent,
              elevation:        0,
              title: const Text('Claim Cashback'),
              leading: IconButton(
                icon:      const Icon(Icons.arrow_back),
                onPressed: () => context.go('/'),
              ),
            )
          : null,
      body: Column(
        children: [
          if (_step < 3) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: StepIndicator(total: 3, current: _step),
            ),
          ],

          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child:   SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.06),
                    end:   Offset.zero,
                  ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
                  child: child,
                ),
              ),
              child: switch (_step) {
                1 => _OcrWaitStep(
                    key:     const ValueKey(1),
                    receipt: _receipt,
                    error:   _error,
                  ),
                2 => _ConfirmStep(
                    key:          const ValueKey(2),
                    receipt:      _receipt,
                    product:      widget.product,
                    error:        _error,
                    isSubmitting: _isSubmitting,
                    onConfirm:    _submitClaim,
                  ),
                _ => _ResultStep(
                    key:     const ValueKey(3),
                    claim:   _claim!,
                    product: widget.product,
                  ),
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Step 1: OCR in progress ───────────────────────────────────────────────────

class _OcrWaitStep extends StatelessWidget {
  final Receipt receipt;
  final String? error;
  const _OcrWaitStep({super.key, required this.receipt, this.error});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            OcrStatusBanner(status: receipt.ocrStatus),
            const SizedBox(height: 32),

            if (error != null)
              ErrorCard(
                message: error!,
                onRetry: () => context.go('/'),
              )
            else ...[
              Container(
                width: 88, height: 88,
                decoration: BoxDecoration(
                  color:        AppTheme.primaryBg,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Center(
                  child: SizedBox(
                    width: 40, height: 40,
                    child: CircularProgressIndicator(
                      color:       AppTheme.primary,
                      strokeWidth: 3,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Reading your receipt…',
                style: AppTheme.subheading,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'This usually takes 5–15 seconds.\nPlease keep the app open.',
                style: AppTheme.body,
                textAlign: TextAlign.center,
              ),
            ],

            if (receipt.isDone && receipt.items.isNotEmpty) ...[
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color:        Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border:       Border.all(color: AppTheme.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Items found on receipt',
                        style: AppTheme.subheading),
                    const SizedBox(height: 12),
                    ...receipt.items.map((item) => _ReceiptItemTile(item: item)),
                  ],
                ),
              ),
            ],
          ],
        ),
      );
}

class _ReceiptItemTile extends StatelessWidget {
  final ReceiptItem item;
  const _ReceiptItemTile({required this.item});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color:        item.isMatched
                    ? AppTheme.primaryBg
                    : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                item.isMatched
                    ? Icons.check_rounded
                    : Icons.remove_rounded,
                size:  16,
                color: item.isMatched ? AppTheme.primary : AppTheme.inkMuted,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                item.productName ?? item.description ?? 'Unknown item',
                style: TextStyle(
                  fontSize:   14,
                  fontWeight: item.isMatched ? FontWeight.w600 : FontWeight.normal,
                  color:      AppTheme.ink,
                ),
              ),
            ),
            if (item.unitPrice != null)
              Text(
                '\$${item.unitPrice!.toStringAsFixed(2)}',
                style: AppTheme.body.copyWith(fontWeight: FontWeight.w600),
              ),
          ],
        ),
      );
}

// ── Step 2: Confirm & Submit ──────────────────────────────────────────────────

class _ConfirmStep extends StatelessWidget {
  final Receipt receipt;
  final Product product;
  final String? error;
  final bool isSubmitting;
  final VoidCallback onConfirm;

  const _ConfirmStep({
    super.key,
    required this.receipt,
    required this.product,
    required this.isSubmitting,
    required this.onConfirm,
    this.error,
  });

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Summary card ───────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppTheme.primaryBg, Colors.white],
                  begin:  Alignment.topLeft,
                  end:    Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.primary.withOpacity(0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color:        AppTheme.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.receipt_outlined,
                          color: AppTheme.primary, size: 18),
                    ),
                    const SizedBox(width: 10),
                    const Text('Claim Summary', style: AppTheme.subheading),
                  ]),
                  const SizedBox(height: 16),
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  _SummaryRow(label: 'Product', value: product.name),
                  _SummaryRow(
                      label: 'Store',
                      value: receipt.storeName ?? 'Unknown'),
                  _SummaryRow(
                    label: 'Purchase Date',
                    value: receipt.purchaseDate != null
                        ? '${receipt.purchaseDate!.day}/${receipt.purchaseDate!.month}/${receipt.purchaseDate!.year}'
                        : 'Unknown',
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color:        AppTheme.primary.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Cashback',
                            style: TextStyle(
                                fontSize:   13,
                                color:      AppTheme.inkMuted,
                                fontWeight: FontWeight.w500)),
                        Text(
                          product.campaign?.displayValue ?? '—',
                          style: AppTheme.cashbackLabel.copyWith(fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ── Terms ──────────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color:        Colors.white,
                borderRadius: BorderRadius.circular(14),
                border:       Border.all(color: AppTheme.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('By submitting this claim you confirm:',
                      style: TextStyle(
                          fontSize:   13,
                          fontWeight: FontWeight.w600,
                          color:      AppTheme.ink)),
                  const SizedBox(height: 10),
                  _TermRow('You purchased this product at the listed store'),
                  _TermRow('The receipt has not been used for a previous claim'),
                  _TermRow('The information shown above is accurate'),
                ],
              ),
            ),

            const SizedBox(height: 24),

            if (error != null) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color:        const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(12),
                  border:       Border.all(color: const Color(0xFFFCA5A5)),
                ),
                child: Row(children: [
                  const Icon(Icons.error_outline,
                      color: AppTheme.error, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(error!,
                        style: const TextStyle(
                            color: AppTheme.error, fontSize: 13)),
                  ),
                ]),
              ),
              const SizedBox(height: 16),
            ],

            // ── Submit button ──────────────────────────────────────────────
            _SubmitButton(isSubmitting: isSubmitting, onTap: onConfirm),
            const SizedBox(height: 32),
          ],
        ),
      );
}

class _SummaryRow extends StatelessWidget {
  final String label, value;
  const _SummaryRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 13, color: AppTheme.inkMuted,
                    fontWeight: FontWeight.w500)),
            Text(value,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600,
                    color: AppTheme.ink)),
          ],
        ),
      );
}

class _TermRow extends StatelessWidget {
  final String text;
  const _TermRow(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.check_circle_outline,
                size: 15, color: AppTheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text,
                  style: const TextStyle(
                      fontSize: 13, color: AppTheme.inkMuted)),
            ),
          ],
        ),
      );
}

class _SubmitButton extends StatefulWidget {
  final bool isSubmitting;
  final VoidCallback onTap;
  const _SubmitButton({required this.isSubmitting, required this.onTap});

  @override
  State<_SubmitButton> createState() => _SubmitButtonState();
}

class _SubmitButtonState extends State<_SubmitButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync:      this,
    duration:   const Duration(milliseconds: 80),
    lowerBound: 0.95,
    upperBound: 1.0,
    value:      1.0,
  );

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTapDown:   (_) { if (!widget.isSubmitting) _ctrl.reverse(); },
        onTapUp:     (_) { _ctrl.forward(); if (!widget.isSubmitting) widget.onTap(); },
        onTapCancel: () => _ctrl.forward(),
        child: ScaleTransition(
          scale: _ctrl,
          child: Container(
            height: 56,
            decoration: BoxDecoration(
              gradient:     widget.isSubmitting
                  ? LinearGradient(
                      colors: [Colors.grey.shade300, Colors.grey.shade300])
                  : AppTheme.primaryGradient,
              borderRadius: BorderRadius.circular(14),
              boxShadow:    widget.isSubmitting ? [] : AppTheme.cardShadow,
            ),
            child: Center(
              child: widget.isSubmitting
                  ? const SizedBox(
                      height: 22, width: 22,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5))
                  : const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.send_rounded,
                            color: Colors.white, size: 18),
                        SizedBox(width: 10),
                        Text('Submit Claim',
                            style: TextStyle(
                                color:      Colors.white,
                                fontSize:   16,
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
            ),
          ),
        ),
      );
}

// ── Step 3: Result ────────────────────────────────────────────────────────────

class _ResultStep extends StatefulWidget {
  final Claim claim;
  final Product product;
  const _ResultStep({super.key, required this.claim, required this.product});

  @override
  State<_ResultStep> createState() => _ResultStepState();
}

class _ResultStepState extends State<_ResultStep>
    with SingleTickerProviderStateMixin {
  late final AnimationController _amountCtrl = AnimationController(
    vsync:    this,
    duration: const Duration(milliseconds: 600),
  );
  late final Animation<double> _amountScale = CurvedAnimation(
    parent: _amountCtrl,
    curve:  Curves.elasticOut,
  );

  @override
  void initState() {
    super.initState();
    // Delay so the AnimatedSuccessIcon plays first
    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted) _amountCtrl.forward();
    });
    if (widget.claim.isApproved) {
      HapticFeedback.heavyImpact();
    }
  }

  @override
  void dispose() { _amountCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final isApproved = widget.claim.isApproved;
    final isFlagged  = widget.claim.isFlagged;

    final Color accentColor = isApproved
        ? AppTheme.primary
        : isFlagged
            ? const Color(0xFFEA580C)
            : const Color(0xFFDC2626);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 24, 32, 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // ── Animated icon ──────────────────────────────────────────────
            if (isApproved)
              AnimatedSuccessIcon(color: AppTheme.primary)
            else
              _StatusIcon(isFlagged: isFlagged, color: accentColor),

            const SizedBox(height: 28),

            // ── Title ──────────────────────────────────────────────────────
            Text(
              isApproved
                  ? 'Cashback Earned!'
                  : isFlagged
                      ? 'Under Review'
                      : 'Claim Rejected',
              style: AppTheme.display,
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 12),

            // ── Amount / subtitle ──────────────────────────────────────────
            if (isApproved) ...[
              const SizedBox(height: 4),
              ScaleTransition(
                scale: _amountScale,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 14),
                  decoration: BoxDecoration(
                    gradient:     AppTheme.primaryGradient,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow:    AppTheme.cardShadow,
                  ),
                  child: Text(
                    '\$${widget.claim.cashbackAmount.toStringAsFixed(2)}',
                    style: const TextStyle(
                      color:      Colors.white,
                      fontSize:   40,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'added to your wallet',
                style: AppTheme.body,
                textAlign: TextAlign.center,
              ),
            ] else if (isFlagged) ...[
              const Text(
                'Your claim is being reviewed by our team.\nThis usually takes 24–48 hours.',
                style: AppTheme.body,
                textAlign: TextAlign.center,
              ),
            ] else ...[
              const Text(
                'This claim was not approved.\nCommon reasons: duplicate receipt, '
                'claim window expired, or product not found.',
                style: AppTheme.body,
                textAlign: TextAlign.center,
              ),
            ],

            const SizedBox(height: 40),

            // ── Action buttons ─────────────────────────────────────────────
            if (isApproved)
              _ResultButton(
                label:   'View Wallet',
                icon:    Icons.account_balance_wallet_outlined,
                primary: true,
                onTap:   () => context.go('/wallet'),
              ),

            const SizedBox(height: 12),

            _ResultButton(
              label:   'Back to Home',
              icon:    Icons.home_outlined,
              primary: !isApproved,
              onTap:   () => context.go('/'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusIcon extends StatelessWidget {
  final bool isFlagged;
  final Color color;
  const _StatusIcon({required this.isFlagged, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        width: 100, height: 100,
        decoration: BoxDecoration(
          color:  color.withOpacity(0.12),
          shape:  BoxShape.circle,
        ),
        child: Icon(
          isFlagged
              ? Icons.access_time_outlined
              : Icons.cancel_outlined,
          size:  52,
          color: color,
        ),
      );
}

class _ResultButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool primary;
  final VoidCallback onTap;
  const _ResultButton({
    required this.label,
    required this.icon,
    required this.primary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => AnimatedPressButton(
        onTap: onTap,
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            gradient:     primary ? AppTheme.primaryGradient : null,
            color:        primary ? null : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: primary
                ? null
                : Border.all(color: AppTheme.border),
            boxShadow: primary ? AppTheme.cardShadow : AppTheme.subtleShadow,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size:  18,
                  color: primary ? Colors.white : AppTheme.ink),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize:   15,
                  fontWeight: FontWeight.w700,
                  color:      primary ? Colors.white : AppTheme.ink,
                ),
              ),
            ],
          ),
        ),
      );
}
