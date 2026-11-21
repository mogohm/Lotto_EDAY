import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lotto_day_blue/core/api/api_client.dart';
import 'package:lotto_day_blue/core/api/lotto_api.dart';
import 'package:lotto_day_blue/core/session.dart';
import 'package:lotto_day_blue/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

const allPerms = [
  'dashboard.view',
  'users.view',
  'users.manage',
  'roles.manage',
  'markets.manage',
  'draws.manage',
  'results.edit',
  'results.review',
  'results.publish',
  'catalog.manage',
  'orders.view',
  'orders.manage',
  'announcements.manage',
  'reports.view',
  'settings.manage',
  'audit.view',
];

Map<String, dynamic> userJson({String role = 'USER', List<String> perms = const []}) => {
      'id': role == 'USER' ? 'u1' : 'a1',
      'email': role == 'USER' ? 'user@lottoday.demo' : 'admin@lottoday.demo',
      'displayName': role == 'USER' ? 'สมชาย ใจดี' : 'ผู้ดูแล',
      'phone': '0812341234',
      'role': role,
      'status': 'ACTIVE',
      'kycStatus': 'VERIFIED',
      'demoBalance': 1240,
      'permissions': perms,
    };

final dailyMarket = {
  'id': 'daily',
  'nameTh': 'หวยรายวัน (DEMO)',
  'kind': 'DAILY',
  'source': 'INTERNAL_DEMO',
  'enabled': true,
  'allowedDigits': [2, 3, 4],
  'allowedPositions': ['front', 'back', 'top', 'bottom'],
  'openTime': '06:00',
  'closeTime': '15:30',
  'resultTime': '16:00',
  'drawWeekdays': [0, 1, 2, 3, 4, 5, 6],
  'ticketPrice': 80,
  'version': 1,
  'description': '',
};
final thaiMarket = {...dailyMarket, 'id': 'thai', 'nameTh': 'หวยไทย', 'kind': 'THAI', 'source': 'EXTERNAL_UNVERIFIED', 'drawWeekdays': <int>[]};
final laoMarket = {...thaiMarket, 'id': 'lao', 'nameTh': 'หวยลาว', 'kind': 'LAO'};
final vnMarket = {...thaiMarket, 'id': 'vietnam', 'nameTh': 'หวยเวียดนาม', 'kind': 'VIETNAM'};

const fullResults = {
  '2:front': '12',
  '2:back': '34',
  '2:top': '56',
  '2:bottom': '07',
  '3:front': '789',
  '3:back': '012',
  '3:top': '345',
  '3:bottom': '678',
  '4:front': '0001',
  '4:back': '1234',
  '4:top': '5678',
  '4:bottom': '9012',
};

/// In-memory fake of the REST API used by widget tests. Records every request.
class FakeBackend {
  FakeBackend({this.role = 'USER'});
  String role;
  final requests = <http.Request>[];
  final Map<String, dynamic> draw = {
    'id': 'd1',
    'marketId': 'daily',
    'drawDate': '2026-11-21',
    'status': 'SCHEDULED',
    'salesState': 'OPEN',
    'results': <String, String>{},
    'version': 1,
    'opensAt': '2026-11-20T08:30:00.000Z',
    'closesAt': '2026-11-21T08:30:00.000Z',
    'sourceNote': '',
    'sourceVerified': false,
    'market': dailyMarket,
  };
  int cartCount = 0;

  List<String> get perms => role == 'USER' ? const [] : allPerms;

  http.Response json(Object body, [int status = 200]) =>
      http.Response.bytes(utf8.encode(jsonEncode(body)), status, headers: {'content-type': 'application/json; charset=utf-8'});

