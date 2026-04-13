import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/models/models.dart';
import '../../../core/providers/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/widgets.dart';

// ── Category filter state ─────────────────────────────────────────────────────

final _selectedCategoryProvider = StateProvider<String?>((ref) => null);

const _categories = [
  (value: null,            label: 'All',          icon: '✨'),
  (value: 'snacks',        label: 'Snacks',        icon: '🍿'),
  (value: 'beverages',     label: 'Beverages',     icon: '🥤'),
  (value: 'dairy',         label: 'Dairy',         icon: '🧀'),
  (value: 'cosmetics',     label: 'Cosmetics',     icon: '💄'),
  (value: 'personal_care', label: 'Personal Care', icon: '🧴'),
  (value: 'pantry',        label: 'Pantry',        icon: '🫙'),
  (value: 'produce',       label: 'Produce',       icon: '🥦'),
  (value: 'household',     label: 'Household',     icon: '🧹'),
];

// ─────────────────────────────────────────────────────────────────────────────

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final walletAsync    = ref.watch(walletProvider);
    final campaignsAsync = ref.watch(campaignsProvider);
    final selectedCat    = ref.watch(_selectedCategoryProvider);

    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: RefreshIndicator(
        color:         AppTheme.primary,
        strokeWidth:   2.5,
        displacement:  80,
        onRefresh: () async {
          ref.invalidate(walletProvider);
          ref.invalidate(campaignsProvider);
        },
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics()),
          slivers: [
            // ── App bar ─────────────────────────────────────────────────
            _HomeAppBar(walletAsync: walletAsync),

            // ── Wallet balance card ──────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                child: walletAsync.when(
                  loading: () => const SkeletonBox(width: double.infinity, height: 88, radius: 20),
                  error:   (_, __) => const SizedBox.shrink(),
                  data: (w) => AnimatedPressButton(
                    onTap: () => context.go('/wallet'),
                    child: _WalletCard(balance: w.balance),
                  ),
                ),
              ),
            ),

            // ── Featured offers ──────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Featured', style: AppTheme.subheading),
                    PulsingDot(color: AppTheme.primary),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 168,
                child: campaignsAsync.when(
                  loading: () => ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: 3,
                    itemBuilder: (_, __) => const Padding(
                      padding: EdgeInsets.only(right: 14),
                      child: SkeletonFeaturedCard(),
                    ),
                  ),
                  error: (_, __) => const SizedBox.shrink(),
                  data: (campaigns) {
                    final featured = campaigns.take(5).toList();
                    return ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: featured.length,
                      itemBuilder: (_, i) => Padding(
                        padding: const EdgeInsets.only(right: 14),
                        child: _FeaturedCard(
                          offer: featured[i],
                          index: i,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

            // ── Category chips ────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 24, 20, 12),
                    child: Text('All Offers', style: AppTheme.subheading),
                  ),
                  SizedBox(
                    height: 40,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: _categories.length,
                      itemBuilder: (_, i) {
                        final cat      = _categories[i];
                        final selected = selectedCat == cat.value;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: AnimatedPressButton(
                            onTap: () => ref
                                .read(_selectedCategoryProvider.notifier)
                                .state = cat.value,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: selected ? AppTheme.primary : Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: selected
                                      ? AppTheme.primary
                                      : AppTheme.border,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(cat.icon,
                                      style: const TextStyle(fontSize: 13)),
                                  const SizedBox(width: 5),
                                  Text(
                                    cat.label,
                                    style: TextStyle(
                                      fontSize:   13,
                                      fontWeight: FontWeight.w600,
                                      color: selected
                                          ? Colors.white
                                          : AppTheme.ink,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
              ),
            ),

            // ── Offers list ───────────────────────────────────────────────
            campaignsAsync.when(
              loading: () => SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, __) => const SkeletonOfferCard(),
                    childCount: 5,
                  ),
                ),
              ),
              error: (_, __) => const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(
                    child: Text('Could not load offers', style: AppTheme.body),
                  ),
                ),
              ),
              data: (campaigns) {
                final filtered = selectedCat == null
                    ? campaigns
                    : campaigns
                        .where((c) =>
                            c.category?.toLowerCase() == selectedCat)
                        .toList();

                if (filtered.isEmpty) {
                  return SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Center(
                        child: Column(
                          children: [
                            const Text('😕',
                                style: TextStyle(fontSize: 40)),
                            const SizedBox(height: 12),
                            const Text('No offers in this category yet.',
                                style: AppTheme.body,
                                textAlign: TextAlign.center),
                          ],
                        ),
                      ),
                    ),
                  );
                }

                return SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (_, i) => _OfferListCard(
                        offer: filtered[i],
                        index: i,
                      ),
                      childCount: filtered.length,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ── App bar ───────────────────────────────────────────────────────────────────

