import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/api/models.dart';
import '../core/session.dart';
import '../core/theme/app_theme.dart';

/// Original ticket-shaped brand mark (no third-party logos).
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 34, this.light = true});
  final double size;
  final bool light;
  @override
  Widget build(BuildContext context) => FittedBox(fit: BoxFit.scaleDown, child: _mark());

  Widget _mark() => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(size * 0.28)),
          child: Icon(Icons.confirmation_number_rounded, color: LottoColors.primary, size: size * 0.66),
        ),
        const SizedBox(width: 8),
        Text.rich(
            TextSpan(children: [
              TextSpan(text: 'LOTTO ', style: TextStyle(color: light ? Colors.white : LottoColors.navy, fontWeight: FontWeight.w900)),
              const TextSpan(text: 'DAY', style: TextStyle(color: LottoColors.accent, fontWeight: FontWeight.w900)),
            ]),
            style: TextStyle(fontSize: size * 0.55)),
      ]);
}

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.child});
  final Widget child;
  static const tabs = [
    ('หน้าหลัก', Icons.home_outlined, Icons.home_rounded, '/app/home'),
    ('ซื้อสลาก', Icons.confirmation_number_outlined, Icons.confirmation_number, '/app/catalog'),
    ('ตรวจผล', Icons.manage_search_outlined, Icons.manage_search, '/app/results'),
    ('รายการ', Icons.receipt_long_outlined, Icons.receipt_long, '/app/orders'),
    ('โปรไฟล์', Icons.person_outline, Icons.person, '/app/profile'),
  ];

  static int indexFor(String path) {
    if (path.startsWith('/app/markets')) return 2;
    if (path.startsWith('/app/my-tickets') || path.startsWith('/app/wallet')) return 3;
    final i = tabs.indexWhere((t) => path.startsWith(t.$4));
    return i < 0 ? 0 : i;
  }

  @override
  Widget build(BuildContext context) {
    final session = AppScope.of(context);
    final path = GoRouterState.of(context).uri.path;
    final selected = indexFor(path);
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 880;
    return Scaffold(
      appBar: AppBar(
        flexibleSpace: Container(decoration: const BoxDecoration(gradient: LinearGradient(colors: [LottoColors.primary, LottoColors.secondary]))),
        title: InkWell(onTap: () => context.go('/app/home'), child: const BrandMark(size: 30)),
        actions: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Center(child: Text('DEMO', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11, color: LottoColors.accent))),
          ),
          IconButton(
            tooltip: 'การแจ้งเตือน',
            onPressed: () => context.go('/app/notifications'),
            icon: Badge(isLabelVisible: session.unread > 0, label: Text('${session.unread}'), child: const Icon(Icons.notifications_none_rounded)),
          ),
          IconButton(
            tooltip: 'ตะกร้า',
            onPressed: () => context.go('/app/cart'),
            icon: Badge(isLabelVisible: session.cartCount > 0, label: Text('${session.cartCount}'), child: const Icon(Icons.shopping_cart_outlined)),
          ),
          if (session.isStaff) IconButton(tooltip: 'หลังบ้าน', onPressed: () => context.go('/admin'), icon: const Icon(Icons.admin_panel_settings_outlined)),
        ],
      ),
      body: Row(children: [
        if (wide)
          NavigationRail(
            selectedIndex: selected,
            extended: width >= 1200,
            backgroundColor: Colors.white,
            indicatorColor: LottoColors.surface,
            selectedIconTheme: const IconThemeData(color: LottoColors.primary),
            onDestinationSelected: (i) => context.go(tabs[i].$4),
            destinations: [for (final t in tabs) NavigationRailDestination(icon: Icon(t.$2), selectedIcon: Icon(t.$3), label: Text(t.$1))],
          ),
        Expanded(child: child),
      ]),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              height: 68,
              selectedIndex: selected,
              onDestinationSelected: (i) => context.go(tabs[i].$4),
              destinations: [for (final t in tabs) NavigationDestination(icon: Icon(t.$2), selectedIcon: Icon(t.$3, color: LottoColors.primary), label: t.$1)],
            ),
    );
  }
}

class AdminShell extends StatelessWidget {
  const AdminShell({super.key, required this.child});
  final Widget child;

