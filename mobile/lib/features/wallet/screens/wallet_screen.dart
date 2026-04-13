import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/models/models.dart';
import '../../../core/providers/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/widgets.dart';

class WalletScreen extends ConsumerWidget {
  const WalletScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final walletAsync = ref.watch(walletProvider);

    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: walletAsync.when(
        loading: () => const _WalletSkeleton(),
        error: (e, _) => Scaffold(
          appBar: AppBar(title: const Text('My Wallet')),
          body: ErrorCard(
            message: 'Could not load wallet',
            onRetry: () => ref.invalidate(walletProvider),
          ),
        ),
        data: (wallet) => RefreshIndicator(
          color:       AppTheme.primary,
          strokeWidth: 2.5,
          onRefresh:   () async => ref.invalidate(walletProvider),
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics()),
            slivers: [
              // ── App bar ────────────────────────────────────────────────
              SliverAppBar(
                backgroundColor:  AppTheme.surface,
                surfaceTintColor: Colors.transparent,
                floating:         true,
                snap:             true,
                elevation:        0,
                titleSpacing:     20,
                title:  const Text('My Wallet', style: AppTheme.subheading),
                actions: [
                  IconButton(
                    icon:      const Icon(Icons.refresh_outlined,
                        color: AppTheme.inkMuted),
                    onPressed: () => ref.invalidate(walletProvider),
                  ),
                  const SizedBox(width: 8),
                ],
              ),

              // ── Balance card ───────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                  child: _BalanceCard(wallet: wallet),
                ),
              ),

              // ── Stats row ──────────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: _StatsRow(wallet: wallet),
                ),
              ),

              // ── Transactions header ────────────────────────────────────
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, 28, 20, 12),
                  child: Text('Transaction History', style: AppTheme.subheading),
                ),
              ),

              // ── Transactions list ──────────────────────────────────────
              wallet.transactions.isEmpty
                  ? SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(40),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 80, height: 80,
                                decoration: BoxDecoration(
                                  color:        AppTheme.primaryBg,
                                  borderRadius: BorderRadius.circular(24),
                                ),
                                child: Icon(Icons.receipt_long_outlined,
                                    size: 36, color: AppTheme.primary),
                              ),
                              const SizedBox(height: 16),
                              const Text('No transactions yet',
                                  style: AppTheme.subheading,
                                  textAlign: TextAlign.center),
                              const SizedBox(height: 8),
                              const Text(
                                'Start scanning products and\nclaiming cashback!',
                                style: AppTheme.body,
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  : SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (ctx, i) {
                            // Group by date — insert a date header when day changes
                            final tx   = wallet.transactions[i];
                            final prev = i > 0 ? wallet.transactions[i - 1] : null;
                            final showHeader = prev == null ||
                                !_sameDay(tx.createdAt, prev.createdAt);
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (showHeader)
                                  _DateHeader(date: tx.createdAt),
                                _TransactionTile(tx: tx),
                              ],
                            );
                          },
                          childCount: wallet.transactions.length,
                        ),
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }

  static bool _sameDay(DateTime a, DateTime b) {
    final la = a.toLocal();
    final lb = b.toLocal();
    return la.year == lb.year && la.month == lb.month && la.day == lb.day;
  }
}

// ── Balance card ──────────────────────────────────────────────────────────────

class _BalanceCard extends StatelessWidget {
  final Wallet wallet;
  const _BalanceCard({required this.wallet});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient:     AppTheme.primaryGradient,
          borderRadius: BorderRadius.circular(24),
          boxShadow:    AppTheme.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Available Balance',
                style: TextStyle(
                    color: Colors.white70, fontSize: 13, letterSpacing: 0.3)),
            const SizedBox(height: 6),
            Text(
              '\$${wallet.balance.toStringAsFixed(2)}',
              style: const TextStyle(
                color:      Colors.white,
                fontSize:   46,
                fontWeight: FontWeight.w800,
                letterSpacing: -1.5,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color:        Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.account_balance_wallet_outlined,
                      color: Colors.white, size: 14),
                ),
                const SizedBox(width: 8),
                Text(
                  'Updated ${DateFormat('MMM d, y').format(wallet.updatedAt)}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ],
        ),
      );
}

// ── Stats row ─────────────────────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  final Wallet wallet;
  const _StatsRow({required this.wallet});

  double _totalEarned() => wallet.transactions
      .where((t) => t.amount > 0)
      .fold(0.0, (sum, t) => sum + t.amount);

  double _thisMonth() {
    final now = DateTime.now();
    return wallet.transactions
        .where((t) =>
            t.amount > 0 &&
            t.createdAt.year == now.year &&
            t.createdAt.month == now.month)
        .fold(0.0, (sum, t) => sum + t.amount);
  }

  int _claimCount() =>
      wallet.transactions.where((t) => t.type == 'cashback').length;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          _StatCard(
            label: 'Total Earned',
            value: '\$${_totalEarned().toStringAsFixed(2)}',
            icon:  Icons.trending_up_rounded,
            color: AppTheme.primary,
          ),
          const SizedBox(width: 10),
          _StatCard(
            label: 'This Month',
            value: '\$${_thisMonth().toStringAsFixed(2)}',
            icon:  Icons.calendar_today_outlined,
            color: const Color(0xFF7C3AED),
          ),
          const SizedBox(width: 10),
          _StatCard(
            label: 'Claims',
            value: '${_claimCount()}',
            icon:  Icons.receipt_outlined,
            color: const Color(0xFF2563EB),
          ),
        ],
      );
}

