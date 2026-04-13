import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'core/models/models.dart';
import 'core/providers/providers.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/screens/login_screen.dart';
import 'features/auth/screens/register_screen.dart';
import 'features/auth/screens/onboarding_screen.dart';
import 'features/home/screens/home_screen.dart';
import 'features/scan/screens/scan_screen.dart';
import 'features/product/screens/product_detail_screen.dart';
import 'features/claim/screens/claim_screen.dart';
import 'features/wallet/screens/wallet_screen.dart';
import 'features/history/screens/history_screen.dart';
import 'features/account/screens/account_screen.dart';

// ── Bottom-tab shell ──────────────────────────────────────────────────────────

class _AppShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;
  const _AppShell({required this.navigationShell});

  static const _tabs = [
    (icon: Icons.local_offer_outlined,            activeIcon: Icons.local_offer,            label: 'Offers'),
    (icon: Icons.qr_code_scanner_outlined,        activeIcon: Icons.qr_code_scanner,        label: 'Scan'),
    (icon: Icons.receipt_long_outlined,           activeIcon: Icons.receipt_long,           label: 'History'),
    (icon: Icons.person_outline,                  activeIcon: Icons.person,                 label: 'Account'),
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
        body: navigationShell,
        bottomNavigationBar: NavigationBar(
          selectedIndex:         navigationShell.currentIndex,
          onDestinationSelected: navigationShell.goBranch,
          backgroundColor:  Colors.white,
          indicatorColor:   AppTheme.primaryBg,
          destinations: _tabs
              .map((t) => NavigationDestination(
                    icon:         Icon(t.icon),
                    selectedIcon: Icon(t.activeIcon, color: AppTheme.primary),
                    label:        t.label,
                  ))
              .toList(),
        ),
      );
}

// ── Router ────────────────────────────────────────────────────────────────────

final _routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authProvider);

  return GoRouter(
    initialLocation: '/login',
    redirect: (context, state) {
      final loggedIn    = authState.isAuthenticated;
      final loc         = state.matchedLocation;
      final onAuthPages = loc == '/login' || loc == '/register';

      // Not logged in → force to login
      if (!loggedIn && !onAuthPages && loc != '/onboarding') return '/login';

      // On /register: the screen manages its own steps — never interfere
      if (loc == '/register') {
        if (!loggedIn) return null;
        final user = authState.user!;
        if (user.onboardingCompleted) return '/';
        return null;
      }

      // Logged in on /login → route based on registration progress
      if (loggedIn && loc == '/login') {
        final user = authState.user!;
        if (!user.onboardingCompleted) return '/onboarding';
        return '/';
      }

      // Logged in on home but onboarding not done
      if (loggedIn && loc == '/' && authState.user != null) {
        final user = authState.user!;
        if (!user.onboardingCompleted) return '/onboarding';
      }

      return null;
    },
    routes: [
      GoRoute(path: '/login',      builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/register',   builder: (_, __) => const RegisterScreen()),
      GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingScreen()),

      // ── Tabbed shell ────────────────────────────────────────────────
      StatefulShellRoute.indexedStack(
        builder: (_, __, shell) => _AppShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/',
              builder: (_, __) => const HomeScreen(),
              routes: [
                GoRoute(
                  path: 'product/:barcode',
                  builder: (_, state) =>
                      ProductDetailScreen(barcode: state.pathParameters['barcode']!),
                ),
                GoRoute(
                  path: 'claim',
                  builder: (_, state) {
                    final extra = state.extra! as Map<String, dynamic>;
                    return ClaimScreen(
                      receipt: extra['receipt'] as Receipt,
                      product: extra['product'] as Product,
                    );
                  },
                ),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/scan', builder: (_, __) => const ScanScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/history', builder: (_, __) => const HistoryScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/account', builder: (_, __) => const AccountScreen()),
          ]),
        ],
      ),
    ],
  );
});

// ── App root ──────────────────────────────────────────────────────────────────

class CashbackApp extends ConsumerWidget {
  const CashbackApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(_routerProvider);

    return MaterialApp.router(
      title:        'Cashback',
      theme:        AppTheme.light,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
