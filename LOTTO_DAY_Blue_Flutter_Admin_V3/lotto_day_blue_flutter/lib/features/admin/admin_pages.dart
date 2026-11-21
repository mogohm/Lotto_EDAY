import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/models.dart';
import '../../core/format.dart';
import '../../core/session.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/download/download.dart';
import '../../shared/ui.dart';

const _pad = EdgeInsets.all(20);

// ============================================================ DASHBOARD
class AdminDashboardPage extends StatelessWidget {
  const AdminDashboardPage({super.key});
  @override
  Widget build(BuildContext context) => AsyncView<(Json, Json)>(
        load: () async {
          final api = context.api;
          return (await api.dashboard(), await api.config());
        },
        builder: (context, data, reload) {
          final (d, cfg) = data;
          final k = jsonMap(d['kpi']);
          final daily = jsonList(d['daily']);
          final width = MediaQuery.sizeOf(context).width;
          final cols = width >= 1300
              ? 4
              : width >= 700
                  ? 2
                  : 1;
          final s = context.session;
          final flags = jsonMap(cfg['flags']);
          return PageList(onRefresh: reload, maxWidth: 1350, padding: _pad, children: [
            SectionTitle('ภาพรวมระบบ', trailing: Text('ข้อมูล ณ ${thaiDateTime(DateTime.now())}', style: const TextStyle(fontSize: 12))),
            GridView.count(
              crossAxisCount: cols,
              childAspectRatio: cols == 1 ? 3.6 : 2.3,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                AdminMetric('ยอดขายรวม (DEMO)', '${money(k['demoSalesTotal'] as num?)} บาท', Icons.payments_outlined),
                AdminMetric('จำนวนรายการ', '${money(k['orders'] as num?)} รายการ', Icons.receipt_long),
                AdminMetric('ผู้ใช้ทั้งหมด', '${money(k['users'] as num?)} คน', Icons.groups),
                AdminMetric('ผู้ใช้วันนี้', '${money(k['usersToday'] as num?)} คน', Icons.person_pin_circle_outlined),
              ],
            ),
            const SectionTitle('ยอดขายรายวัน (บาท, เครดิตจำลอง)'),
            Card(
                child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 18, 18, 12),
                    child: SizedBox(
                        height: 220,
                        child: LineChart(
                            values: [for (final r in daily) (r['total'] as num).toDouble()],
                            labels: [for (final r in daily) thaiDate(r['day'], short: true).split(' ').take(2).join(' ')])))),
            const SectionTitle('งานที่ต้องดำเนินการ'),
            Wrap(spacing: 10, runSpacing: 10, children: [
              _TaskCard('รอตรวจสอบผล', k['awaitingReview'], Icons.hourglass_top, () => context.go('/admin/results')),
              _TaskCard('อนุมัติแล้ว รอเผยแพร่', k['approved'], Icons.publish, () => context.go('/admin/results?status=APPROVED')),
              _TaskCard('คำขอถอน (จำลอง)', k['pendingWithdrawals'], Icons.savings_outlined, () => context.go('/admin/orders')),
              _TaskCard('สลากคงเหลือ', k['ticketsAvailable'], Icons.confirmation_number_outlined, () => context.go('/admin/catalog')),
            ]),
            const SectionTitle('เมนูหลักหลังบ้าน'),
            LayoutBuilder(builder: (context, c) {
              final n = c.maxWidth >= 900
                  ? 5
                  : c.maxWidth >= 560
                      ? 3
                      : 2;
              const tiles = [
                ('จัดการผู้ใช้งาน', Icons.groups, '/admin/users', 'users.view'),
                ('จัดการสลาก / งวด', Icons.confirmation_number, '/admin/catalog', 'catalog.manage'),
                ('จัดการหวย 4 ประเภท', Icons.grid_view_rounded, '/admin/lottery', 'dashboard.view'),
                ('จัดการรายการ', Icons.receipt_long, '/admin/orders', 'orders.view'),
                ('ผลรางวัล', Icons.emoji_events, '/admin/results', 'dashboard.view'),
                ('ประกาศ / ข่าวสาร', Icons.campaign, '/admin/announcements', 'announcements.manage'),
                ('รายงาน / Export', Icons.bar_chart, '/admin/reports', 'reports.view'),
                ('สิทธิ์ผู้ใช้งาน (Role)', Icons.admin_panel_settings, '/admin/access', 'dashboard.view'),
                ('ตั้งค่าระบบ', Icons.settings, '/admin/settings', 'settings.manage'),
                ('Log / Audit', Icons.security, '/admin/audit', 'audit.view'),
              ];
              final visible = tiles.where((t) => s.can(t.$4)).toList();
              return Wrap(spacing: 10, runSpacing: 10, children: [
                for (final t in visible)
                  SizedBox(width: (c.maxWidth - (n - 1) * 10) / n, height: 110, child: QuickTile(label: t.$1, icon: t.$2, onTap: () => context.go(t.$3))),
              ]);
            }),
            const SectionTitle('รายการล่าสุด'),
            Card(
              child: Column(children: [
                for (final o in jsonList(d['recentOrders']))
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.receipt_long, color: LottoColors.primary),
                    title: Text('${o['receiptNo']} • ${o['user']}'),
                    subtitle: Text(thaiDateTime(o['createdAt'])),
                    trailing: Text(baht(o['total'] as num?), style: const TextStyle(fontWeight: FontWeight.w800)),
                  ),
                if (jsonList(d['recentOrders']).isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('ยังไม่มีรายการ')),
              ]),
            ),
            const SectionTitle('สถานะความปลอดภัยทางการเงิน'),
            Card(
              child: Column(children: [
                for (final f in flags.entries)
                  ListTile(
                    dense: true,
                    leading: Icon(f.value == true ? Icons.toggle_on : Icons.lock, color: f.key == 'DEMO_MODE' ? LottoColors.positive : LottoColors.negative),
                    title: Text(f.key),
                    trailing: Text('${f.value}'.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w800)),
                  ),
              ]),
            ),
          ]);
        },
      );
}

