import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_shell.dart';
import '../../core/api/api_client.dart';
import '../../core/session.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/ui.dart';

class _BlueBackground extends StatelessWidget {
  const _BlueBackground({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
                colors: [LottoColors.primary, LottoColors.secondary, LottoColors.surface],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0, 0.45, 1]),
          ),
          child: SafeArea(
              child: Center(
                  child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20), child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 440), child: child)))),
        ),
      );
}

class SplashPage extends StatelessWidget {
  const SplashPage({super.key});
  @override
  Widget build(BuildContext context) => const _BlueBackground(
        child: Column(mainAxisSize: MainAxisSize.min, children: [BrandMark(size: 56), SizedBox(height: 24), CircularProgressIndicator(color: Colors.white)]),
      );
}

class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});
  @override
  Widget build(BuildContext context) => _BlueBackground(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Center(child: BrandMark(size: 64)),
          const SizedBox(height: 18),
          const Text('แอปซื้อสลากออนไลน์\nสะดวก ปลอดภัย ใช้งานได้ทุกที่',
              textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800, height: 1.4)),
          const SizedBox(height: 22),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(children: const [
                _Feature(Icons.verified_user, 'ใช้งานง่าย เหมือนกระเป๋าเงินดิจิทัล'),
                _Feature(Icons.lock_outline, 'ปลอดภัย สิทธิ์ผู้ใช้แยกตามบทบาท และบันทึก Audit'),
                _Feature(Icons.devices, 'รองรับมือถือและเว็บ (Responsive)'),
                _Feature(Icons.bolt, 'ตรวจผลรางวัล 4 ประเภท และแจ้งเตือนทันที'),
                _Feature(Icons.info_outline, 'ระบบสาธิต: ใช้เครดิตจำลอง ไม่มีการชำระเงินจริง'),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: () => context.go('/auth/login'), child: const Text('เข้าสู่ระบบ')),
          const SizedBox(height: 10),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
                backgroundColor: Colors.white, minimumSize: const Size(48, 50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            onPressed: () => context.go('/auth/register'),
            child: const Text('สมัครสมาชิก'),
          ),
        ]),
      );
}