  /// (label, icon, route, required permission)
  static const routes = [
    ('ภาพรวม', Icons.dashboard_outlined, '/admin', 'dashboard.view'),
    ('ผู้ใช้งาน', Icons.groups_outlined, '/admin/users', 'users.view'),
    ('สลาก / งวด', Icons.confirmation_number_outlined, '/admin/catalog', 'catalog.manage'),
    ('หวย 4 ประเภท', Icons.grid_view_rounded, '/admin/lottery', 'dashboard.view'),
    ('ผลรางวัล / ตรวจสอบ', Icons.emoji_events_outlined, '/admin/results', 'dashboard.view'),
    ('Audit ผลหวย', Icons.fact_check_outlined, '/admin/lottery/audit', 'audit.view'),
    ('รายการ / ธุรกรรม', Icons.receipt_long_outlined, '/admin/orders', 'orders.view'),
    ('ประกาศ / ข่าวสาร', Icons.campaign_outlined, '/admin/announcements', 'announcements.manage'),
    ('รายงาน / Export', Icons.bar_chart_outlined, '/admin/reports', 'reports.view'),
    ('สิทธิ์ผู้ใช้ (Role)', Icons.admin_panel_settings_outlined, '/admin/access', 'dashboard.view'),
    ('ตั้งค่าระบบ', Icons.settings_outlined, '/admin/settings', 'settings.manage'),
    ('Log / Audit', Icons.security_outlined, '/admin/audit', 'audit.view'),
  ];

  static bool isSelected(String route, String path) {
    if (route == '/admin') return path == '/admin';
    if (route == '/admin/lottery') return path == '/admin/lottery' || path.startsWith('/admin/lottery/draws') || path.startsWith('/admin/lottery/result');
    return path == route || path.startsWith('$route/');
  }

  @override
  Widget build(BuildContext context) {
    final session = AppScope.of(context);
    final narrow = MediaQuery.sizeOf(context).width < 920;
    final path = GoRouterState.of(context).uri.path;
    final user = session.user;
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          if (narrow) const BrandMark(size: 26) else const Text('หน้าจัดการหลังบ้าน (Admin)'),
          const SizedBox(width: 8),
          const Text('DEMO', style: TextStyle(color: LottoColors.accent, fontSize: 11, fontWeight: FontWeight.w900)),
        ]),
        actions: [
          if (user != null && !narrow)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Center(child: Text('${user.displayName} • ${roleTh[user.role] ?? user.role}', style: const TextStyle(fontSize: 13))),
            ),
          IconButton(tooltip: 'กลับหน้าผู้ใช้', onPressed: () => context.go('/app/home'), icon: const Icon(Icons.storefront_outlined)),
          IconButton(
            tooltip: 'ออกจากระบบ',
            onPressed: () async {
              await session.logout();
              if (context.mounted) context.go('/auth/login');
            },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      drawer: narrow ? Drawer(backgroundColor: LottoColors.navy, child: SafeArea(child: _menu(context, session, path))) : null,
      body: Row(children: [
        if (!narrow) SizedBox(width: 250, child: Material(color: LottoColors.navy, child: _menu(context, session, path))),
        Expanded(child: child),
      ]),
    );
  }

  Widget _menu(BuildContext context, Session session, String path) => ListView(padding: const EdgeInsets.all(10), children: [
        const Padding(padding: EdgeInsets.fromLTRB(10, 12, 10, 4), child: BrandMark(size: 32)),
        const Padding(padding: EdgeInsets.fromLTRB(12, 0, 12, 12), child: Text('Admin • ระบบสาธิต', style: TextStyle(color: Colors.white70, fontSize: 12))),
        for (final item in routes)
          if (session.can(item.$4))
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: ListTile(
                dense: true,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                selected: isSelected(item.$3, path),
                selectedTileColor: LottoColors.primary,
                selectedColor: Colors.white,
                textColor: Colors.white,
                iconColor: Colors.white70,
                leading: Icon(item.$2),
                title: Text(item.$1),
                onTap: () {
                  if (Scaffold.maybeOf(context)?.isDrawerOpen ?? false) Navigator.of(context).pop();
                  context.go(item.$3);
                },
              ),
            ),
        const Divider(color: Colors.white24),
        ListTile(
          dense: true,
          title: const Text('กลับหน้าผู้ใช้', style: TextStyle(color: Colors.white)),
          leading: const Icon(Icons.arrow_back, color: LottoColors.secondary),
          onTap: () => context.go('/app/home'),
        ),
      ]);
}
