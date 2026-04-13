import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/providers.dart';
import '../../../core/theme/app_theme.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  List<Map<String, dynamic>>? _claims;
  bool _loading = true;
  String _filter = 'all'; // all | approved | pending | rejected

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final api    = ref.read(apiServiceProvider);
      final claims = await api.getClaims();
      if (mounted) setState(() { _claims = claims; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _filtered {
    if (_claims == null) return [];
    if (_filter == 'all') return _claims!;
    return _claims!.where((c) => c['status'] == _filter).toList();
  }

  double get _totalEarned => (_claims ?? [])
      .where((c) => c['status'] == 'approved')
      .fold(0.0, (sum, c) => sum + (double.tryParse(c['cashback_amount']?.toString() ?? '0') ?? 0));

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;

    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: SafeArea(
        child: RefreshIndicator(
          color: AppTheme.primary,
          onRefresh: _load,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // ── Header ────────────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Claim History',
                          style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF111827))),
                      const SizedBox(height: 4),
                      Text(
                        _loading ? 'Loading...' : '${_claims?.length ?? 0} total claims',
                        style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Summary card ──────────────────────────────────────────
              if (!_loading && (_claims?.isNotEmpty ?? false))
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: AppTheme.primaryGradient,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _SummaryTile(
                              label: 'Total Earned',
                              value: '\$${_totalEarned.toStringAsFixed(2)}',
                            ),
                          ),
                          _VertDivider(),
                          Expanded(
                            child: _SummaryTile(
                              label: 'Approved',
                              value: '${(_claims ?? []).where((c) => c['status'] == 'approved').length}',
                            ),
                          ),
                          _VertDivider(),
                          Expanded(
                            child: _SummaryTile(
                              label: 'Pending',
                              value: '${(_claims ?? []).where((c) => c['status'] == 'pending').length}',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // ── Filter chips ─────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _FilterChip(label: 'All',      value: 'all',      selected: _filter, onTap: (v) => setState(() => _filter = v)),
                        const SizedBox(width: 8),
                        _FilterChip(label: 'Approved', value: 'approved', selected: _filter, onTap: (v) => setState(() => _filter = v)),
                        const SizedBox(width: 8),
                        _FilterChip(label: 'Pending',  value: 'pending',  selected: _filter, onTap: (v) => setState(() => _filter = v)),
                        const SizedBox(width: 8),
                        _FilterChip(label: 'Rejected', value: 'rejected', selected: _filter, onTap: (v) => setState(() => _filter = v)),
                      ],
                    ),
                  ),
                ),
              ),

              // ── List ─────────────────────────────────────────────────
              if (_loading)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: _SkeletonList(),
                  ),
                )
              else if (filtered.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('🧾', style: TextStyle(fontSize: 48)),
                        const SizedBox(height: 12),
                        Text(
                          _filter == 'all'
                              ? 'No claims yet'
                              : 'No ${_filter} claims',
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF111827)),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Scan a receipt to earn cashback!',
                          style: TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
                        ),
                      ],
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (_, i) => _ClaimCard(claim: filtered[i]),
                      childCount: filtered.length,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Widgets ───────────────────────────────────────────────────────────────────

class _SummaryTile extends StatelessWidget {
  final String label;
  final String value;
  const _SummaryTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text(value,
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(
                  fontSize: 11, color: Colors.white.withValues(alpha: 0.75))),
        ],
      );
}

class _VertDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        width: 1, height: 36,
        color: Colors.white.withValues(alpha: 0.2),
      );
}

class _FilterChip extends StatelessWidget {
  final String label;
  final String value;
  final String selected;
  final void Function(String) onTap;
  const _FilterChip({required this.label, required this.value, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isSelected = value == selected;
    return GestureDetector(
      onTap: () => onTap(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color:        isSelected ? AppTheme.primary : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppTheme.primary : AppTheme.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize:   13,
            fontWeight: FontWeight.w600,
            color:      isSelected ? Colors.white : const Color(0xFF6B7280),
          ),
        ),
      ),
    );
  }
}

class _ClaimCard extends StatelessWidget {
  final Map<String, dynamic> claim;
  const _ClaimCard({required this.claim});

  @override
  Widget build(BuildContext context) {
    final status      = claim['status']      as String? ?? 'pending';
    final amount      = double.tryParse(claim['cashback_amount']?.toString() ?? '0') ?? 0;
    final productName = claim['product_name'] as String? ?? 'Product';
    final storeName   = claim['store_name']   as String?;
    final submittedAt = claim['submitted_at'] as String?;
    final barcode     = claim['barcode']      as String?;

    final dateStr = submittedAt != null
        ? _fmtDate(DateTime.tryParse(submittedAt) ?? DateTime.now())
        : '';

    final (color, bg, icon, label) = switch (status) {
      'approved' => (const Color(0xFF059669), const Color(0xFFECFDF5), Icons.check_circle_outline, 'Approved'),
      'rejected' => (const Color(0xFFDC2626), const Color(0xFFFEF2F2), Icons.cancel_outlined,      'Rejected'),
      'flagged'  => (const Color(0xFFD97706), const Color(0xFFFFFBEB), Icons.flag_outlined,        'Flagged'),
      _          => (const Color(0xFF6B7280), const Color(0xFFF9FAFB), Icons.hourglass_empty,      'Pending'),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color:        Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          // Status icon
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(productName,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF111827)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 3),
                Row(
                  children: [
                    if (storeName != null) ...[
                      const Icon(Icons.store_outlined, size: 11, color: Color(0xFF9CA3AF)),
                      const SizedBox(width: 3),
                      Text(storeName,
                          style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
                      const SizedBox(width: 8),
                    ],
                    if (dateStr.isNotEmpty) ...[
                      const Icon(Icons.calendar_today_outlined, size: 11, color: Color(0xFF9CA3AF)),
                      const SizedBox(width: 3),
                      Text(dateStr,
                          style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
                    ],
                  ],
                ),
                if (barcode != null) ...[
                  const SizedBox(height: 2),
                  Text(barcode,
                      style: const TextStyle(fontSize: 10, color: Color(0xFFD1D5DB))),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Amount + status
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('\$${amount.toStringAsFixed(2)}',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800, color: color)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: bg, borderRadius: BorderRadius.circular(8),
                ),
                child: Text(label,
                    style: TextStyle(
                        fontSize: 10, fontWeight: FontWeight.w700, color: color)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _fmtDate(DateTime dt) {
    const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${m[dt.month - 1]} ${dt.day}, ${dt.year}';
  }
}

class _SkeletonList extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Column(
        children: List.generate(5, (i) => Container(
          margin: const EdgeInsets.only(bottom: 10),
          height: 76,
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(16),
          ),
        )),
      );
}
