import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../../core/theme/app_theme.dart';

// ── Cashback badge ────────────────────────────────────────────────────────────

class CashbackBadge extends StatelessWidget {
  final String label;
  final bool large;
  const CashbackBadge({super.key, required this.label, this.large = false});

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(
          horizontal: large ? 14 : 10,
          vertical:   large ? 6  : 4,
        ),
        decoration: BoxDecoration(
          gradient:     AppTheme.primaryGradient,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color:      AppTheme.primary.withOpacity(0.3),
              blurRadius: 8,
              offset:     const Offset(0, 3),
            ),
          ],
        ),
        child: Text(
          label,
          style: TextStyle(
            color:      Colors.white,
            fontSize:   large ? 14 : 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
      );
}

// ── Animated press button — scales down on tap ────────────────────────────────

class AnimatedPressButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double scale;
  const AnimatedPressButton({
    super.key,
    required this.child,
    this.onTap,
    this.scale = 0.96,
  });

  @override
  State<AnimatedPressButton> createState() => _AnimatedPressButtonState();
}

class _AnimatedPressButtonState extends State<AnimatedPressButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync:    this,
    duration: const Duration(milliseconds: 80),
    lowerBound: widget.scale,
    upperBound: 1.0,
    value: 1.0,
  );

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTapDown:  (_) => _ctrl.reverse(),
        onTapUp:    (_) { _ctrl.forward(); widget.onTap?.call(); },
        onTapCancel: () => _ctrl.forward(),
        child: ScaleTransition(scale: _ctrl, child: widget.child),
      );
}

// ── Full-screen loading overlay ───────────────────────────────────────────────

class LoadingOverlay extends StatefulWidget {
  final String? message;
  const LoadingOverlay({super.key, this.message});

  @override
  State<LoadingOverlay> createState() => _LoadingOverlayState();
}

class _LoadingOverlayState extends State<LoadingOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this, duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Container(
        color: Colors.black.withOpacity(0.55),
        child: Center(
          child: Container(
            padding:      const EdgeInsets.all(32),
            decoration:   BoxDecoration(
              color:        Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow:    AppTheme.subtleShadow,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _SpinningRing(controller: _ctrl),
                if (widget.message != null) ...[
                  const SizedBox(height: 20),
                  Text(widget.message!,
                      style: AppTheme.body, textAlign: TextAlign.center),
                ],
              ],
            ),
          ),
        ),
      );
}

class _SpinningRing extends StatelessWidget {
  final AnimationController controller;
  const _SpinningRing({required this.controller});

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: controller,
        builder: (_, child) => Transform.rotate(
          angle: controller.value * 2 * math.pi,
          child: child,
        ),
        child: SizedBox(
          width: 48, height: 48,
          child: CustomPaint(painter: _RingPainter()),
        ),
      );
}

class _RingPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style       = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap   = StrokeCap.round
      ..shader = SweepGradient(
          colors: [AppTheme.primary, AppTheme.primary.withOpacity(0)],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawArc(
      Rect.fromLTWH(2, 2, size.width - 4, size.height - 4),
      0, math.pi * 1.7, false, paint,
    );
  }
  @override bool shouldRepaint(_) => false;
}

// ── Inline error card ─────────────────────────────────────────────────────────

class ErrorCard extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  const ErrorCard({super.key, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) => Container(
        margin:  const EdgeInsets.all(16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color:        const Color(0xFFFEF2F2),
          border:       Border.all(color: const Color(0xFFFCA5A5)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: AppTheme.error),
            const SizedBox(width: 12),
            Expanded(
              child: Text(message,
                  style: const TextStyle(color: Color(0xFF991B1B))),
            ),
            if (onRetry != null)
              TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      );
}

// ── OCR status banner ─────────────────────────────────────────────────────────

class OcrStatusBanner extends StatefulWidget {
  final String status;
  const OcrStatusBanner({super.key, required this.status});

  @override
  State<OcrStatusBanner> createState() => _OcrStatusBannerState();
}

class _OcrStatusBannerState extends State<OcrStatusBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this, duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() { _pulse.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    if (widget.status == 'done') {
      return _banner(AppTheme.primaryBg, AppTheme.primaryDark,
          Icons.check_circle_outline, 'Receipt verified');
    }
    if (widget.status == 'failed') {
      return _banner(const Color(0xFFFEF2F2), AppTheme.error,
          Icons.error_outline, 'Could not read receipt');
    }
    return FadeTransition(
      opacity: _pulse,
      child: _banner(const Color(0xFFFFF7ED), const Color(0xFFD97706),
          Icons.document_scanner_outlined, 'Reading receipt…'),
    );
  }

  Widget _banner(Color bg, Color fg, IconData icon, String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Icon(icon, color: fg, size: 20),
          const SizedBox(width: 10),
          Text(text,
              style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 14)),
        ]),
      );
}

// ── Step indicator (pill dots) ────────────────────────────────────────────────