class _TaskCard extends StatelessWidget {
  const _TaskCard(this.label, this.value, this.icon, this.onTap);
  final String label;
  final Object? value;
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: 250,
        child: Card(
          child: ListTile(
            leading: Icon(icon, color: LottoColors.primary),
            title: Text(label),
            trailing: Text('${value ?? 0}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: LottoColors.navy)),
            onTap: onTap,
          ),
        ),
      );
}

class AdminMetric extends StatelessWidget {
  const AdminMetric(this.label, this.value, this.icon, {super.key});
  final String label;
  final String value;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(children: [
            Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: LottoColors.surface, borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: LottoColors.primary)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: const TextStyle(fontSize: 12)),
                FittedBox(child: Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: LottoColors.navy))),
              ]),
            ),
          ]),
        ),
      );
}

/// Minimal dependency-free line chart (sky-blue line with soft fill).
class LineChart extends StatelessWidget {
  const LineChart({super.key, required this.values, required this.labels});
  final List<double> values;
  final List<String> labels;
  @override
  Widget build(BuildContext context) => CustomPaint(painter: _LinePainter(values, labels), size: Size.infinite);
}

class _LinePainter extends CustomPainter {
  _LinePainter(this.values, this.labels);
  final List<double> values;
  final List<String> labels;
  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    const left = 44.0, bottom = 22.0;
    final w = size.width - left, h = size.height - bottom;
    final maxV = values.reduce((a, b) => a > b ? a : b);
    final top = maxV <= 0 ? 1.0 : maxV * 1.15;
    final grid = Paint()
      ..color = LottoColors.border
      ..strokeWidth = 1;
    final tp = TextPainter(textDirection: TextDirection.ltr);
    for (var i = 0; i <= 3; i++) {
      final y = h - h * i / 3;
      canvas.drawLine(Offset(left, y), Offset(size.width, y), grid);
      tp.text = TextSpan(text: money(top * i / 3), style: const TextStyle(fontSize: 10, color: Color(0xFF4A6380)));
      tp.layout();
      tp.paint(canvas, Offset(0, y - 6));
    }
    final dx = values.length == 1 ? 0.0 : w / (values.length - 1);
    final pts = [for (var i = 0; i < values.length; i++) Offset(left + dx * i, h - h * values[i] / top)];
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final p in pts.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    final fill = Path.from(path)
      ..lineTo(pts.last.dx, h)
      ..lineTo(pts.first.dx, h)
      ..close();
    canvas.drawPath(
        fill,
        Paint()
          ..shader = LinearGradient(
                  colors: [LottoColors.secondary.withValues(alpha: 0.35), LottoColors.secondary.withValues(alpha: 0.02)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter)
              .createShader(Rect.fromLTWH(0, 0, size.width, h)));
    canvas.drawPath(
        path,
        Paint()
          ..color = LottoColors.primary
          ..strokeWidth = 2.5
          ..style = PaintingStyle.stroke);
    for (final p in pts) {
      canvas.drawCircle(p, 3.5, Paint()..color = LottoColors.primary);
    }
    final step = (labels.length / 7).ceil().clamp(1, 99);
    for (var i = 0; i < labels.length; i += step) {
      tp.text = TextSpan(text: labels[i], style: const TextStyle(fontSize: 10, color: Color(0xFF4A6380)));
      tp.layout();
      tp.paint(canvas, Offset(pts[i].dx - tp.width / 2, h + 6));
    }
  }

  @override
  bool shouldRepaint(covariant _LinePainter old) => old.values != values;
}

// ============================================================ USERS
class AdminUsersPage extends StatefulWidget {
  const AdminUsersPage({super.key});
  @override
  State<AdminUsersPage> createState() => _AdminUsersPageState();
}

class _AdminUsersPageState extends State<AdminUsersPage> {
  String _q = '';
  String? _role;
  String? _status;
  int _version = 0;

  Future<void> _edit(BuildContext context, AppUser u) async {
    final s = context.session;
    var role = u.role, status = u.status, kyc = u.kycStatus;
    final pw = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text('แก้ไข ${u.displayName}'),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(u.email),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: role,
                decoration: const InputDecoration(labelText: 'บทบาท (ต้องมีสิทธิ์ roles.manage)'),
                items: [for (final r in roleTh.entries) DropdownMenuItem(value: r.key, child: Text(r.value))],
                onChanged: s.can('roles.manage') && u.id != s.user?.id ? (v) => setS(() => role = v!) : null,
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: status,
                decoration: const InputDecoration(labelText: 'สถานะบัญชี'),
                items: const [DropdownMenuItem(value: 'ACTIVE', child: Text('ใช้งาน')), DropdownMenuItem(value: 'SUSPENDED', child: Text('ระงับ'))],
                onChanged: (v) => setS(() => status = v!),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: kyc,
                decoration: const InputDecoration(labelText: 'สถานะ KYC (DEMO)'),
                items: [for (final k in kycTh.entries) DropdownMenuItem(value: k.key, child: Text(k.value))],
                onChanged: (v) => setS(() => kyc = v!),
              ),
              const SizedBox(height: 10),
              TextField(controller: pw, decoration: const InputDecoration(labelText: 'รีเซ็ตรหัสผ่าน (เว้นว่างถ้าไม่เปลี่ยน)')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ยกเลิก')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('บันทึก'))
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    final body = <String, dynamic>{
      if (role != u.role) 'role': role,
      if (status != u.status) 'status': status,
      if (kyc != u.kycStatus) 'kycStatus': kyc,
      if (pw.text.isNotEmpty) 'resetPassword': pw.text,
    };
    if (body.isEmpty) return;
    if (await runAction(context, () => context.api.updateUser(u.id, body), success: 'บันทึกแล้ว')) setState(() => _version++);
  }

