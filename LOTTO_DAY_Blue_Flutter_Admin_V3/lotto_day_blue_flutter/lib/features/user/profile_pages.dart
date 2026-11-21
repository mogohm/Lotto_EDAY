import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/models.dart';
import '../../core/format.dart';
import '../../core/session.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/ui.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});
  @override
  Widget build(BuildContext context) {
    final session = AppScope.of(context);
    final u = session.user;
    if (u == null) return const SizedBox.shrink();
    Widget item(IconData icon, String title, String? sub, VoidCallback onTap) => ListTile(
          leading: Icon(icon, color: LottoColors.primary),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: sub == null ? null : Text(sub),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        );
    return PageList(maxWidth: 720, children: [
      const SectionTitle('โปรไฟล์'),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            CircleAvatar(
                radius: 32,
                backgroundColor: LottoColors.surface,
                child: Text(u.displayName.characters.first, style: const TextStyle(fontSize: 26, color: LottoColors.primary, fontWeight: FontWeight.w900))),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(u.displayName, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: LottoColors.navy)),
                Text(maskPhone(u.phone)),
                Text(u.email, style: const TextStyle(fontSize: 12, color: Color(0xFF4A6380))),
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  StatusChip(kycTh[u.kycStatus] ?? u.kycStatus,
                      color: u.kycStatus == 'VERIFIED' ? LottoColors.positive : const Color(0xFFB7791F), icon: Icons.verified_user),
                  if (u.isStaff) StatusChip(roleTh[u.role] ?? u.role, icon: Icons.badge_outlined),
                ]),
              ]),
            ),
          ]),
        ),
      ),
      Card(
        child: Column(children: [
          item(Icons.person_outline, 'ข้อมูลส่วนตัว', 'ชื่อ เบอร์โทร', () => context.go('/app/profile/edit')),
          const Divider(height: 1),
          item(Icons.lock_outline, 'ความปลอดภัย', 'ตั้งรหัสผ่าน / ออกจากระบบทุกอุปกรณ์', () => context.go('/app/profile/security')),
          const Divider(height: 1),
          item(Icons.account_balance_wallet_outlined, 'กระเป๋าเครดิตจำลอง', 'คงเหลือ ${baht(u.demoBalance)}', () => context.go('/app/wallet')),
          const Divider(height: 1),
          item(Icons.notifications_none, 'การแจ้งเตือน', session.unread > 0 ? 'ยังไม่อ่าน ${session.unread} รายการ' : null,
              () => context.go('/app/notifications')),
          const Divider(height: 1),
          item(Icons.support_agent, 'ช่วยเหลือ / ติดต่อเรา', null, () => context.go('/app/help')),
          const Divider(height: 1),
          item(Icons.info_outline, 'เกี่ยวกับแอป', null, () => context.go('/app/about')),
          if (u.isStaff) ...[
            const Divider(height: 1),
            item(Icons.admin_panel_settings_outlined, 'หน้าจัดการหลังบ้าน', roleTh[u.role], () => context.go('/admin'))
          ],
        ]),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        key: const Key('logout'),
        onPressed: () async {
          await session.logout();
          if (context.mounted) context.go('/auth/login');
        },
        icon: const Icon(Icons.logout, color: LottoColors.negative),
        label: const Text('ออกจากระบบ', style: TextStyle(color: LottoColors.negative)),
      ),
      const SizedBox(height: 12),
      const DemoBanner(),
    ]);
  }
}

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});
  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: context.session.user?.displayName);
  late final _phone = TextEditingController(text: context.session.user?.phone);

  @override
  Widget build(BuildContext context) => PageList(maxWidth: 600, children: [
        SectionTitle('ข้อมูลส่วนตัว',
            trailing: TextButton.icon(onPressed: () => context.go('/app/profile'), icon: const Icon(Icons.arrow_back), label: const Text('กลับ'))),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _form,
              child: Column(children: [
                TextFormField(
                    controller: _name,
                    decoration: const InputDecoration(labelText: 'ชื่อที่แสดง'),
                    validator: (v) => (v == null || v.trim().length < 2) ? 'อย่างน้อย 2 ตัวอักษร' : null),
                const SizedBox(height: 12),
                TextFormField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'เบอร์โทร'),
                    validator: (v) => (v != null && v.isNotEmpty && !RegExp(r'^0\d{8,9}$').hasMatch(v)) ? 'เบอร์โทรไม่ถูกต้อง' : null),
                const SizedBox(height: 12),
                TextFormField(initialValue: context.session.user?.email, enabled: false, decoration: const InputDecoration(labelText: 'อีเมล (แก้ไขไม่ได้)')),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () async {
                      if (!_form.currentState!.validate()) return;
                      final ok = await runAction(context, () async {
                        await context.api.updateProfile(displayName: _name.text.trim(), phone: _phone.text.trim());
                        if (context.mounted) await context.session.reloadUser();
                      }, success: 'บันทึกข้อมูลแล้ว');
                      if (ok && context.mounted) context.go('/app/profile');
                    },
                    child: const Text('บันทึก'),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ]);
}

