import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nep_storefront/core/network/api_client.dart';
import 'package:nep_storefront/core/network/session_tokens.dart';
import 'package:nep_storefront/data/remote_admin.dart';
import 'remote_session_test.dart' show jsonResponse;

void main() {
  test('admin list keeps disabled variants and server pagination', () async {
    final api = ApiClient(
      baseUrl: 'http://localhost/api/v1',
      tokens: SessionTokens()
        ..set(accessToken: 'admin', refreshToken: 'refresh'),
      client: MockClient((r) async {
        expect(r.headers['authorization'], 'Bearer admin');
        expect(r.url.queryParameters, {'page': '2', 'limit': '20'});
        return jsonResponse({
          'items': [
            {
              'id': 'p',
              'variants': [
                {'id': 'v', 'active': false, 'price': '99999999999999'},
              ],
            },
          ],
          'total': 21,
          'page': 2,
          'limit': 20,
        });
      }),
    );
    final result = await AdminRepository(api).list('products', 2);
    expect(result.total, 21);
    expect(result.hasNext, false);
    expect(result.items.single['variants'][0]['active'], false);
    expect(result.items.single['variants'][0]['price'], '99999999999999');
    api.close();
  });
  test(
    'stock and order writes carry observed versions and are never retried on conflict',
    () async {
      final requests = <http.Request>[];
      final api = ApiClient(
        baseUrl: 'http://localhost/api/v1',
        client: MockClient((r) async {
          requests.add(r);
          return jsonResponse({
            'error': {'code': 'VERSION_CONFLICT', 'message': 'Changed'},
          }, 409);
        }),
      );
      final repo = AdminRepository(api);
      await expectLater(
        repo.adjust('inv', delta: -2, version: 7, reason: 'Stock count'),
        throwsA(isA<ApiException>()),
      );
      expect(jsonDecode(requests.single.body), {
        'delta': -2,
        'expectedVersion': 7,
        'reason': 'Stock count',
      });
      await expectLater(
        repo.status('order', status: 'CONFIRMED', version: 4),
        throwsA(isA<ApiException>()),
      );
      expect(requests.length, 2);
      expect(requests.last.method, 'PATCH');
      expect(jsonDecode(requests.last.body), {
        'status': 'CONFIRMED',
        'expectedVersion': 4,
      });
      api.close();
    },
  );
  test(
    'late admin response and retained repository cannot cross sessions',
    () async {
      final pending = Completer<http.Response>();
      final started = Completer<void>();
      final tokens = SessionTokens()
        ..set(accessToken: 'admin', refreshToken: 'r');
      var requests = 0;
      final api = ApiClient(
        baseUrl: 'http://localhost/api/v1',
        tokens: tokens,
        client: MockClient((r) {
          requests++;
          started.complete();
          return pending.future;
        }),
      );
      final repo = AdminRepository(api);
      final result = repo.summary();
      final rejected = expectLater(
        result,
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'SESSION_CHANGED'),
        ),
      );
      await started.future;
      tokens.clear();
      tokens.set(accessToken: 'customer', refreshToken: 'r2');
      pending.complete(jsonResponse({'products': 3}));
      await rejected;
      await expectLater(repo.summary(), throwsA(isA<ApiException>()));
      expect(requests, 1);
      api.close();
    },
  );
}