  Future<void> _create(BuildContext context) async {
    final email = TextEditingController(), name = TextEditingController(), pw = TextEditingController();
    var role = 'RESULT_EDITOR';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('เพิ่มผู้ใช้ / เจ้าหน้าที่'),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: email, decoration: const InputDecoration(labelText: 'อีเมล')),
              const SizedBox(height: 10),
              TextField(controller: name, decoration: const InputDecoration(labelText: 'ชื่อที่แสดง')),
              const SizedBox(height: 10),
              TextField(controller: pw, decoration: const InputDecoration(labelText: 'รหัสผ่านเริ่มต้น', helperText: '8 ตัวขึ้นไป มีตัวอักษรและตัวเลข')),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: role,
                decoration: const InputDecoration(labelText: 'บทบาท'),
                items: [for (final r in roleTh.entries) DropdownMenuItem(value: r.key, child: Text(r.value))],
                onChanged: (v) => setS(() => role = v!),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ยกเลิก')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('สร้าง'))
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    if (await runAction(context, () => context.api.createUser({'email': email.text.trim(), 'displayName': name.text.trim(), 'password': pw.text, 'role': role}),
        success: 'สร้างบัญชีแล้ว')) {
      setState(() => _version++);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canManage = context.session.can('users.manage');
    return AsyncView<Json>(
      key: ValueKey('$_q|$_role|$_status|$_version'),
      load: () => context.api.users(q: _q, role: _role, status: _status),
      builder: (context, r, reload) {
        final users = jsonList(r['items']).map(AppUser.new).toList();
        return PageList(maxWidth: 1250, padding: _pad, children: [
          SectionTitle('จัดการผู้ใช้งาน (${r['total']})',
              trailing: canManage
                  ? FilledButton.icon(onPressed: () => _create(context), icon: const Icon(Icons.person_add), label: const Text('เพิ่มผู้ใช้'))
                  : null),
          Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SizedBox(
              width: 280,
              child: TextField(
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'ค้นหาชื่อ อีเมล เบอร์โทร'),
                onSubmitted: (v) => setState(() => _q = v.trim()),
              ),
            ),
            DropdownButton<String?>(
              value: _role,
              hint: const Text('ทุกบทบาท'),
              items: [
                const DropdownMenuItem(value: null, child: Text('ทุกบทบาท')),
                for (final e in roleTh.entries) DropdownMenuItem(value: e.key, child: Text(e.value))
              ],
              onChanged: (v) => setState(() => _role = v),
            ),
            DropdownButton<String?>(
              value: _status,
              hint: const Text('ทุกสถานะ'),
              items: const [
                DropdownMenuItem(value: null, child: Text('ทุกสถานะ')),
                DropdownMenuItem(value: 'ACTIVE', child: Text('ใช้งาน')),
                DropdownMenuItem(value: 'SUSPENDED', child: Text('ระงับ'))
              ],
              onChanged: (v) => setState(() => _status = v),
            ),
          ]),
          const SizedBox(height: 12),
          if (users.isEmpty) const EmptyState('ไม่พบผู้ใช้'),
          if (isWide(context, 1000) && users.isNotEmpty)
            Card(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(columns: const [
                  DataColumn(label: Text('ชื่อ')),
                  DataColumn(label: Text('อีเมล')),
                  DataColumn(label: Text('บทบาท')),
                  DataColumn(label: Text('สถานะ')),
                  DataColumn(label: Text('KYC')),
                  DataColumn(label: Text('เครดิต DEMO'), numeric: true),
                  DataColumn(label: Text('เข้าระบบล่าสุด')),
                  DataColumn(label: Text('')),
                ], rows: [
                  for (final u in users)
                    DataRow(cells: [
                      DataCell(Text(u.displayName)),
                      DataCell(Text(u.email)),
                      DataCell(Text(roleTh[u.role] ?? u.role)),
                      DataCell(
                          StatusChip(u.status == 'ACTIVE' ? 'ใช้งาน' : 'ระงับ', color: u.status == 'ACTIVE' ? LottoColors.positive : LottoColors.negative)),
                      DataCell(Text(kycTh[u.kycStatus] ?? u.kycStatus)),
                      DataCell(Text(money(u.demoBalance))),
                      DataCell(Text(thaiDateTime(u.j['lastLoginAt']))),
                      DataCell(canManage
                          ? IconButton(tooltip: 'แก้ไข', onPressed: () => _edit(context, u), icon: const Icon(Icons.edit_outlined))
                          : const SizedBox()),
                    ]),
                ]),
              ),
            )
          else
            for (final u in users)
              Card(
                child: ListTile(
                  leading: CircleAvatar(backgroundColor: LottoColors.surface, child: Text(u.displayName.characters.first)),
                  title: Text(u.displayName, style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text('${u.email}\n${roleTh[u.role]} • ${u.status == 'ACTIVE' ? 'ใช้งาน' : 'ระงับ'} • ${kycTh[u.kycStatus]}'),
                  isThreeLine: true,
                  trailing: canManage ? IconButton(onPressed: () => _edit(context, u), icon: const Icon(Icons.edit_outlined)) : null,
                ),
              ),
        ]);
      },
    );
  }
}

// ============================================================ CATALOG (tickets / draws)
class AdminCatalogPage extends StatefulWidget {
  const AdminCatalogPage({super.key});
  @override
  State<AdminCatalogPage> createState() => _AdminCatalogPageState();
}

class _AdminCatalogPageState extends State<AdminCatalogPage> {
  String? _drawId;
  String? _status;
  String _number = '';
  int _v = 0;