class _StatCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
            color:        Colors.white,
            borderRadius: BorderRadius.circular(16),
            border:       Border.all(color: AppTheme.border),
            boxShadow:    AppTheme.subtleShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color:        color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 14),
              ),
              const SizedBox(height: 8),
              Text(value,
                  style: const TextStyle(
                      fontSize:   16,
                      fontWeight: FontWeight.w800,
                      color:      AppTheme.ink,
                      letterSpacing: -0.3)),
              const SizedBox(height: 2),
              Text(label,
                  style: const TextStyle(
                      fontSize: 11,
                      color:    AppTheme.inkMuted,
                      fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      );
}

// ── Date header ───────────────────────────────────────────────────────────────

class _DateHeader extends StatelessWidget {
  final DateTime date;
  const _DateHeader({required this.date});

  String _label() {
    final now   = DateTime.now();
    final local = date.toLocal();
    if (local.year == now.year &&
        local.month == now.month &&
        local.day == now.day) {
      return 'Today';
    }
    final yesterday = now.subtract(const Duration(days: 1));
    if (local.year == yesterday.year &&
        local.month == yesterday.month &&
        local.day == yesterday.day) {
      return 'Yesterday';
    }
    return DateFormat('MMMM d, y').format(local);
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8),
        child: Text(
          _label(),
          style: const TextStyle(
            fontSize:      12,
            fontWeight:    FontWeight.w700,
            color:         AppTheme.inkMuted,
            letterSpacing: 0.4,
          ),
        ),
      );
}

// ── Transaction tile ──────────────────────────────────────────────────────────

class _TransactionTile extends StatelessWidget {
  final WalletTransaction tx;
  const _TransactionTile({required this.tx});

  static const _typeConfig = {
    'cashback':   (icon: Icons.arrow_downward_rounded, label: 'Cashback Earned'),
    'withdrawal': (icon: Icons.arrow_upward_rounded,   label: 'Withdrawal'),
    'adjustment': (icon: Icons.tune_rounded,            label: 'Adjustment'),
  };

  @override
  Widget build(BuildContext context) {
    final isCredit  = tx.amount > 0;
    final config    = _typeConfig[tx.type];
    final label     = config?.label ?? tx.type;
    final iconData  = config?.icon  ?? Icons.swap_horiz_rounded;

    final Color creditColor = AppTheme.primary;
    final Color debitColor  = const Color(0xFFDC2626);
    final Color amountColor = isCredit ? creditColor : debitColor;
    final Color bgColor     = isCredit
        ? AppTheme.primary.withOpacity(0.08)
        : debitColor.withOpacity(0.08);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color:        Colors.white,
        borderRadius: BorderRadius.circular(14),
        border:       Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          // Icon
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
              color:        bgColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(iconData, color: amountColor, size: 18),
          ),
          const SizedBox(width: 12),

          // Label + time
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize:   14,
                        fontWeight: FontWeight.w600,
                        color:      AppTheme.ink)),
                const SizedBox(height: 2),
                Text(
                  DateFormat('h:mm a').format(tx.createdAt.toLocal()),
                  style: AppTheme.caption,
                ),
              ],
            ),
          ),

          // Amount
          Text(
            '${isCredit ? '+' : ''}\$${tx.amount.abs().toStringAsFixed(2)}',
            style: TextStyle(
              fontSize:   15,
              fontWeight: FontWeight.w700,
              color:      amountColor,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Skeleton ──────────────────────────────────────────────────────────────────

class _WalletSkeleton extends StatelessWidget {
  const _WalletSkeleton();

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppTheme.surface,
        appBar: AppBar(
            backgroundColor:  AppTheme.surface,
            surfaceTintColor: Colors.transparent,
            title: const Text('My Wallet', style: AppTheme.subheading)),
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SkeletonBox(
                  width: double.infinity, height: 130, radius: 24),
              const SizedBox(height: 12),
              Row(children: const [
                Expanded(child: SkeletonBox(width: double.infinity, height: 80, radius: 16)),
                SizedBox(width: 10),
                Expanded(child: SkeletonBox(width: double.infinity, height: 80, radius: 16)),
                SizedBox(width: 10),
                Expanded(child: SkeletonBox(width: double.infinity, height: 80, radius: 16)),
              ]),
              const SizedBox(height: 28),
              const SkeletonBox(width: 160, height: 18, radius: 6),
              const SizedBox(height: 16),
              const SkeletonBox(
                  width: double.infinity, height: 68, radius: 14),
              const SizedBox(height: 8),
              const SkeletonBox(
                  width: double.infinity, height: 68, radius: 14),
              const SizedBox(height: 8),
              const SkeletonBox(
                  width: double.infinity, height: 68, radius: 14),
            ],
          ),
        ),
      );
}