class SecurityPage extends StatefulWidget {
  const SecurityPage({super.key});
  @override
  State<SecurityPage> createState() => _SecurityPageState();
}

class _SecurityPageState extends State<SecurityPage> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();

  @override
  Widget build(BuildContext context) => PageList(maxWidth: 600, children: [
        SectionTitle('ความปลอดภัย',
            trailing: TextButton.icon(onPressed: () => context.go('/app/profile'), icon: const Icon(Icons.arrow_back), label: const Text('กลับ'))),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _form,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text('เปลี่ยนรหัสผ่าน', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 12),
                TextFormField(
                    controller: _current,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'รหัสผ่านปัจจุบัน'),
                    validator: (v) => (v == null || v.isEmpty) ? 'จำเป็น' : null),
                const SizedBox(height: 12),
                TextFormField(
                    controller: _next,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'รหัสผ่านใหม่', helperText: '8 ตัวขึ้นไป มีทั้งตัวอักษรและตัวเลข'),
                    validator: (v) => (v == null || !RegExp(r'^(?=.*[A-Za-z])(?=.*\d).{8,72}$').hasMatch(v)) ? 'รหัสผ่านไม่ปลอดภัยพอ' : null),
                const SizedBox(height: 12),
                TextFormField(
                    controller: _confirm,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'ยืนยันรหัสผ่านใหม่'),
                    validator: (v) => v != _next.text ? 'ไม่ตรงกัน' : null),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () async {
                    if (!_form.currentState!.validate()) return;
                    final ok = await runAction(context, () => context.session.changePassword(_current.text, _next.text),
                        success: 'เปลี่ยนรหัสผ่านแล้ว (อุปกรณ์อื่นถูกออกจากระบบ)');
                    if (ok) {
                      _current.clear();
                      _next.clear();
                      _confirm.clear();
                    }
                  },
                  child: const Text('เปลี่ยนรหัสผ่าน'),
                ),
              ]),
            ),
          ),
        ),
        const Card(
          child: ListTile(
            leading: Icon(Icons.phonelink_lock, color: LottoColors.primary),
            title: Text('การยืนยันตัวตน 2 ขั้นตอน (2FA / OTP)'),
            subtitle: Text('ยังไม่เปิดให้บริการในระบบสาธิต — ต้องเชื่อมต่อผู้ให้บริการ OTP ที่ได้รับอนุญาต'),
          ),
        ),
      ]);
}

class NotificationsPage extends StatelessWidget {
  const NotificationsPage({super.key});
  @override
  Widget build(BuildContext context) => AsyncView<List<Json>>(
        load: () => context.api.notifications(),
        builder: (context, items, reload) => PageList(onRefresh: reload, maxWidth: 760, children: [
          SectionTitle('การแจ้งเตือน',
              trailing: TextButton(
                onPressed: items.any((n) => n['read'] != true)
                    ? () => runAction(context, () async {
                          await context.api.markAllRead();
                          if (context.mounted) await context.session.refreshCounters();
                          await reload();
                        })
                    : null,
                child: const Text('อ่านทั้งหมด'),
              )),
          if (items.isEmpty) const EmptyState('ไม่มีการแจ้งเตือน', icon: Icons.notifications_off_outlined),
          for (final n in items)
            Card(
              color: n['read'] == true ? Colors.white : LottoColors.surface,
              child: ListTile(
                leading: Icon(n['read'] == true ? Icons.notifications_none : Icons.notifications_active, color: LottoColors.primary),
                title: Text('${n['title']}', style: TextStyle(fontWeight: n['read'] == true ? FontWeight.w500 : FontWeight.w800)),
                subtitle: Text('${n['body']}\n${thaiDateTime(n['createdAt'])}'),
                isThreeLine: true,
                onTap: () async {
                  if (n['read'] != true) {
                    await context.api.markRead('${n['id']}');
                    if (context.mounted) await context.session.refreshCounters();
                  }
                  if (context.mounted && n['link'] != null) {
                    context.go('${n['link']}');
                  } else {
                    await reload();
                  }
                },
              ),
            ),
        ]),
      );
}