  @override
  Widget build(BuildContext context) => AsyncView<(List<Draw>, Json?)>(
        key: ValueKey('$_drawId|$_status|$_number|$_v'),
        load: () async {
          final api = context.api;
          final draws = (await api.adminDraws()).where((d) => d.status == 'SCHEDULED' || d.status == 'DRAFT').toList();
          _drawId ??= draws.firstOrNull?.id;
          final t = _drawId == null ? null : await api.adminTickets(drawId: _drawId, status: _status, number: _number);
          return (draws, t);
        },
        builder: (context, data, reload) {
          final (draws, t) = data;
          final items = jsonList(t?['items']);
          final draw = draws.where((d) => d.id == _drawId).firstOrNull;
          return PageList(maxWidth: 1250, padding: _pad, children: [
            const SectionTitle('จัดการสลาก / งวด'),
            const Text('สลากเป็นข้อมูลจำลอง 6 หลัก ใช้ทดสอบการซื้อด้วยเครดิตจำลองเท่านั้น'),
            const SizedBox(height: 10),
            Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
              DropdownButton<String>(
                value: _drawId,
                hint: const Text('เลือกงวดที่เปิดขาย'),
                items: [
                  for (final d in draws) DropdownMenuItem(value: d.id, child: Text('${d.market?.nameTh ?? d.marketId} • ${thaiDate(d.drawDate, short: true)}'))
                ],
                onChanged: (v) => setState(() => _drawId = v),
              ),
              DropdownButton<String?>(
                value: _status,
                hint: const Text('ทุกสถานะ'),
                items: const [
                  DropdownMenuItem(value: null, child: Text('ทุกสถานะ')),
                  DropdownMenuItem(value: 'AVAILABLE', child: Text('ว่าง')),
                  DropdownMenuItem(value: 'SOLD', child: Text('ขายแล้ว')),
                  DropdownMenuItem(value: 'WITHDRAWN', child: Text('ถอนออก')),
                ],
                onChanged: (v) => setState(() => _status = v),
              ),
              SizedBox(
                  width: 200,
                  child: TextField(
                      decoration: const InputDecoration(hintText: 'ค้นหาเลข', prefixIcon: Icon(Icons.search)),
                      onSubmitted: (v) => setState(() => _number = v))),
              if (draw != null)
                FilledButton.icon(
                  onPressed: () async {
                    final c = TextEditingController(text: '50');
                    final n = await showDialog<int>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('สร้างสลากสุ่ม (DEMO)'),
                        content: TextField(controller: c, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'จำนวนใบ (1-500)')),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ยกเลิก')),
                          FilledButton(onPressed: () => Navigator.pop(ctx, int.tryParse(c.text)), child: const Text('สร้าง'))
                        ],
                      ),
                    );
                    if (n == null || !context.mounted) return;
                    var created = 0;
                    if (await runAction(context, () async => created = await context.api.generateTickets(draw.id, n)) && context.mounted) {
                      toast(context, 'สร้างสลาก $created ใบ');
                      setState(() => _v++);
                    }
                  },
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('สร้างสลากสุ่ม'),
                ),
              OutlinedButton.icon(onPressed: () => context.go('/admin/lottery'), icon: const Icon(Icons.calendar_month), label: const Text('จัดการงวด')),
            ]),
            const SizedBox(height: 12),
            if (draws.isEmpty) const EmptyState('ไม่มีงวดที่เปิดขาย — สร้างงวดในเมนูหวย 4 ประเภท'),
            if (t != null) Text('ทั้งหมด ${t['total']} ใบ (แสดง 50 ใบแรก)'),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final x in items)
                Container(
                  width: 190,
                  padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: LottoColors.border)),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${x['number']}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: 2)),
                        Text('${x['status']} • ${x['price']} บ.', style: const TextStyle(fontSize: 11)),
                      ]),
                    ),
                    if (x['status'] != 'SOLD')
                      IconButton(
                        tooltip: x['status'] == 'AVAILABLE' ? 'ถอนออกจากการขาย' : 'นำกลับมาขาย',
                        icon: Icon(x['status'] == 'AVAILABLE' ? Icons.remove_circle_outline : Icons.replay, color: LottoColors.primary),
                        onPressed: () async {
                          if (await runAction(
                              context, () => context.api.setTicketStatus('${x['id']}', x['status'] == 'AVAILABLE' ? 'WITHDRAWN' : 'AVAILABLE'))) {
                            setState(() => _v++);
                          }
                        },
                      ),
                  ]),
                ),
            ]),
          ]);
        },
      );
}

// ============================================================ ORDERS + WITHDRAWALS
class AdminOrdersPage extends StatefulWidget {
  const AdminOrdersPage({super.key});
  @override
  State<AdminOrdersPage> createState() => _AdminOrdersPageState();
}

class _AdminOrdersPageState extends State<AdminOrdersPage> {
  String _q = '';
  String? _status;
  int _v = 0;

