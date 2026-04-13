import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../../core/api/api_client.dart';
import '../../../core/providers/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/widgets.dart';

class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen>
    with TickerProviderStateMixin {
  final MobileScannerController _scanner = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing:         CameraFacing.back,
    torchEnabled:   false,
  );

  bool    _isProcessing = false;
  bool    _torchOn      = false;
  String? _error;

  // Animated scan line
  late final AnimationController _lineCtrl = AnimationController(
    vsync:    this,
    duration: const Duration(milliseconds: 1800),
  )..repeat(reverse: true);

  // Corner pulse animation
  late final AnimationController _pulseCtrl = AnimationController(
    vsync: this, duration: const Duration(milliseconds: 1000),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _scanner.dispose();
    _lineCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _onBarcodeDetected(BarcodeCapture capture) async {
    final barcode = capture.barcodes.firstOrNull?.rawValue;
    if (barcode == null || _isProcessing) return;

    HapticFeedback.mediumImpact();
    setState(() { _isProcessing = true; _error = null; });
    await _scanner.stop();

    try {
      final api     = ref.read(apiServiceProvider);
      final product = await api.getProductByBarcode(barcode);
      if (!mounted) return;

      if (!product.hasActiveCampaign) {
        HapticFeedback.lightImpact();
        setState(() {
          _error        = 'No active cashback offer for this product.';
          _isProcessing = false;
        });
        await _scanner.start();
        return;
      }

      context.go('/product/$barcode');
    } on ApiException catch (e) {
      if (!mounted) return;
      HapticFeedback.lightImpact();
      setState(() {
        _error        = e.statusCode == 404
            ? 'Product not in our system yet. Only eligible products can be claimed.'
            : e.userMessage;
        _isProcessing = false;
      });
      await _scanner.start();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── Camera feed ─────────────────────────────────────────────────
          MobileScanner(
            controller: _scanner,
            onDetect:   _onBarcodeDetected,
          ),

          // ── Dark overlay with transparent cutout ────────────────────────
          _ScanOverlay(
            lineAnim:  _lineCtrl,
            pulseAnim: _pulseCtrl,
          ),

          // ── Top bar ─────────────────────────────────────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Back
                  _GlassButton(
                    icon:    Icons.arrow_back,
                    onTap:   () => context.go('/'),
                  ),
                  // Title
                  const Text('Scan Barcode',
                      style: TextStyle(
                          color:      Colors.white,
                          fontSize:   17,
                          fontWeight: FontWeight.w700)),
                  // Torch
                  _GlassButton(
                    icon:    _torchOn
                        ? Icons.flash_on
                        : Icons.flash_off_outlined,
                    onTap: () {
                      _scanner.toggleTorch();
                      setState(() => _torchOn = !_torchOn);
                    },
                    active: _torchOn,
                  ),
                ],
              ),
            ),
          ),

          // ── Bottom instructions ──────────────────────────────────────────
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 48),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin:  Alignment.bottomCenter,
                  end:    Alignment.topCenter,
                  colors: [
                    Colors.black.withOpacity(0.85),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Column(
                children: [
                  if (_error != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color:        Colors.red.shade900.withOpacity(0.95),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(children: [
                        const Icon(Icons.error_outline,
                            color: Colors.white, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(_error!,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 14)),
                        ),
                        GestureDetector(
                          onTap: () => setState(() => _error = null),
                          child: const Icon(Icons.close,
                              color: Colors.white70, size: 18),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Instruction pill
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      color:        Colors.white.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                          color: Colors.white.withOpacity(0.2)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.qr_code_scanner,
                            color: Colors.white70, size: 16),
                        const SizedBox(width: 8),
                        const Text(
                          'Point camera at the product barcode',
                          style: TextStyle(
                              color:    Colors.white70,
                              fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Processing overlay ───────────────────────────────────────────
          if (_isProcessing)
            const LoadingOverlay(message: 'Looking up product…'),
        ],
      ),
    );
  }
}

// ── Glassmorphism button ──────────────────────────────────────────────────────

class _GlassButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool active;
  const _GlassButton({
    required this.icon,
    required this.onTap,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: active
                ? AppTheme.primary.withOpacity(0.8)
                : Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: Colors.white.withOpacity(0.2)),
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      );
}

// ── Scan overlay with cutout + animated line ──────────────────────────────────

class _ScanOverlay extends StatelessWidget {
  final AnimationController lineAnim;
  final AnimationController pulseAnim;
  const _ScanOverlay({required this.lineAnim, required this.pulseAnim});

  @override
  Widget build(BuildContext context) {
    const frameSize = 250.0;
    return Stack(
      children: [
        // Dimmed background with cutout
        CustomPaint(
          size:    Size.infinite,
          painter: _DimPainter(frameSize: frameSize),
        ),

        // Scan frame + animated elements
        Center(
          child: SizedBox(
            width:  frameSize,
            height: frameSize,
            child: Stack(
              children: [
                // Corner markers (pulsing)
                AnimatedBuilder(
                  animation: pulseAnim,
                  builder: (_, __) => CustomPaint(
                    size:    const Size(frameSize, frameSize),
                    painter: _CornerPainter(
                      opacity: 0.7 + 0.3 * pulseAnim.value,
                    ),
                  ),
                ),

                // Animated scan line
                AnimatedBuilder(
                  animation: lineAnim,
                  builder: (_, __) {
                    final y = lineAnim.value * (frameSize - 4);
                    return Positioned(
                      top:   y,
                      left:  12,
                      right: 12,
                      child: Container(
                        height: 2.5,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AppTheme.primary.withOpacity(0),
                              AppTheme.primary,
                              AppTheme.primary.withOpacity(0),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(2),
                          boxShadow: [
                            BoxShadow(
                              color:      AppTheme.primary.withOpacity(0.5),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _DimPainter extends CustomPainter {
  final double frameSize;
  const _DimPainter({required this.frameSize});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width  / 2;
    final cy = size.height / 2;
    final half = frameSize / 2;

    final full = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final hole = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Rect.fromLTRB(cx - half, cy - half, cx + half, cy + half),
        const Radius.circular(16),
      ));

    canvas.drawPath(
      Path.combine(PathOperation.difference, full, hole),
      Paint()..color = Colors.black.withOpacity(0.65),
    );
  }

  @override bool shouldRepaint(_) => false;
}

class _CornerPainter extends CustomPainter {
  final double opacity;
  const _CornerPainter({required this.opacity});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color       = AppTheme.primary.withOpacity(opacity)
      ..strokeWidth = 3.5
      ..style       = PaintingStyle.stroke
      ..strokeCap   = StrokeCap.round;

    const len = 28.0;
    const r   = 16.0;

    // Top-left
    canvas.drawLine(const Offset(r, 0), const Offset(r + len, 0), paint);
    canvas.drawLine(const Offset(0, r), const Offset(0, r + len), paint);
    canvas.drawArc(const Rect.fromLTWH(0, 0, r * 2, r * 2),
        math.pi, math.pi / 2, false, paint);
    // Top-right
    canvas.drawLine(Offset(size.width - r, 0),
        Offset(size.width - r - len, 0), paint);
    canvas.drawLine(Offset(size.width, r),
        Offset(size.width, r + len), paint);
    canvas.drawArc(
        Rect.fromLTWH(size.width - r * 2, 0, r * 2, r * 2),
        -math.pi / 2, math.pi / 2, false, paint);
    // Bottom-left
    canvas.drawLine(Offset(0, size.height - r),
        Offset(0, size.height - r - len), paint);
    canvas.drawLine(Offset(r, size.height),
        Offset(r + len, size.height), paint);
    canvas.drawArc(
        Rect.fromLTWH(0, size.height - r * 2, r * 2, r * 2),
        math.pi / 2, math.pi / 2, false, paint);
    // Bottom-right
    canvas.drawLine(Offset(size.width, size.height - r),
        Offset(size.width, size.height - r - len), paint);
    canvas.drawLine(Offset(size.width - r, size.height),
        Offset(size.width - r - len, size.height), paint);
    canvas.drawArc(
        Rect.fromLTWH(
            size.width - r * 2, size.height - r * 2, r * 2, r * 2),
        0, math.pi / 2, false, paint);
  }

  @override bool shouldRepaint(_CornerPainter old) =>
      old.opacity != opacity;
}
