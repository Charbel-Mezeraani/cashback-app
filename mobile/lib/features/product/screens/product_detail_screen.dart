import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_service.dart';
import '../../../core/models/models.dart';
import '../../../core/providers/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/widgets.dart';

final productByBarcodeProvider =
    FutureProvider.family<Product, String>((ref, barcode) async {
  return ref.watch(apiServiceProvider).getProductByBarcode(barcode);
});

// ─────────────────────────────────────────────────────────────────────────────

class ProductDetailScreen extends ConsumerStatefulWidget {
  final String barcode;
  const ProductDetailScreen({super.key, required this.barcode});

  @override
  ConsumerState<ProductDetailScreen> createState() =>
      _ProductDetailScreenState();
}

class _ProductDetailScreenState extends ConsumerState<ProductDetailScreen>
    with SingleTickerProviderStateMixin {
  bool    _isUploading = false;
  String? _uploadError;

  late final AnimationController _heroCtrl = AnimationController(
    vsync:    this,
    duration: const Duration(milliseconds: 600),
  )..forward();
  late final Animation<double> _heroAnim =
      CurvedAnimation(parent: _heroCtrl, curve: Curves.easeOutCubic);

  @override
  void dispose() {
    _heroCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickAndUploadReceipt(Product product) async {
    HapticFeedback.mediumImpact();
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source:       ImageSource.camera,
      imageQuality: 85,
      maxWidth:     1920,
    );
    if (picked == null) return;

    setState(() { _isUploading = true; _uploadError = null; });

    try {
      final imageBytes = await picked.readAsBytes();
      final api        = ref.read(apiServiceProvider);
      final client     = ref.read(apiClientProvider);

      final upload  = await api.getUploadUrl('image/jpeg');
      await client.putBytes(upload.uploadUrl, imageBytes, 'image/jpeg');
      final receipt = await api.submitReceipt(
          s3Key: upload.s3Key, imageBytes: imageBytes);

      if (!mounted) return;
      context.go('/claim', extra: {'receipt': receipt, 'product': product});
    } on ApiException catch (e) {
      setState(() { _uploadError = e.userMessage; _isUploading = false; });
    } catch (_) {
      setState(() {
        _uploadError = 'Failed to upload. Please try again.';
        _isUploading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final productAsync = ref.watch(productByBarcodeProvider(widget.barcode));

    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: productAsync.when(
        loading: () => const _ProductSkeleton(),
        error: (e, _) => Scaffold(
          appBar: AppBar(title: const Text('Product')),
          body: ErrorCard(
            message: e is ApiException ? e.userMessage : 'Failed to load product',
            onRetry: () => ref.invalidate(productByBarcodeProvider(widget.barcode)),
          ),
        ),
        data: (product) => Stack(
          children: [
            _ProductBody(
              product:     product,
              heroAnim:    _heroAnim,
              uploadError: _uploadError,
              isUploading: _isUploading,
              onClaimTap:  () => _pickAndUploadReceipt(product),
            ),
            if (_isUploading)
              const LoadingOverlay(message: 'Uploading receipt…'),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _ProductBody extends StatelessWidget {
  final Product product;
  final Animation<double> heroAnim;
  final String? uploadError;
  final bool isUploading;
  final VoidCallback onClaimTap;

  const _ProductBody({
    required this.product,
    required this.heroAnim,
    required this.uploadError,
    required this.isUploading,
    required this.onClaimTap,
  });

  @override
  Widget build(BuildContext context) {
    final campaign = product.campaign;
    final top = MediaQuery.of(context).padding.top;

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        // ── Hero image area ─────────────────────────────────────────────
        SliverAppBar(
          expandedHeight:  260,
          backgroundColor: AppTheme.primaryBg,
          surfaceTintColor: Colors.transparent,
          pinned:           true,
          leading: Padding(
            padding: const EdgeInsets.all(8),
            child: CircleAvatar(
              backgroundColor: Colors.white.withOpacity(0.9),
              child: IconButton(
                icon:      const Icon(Icons.arrow_back, size: 18),
                color:     AppTheme.ink,
                onPressed: () => context.pop(),
              ),
            ),
          ),
          flexibleSpace: FlexibleSpaceBar(
            background: FadeTransition(
              opacity: heroAnim,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end:   Alignment.bottomCenter,
                    colors: [AppTheme.primaryBg, Colors.white],
                  ),
                ),
                child: Center(
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.3),
                      end:   Offset.zero,
                    ).animate(heroAnim),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 100, height: 100,
                          decoration: BoxDecoration(
                            color:        Colors.white,
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color:      AppTheme.primary.withOpacity(0.12),
                                blurRadius: 20,
                                offset:     const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: product.imageUrl != null
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(24),
                                  child: Image.network(product.imageUrl!,
                                      fit: BoxFit.cover),
                                )
                              : Center(
                                  child: Text(
                                    product.name[0].toUpperCase(),
                                    style: TextStyle(
                                      fontSize:   42,
                                      fontWeight: FontWeight.w800,
                                      color:      AppTheme.primary,
                                    ),
                                  ),
                                ),
                        ),
                        if (campaign != null) ...[
                          const SizedBox(height: 12),
                          CashbackBadge(label: campaign.displayValue, large: true),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),

        // ── Content ─────────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Product name + brand
                Text(product.name, style: AppTheme.heading),
                if (product.brand != null) ...[
                  const SizedBox(height: 4),
                  Text(product.brand!, style: AppTheme.body),
                ],
                const SizedBox(height: 6),
                Row(children: [
                  const Icon(Icons.qr_code, size: 14, color: AppTheme.inkMuted),
                  const SizedBox(width: 4),
                  Text(product.barcode, style: AppTheme.caption),
                  if (product.category != null) ...[
                    const Text('  ·  ', style: AppTheme.caption),
                    Text(product.category!, style: AppTheme.caption),
                  ],
                ]),
                const SizedBox(height: 24),

                // Campaign card or no-offer state
                if (campaign != null)
                  _CampaignCard(campaign: campaign)
                else
                  _NoCampaignCard(),

                const SizedBox(height: 28),

                // How to claim steps
                const Text('How it works', style: AppTheme.subheading),
                const SizedBox(height: 16),
                const _HowItWorks(),
                const SizedBox(height: 28),

                // Upload error
                if (uploadError != null) ...[
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
                        child: Text(uploadError!,
                            style: const TextStyle(
                                color: AppTheme.error, fontSize: 13)),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 16),
                ],

                // CTA
                if (campaign != null)
                  _ClaimButton(
                    isUploading: isUploading,
                    onTap:       onClaimTap,
                  ),

                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Campaign card ─────────────────────────────────────────────────────────────

class _CampaignCard extends StatelessWidget {
  final Campaign campaign;
  const _CampaignCard({required this.campaign});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [AppTheme.primaryBg, Colors.white],
            begin:  Alignment.topLeft,
            end:    Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.primary.withOpacity(0.25)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color:        AppTheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.local_offer, color: AppTheme.primary, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Active Offer',
                      style: TextStyle(
                          fontSize: 11, color: AppTheme.inkMuted,
                          fontWeight: FontWeight.w600, letterSpacing: 0.5)),
                  const SizedBox(height: 3),
                  Text(campaign.displayValue,
                      style: AppTheme.cashbackLabel),
                  const SizedBox(height: 2),
                  Text(campaign.name,
                      style: AppTheme.caption,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      );
}

class _NoCampaignCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color:        const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(14),
          border:       Border.all(color: AppTheme.border),
        ),
        child: const Row(children: [
          Icon(Icons.info_outline, color: AppTheme.inkMuted, size: 18),
          SizedBox(width: 10),
          Text('No active cashback offer at the moment.',
              style: AppTheme.body),
        ]),
      );
}

// ── How it works ──────────────────────────────────────────────────────────────

class _HowItWorks extends StatelessWidget {
  const _HowItWorks();

  static const _steps = [
    (icon: Icons.shopping_cart_outlined, text: 'Buy this product at any supermarket'),
    (icon: Icons.camera_alt_outlined,    text: 'Photograph your receipt clearly'),
    (icon: Icons.document_scanner,       text: 'Our AI reads and verifies the purchase'),
    (icon: Icons.account_balance_wallet, text: 'Cashback lands in your wallet instantly'),
  ];

  @override
  Widget build(BuildContext context) => Column(
        children: List.generate(_steps.length, (i) {
          final step = _steps[i];
          final isLast = i == _steps.length - 1;
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Step number + connector line
                SizedBox(
                  width: 40,
                  child: Column(
                    children: [
                      Container(
                        width: 32, height: 32,
                        decoration: BoxDecoration(
                          color:        AppTheme.primary,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: Text('${i + 1}',
                              style: const TextStyle(
                                  color:      Colors.white,
                                  fontSize:   13,
                                  fontWeight: FontWeight.w800)),
                        ),
                      ),
                      if (!isLast)
                        Expanded(
                          child: Center(
                            child: Container(
                              width: 2,
                              color: AppTheme.border,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                // Content
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: isLast ? 0 : 20),
                    child: Row(
                      children: [
                        Icon(step.icon, color: AppTheme.inkMuted, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(step.text, style: AppTheme.body),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      );
}

// ── Claim CTA button with press animation ─────────────────────────────────────

class _ClaimButton extends StatefulWidget {
  final bool isUploading;
  final VoidCallback onTap;
  const _ClaimButton({required this.isUploading, required this.onTap});

  @override
  State<_ClaimButton> createState() => _ClaimButtonState();
}

class _ClaimButtonState extends State<_ClaimButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this, duration: const Duration(milliseconds: 80),
    lowerBound: 0.95, upperBound: 1.0, value: 1.0,
  );

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTapDown:  (_) { if (!widget.isUploading) _ctrl.reverse(); },
        onTapUp:    (_) { _ctrl.forward(); if (!widget.isUploading) widget.onTap(); },
        onTapCancel: () => _ctrl.forward(),
        child: ScaleTransition(
          scale: _ctrl,
          child: Container(
            height: 56,
            decoration: BoxDecoration(
              gradient:     widget.isUploading
                  ? LinearGradient(colors: [Colors.grey.shade300, Colors.grey.shade300])
                  : AppTheme.primaryGradient,
              borderRadius: BorderRadius.circular(14),
              boxShadow: widget.isUploading
                  ? []
                  : AppTheme.cardShadow,
            ),
            child: Center(
              child: widget.isUploading
                  ? const SizedBox(
                      height: 22, width: 22,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5))
                  : const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.camera_alt_outlined,
                            color: Colors.white, size: 20),
                        SizedBox(width: 10),
                        Text('Upload Receipt & Claim',
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

// ── Skeleton ──────────────────────────────────────────────────────────────────

class _ProductSkeleton extends StatelessWidget {
  const _ProductSkeleton();

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(),
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: SkeletonBox(
                    width: 100, height: 100, radius: 24),
              ),
              const SizedBox(height: 24),
              const SkeletonBox(width: 200, height: 22, radius: 6),
              const SizedBox(height: 10),
              const SkeletonBox(width: 120, height: 14, radius: 6),
              const SizedBox(height: 24),
              const SkeletonBox(width: double.infinity, height: 80, radius: 16),
            ],
          ),
        ),
      );
}