class _HomeAppBar extends ConsumerWidget {
  final AsyncValue walletAsync;
  const _HomeAppBar({required this.walletAsync});

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      SliverAppBar(
        backgroundColor:    AppTheme.surface,
        surfaceTintColor:   Colors.transparent,
        floating:           true,
        snap:               true,
        elevation:          0,
        titleSpacing:       20,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Good ${_greeting()}',
                style: AppTheme.caption.copyWith(color: AppTheme.inkMuted)),
            const Text('Cashback Offers', style: AppTheme.subheading),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_outlined),
            color: AppTheme.inkMuted,
            onPressed: () => ref.read(authProvider.notifier).logout(),
          ),
          const SizedBox(width: 8),
        ],
      );

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'morning ☀️';
    if (h < 17) return 'afternoon 🌤';
    return 'evening 🌙';
  }
}

// ── Wallet balance card ───────────────────────────────────────────────────────

class _WalletCard extends StatelessWidget {
  final double balance;
  const _WalletCard({required this.balance});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          gradient:     AppTheme.primaryGradient,
          borderRadius: BorderRadius.circular(20),
          boxShadow:    AppTheme.cardShadow,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Available Balance',
                      style: TextStyle(
                          color: Colors.white70, fontSize: 12,
                          letterSpacing: 0.3)),
                  const SizedBox(height: 4),
                  Text('\$${balance.toStringAsFixed(2)}',
                      style: const TextStyle(
                          color:      Colors.white,
                          fontSize:   28,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color:        Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.account_balance_wallet_outlined,
                  color: Colors.white, size: 22),
            ),
          ],
        ),
      );
}

// ── Featured card (horizontal scroll) ────────────────────────────────────────

class _FeaturedCard extends StatelessWidget {
  final CampaignOffer offer;
  final int index;
  const _FeaturedCard({required this.offer, required this.index});

  // Cycle through a set of gradient backgrounds
  static const _gradients = [
    [Color(0xFF059669), Color(0xFF047857)],
    [Color(0xFF7C3AED), Color(0xFF5B21B6)],
    [Color(0xFFD97706), Color(0xFFB45309)],
    [Color(0xFF2563EB), Color(0xFF1D4ED8)],
    [Color(0xFFDB2777), Color(0xFFBE185D)],
  ];

  @override
  Widget build(BuildContext context) {
    final colors = _gradients[index % _gradients.length];
    return AnimatedPressButton(
      onTap: () => context.go('/product/${offer.barcode}'),
      child: Container(
        width:  210,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color:      colors[0].withOpacity(0.35),
              blurRadius: 16,
              offset:     const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Category pill
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color:        Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                offer.category ?? 'Offer',
                style: const TextStyle(
                    color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ),

            const Spacer(),

            // Cashback value — big
            Text(
              offer.displayValue,
              style: const TextStyle(
                  color:      Colors.white,
                  fontSize:   22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3),
            ),
            const SizedBox(height: 4),
            Text(
              offer.productName,
              style: const TextStyle(
                  color:      Colors.white70,
                  fontSize:   13,
                  fontWeight: FontWeight.w500),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),

            const SizedBox(height: 12),

            // Claim arrow
            Row(
              children: [
                const Text('Claim now',
                    style: TextStyle(
                        color:      Colors.white,
                        fontSize:   12,
                        fontWeight: FontWeight.w700)),
                const SizedBox(width: 4),
                const Icon(Icons.arrow_forward, color: Colors.white, size: 14),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Offer list card ───────────────────────────────────────────────────────────

class _OfferListCard extends StatelessWidget {
  final CampaignOffer offer;
  final int index;
  const _OfferListCard({required this.offer, required this.index});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: AnimatedPressButton(
          onTap: () => context.go('/product/${offer.barcode}'),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color:        Colors.white,
              borderRadius: BorderRadius.circular(16),
              border:       Border.all(color: AppTheme.border),
            ),
            child: Row(
              children: [
                // Avatar
                Container(
                  width: 52, height: 52,
                  decoration: BoxDecoration(
                    color:        AppTheme.primaryBg,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: Text(
                      offer.productName[0].toUpperCase(),
                      style: TextStyle(
                        fontSize:   20,
                        fontWeight: FontWeight.w800,
                        color:      AppTheme.primary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Product info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        offer.productName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize:   14,
                          color:      AppTheme.ink,
                        ),
                        maxLines:  1,
                        overflow:  TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        [offer.brand, offer.category]
                            .whereType<String>()
                            .join(' · '),
                        style: AppTheme.caption,
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 10),
                CashbackBadge(label: offer.displayValue),
              ],
            ),
          ),
        ),
      );
}