  @override
  Widget build(BuildContext context) {
    final canManage = context.session.can('orders.manage');
    return DefaultTabController(
      length: 2,
      child: Column(children: [
        const Material(color: Colors.white, child: TabBar(tabs: [Tab(text: 'รายการซื้อ (DEMO)'), Tab(text: 'คำขอถอน (จำลอง)')])),
        Expanded(
          child: TabBarView(children: [
            AsyncView<Json>(
              key: ValueKey('$_q|$_status|$_v'),
              load: () => context.api.adminOrders(q: _q, status: _status),
              builder: (context, r, reload) => PageList(maxWidth: 1200, padding: _pad, children: [
                Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  SizedBox(
                      width: 300,
                      child: TextField(
                          decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'เลขใบรับ / อีเมล / เลขสลาก'),
                          onSubmitted: (v) => setState(() => _q = v.trim()))),
                  DropdownButton<String?>(
                    value: _status,
                    hint: const Text('ทุกสถานะ'),
                    items: const [
                      DropdownMenuItem(value: null, child: Text('ทุกสถานะ')),
                      DropdownMenuItem(value: 'CONFIRMED_DEMO', child: Text('สำเร็จ')),
                      DropdownMenuItem(value: 'CANCELLED', child: Text('ยกเลิก'))
                    ],
                    onChanged: (v) => setState(() => _status = v),
                  ),
                  Text('ทั้งหมด ${r['total']} รายการ'),
                ]),
                const SizedBox(height: 10),
                if (jsonList(r['items']).isEmpty) const EmptyState('ไม่พบรายการ'),
                for (final o in jsonList(r['items']))
                  Card(
                    child: ListTile(
                      leading: Icon(o['status'] == 'CANCELLED' ? Icons.cancel_outlined : Icons.check_circle_outline,
                          color: o['status'] == 'CANCELLED' ? LottoColors.negative : LottoColors.positive),
                      title: Text('${o['receiptNo']} • ${baht(o['total'] as num?)}', style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text(
                          '${jsonMap(o['user'])['displayName']} (${jsonMap(o['user'])['email']}) • ${thaiDateTime(o['createdAt'])}\nเลข: ${jsonList(o['items']).map((i) => i['number']).join(', ')}'),
                      isThreeLine: true,
                      trailing: canManage && o['status'] == 'CONFIRMED_DEMO'
                          ? TextButton(
                              onPressed: () async {
                                final n = await promptText(context, 'ยกเลิกรายการ ${o['receiptNo']}', label: 'เหตุผล (คืนเครดิตจำลองให้ผู้ใช้)');
                                if (n != null &&
                                    context.mounted &&
                                    await runAction(context, () => context.api.cancelOrder('${o['id']}', n), success: 'ยกเลิกและคืนเครดิตแล้ว')) {
                                  setState(() => _v++);
                                }
                              },
                              child: const Text('ยกเลิก'),
                            )
                          : Text(o['status'] == 'CANCELLED' ? 'ยกเลิก' : 'สำเร็จ'),
                    ),
                  ),
              ]),
            ),
            AsyncView<List<Json>>(
              key: ValueKey('w$_v'),
              load: () => context.api.withdrawals(),
              builder: (context, items, reload) => PageList(maxWidth: 1000, padding: _pad, children: [
                const Text('คำขอถอนจำลอง — ไม่มีการโอนเงินจริง การปฏิเสธจะคืนเครดิตจำลองให้ผู้ใช้'),
                const SizedBox(height: 10),
                if (items.isEmpty) const EmptyState('ไม่มีคำขอ'),
                for (final t in items)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.savings_outlined, color: LottoColors.primary),
                      title: Text('${jsonMap(t['user'])['displayName']} • ${baht(-(t['amount'] as int))}'),
                      subtitle: Text('${thaiDateTime(t['createdAt'])} • ${txStatusTh[t['status']] ?? t['status']}'),
                      trailing: canManage && t['status'] == 'PENDING'
                          ? Wrap(spacing: 4, children: [
                              IconButton(
                                  tooltip: 'อนุมัติ',
                                  icon: const Icon(Icons.check, color: LottoColors.positive),
                                  onPressed: () async {
                                    if (await runAction(context, () => context.api.decideWithdrawal('${t['id']}', true), success: 'อนุมัติแล้ว')) {
                                      setState(() => _v++);
                                    }
                                  }),
                              IconButton(
                                  tooltip: 'ปฏิเสธ',
                                  icon: const Icon(Icons.close, color: LottoColors.negative),
                                  onPressed: () async {
                                    if (await runAction(context, () => context.api.decideWithdrawal('${t['id']}', false), success: 'ปฏิเสธและคืนเครดิตแล้ว')) {
                                      setState(() => _v++);
                                    }
                                  }),
                            ])
                          : null,
                    ),
                  ),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }
}

// ============================================================ RESULTS QUEUE
class AdminResultsQueuePage extends StatefulWidget {
  const AdminResultsQueuePage({super.key});
  @override
  State<AdminResultsQueuePage> createState() => _AdminResultsQueuePageState();
}

class _AdminResultsQueuePageState extends State<AdminResultsQueuePage> {
  String? _status;
  String? _market;
  DateTimeRange? _range;
  bool _init = false;

  @override
  Widget build(BuildContext context) {
    if (!_init) {
      _status = GoRouterState.of(context).uri.queryParameters['status'] ?? 'AWAITING_REVIEW';
      _init = true;
    }
    return AsyncView<(List<Market>, List<Draw>)>(
      key: ValueKey('$_status|$_market|$_range'),
      load: () async {
        final api = context.api;
        return (
          await api.adminMarkets(),
          await api.adminDraws(
              status: _status, marketId: _market, from: _range == null ? null : isoDay(_range!.start), to: _range == null ? null : isoDay(_range!.end)),
        );
      },
      builder: (context, data, reload) {
        final (markets, draws) = data;
        return PageList(onRefresh: reload, maxWidth: 1200, padding: _pad, children: [
          const SectionTitle('ผลรางวัล • ตรวจสอบ อนุมัติ และเผยแพร่'),
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            for (final s in [null, ...drawStatusTh.keys])
              ChoiceChip(label: Text(s == null ? 'ทั้งหมด' : drawStatusTh[s]!), selected: _status == s, onSelected: (_) => setState(() => _status = s)),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            DropdownButton<String?>(
              value: _market,
              hint: const Text('ทุกประเภท'),
              items: [
                const DropdownMenuItem(value: null, child: Text('ทุกประเภท')),
                for (final m in markets) DropdownMenuItem(value: m.id, child: Text(m.nameTh))
              ],
              onChanged: (v) => setState(() => _market = v),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                final r = await showDateRangePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime(2100), initialDateRange: _range);
                if (r != null) setState(() => _range = r);
              },
              icon: const Icon(Icons.date_range),
              label: Text(_range == null ? 'ช่วงวันที่' : '${thaiDate(isoDay(_range!.start), short: true)} - ${thaiDate(isoDay(_range!.end), short: true)}'),
            ),
            if (_range != null) IconButton(onPressed: () => setState(() => _range = null), icon: const Icon(Icons.clear)),
          ]),
          const SizedBox(height: 10),
          if (draws.isEmpty) const EmptyState('ไม่มีงวดในสถานะนี้', icon: Icons.task_alt),
          for (final d in draws)
            Card(
              child: ListTile(
                leading: CircleAvatar(
                    backgroundColor: LottoColors.surface,
                    child: Icon(d.market?.isDaily == true ? Icons.casino_outlined : Icons.public, color: LottoColors.primary)),
                title: Text('${d.market?.nameTh ?? d.marketId} • งวด ${thaiDate(d.drawDate)}', style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text(d.market?.isExternal == true
                    ? 'แหล่ง: ${d.sourceName ?? '-'} • ${d.sourceVerified ? 'ตรวจสอบแล้ว' : 'ยังไม่ยืนยันแหล่ง'}'
                    : 'ผลจำลอง DEMO • ${d.results.length} ช่อง'),
                trailing: StatusChip.draw(d.status),
                onTap: () => context.go('/admin/lottery/result/${d.id}'),
              ),
            ),
        ]);
      },
    );
  }
}

// ============================================================ ANNOUNCEMENTS
class AdminAnnouncementsPage extends StatelessWidget {
  const AdminAnnouncementsPage({super.key});

