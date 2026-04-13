import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/providers/providers.dart';
import '../../../core/theme/app_theme.dart';

class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;

    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // ── Header ────────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: AppTheme.primaryGradient,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 60, height: 60,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Center(
                        child: Text(
                          _initials(user?.fullName ?? user?.email ?? '?'),
                          style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user?.fullName ?? 'My Account',
                            style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            user?.email ?? '',
                            style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.8)),
                          ),
                          if (user?.phone != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              user!.phone!,
                              style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.7)),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── My Information ────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionLabel('My Information'),
                    const SizedBox(height: 10),
                    _InfoCard(children: [
                      if (user?.country != null)
                        _InfoRow(icon: Icons.flag_outlined, label: 'Country', value: user!.country!),
                      if (user?.city != null)
                        _InfoRow(icon: Icons.location_on_outlined, label: 'City', value: user!.city!),
                      if (user?.dateOfBirth != null)
                        _InfoRow(
                          icon: Icons.cake_outlined,
                          label: 'Date of birth',
                          value: _formatDob(user!.dateOfBirth!),
                        ),
                      if (user?.ageRange != null)
                        _InfoRow(icon: Icons.person_outlined, label: 'Age range', value: user!.ageRange!),
                      if (user?.preferences != null && user!.preferences.isNotEmpty)
                        _InfoRow(
                          icon: Icons.favorite_outline,
                          label: 'Interests',
                          value: user.preferences
                              .map((p) => p.replaceAll('_', ' '))
                              .map((p) => '${p[0].toUpperCase()}${p.substring(1)}')
                              .join(', '),
                        ),
                      if ((user?.country == null) &&
                          (user?.city == null) &&
                          (user?.dateOfBirth == null) &&
                          (user?.ageRange == null))
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 10),
                          child: Text(
                            'No profile info yet.',
                            style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
                          ),
                        ),
                    ]),
                  ],
                ),
              ),
            ),

            // ── Support ───────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionLabel('Support'),
                    const SizedBox(height: 10),
                    _InfoCard(children: [
                      _ActionRow(
                        icon: Icons.email_outlined,
                        label: 'Email us',
                        subtitle: 'support@cashbackapp.com',
                        color: const Color(0xFF2563EB),
                        onTap: () => _launchEmail(),
                      ),
                      const _Divider(),
                      _ActionRow(
                        icon: Icons.phone_outlined,
                        label: 'Call us',
                        subtitle: '+961 1 234 567',
                        color: const Color(0xFF059669),
                        onTap: () => _launchPhone(),
                      ),
                      const _Divider(),
                      _ActionRow(
                        icon: Icons.chat_outlined,
                        label: 'WhatsApp',
                        subtitle: 'Chat with support',
                        color: const Color(0xFF16A34A),
                        onTap: () => _launchWhatsApp(),
                      ),
                    ]),
                  ],
                ),
              ),
            ),

            // ── Logout ────────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
                child: GestureDetector(
                  onTap: () => _logout(context, ref),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.logout, color: Colors.red[600], size: 20),
                        const SizedBox(width: 10),
                        Text(
                          'Log out',
                          style: TextStyle(
                            color: Colors.red[600],
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Future<void> _launchEmail() async {
    final uri = Uri(scheme: 'mailto', path: 'support@cashbackapp.com',
        query: 'subject=Support%20Request');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  static Future<void> _launchPhone() async {
    final uri = Uri(scheme: 'tel', path: '+9611234567');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  static Future<void> _launchWhatsApp() async {
    final uri = Uri.parse('https://wa.me/9611234567');
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  static Future<void> _logout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Log out?'),
        content: const Text('You will need to sign in again to access your account.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Log out', style: TextStyle(color: Colors.red[600])),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(authProvider.notifier).logout();
      if (context.mounted) context.go('/login');
    }
  }

  static String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    if (name.isNotEmpty) return name[0].toUpperCase();
    return '?';
  }

  static String _formatDob(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          fontSize: 13, fontWeight: FontWeight.w700,
          color: Color(0xFF6B7280), letterSpacing: 0.5,
        ),
      );
}

class _InfoCard extends StatelessWidget {
  final List<Widget> children;
  const _InfoCard({required this.children});

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.border),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Column(children: children),
      );
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppTheme.primary),
            const SizedBox(width: 12),
            Text(label,
                style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280), fontWeight: FontWeight.w500)),
            const Spacer(),
            Flexible(
              child: Text(
                value,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
      );
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  const _ActionRow({
    required this.icon, required this.label, required this.subtitle,
    required this.color, required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
                  Text(subtitle,
                      style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
                ],
              ),
              const Spacer(),
              const Icon(Icons.chevron_right, color: Color(0xFFD1D5DB), size: 20),
            ],
          ),
        ),
      );
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) =>
      const Divider(height: 1, thickness: 1, color: Color(0xFFF3F4F6));
}
