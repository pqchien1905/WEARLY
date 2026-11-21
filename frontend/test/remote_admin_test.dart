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
  test(
    'editor references include empty categories from every private page',
    () async {
      final paths = <String>[];
      final api = ApiClient(
        baseUrl: 'http://localhost/api/v1',
        tokens: SessionTokens()
          ..set(accessToken: 'admin', refreshToken: 'refresh'),
        client: MockClient((r) async {
          paths.add(r.url.path);
          expect(r.url.path, startsWith('/api/v1/admin/'));
          expect(r.headers['authorization'], 'Bearer admin');
          final page = int.parse(r.url.queryParameters['page']!);
          return jsonResponse({
            'items': [
              {'id': '${r.url.path}-$page', 'name': 'New empty category'},
            ],
            'total': r.url.path.endsWith('/categories') ? 101 : 1,
            'page': page,
            'limit': 100,
          });
        }),
      );
      addTearDown(api.close);
      final references = await AdminRepository(api).references();
      expect((references['categories'] as List).length, 2);
      expect((references['brands'] as List).length, 1);
      expect(paths.length, 3);
    },
  );
  test(
    'late publication completion invalidates public content without replaying the write',
    () async {
      final response = Completer<http.Response>();
      var requests = 0, late = 0;
      final api = ApiClient(
        baseUrl: 'http://localhost/api/v1',
        timeout: const Duration(milliseconds: 5),
        client: MockClient((r) {
          requests++;
          return response.future;
        }),
      );
      final repository = AdminRepository(api);
      await expectLater(
        repository.publishContent(7, onLateCompletion: () => late++),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'TIMEOUT')),
      );
      repository.dispose();
      response.complete(jsonResponse({'version': 8}));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(requests, 1);
      expect(late, 1);
      api.close();
    },
  );
  test('admin list keeps disabled variants and server pagination', () async {
    final api = ApiClient(
      baseUrl: 'http://localhost/api/v1',
      tokens: SessionTokens()
        ..set(accessToken: 'admin', refreshToken: 'refresh'),
      client: MockClient((r) async {
        expect(r.headers['authorization'], 'Bearer admin');
        expect(r.url.queryParameters, {'page': '2', 'limit': '10'});
        return jsonResponse({
          'items': [
            {
              'id': 'p',
              'variants': [
                {'id': 'v', 'active': false, 'price': '99999999999999'},
              ],
            },
          ],
          'total': 11,
          'page': 2,
          'limit': 10,
        });
      }),
    );
    final result = await AdminRepository(api).list('products', 2);
    expect(result.total, 11);
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