  Future<bool> _editDialog(BuildContext context, Json? a) async {
    final title = TextEditingController(text: a?['title'] as String?);
    final body = TextEditingController(text: a?['body'] as String?);
    var category = (a?['category'] ?? 'NEWS') as String;
    var pinned = (a?['pinned'] ?? false) as bool;
    var published = (a?['published'] ?? false) as bool;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(a == null ? 'สร้างประกาศ' : 'แก้ไขประกาศ'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(controller: title, decoration: const InputDecoration(labelText: 'หัวข้อ')),
                const SizedBox(height: 10),
                TextField(controller: body, maxLines: 6, decoration: const InputDecoration(labelText: 'เนื้อหา')),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: category,
                  decoration: const InputDecoration(labelText: 'หมวดหมู่'),
                  items: const [
                    DropdownMenuItem(value: 'NEWS', child: Text('ข่าวสาร')),
                    DropdownMenuItem(value: 'RESULT', child: Text('ผลรางวัล')),
                    DropdownMenuItem(value: 'SYSTEM', child: Text('ระบบ')),
                    DropdownMenuItem(value: 'PROMO', child: Text('กิจกรรม')),
                  ],
                  onChanged: (v) => setS(() => category = v!),
                ),
                SwitchListTile(contentPadding: EdgeInsets.zero, value: pinned, onChanged: (v) => setS(() => pinned = v), title: const Text('ปักหมุด')),
                SwitchListTile(contentPadding: EdgeInsets.zero, value: published, onChanged: (v) => setS(() => published = v), title: const Text('เผยแพร่')),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ยกเลิก')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('บันทึก'))
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return false;
    return runAction(
        context,
        () => context.api.saveAnnouncement(
            a?['id'] as String?, {'title': title.text.trim(), 'body': body.text.trim(), 'category': category, 'pinned': pinned, 'published': published}),
        success: 'บันทึกประกาศแล้ว');
  }

