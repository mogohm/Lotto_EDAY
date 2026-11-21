// End-to-end: real Flutter app ↔ real NestJS API ↔ real PostgreSQL.
// Run (backend must be running with seed data):
//   flutter drive --driver=test_driver/integration_test.dart --target=integration_test/app_test.dart \
//     -d chrome --web-port 8080 --dart-define=API_BASE_URL=http://localhost:3000/api/v1
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lotto_day_blue/core/api/api_client.dart';
import 'package:lotto_day_blue/core/api/lotto_api.dart';
import 'package:lotto_day_blue/core/session.dart';
import 'package:lotto_day_blue/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

const staffPassword = String.fromEnvironment('STAFF_PASSWORD', defaultValue: 'Admin@1234');

Future<void> settle(WidgetTester tester, {Duration max = const Duration(seconds: 15)}) async {
  // Real network: pump until idle or timeout.
  final end = DateTime.now().add(max);
  await tester.pump(const Duration(milliseconds: 200));
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (!tester.binding.hasScheduledFrame && find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
  }
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> waitFor(WidgetTester tester, Finder f, {Duration max = const Duration(seconds: 20)}) async {
  final end = DateTime.now().add(max);
  while (f.evaluate().isEmpty && DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 250));
  }
  expect(f, findsWidgets);
}

GoRouter router(WidgetTester tester) => tester.widget<MaterialApp>(find.byType(MaterialApp)).routerConfig! as GoRouter;

Future<void> login(WidgetTester tester, String email, String password) async {
  router(tester).go('/auth/login');
  await waitFor(tester, find.byKey(const Key('login-email')));
  await tester.enterText(find.byKey(const Key('login-email')), email);
  await tester.enterText(find.byKey(const Key('login-password')), password);
  await tester.tap(find.byKey(const Key('login-submit')));
  await settle(tester);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('member buys a demo ticket; editor + reviewer publish a daily result', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final session = Session(LottoApi(ApiClient()));
    await session.restore();
    await tester.pumpWidget(LottoDayApp(session: session));
    await settle(tester);

    // ---------- member flow
    await login(tester, 'user@lottoday.demo', 'User@1234');
    await waitFor(tester, find.text('ซื้อสลากเลย'));
    final balanceBefore = session.user!.demoBalance;
    router(tester).go('/app/catalog');
    await waitFor(tester, find.byTooltip('เพิ่มในตะกร้า'));
    await tester.tap(find.byTooltip('เพิ่มในตะกร้า').first);
    await settle(tester);
    expect(session.cartCount, greaterThanOrEqualTo(1));
    router(tester).go('/app/cart');
    await waitFor(tester, find.byKey(const Key('checkout')));
    await tester.tap(find.byKey(const Key('checkout')));
    await settle(tester);
    await tester.tap(find.text('ยืนยัน'));
    await settle(tester);
    await waitFor(tester, find.text('ยืนยันรายการสำเร็จ'));
    expect(session.cartCount, 0);
    expect(session.user!.demoBalance, lessThan(balanceBefore));
    await session.logout();
    await settle(tester);

    // ---------- setup: a fresh daily draw for the workflow (created through the API as the editor)
    final setup = LottoApi(ApiClient());
    final auth = await setup.login('editor@lottoday.demo', staffPassword);
    setup.client.token = auth['accessToken'] as String;
    final day = DateTime.utc(2040).add(Duration(days: Random().nextInt(3000)));
    final draw = await setup.createDraw('daily', '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}');

    // ---------- editor: generate DEMO result + submit via UI
    await login(tester, 'editor@lottoday.demo', staffPassword);
    router(tester).go('/admin/lottery/result/${draw.id}');
    await waitFor(tester, find.byKey(const Key('generate-demo')));
    await tester.tap(find.byKey(const Key('generate-demo')));
    await settle(tester);
    await waitFor(tester, find.byKey(const Key('submit')));
    await tester.tap(find.byKey(const Key('submit')));
    await settle(tester);
    expect((await setup.adminDraw(draw.id)).status, 'AWAITING_REVIEW');
    await session.logout();
    await settle(tester);

    // ---------- reviewer: approve + publish via UI
    await login(tester, 'reviewer@lottoday.demo', staffPassword);
    router(tester).go('/admin/lottery/result/${draw.id}');
    await waitFor(tester, find.byKey(const Key('approve')));
    await tester.tap(find.byKey(const Key('approve')));
    await settle(tester);
    await tester.tap(find.text('ตกลง'));
    await settle(tester);
    await waitFor(tester, find.byKey(const Key('publish')));
    await tester.tap(find.byKey(const Key('publish')));
    await settle(tester);
    await tester.tap(find.text('เผยแพร่'));
    await settle(tester);
    final published = await setup.adminDraw(draw.id);
    expect(published.status, 'PUBLISHED');
    expect(published.results.length, 12);
    expect(published.approvedBy, 'reviewer@lottoday.demo');

    // published result is visible publicly and the draw is locked in the UI
    expect((await setup.published(marketId: 'daily')).any((d) => d.id == draw.id), isTrue);
    expect(find.byKey(const Key('save-draft')), findsNothing);
  });
}