class StepIndicator extends StatelessWidget {
  final int total, current; // current is 1-based
  const StepIndicator({super.key, required this.total, required this.current});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(total, (i) => AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve:    Curves.easeInOut,
          margin:   const EdgeInsets.symmetric(horizontal: 4),
          width:    i + 1 == current ? 28 : 8,
          height:   8,
          decoration: BoxDecoration(
            color:        i + 1 <= current ? AppTheme.primary : AppTheme.border,
            borderRadius: BorderRadius.circular(4),
          ),
        )),
      );
}

// ── Skeleton loaders ──────────────────────────────────────────────────────────

class SkeletonBox extends StatelessWidget {
  final double width, height;
  final double radius;
  const SkeletonBox({
    super.key,
    required this.width,
    required this.height,
    this.radius = 8,
  });

  @override
  Widget build(BuildContext context) => Shimmer.fromColors(
        baseColor:      const Color(0xFFE5E7EB),
        highlightColor: const Color(0xFFF9FAFB),
        child: Container(
          width:  width,
          height: height,
          decoration: BoxDecoration(
            color:        Colors.white,
            borderRadius: BorderRadius.circular(radius),
          ),
        ),
      );
}

class SkeletonOfferCard extends StatelessWidget {
  const SkeletonOfferCard({super.key});

  @override
  Widget build(BuildContext context) => Shimmer.fromColors(
        baseColor:      const Color(0xFFE5E7EB),
        highlightColor: const Color(0xFFF9FAFB),
        child: Container(
          height: 80,
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color:        Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                width: 48, height: 48,
                decoration: const BoxDecoration(
                  color: Colors.white, shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment:  MainAxisAlignment.center,
                  children: [
                    Container(height: 12, width: 120,
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4))),
                    const SizedBox(height: 8),
                    Container(height: 10, width: 80,
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4))),
                  ],
                ),
              ),
              Container(
                width: 64, height: 28,
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
              ),
            ],
          ),
        ),
      );
}

class SkeletonFeaturedCard extends StatelessWidget {
  const SkeletonFeaturedCard({super.key});

  @override
  Widget build(BuildContext context) => Shimmer.fromColors(
        baseColor:      const Color(0xFFE5E7EB),
        highlightColor: const Color(0xFFF9FAFB),
        child: Container(
          width: 280,
          decoration: BoxDecoration(
            color:        Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      );
}

// ── Animated success checkmark ────────────────────────────────────────────────

class AnimatedSuccessIcon extends StatefulWidget {
  final Color color;
  const AnimatedSuccessIcon({super.key, required this.color});

  @override
  State<AnimatedSuccessIcon> createState() => _AnimatedSuccessIconState();
}

class _AnimatedSuccessIconState extends State<AnimatedSuccessIcon>
    with TickerProviderStateMixin {
  late final AnimationController _scale = AnimationController(
    vsync: this, duration: const Duration(milliseconds: 500),
  );
  late final AnimationController _check = AnimationController(
    vsync: this, duration: const Duration(milliseconds: 400),
  );

  late final Animation<double> _scaleAnim =
      CurvedAnimation(parent: _scale, curve: Curves.elasticOut);
  late final Animation<double> _checkAnim =
      CurvedAnimation(parent: _check, curve: Curves.easeOut);

  @override
  void initState() {
    super.initState();
    _scale.forward().then((_) => _check.forward());
  }

  @override
  void dispose() {
    _scale.dispose();
    _check.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScaleTransition(
        scale: _scaleAnim,
        child: Container(
          width: 100, height: 100,
          decoration: BoxDecoration(
            color:  widget.color.withOpacity(0.15),
            shape:  BoxShape.circle,
          ),
          child: AnimatedBuilder(
            animation: _checkAnim,
            builder: (_, __) => CustomPaint(
              painter: _CheckPainter(
                progress: _checkAnim.value,
                color:    widget.color,
              ),
            ),
          ),
        ),
      );
}

class _CheckPainter extends CustomPainter {
  final double progress;
  final Color color;
  const _CheckPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color       = color
      ..strokeWidth = 4
      ..style       = PaintingStyle.stroke
      ..strokeCap   = StrokeCap.round
      ..strokeJoin  = StrokeJoin.round;

    final cx = size.width / 2;
    final cy = size.height / 2;

    // Check path: short leg then long leg
    final path = Path()
      ..moveTo(cx - 18, cy)
      ..lineTo(cx - 5,  cy + 13)
      ..lineTo(cx + 18, cy - 13);

    final total  = _pathLength(path);
    final metric = path.computeMetrics().first;
    final drawn  = metric.extractPath(0, total * progress);
    canvas.drawPath(drawn, paint);
  }

  double _pathLength(Path path) {
    return path.computeMetrics().fold(0.0, (sum, m) => sum + m.length);
  }

  @override bool shouldRepaint(_CheckPainter old) => old.progress != progress;
}

// ── Pulsing dot (live indicator) ──────────────────────────────────────────────

class PulsingDot extends StatefulWidget {
  final Color color;
  const PulsingDot({super.key, required this.color});

  @override
  State<PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this, duration: const Duration(milliseconds: 1000),
  )..repeat(reverse: true);

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => Container(
          width:  10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color.withOpacity(0.4 + 0.6 * _ctrl.value),
          ),
        ),
      );
}