  @override
  Widget build(BuildContext context) => AsyncView<List<Json>>(
        load: () => context.api.adminAnnouncements(),
        builder: (context, items, reload) => PageList(onRefresh: reload, maxWidth: 1000, padding: _pad, children: [
          SectionTitle('ประกาศ / ข่าวสาร',
              trailing: FilledButton.icon(
                  onPressed: () async {
                    if (await _editDialog(context, null)) await reload();
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('สร้างประกาศ'))),
          if (items.isEmpty) const EmptyState('ยังไม่มีประกาศ'),
          for (final a in items)
            Card(
              child: ListTile(
                leading: Icon(a['pinned'] == true ? Icons.push_pin : Icons.campaign_outlined, color: LottoColors.primary),
                title: Text('${a['title']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text('${a['category']} • ${a['published'] == true ? 'เผยแพร่ ${thaiDateTime(a['publishedAt'])}' : 'ร่าง'}\n${a['body']}',
                    maxLines: 3, overflow: TextOverflow.ellipsis),
                isThreeLine: true,
                trailing: Wrap(children: [
                  IconButton(
                      tooltip: 'แก้ไข',
                      onPressed: () async {
                        if (await _editDialog(context, a)) await reload();
                      },
                      icon: const Icon(Icons.edit_outlined)),
                  IconButton(
                    tooltip: 'ลบ',
                    onPressed: () async {
                      if (await confirmDialog(context, 'ลบประกาศ', 'ต้องการลบ "${a['title']}" หรือไม่?', ok: 'ลบ') && context.mounted) {
                        if (await runAction(context, () => context.api.deleteAnnouncement('${a['id']}'), success: 'ลบแล้ว')) await reload();
                      }
                    },
                    icon: const Icon(Icons.delete_outline, color: LottoColors.negative),
                  ),
                ]),
              ),
            ),
        ]),
      );
}

// ============================================================ REPORTS
Future<void> exportCsv(BuildContext context, String type) async {
  await runAction(context, () async {
    final csv = await context.api.reportCsv(type);
    final name = 'lotto-day-$type-${isoDay(DateTime.now())}.csv';
    if (!await downloadText(name, csv) && context.mounted) {
      await showDialog<void>(
          context: context,
          builder: (c) => AlertDialog(title: Text(name), content: SizedBox(width: 600, child: SingleChildScrollView(child: SelectableText(csv)))));
    }
  }, success: 'ส่งออก $type.csv แล้ว');
}

class AdminReportsPage extends StatelessWidget {
  const AdminReportsPage({super.key});
  @override
  Widget build(BuildContext context) => AsyncView<Json>(
        load: () => context.api.reportSummary(),
        builder: (context, r, reload) => PageList(onRefresh: reload, maxWidth: 1100, padding: _pad, children: [
          const SectionTitle('รายงาน / Export'),
          Wrap(spacing: 10, runSpacing: 10, children: [
            for (final t in const [('orders', 'รายการซื้อ'), ('draws', 'งวดและผล'), ('users', 'ผู้ใช้งาน'), ('wallet', 'ธุรกรรมจำลอง'), ('audit', 'Audit log')])
              OutlinedButton.icon(onPressed: () => exportCsv(context, t.$1), icon: const Icon(Icons.download), label: Text('${t.$2} (CSV)')),
          ]),
          const SectionTitle('ยอดขายตามประเภทหวย (DEMO)'),
          Card(
            child: DataTable(columns: const [
              DataColumn(label: Text('ประเภท')),
              DataColumn(label: Text('ใบ'), numeric: true),
              DataColumn(label: Text('ยอด (บาท)'), numeric: true)
            ], rows: [
              for (final x in jsonList(r['salesByMarket']))
                DataRow(cells: [DataCell(Text('${x['marketId']}')), DataCell(Text(money(x['tickets'] as num))), DataCell(Text(money(x['total'] as num)))]),
            ]),
          ),
          const SectionTitle('งวดตามสถานะ'),
          Card(
            child: Wrap(spacing: 10, runSpacing: 10, children: [
              for (final x in jsonList(r['drawsByStatus']))
                Padding(padding: const EdgeInsets.all(10), child: Chip(label: Text('${drawStatusTh[x['status']] ?? x['status']}: ${x['count']}'))),
            ]),
          ),
          const SectionTitle('ธุรกรรมจำลองตามประเภท'),
          Card(
            child: DataTable(columns: const [
              DataColumn(label: Text('ประเภท')),
              DataColumn(label: Text('จำนวน'), numeric: true),
              DataColumn(label: Text('รวม (บาท)'), numeric: true)
            ], rows: [
              for (final x in jsonList(r['walletByType']))
                DataRow(
                    cells: [DataCell(Text(txTypeTh[x['type']] ?? '${x['type']}')), DataCell(Text('${x['count']}')), DataCell(Text(money(x['sum'] as num)))]),
            ]),
          ),
        ]),
      );
}

// ============================================================ ACCESS (RBAC)
class AdminAccessPage extends StatelessWidget {
  const AdminAccessPage({super.key});
  @override
  Widget build(BuildContext context) => AsyncView<Json>(
        load: () => context.api.roles(),
        builder: (context, r, reload) {
          final perms = (r['permissions'] as List).map((e) => '$e').toList();
          final roles = jsonList(r['roles']);
          return PageList(maxWidth: 1300, padding: _pad, children: [
            SectionTitle('สิทธิ์ผู้ใช้งาน (Role-Based Access Control)',
                trailing: context.session.can('users.view')
                    ? OutlinedButton.icon(
                        onPressed: () => context.go('/admin/users'), icon: const Icon(Icons.manage_accounts), label: const Text('กำหนดบทบาทผู้ใช้'))
                    : null),
            const Text('สิทธิ์ถูกบังคับใช้ที่ API ทุก endpoint • ผู้บันทึกผลกับผู้อนุมัติผลหวยภายนอกต้องเป็นคนละคน • การเปลี่ยนบทบาทต้องมีสิทธิ์ roles.manage'),
            const SizedBox(height: 12),
            Card(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columnSpacing: 18,
                  columns: [const DataColumn(label: Text('สิทธิ์')), for (final role in roles) DataColumn(label: Text('${role['label']}'))],
                  rows: [
                    for (final p in perms)
                      DataRow(cells: [
                        DataCell(Text(p)),
                        for (final role in roles)
                          DataCell((role['permissions'] as List).contains(p)
                              ? const Icon(Icons.check_circle, color: LottoColors.positive, semanticLabel: 'มีสิทธิ์')
                              : const Icon(Icons.remove, color: LottoColors.border, semanticLabel: 'ไม่มีสิทธิ์')),
                      ]),
                  ],
                ),
              ),
            ),
          ]);
        },
      );
}

// ============================================================ SETTINGS
class AdminSettingsPage extends StatelessWidget {
  const AdminSettingsPage({super.key});
  static const locked = ['LIVE_PURCHASE_ENABLED', 'PAYMENT_ENABLED', 'PRIZE_SETTLEMENT_ENABLED', 'OFFICIAL_FEED_ENABLED'];

