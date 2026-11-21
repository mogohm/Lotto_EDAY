import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/session.dart';
import '../features/admin/admin_pages.dart';
import '../features/auth/auth_pages.dart';
import '../features/lottery/lottery_admin_pages.dart';
import '../features/lottery/lottery_public_page.dart';
import '../features/user/user_pages.dart';
import '../features/user/wallet_pages.dart';
import 'app_shell.dart';

const publicPrefixes = ['/welcome', '/auth/'];

/// Route guard: anonymous → login; non-staff → no /admin; per-module permission checks.
String? guard(Session session, String path) {
  final isPublic = publicPrefixes.any(path.startsWith);
  if (!session.isLoggedIn) return isPublic ? null : '/auth/login?from=${Uri.encodeComponent(path)}';
  if (isPublic) return session.isStaff ? '/admin' : '/app/home';
  if (path.startsWith('/admin') && !session.isStaff) return '/app/home';
  final needed = adminPermissionFor(path);
  if (needed != null && !session.can(needed)) return '/admin';
  return null;
}

/// Full redirect incl. the splash screen shown while a stored session is restored.
String? resolveRedirect(Session session, Uri uri) {
  final path = uri.path;
  if (session.restoring) return path == '/splash' ? null : '/splash?from=${Uri.encodeComponent(uri.toString())}';
  if (path == '/splash') {
    final from = uri.queryParameters['from'];
    final target = (from == null || from.isEmpty || from.startsWith('/splash')) ? (session.isLoggedIn ? '/app/home' : '/welcome') : from;
    return guard(session, Uri.parse(target).path) ?? target;
  }
  return guard(session, path);
}

String? adminPermissionFor(String path) {
  const map = {
    '/admin/users': 'users.view',
    '/admin/catalog': 'catalog.manage',
    '/admin/orders': 'orders.view',
    '/admin/announcements': 'announcements.manage',
    '/admin/reports': 'reports.view',
    '/admin/settings': 'settings.manage',
    '/admin/audit': 'audit.view',
    '/admin/lottery/audit': 'audit.view',
  };
  for (final e in map.entries) {
    if (path == e.key || path.startsWith('${e.key}/')) return e.value;
  }
  return null;
}

GoRouter buildRouter(Session session) => GoRouter(
      initialLocation: '/app/home',
      refreshListenable: session,
      redirect: (context, state) => resolveRedirect(session, state.uri),
      errorBuilder: (context, state) => Scaffold(
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('ไม่พบหน้าที่ต้องการ'),
            TextButton(onPressed: () => context.go('/app/home'), child: const Text('กลับหน้าหลัก')),
          ]),
        ),
      ),
      routes: [
        GoRoute(path: '/splash', builder: (_, __) => const SplashPage()),
        GoRoute(path: '/welcome', builder: (_, __) => const WelcomePage()),
        GoRoute(path: '/auth/login', builder: (_, s) => LoginPage(from: s.uri.queryParameters['from'])),
        GoRoute(path: '/auth/register', builder: (_, __) => const RegisterPage()),
        ShellRoute(builder: (context, state, child) => AppShell(child: child), routes: [
          GoRoute(path: '/app/home', builder: (_, __) => const HomePage()),
          GoRoute(path: '/app/catalog', builder: (_, s) => CatalogPage(drawId: s.uri.queryParameters['drawId'])),
          GoRoute(path: '/app/ticket/:id', builder: (_, s) => TicketDetailPage(id: s.pathParameters['id']!)),
          GoRoute(path: '/app/cart', builder: (_, __) => const CartPage()),
          GoRoute(path: '/app/my-tickets', builder: (_, __) => const MyTicketsPage()),
          GoRoute(path: '/app/orders', builder: (_, __) => const HistoryPage()),
          GoRoute(path: '/app/orders/:id', builder: (_, s) => OrderDetailPage(id: s.pathParameters['id']!)),
          GoRoute(path: '/app/results', builder: (_, __) => const ResultsPage()),
          GoRoute(path: '/app/markets', builder: (_, __) => const LotteryPublicPage()),
          GoRoute(path: '/app/wallet', builder: (_, s) => WalletPage(action: s.uri.queryParameters['action'])),
          GoRoute(path: '/app/notifications', builder: (_, __) => const NotificationsPage()),
          GoRoute(path: '/app/news', builder: (_, __) => const NewsPage()),
          GoRoute(path: '/app/profile', builder: (_, __) => const ProfilePage()),
          GoRoute(path: '/app/profile/edit', builder: (_, __) => const EditProfilePage()),
          GoRoute(path: '/app/profile/security', builder: (_, __) => const SecurityPage()),
          GoRoute(path: '/app/help', builder: (_, __) => const HelpPage()),
          GoRoute(path: '/app/about', builder: (_, __) => const AboutPage()),
        ]),
        ShellRoute(builder: (context, state, child) => AdminShell(child: child), routes: [
          GoRoute(path: '/admin', builder: (_, __) => const AdminDashboardPage()),
          GoRoute(path: '/admin/lottery', builder: (_, __) => const LotteryMarketsAdminPage()),
          GoRoute(path: '/admin/lottery/draws/:marketId', builder: (_, s) => LotteryDrawsAdminPage(marketId: s.pathParameters['marketId']!)),
          GoRoute(path: '/admin/lottery/result/:drawId', builder: (_, s) => LotteryResultEditorPage(drawId: s.pathParameters['drawId']!)),
          GoRoute(path: '/admin/lottery/audit', builder: (_, __) => const LotteryAuditPage()),
          GoRoute(path: '/admin/users', builder: (_, __) => const AdminUsersPage()),
          GoRoute(path: '/admin/catalog', builder: (_, __) => const AdminCatalogPage()),
          GoRoute(path: '/admin/orders', builder: (_, __) => const AdminOrdersPage()),
          GoRoute(path: '/admin/results', builder: (_, __) => const AdminResultsQueuePage()),
          GoRoute(path: '/admin/announcements', builder: (_, __) => const AdminAnnouncementsPage()),
          GoRoute(path: '/admin/reports', builder: (_, __) => const AdminReportsPage()),
          GoRoute(path: '/admin/access', builder: (_, __) => const AdminAccessPage()),
          GoRoute(path: '/admin/settings', builder: (_, __) => const AdminSettingsPage()),
          GoRoute(path: '/admin/audit', builder: (_, __) => const AdminAuditPage()),
        ]),
      ],
    );