  Future<http.Response> handle(http.Request r) async {
    requests.add(r);
    final p = r.url.path.replaceFirst('/api/v1', '');
    final m = r.method;
    final body = r.body.isEmpty ? <String, dynamic>{} : jsonDecode(r.body) as Map<String, dynamic>;
    if (p == '/auth/login') {
      if (body['password'] == 'bad') return json({'statusCode': 401, 'message': 'อีเมลหรือรหัสผ่านไม่ถูกต้อง'}, 401);
      return json({'accessToken': 'tok', 'user': userJson(role: role, perms: perms)});
    }
    if (r.headers['Authorization'] != 'Bearer tok' && !p.startsWith('/lottery') && !p.startsWith('/catalog') && p != '/announcements' && p != '/config') {
      return json({'statusCode': 401, 'message': 'กรุณาเข้าสู่ระบบ'}, 401);
    }
    switch ((m, p)) {
      case ('GET', '/auth/me'):
        return json(userJson(role: role, perms: perms));
      case ('GET', '/config'):
        return json({
          'supportPhone': '02-000-0000',
          'supportEmail': 's@x',
          'flags': {'DEMO_MODE': true, 'PAYMENT_ENABLED': false}
        });
      case ('GET', '/me/summary'):
        return json({
          'displayName': 'สมชาย ใจดี',
          'kycStatus': 'VERIFIED',
          'balance': 1240,
          'unread': 2,
          'ticketCount': 4,
          'nextDraw': {
            'id': 'd1',
            'marketName': 'หวยรายวัน (DEMO)',
            'drawDate': '2026-11-21',
            'closesAt': '2026-11-21T08:30:00.000Z',
            'salesState': 'OPEN',
            'available': 80
          },
          'latestResults': [
            {'id': 'p1', 'marketName': 'หวยรายวัน (DEMO)', 'drawDate': '2026-11-20', 'results': fullResults}
          ],
        });
      case ('GET', '/announcements'):
        return json([
          {'id': 'n1', 'title': 'ยินดีต้อนรับ', 'body': 'ระบบสาธิต', 'category': 'SYSTEM', 'pinned': true, 'publishedAt': '2026-11-20T00:00:00Z'}
        ]);
      case ('GET', '/cart'):
        return json({'items': [], 'count': cartCount, 'total': cartCount * 80, 'balance': 1240});
      case ('POST', '/cart'):
        cartCount++;
        return json({'items': [], 'count': cartCount, 'total': cartCount * 80, 'balance': 1240}, 201);
      case ('GET', '/catalog/draws'):
        return json([
          {
            'id': 'd1',
            'marketId': 'daily',
            'marketName': 'หวยรายวัน (DEMO)',
            'drawDate': '2026-11-21',
            'closesAt': '2026-11-21T08:30:00.000Z',
            'salesState': 'OPEN',
            'available': 2,
            'price': 80
          }
        ]);
      case ('GET', '/catalog/tickets'):
        return json({
          'total': 2,
          'page': 1,
          'pageSize': 20,
          'items': [
            for (final n in ['123456', '000789'])
              {
                'id': 't$n',
                'number': n,
                'price': 80,
                'status': 'AVAILABLE',
                'drawId': 'd1',
                'drawDate': '2026-11-21',
                'marketName': 'หวยรายวัน (DEMO)',
                'salesState': 'OPEN'
              },
          ]
        });
      case ('GET', '/lottery/markets'):
        return json([dailyMarket, laoMarket, vnMarket, thaiMarket]);
      case ('GET', '/lottery/published'):
        final mk = r.url.queryParameters['marketId'];
        if (mk != 'daily') return json([]);
        return json([
          {
            'id': 'p1',
            'marketId': 'daily',
            'drawDate': '2026-11-20',
            'status': 'PUBLISHED',
            'results': fullResults,
            'publishedAt': '2026-11-20T09:00:00Z',
            'sourceVerified': false
          }
        ]);
      case ('GET', '/lottery/check'):
        return json({
          'number': r.url.queryParameters['number'],
          'matches': [
            {'key': '2:bottom', 'value': '07', 'label': 'เลขล่าง 2 ตัว'}
          ],
          'disclaimer': 'DEMO เท่านั้น'
        });
      case ('GET', '/admin/dashboard'):
        return json({
          'kpi': {
            'demoSalesTotal': 1245600,
            'orders': 15320,
            'users': 28450,
            'usersToday': 3210,
            'awaitingReview': 2,
            'approved': 0,
            'ticketsAvailable': 300,
            'ticketsSold': 20,
            'pendingWithdrawals': 1
          },
          'daily': [
            for (var i = 1; i <= 14; i++) {'day': '2026-11-${i.toString().padLeft(2, '0')}', 'total': i * 1000, 'count': i}
          ],
          'recentOrders': [],
        });
      case ('GET', '/admin/lottery/markets'):
        return json([dailyMarket, laoMarket, vnMarket, thaiMarket]);
      case ('GET', '/admin/lottery/draws/d1'):
        return json(draw);
      case ('GET', '/admin/audit'):
        return json([]);
      case ('PATCH', '/admin/lottery/draws/d1/draft'):
        draw['results'] = body['results'];
        draw['status'] = 'DRAFT';
        draw['version'] = (draw['version'] as int) + 1;
        return json(draw);
      case ('POST', '/admin/lottery/draws/d1/generate-demo'):
        draw['results'] = fullResults;
        draw['status'] = 'DRAFT';
        draw['version'] = (draw['version'] as int) + 1;
        return json(draw);
      case ('POST', '/admin/lottery/draws/d1/submit'):
        draw['status'] = 'AWAITING_REVIEW';
        return json(draw);
    }
    return json({'statusCode': 404, 'message': 'not found $m $p'}, 404);
  }

  MockClient get client => MockClient(handle);
}

/// Pumps the full app wired to [backend], optionally already signed in.
Future<Session> pumpApp(WidgetTester tester, FakeBackend backend, {bool loggedIn = true, Size size = const Size(1280, 900)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(loggedIn ? {'lotto_day_token': 'tok'} : {});
  final session = Session(LottoApi(ApiClient(baseUrl: 'http://test/api/v1', client: backend.client)));
  await session.restore();
  await tester.pumpWidget(LottoDayApp(session: session));
  await tester.pumpAndSettle();
  return session;
}

Future<void> goTo(WidgetTester tester, String path) async {
  final router = tester.widget<MaterialApp>(find.byType(MaterialApp)).routerConfig! as GoRouter;
  router.go(path);
  await tester.pumpAndSettle();
}