  @override
  Widget build(BuildContext context) => AsyncView<Json>(
        load: () => context.api.settings(),
        builder: (context, s, reload) {
          final siteName = TextEditingController(text: '${s['siteName']}');
          final phone = TextEditingController(text: '${s['supportPhone']}');
          final email = TextEditingController(text: '${s['supportEmail']}');
          final maxTickets = TextEditingController(text: '${s['maxTicketsPerOrder']}');
          final maxTopup = TextEditingController(text: '${s['maxDemoTopup']}');
          Future<void> save(Json values) async {
            if (await runAction(context, () => context.api.updateSettings(values), success: 'บันทึกการตั้งค่าแล้ว')) await reload();
          }

          return PageList(maxWidth: 900, padding: _pad, children: [
            const SectionTitle('ตั้งค่าระบบ'),
            Card(
              child: Column(children: [
                const ListTile(
                    leading: Icon(Icons.science, color: LottoColors.positive),
                    title: Text('DEMO_MODE'),
                    subtitle: Text('เปิดถาวรในเวอร์ชันนี้'),
                    trailing: Text('TRUE', style: TextStyle(fontWeight: FontWeight.w900))),
                for (final f in locked)
                  ListTile(
                    leading: const Icon(Icons.lock, color: LottoColors.negative),
                    title: Text(f),
                    subtitle: const Text('ล็อกปิด — ต้องได้รับอนุญาตทางกฎหมายและผู้ให้บริการก่อน'),
                    trailing: Switch(value: s[f] == true, onChanged: null),
                  ),
              ]),
            ),
            const SectionTitle('ทั่วไป'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(children: [
                  TextField(controller: siteName, decoration: const InputDecoration(labelText: 'ชื่อระบบ')),
                  const SizedBox(height: 10),
                  TextField(controller: phone, decoration: const InputDecoration(labelText: 'เบอร์ติดต่อ')),
                  const SizedBox(height: 10),
                  TextField(controller: email, decoration: const InputDecoration(labelText: 'อีเมลติดต่อ')),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                        child: TextField(
                            controller: maxTickets, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'สลากสูงสุดต่อรายการ'))),
                    const SizedBox(width: 10),
                    Expanded(
                        child: TextField(
                            controller: maxTopup,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'เติมเครดิตจำลองสูงสุด/ครั้ง'))),
                  ]),
                  SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: s['registrationOpen'] == true,
                      onChanged: (v) => save({'registrationOpen': v}),
                      title: const Text('เปิดรับสมัครสมาชิก')),
                  SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: s['maintenanceMode'] == true,
                      onChanged: (v) => save({'maintenanceMode': v}),
                      title: const Text('โหมดปิดปรับปรุง (ปิดการยืนยันรายการ)')),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => save({
                        'siteName': siteName.text.trim(),
                        'supportPhone': phone.text.trim(),
                        'supportEmail': email.text.trim(),
                        'maxTicketsPerOrder': int.tryParse(maxTickets.text) ?? 20,
                        'maxDemoTopup': int.tryParse(maxTopup.text) ?? 10000,
                      }),
                      child: const Text('บันทึกการตั้งค่า'),
                    ),
                  ),
                ]),
              ),
            ),
          ]);
        },
      );
}

// ============================================================ AUDIT LOG
class AdminAuditPage extends StatefulWidget {
  const AdminAuditPage({super.key});
  @override
  State<AdminAuditPage> createState() => _AdminAuditPageState();
}

class _AdminAuditPageState extends State<AdminAuditPage> {
  String? _entity;
  String _actor = '';
  String _action = '';
  Json? _verify;

  @override
  Widget build(BuildContext context) => AsyncView<List<Json>>(
        key: ValueKey('$_entity|$_actor|$_action'),
        load: () => context.api.audit(entityType: _entity, actor: _actor, action: _action.isEmpty ? null : _action.toUpperCase()),
        builder: (context, items, reload) => PageList(onRefresh: reload, maxWidth: 1200, padding: _pad, children: [
          SectionTitle('Log / Audit',
              trailing: Wrap(spacing: 8, children: [
                OutlinedButton.icon(
                  onPressed: () async {
                    Json? v;
                    if (await runAction(context, () async => v = await context.api.verifyAudit())) setState(() => _verify = v);
                  },
                  icon: const Icon(Icons.verified_user_outlined),
                  label: const Text('ตรวจความถูกต้อง (hash chain)'),
                ),
                OutlinedButton.icon(onPressed: () => exportCsv(context, 'audit'), icon: const Icon(Icons.download), label: const Text('CSV')),
              ])),
          if (_verify != null)
            Card(
              color: _verify!['ok'] == true ? const Color(0xFFE8F8F0) : const Color(0xFFFDE8EC),
              child: ListTile(
                leading:
                    Icon(_verify!['ok'] == true ? Icons.verified : Icons.gpp_bad, color: _verify!['ok'] == true ? LottoColors.positive : LottoColors.negative),
                title: Text(_verify!['ok'] == true ? 'Audit chain ถูกต้อง (${_verify!['checked']} รายการ)' : 'พบการแก้ไขข้อมูลที่ seq ${_verify!['brokenAt']}'),
              ),
            ),
          Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
            DropdownButton<String?>(
              value: _entity,
              hint: const Text('ทุกประเภท'),
              items: const [
                DropdownMenuItem(value: null, child: Text('ทุกประเภท')),
                DropdownMenuItem(value: 'draw', child: Text('งวด/ผล')),
                DropdownMenuItem(value: 'market', child: Text('ประเภทหวย')),
                DropdownMenuItem(value: 'user', child: Text('ผู้ใช้')),
                DropdownMenuItem(value: 'order', child: Text('รายการ')),
                DropdownMenuItem(value: 'wallet', child: Text('กระเป๋า')),
                DropdownMenuItem(value: 'settings', child: Text('ตั้งค่า')),
                DropdownMenuItem(value: 'announcement', child: Text('ประกาศ')),
              ],
              onChanged: (v) => setState(() => _entity = v),
            ),
            SizedBox(
                width: 220,
                child: TextField(decoration: const InputDecoration(hintText: 'ผู้กระทำ (อีเมล)'), onSubmitted: (v) => setState(() => _actor = v.trim()))),
            SizedBox(
                width: 200,
                child: TextField(decoration: const InputDecoration(hintText: 'Action เช่น PUBLISH'), onSubmitted: (v) => setState(() => _action = v.trim()))),
          ]),
          const SizedBox(height: 10),
          if (items.isEmpty) const EmptyState('ไม่พบบันทึก'),
          for (final e in items)
            Card(
              child: ExpansionTile(
                leading: const Icon(Icons.security, color: LottoColors.primary),
                title: Text('#${e['seq']} ${e['action']} • ${e['entityType']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('${e['actor']} • ${thaiDateTime(e['timestamp'])}${e['ip'] != null ? ' • ${e['ip']}' : ''}'),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText('entity: ${e['entityId']}\nbefore: ${e['before']}\nafter: ${e['after']}\nhash: ${e['hash']}',
                      style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
                ],
              ),
            ),
        ]),
      );
}
