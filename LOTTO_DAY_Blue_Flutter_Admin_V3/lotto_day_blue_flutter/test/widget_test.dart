import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_backend.dart';

void main() {
  testWidgets('anonymous visitor lands on welcome, logs in and sees wallet home', (tester) async {
    final backend = FakeBackend();
    await pumpApp(tester, backend, loggedIn: false, size: const Size(390, 844));
    // protected route → login page (with return path), demo accounts listed
    expect(find.byKey(const Key('login-email')), findsOneWidget);
    expect(find.text('บัญชีทดลอง (DEMO)'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('login-email')), 'user@lottoday.demo');
    await tester.enterText(find.byKey(const Key('login-password')), 'bad');
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pumpAndSettle();
    expect(find.text('อีเมลหรือรหัสผ่านไม่ถูกต้อง'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('login-password')), 'User@1234');
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pumpAndSettle();
    expect(find.text('คุณสมชาย ใจดี'), findsOneWidget);
    expect(find.text('ซื้อสลากเลย'), findsOneWidget);
    expect(find.text('1,240'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget, reason: 'mobile layout uses bottom navigation');
  });

  testWidgets('desktop layout uses navigation rail', (tester) async {
    await pumpApp(tester, FakeBackend(), size: const Size(1400, 900));
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('catalog lists tickets with leading zeros and adds to cart', (tester) async {
    final backend = FakeBackend();
    final session = await pumpApp(tester, backend);
    await tester.tap(find.text('ซื้อสลาก').first);
    await tester.pumpAndSettle();
    expect(find.text('000789'), findsOneWidget);
    await tester.tap(find.byTooltip('เพิ่มในตะกร้า').first);
    await tester.pumpAndSettle();
    expect(session.cartCount, 1);
    expect(find.text('ตะกร้า (1 ใบ)'), findsOneWidget);
    expect(backend.requests.where((r) => r.method == 'POST' && r.url.path.endsWith('/cart')), hasLength(1));
  });

  testWidgets('results page shows published daily result and checks a number', (tester) async {
    await pumpApp(tester, FakeBackend());
    await tester.tap(find.text('ตรวจผล').first);
    await tester.pumpAndSettle();
    expect(find.text('5678'), findsWidgets);
    await tester.enterText(find.byKey(const Key('check-number')), '123407');
    await tester.tap(find.byKey(const Key('check-submit')));
    await tester.pumpAndSettle();
    expect(find.textContaining('ตรงกับ 1 ตำแหน่ง'), findsOneWidget);
    // External markets without verified results show the waiting state
    await tester.tap(find.text('หวยไทย'));
    await tester.pumpAndSettle();
    expect(find.textContaining('ยังไม่มีผลที่ผ่านการตรวจสอบแหล่งประกาศ'), findsOneWidget);
  });

  testWidgets('members are redirected away from admin', (tester) async {
    await pumpApp(tester, FakeBackend());
    expect(find.byTooltip('หลังบ้าน'), findsNothing);
    await goTo(tester, '/admin/settings');
    expect(find.text('ภาพรวมระบบ'), findsNothing);
    expect(find.text('คุณสมชาย ใจดี'), findsOneWidget);
  });

  testWidgets('welcome page offers login and registration', (tester) async {
    await pumpApp(tester, FakeBackend(), loggedIn: false, size: const Size(390, 844));
    await goTo(tester, '/welcome');
    expect(find.text('เข้าสู่ระบบ'), findsOneWidget);
    await tester.tap(find.text('สมัครสมาชิก'));
    await tester.pumpAndSettle();
    expect(find.text('ยอมรับเงื่อนไขและนโยบายความเป็นส่วนตัว (ระบบสาธิต ไม่มีธุรกรรมเงินจริง)'), findsOneWidget);
  });

  testWidgets('admin dashboard shows KPI and permission-filtered menu', (tester) async {
    await pumpApp(tester, FakeBackend(role: 'SUPER_ADMIN'));
    await goTo(tester, '/admin');
    expect(find.text('ภาพรวมระบบ'), findsOneWidget);
    expect(find.text('1,245,600 บาท'), findsOneWidget);
    expect(find.text('หวย 4 ประเภท'), findsOneWidget);
    expect(find.text('Log / Audit'), findsWidgets);
  });

  testWidgets('result editor validates digits, generates demo results and submits for review', (tester) async {
    final backend = FakeBackend(role: 'SUPER_ADMIN');
    final session = await pumpApp(tester, backend, size: const Size(1400, 1600));
    expect(session.isStaff, isTrue);
    await goTo(tester, '/admin/lottery/result/d1');
    expect(find.text('บันทึกผล • หวยรายวัน (DEMO)'), findsOneWidget);
    expect(find.byKey(const Key('result-4-front')), findsOneWidget);
    // input formatter blocks letters and over-length input
    await tester.enterText(find.byKey(const Key('result-3-top')), '12a45');
    expect(tester.widget<TextField>(find.byKey(const Key('result-3-top'))).controller!.text, '124');
    // partial number is rejected client-side before calling the API
    await tester.enterText(find.byKey(const Key('result-3-top')), '12');
    await tester.tap(find.byKey(const Key('save-draft')));
    await tester.pumpAndSettle();
    expect(find.textContaining('ต้องเป็นตัวเลข 3 หลัก'), findsOneWidget);
    expect(backend.requests.where((r) => r.method == 'PATCH'), isEmpty);
    await tester.tap(find.byKey(const Key('generate-demo')));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byKey(const Key('result-4-front'))).controller!.text, '0001');
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pumpAndSettle();
    expect(backend.draw['status'], 'AWAITING_REVIEW');
  });
}