class _Feature extends StatelessWidget {
  const _Feature(this.icon, this.text);
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [Icon(icon, color: LottoColors.primary), const SizedBox(width: 12), Expanded(child: Text(text))]),
      );
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, this.from});
  final String? from;
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  static const demoAccounts = [
    ('สมาชิก (สมชาย)', 'user@lottoday.demo', 'User@1234'),
    ('ผู้ดูแลสูงสุด', 'superadmin@lottoday.demo', null),
    ('ผู้บันทึกผล', 'editor@lottoday.demo', null),
    ('ผู้ตรวจสอบ', 'reviewer@lottoday.demo', null),
    ('ผู้ตรวจบัญชี', 'auditor@lottoday.demo', null),
  ];

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final session = context.session;
    try {
      await session.login(_email.text, _password.text);
      if (!mounted) return;
      final from = widget.from;
      context.go(from != null && from.isNotEmpty ? from : (session.isStaff ? '/admin' : '/app/home'));
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _BlueBackground(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Center(child: BrandMark(size: 52)),
          const SizedBox(height: 18),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _form,
                child: AutofillGroup(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const Text('เข้าสู่ระบบ', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: LottoColors.navy)),
                    const SizedBox(height: 16),
                    TextFormField(
                      key: const Key('login-email'),
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(labelText: 'อีเมล', prefixIcon: Icon(Icons.alternate_email)),
                      validator: (v) => (v == null || !v.contains('@')) ? 'กรุณากรอกอีเมลให้ถูกต้อง' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const Key('login-password'),
                      controller: _password,
                      obscureText: _obscure,
                      autofillHints: const [AutofillHints.password],
                      onFieldSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: 'รหัสผ่าน',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                            tooltip: 'แสดงรหัสผ่าน',
                            icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                            onPressed: () => setState(() => _obscure = !_obscure)),
                      ),
                      validator: (v) => (v == null || v.isEmpty) ? 'กรุณากรอกรหัสผ่าน' : null,
                    ),
                    if (_error != null)
                      Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: LottoColors.negative))),
                    const SizedBox(height: 16),
                    FilledButton(
                      key: const Key('login-submit'),
                      onPressed: _busy ? null : _submit,
                      child: _busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)) : const Text('เข้าสู่ระบบ'),
                    ),
                    TextButton(onPressed: () => context.go('/auth/register'), child: const Text('ยังไม่มีบัญชี? สมัครสมาชิก')),
                  ]),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            color: Colors.white.withValues(alpha: 0.95),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('บัญชีทดลอง (DEMO)', style: TextStyle(fontWeight: FontWeight.w800, color: LottoColors.navy)),
                const SizedBox(height: 4),
                const Text('แตะเพื่อกรอกอัตโนมัติ • รหัสผ่านของบัญชีเจ้าหน้าที่ได้รับจากผู้ดูแลระบบ', style: TextStyle(fontSize: 12)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final a in demoAccounts)
                    ActionChip(
                      avatar: const Icon(Icons.person_outline, size: 16),
                      label: Text(a.$1),
                      onPressed: () => setState(() {
                        _email.text = a.$2;
                        _password.text = a.$3 ?? '';
                      }),
                    ),
                ]),
              ]),
            ),
          ),
          const SizedBox(height: 10),
          const DemoBanner(),
        ]),
      );
}

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});
  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _accept = false;
  bool _adult = false;
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    if (!_accept || !_adult) {
      setState(() => _error = 'กรุณายืนยันอายุและยอมรับเงื่อนไขการใช้งาน');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.session.register(email: _email.text, password: _password.text, displayName: _name.text, phone: _phone.text.trim());
      if (mounted) context.go('/app/home');
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _BlueBackground(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _form,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  IconButton(onPressed: () => context.go('/welcome'), icon: const Icon(Icons.arrow_back)),
                  const Expanded(
                      child: Text('สมัครสมาชิก',
                          overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: LottoColors.navy))),
                ]),
                const SizedBox(height: 12),
                TextFormField(
                    controller: _name,
                    decoration: const InputDecoration(labelText: 'ชื่อ-นามสกุล', prefixIcon: Icon(Icons.person_outline)),
                    validator: (v) => (v == null || v.trim().length < 2) ? 'กรุณากรอกชื่อ' : null),
                const SizedBox(height: 12),
                TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'อีเมล', prefixIcon: Icon(Icons.alternate_email)),
                    validator: (v) => (v == null || !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim())) ? 'อีเมลไม่ถูกต้อง' : null),
                const SizedBox(height: 12),
                TextFormField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'เบอร์โทร (ไม่บังคับ)', prefixIcon: Icon(Icons.phone_outlined)),
                    validator: (v) => (v != null && v.isNotEmpty && !RegExp(r'^0\d{8,9}$').hasMatch(v)) ? 'เบอร์โทรไม่ถูกต้อง' : null),
                const SizedBox(height: 12),
                TextFormField(
                    controller: _password,
                    obscureText: true,
                    decoration:
                        const InputDecoration(labelText: 'รหัสผ่าน', helperText: '8 ตัวขึ้นไป มีทั้งตัวอักษรและตัวเลข', prefixIcon: Icon(Icons.lock_outline)),
                    validator: (v) => (v == null || !RegExp(r'^(?=.*[A-Za-z])(?=.*\d).{8,72}$').hasMatch(v)) ? 'รหัสผ่านไม่ปลอดภัยพอ' : null),
                const SizedBox(height: 12),
                TextFormField(
                    controller: _confirm,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'ยืนยันรหัสผ่าน', prefixIcon: Icon(Icons.lock_outline)),
                    validator: (v) => v != _password.text ? 'รหัสผ่านไม่ตรงกัน' : null),
                CheckboxListTile(
                    value: _adult,
                    onChanged: (v) => setState(() => _adult = v ?? false),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('ข้าพเจ้ามีอายุ 20 ปีบริบูรณ์ขึ้นไป')),
                CheckboxListTile(
                    value: _accept,
                    onChanged: (v) => setState(() => _accept = v ?? false),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('ยอมรับเงื่อนไขและนโยบายความเป็นส่วนตัว (ระบบสาธิต ไม่มีธุรกรรมเงินจริง)')),
                if (_error != null)
                  Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(_error!, style: const TextStyle(color: LottoColors.negative))),
                FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)) : const Text('สมัครสมาชิก')),
                TextButton(onPressed: () => context.go('/auth/login'), child: const Text('มีบัญชีแล้ว? เข้าสู่ระบบ')),
              ]),
            ),
          ),
        ),
      );
}
