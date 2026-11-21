import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lotto_day_blue/app/router.dart';
import 'package:lotto_day_blue/core/api/api_client.dart';
import 'package:lotto_day_blue/core/api/lotto_api.dart';
import 'package:lotto_day_blue/core/api/models.dart';
import 'package:lotto_day_blue/core/format.dart';
import 'package:lotto_day_blue/core/session.dart';

void main() {
  group('ApiClient', () {
    test('sends bearer token + JSON and decodes UTF-8 Thai', () async {
      late http.Request seen;
      final c = ApiClient(
          baseUrl: 'http://x/api/v1/',
          client: MockClient((r) async {
            seen = r;
            return http.Response.bytes(utf8.encode('{"name":"หวยไทย"}'), 200);
          }))
        ..token = 'abc';
      final r = await c.post('/lottery/admin/draws', {'a': 1});
      expect(seen.url.toString(), 'http://x/api/v1/lottery/admin/draws');
      expect(seen.headers['Authorization'], 'Bearer abc');
      expect(jsonDecode(seen.body), {'a': 1});
      expect(r['name'], 'หวยไทย');
    });

    test('maps API errors (string + list messages) and 401 callback', () async {
      var unauthorized = 0;
      final c = ApiClient(
          baseUrl: 'http://x',
          client: MockClient((r) async {
            if (r.url.path == '/a') return http.Response('{"message":"stale version"}', 409);
            if (r.url.path == '/b') return http.Response('{"message":["e1","e2"]}', 400);
            return http.Response('{}', 401);
          }))
        ..onUnauthorized = () => unauthorized++;
      await expectLater(
          c.get('/a'), throwsA(isA<ApiException>().having((e) => e.isConflict, 'conflict', true).having((e) => e.message, 'msg', 'stale version')));
      await expectLater(c.get('/b'), throwsA(isA<ApiException>().having((e) => e.message, 'msg', 'e1\ne2')));
      await expectLater(c.get('/c'), throwsA(isA<ApiException>().having((e) => e.isUnauthorized, '401', true)));
      expect(unauthorized, 1);
    });

    test('network failure becomes status 0 with Thai message', () async {
      final c = ApiClient(baseUrl: 'http://x', client: MockClient((r) async => throw http.ClientException('down')));
      await expectLater(c.get('/a'), throwsA(isA<ApiException>().having((e) => e.status, 'status', 0)));
    });

    test('query params skip null/empty values', () {
      final c = ApiClient(baseUrl: 'http://x/api/v1');
      expect(c.uri('/t', {'a': null, 'b': '', 'c': 2}).toString(), 'http://x/api/v1/t?c=2');
    });
  });

  group('models', () {
    test('market keys respect configured digits/positions in display order', () {
      final m = Market({
        'id': 'x',
        'allowedDigits': [4, 2],
        'allowedPositions': ['bottom', 'top']
      });
      expect(m.digits, [2, 4]);
      expect(m.positions, ['top', 'bottom']);
      expect(m.keys, ['2:top', '2:bottom', '4:top', '4:bottom']);
    });
    test('validNumber keeps leading zeros and exact length', () {
      expect(validNumber('007', 3), isTrue);
      expect(validNumber('07', 3), isFalse);
      expect(validNumber('0a7', 3), isFalse);
    });
    test('draw lock state', () {
      expect(Draw({'status': 'PUBLISHED'}).isLocked, isTrue);
      expect(Draw({'status': 'DRAFT'}).isEditable, isTrue);
      expect(Draw({'status': 'AWAITING_REVIEW'}).isEditable, isFalse);
    });
  });

  group('format', () {
    test('Thai Buddhist-era dates', () {
      expect(thaiDate('2025-01-16'), '16 มกราคม 2568');
      expect(thaiDate('2025-01-16', short: true), '16 ม.ค. 68');
      expect(thaiDateTime('2025-01-14T07:00:00.000Z'), '14 ม.ค. 68 14:00 น.');
    });
    test('money and phone masking', () {
      expect(money(1245600), '1,245,600');
      expect(money(-80), '-80');
      expect(maskPhone('0812341234'), '081-xxx-1234');
    });
  });

  group('route guard', () {
    Session session({String? role}) {
      final s = Session(LottoApi(ApiClient(baseUrl: 'http://x', client: MockClient((_) async => http.Response('{}', 200)))));
      s.restoring = false;
      if (role != null) {
        s.user = AppUser({
          'id': '1',
          'email': 'e',
          'role': role,
          'permissions': role == 'AUDITOR' ? ['dashboard.view', 'audit.view'] : <String>[]
        });
      }
      return s;
    }

    test('anonymous users are sent to login with return path', () {
      expect(guard(session(), '/app/home'), '/auth/login?from=%2Fapp%2Fhome');
      expect(guard(session(), '/auth/login'), isNull);
    });
    test('members cannot open admin', () {
      expect(guard(session(role: 'USER'), '/admin'), '/app/home');
      expect(guard(session(role: 'USER'), '/app/cart'), isNull);
    });
    test('staff are limited per module permission', () {
      final s = session(role: 'AUDITOR');
      expect(guard(s, '/admin/audit'), isNull);
      expect(guard(s, '/admin/settings'), '/admin');
      expect(guard(s, '/admin/users'), '/admin');
    });
    test('splash waits for restore then forwards', () {
      final s = session(role: 'USER');
      s.restoring = true;
      expect(resolveRedirect(s, Uri.parse('/app/cart')), startsWith('/splash'));
      s.restoring = false;
      expect(resolveRedirect(s, Uri.parse('/splash?from=%2Fapp%2Fcart')), '/app/cart');
    });
  });
}