class NewsPage extends StatelessWidget {
  const NewsPage({super.key});
  @override
  Widget build(BuildContext context) => AsyncView<List<Json>>(
        load: () => context.api.announcements(),
        builder: (context, items, reload) => PageList(onRefresh: reload, maxWidth: 760, children: [
          const SectionTitle('ข่าวสารและประกาศ'),
          if (items.isEmpty) const EmptyState('ยังไม่มีประกาศ'),
          for (final n in items)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    if (n['pinned'] == true)
                      const Padding(padding: EdgeInsets.only(right: 6), child: Icon(Icons.push_pin, size: 18, color: LottoColors.accent)),
                    Expanded(child: Text('${n['title']}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: LottoColors.navy))),
                    StatusChip('${n['category']}', icon: Icons.label_outline),
                  ]),
                  const SizedBox(height: 8),
                  Text('${n['body']}'),
                  const SizedBox(height: 8),
                  Text(thaiDateTime(n['publishedAt']), style: const TextStyle(fontSize: 12, color: Color(0xFF4A6380))),
                ]),
              ),
            ),
        ]),
      );
}

class HelpPage extends StatelessWidget {
  const HelpPage({super.key});
  @override
  Widget build(BuildContext context) => AsyncView<Json>(
        load: () => context.api.config(),
        builder: (context, c, _) => PageList(maxWidth: 720, children: [
          SectionTitle('ช่วยเหลือ / ติดต่อเรา',
              trailing: TextButton.icon(onPressed: () => context.go('/app/profile'), icon: const Icon(Icons.arrow_back), label: const Text('กลับ'))),
          Card(
            child: Column(children: [
              ListTile(leading: const Icon(Icons.phone, color: LottoColors.primary), title: const Text('โทรศัพท์'), subtitle: Text('${c['supportPhone']}')),
              const Divider(height: 1),
              ListTile(
                  leading: const Icon(Icons.email_outlined, color: LottoColors.primary), title: const Text('อีเมล'), subtitle: Text('${c['supportEmail']}')),
            ]),
          ),
          const SectionTitle('คำถามที่พบบ่อย'),
          const Card(
            child: Column(children: [
              ExpansionTile(
                  title: Text('ซื้อสลากแล้วตัดเงินจริงไหม?'),
                  children: [Padding(padding: EdgeInsets.all(16), child: Text('ไม่ ระบบนี้เป็นระบบสาธิต ใช้เครดิตจำลองที่ไม่สามารถแลกเป็นเงินจริงได้'))]),
              ExpansionTile(title: Text('ผลหวยลาว/เวียดนาม/ไทย มาจากไหน?'), children: [
                Padding(padding: EdgeInsets.all(16), child: Text('ผู้ดูแลบันทึกผลพร้อมแหล่งอ้างอิง และต้องผ่านการตรวจสอบโดยผู้ตรวจอีกคนก่อนเผยแพร่'))
              ]),
              ExpansionTile(
                  title: Text('หวยรายวันคืออะไร?'),
                  children: [Padding(padding: EdgeInsets.all(16), child: Text('ผลจำลองที่ผู้ดูแลกำหนดหรือสุ่ม (DEMO) เพื่อทดสอบระบบเท่านั้น'))]),
            ]),
          ),
        ]),
      );
}

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});
  @override
  Widget build(BuildContext context) => PageList(maxWidth: 720, children: [
        SectionTitle('เกี่ยวกับแอป',
            trailing: TextButton.icon(onPressed: () => context.go('/app/profile'), icon: const Icon(Icons.arrow_back), label: const Text('กลับ'))),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('LOTTO DAY V3 (DEMO)', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: LottoColors.navy)),
              SizedBox(height: 8),
              Text('แอปสาธิตการจัดการงวดและผลหวย 4 ประเภท พร้อมร้านค้าสลากจำลอง สร้างด้วย Flutter Web + NestJS + PostgreSQL'),
              SizedBox(height: 8),
              Text('ไม่ใช่แอปทางการของหน่วยงานใด ไม่มีการรับแทง ไม่มีการชำระเงินหรือจ่ายรางวัลจริง ผลหวยภายนอกต้องตรวจสอบกับแหล่งประกาศอย่างเป็นทางการเสมอ'),
            ]),
          ),
        ),
      ]);
}
