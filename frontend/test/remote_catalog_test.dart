import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nep_storefront/core/network/api_client.dart';
import 'package:nep_storefront/core/network/session_tokens.dart';
import 'package:nep_storefront/data/remote_catalog.dart';
import 'package:nep_storefront/domain/catalog.dart';

Map<String, Object?> productJson() => {
  'id': 'product-id',
  'slug': 'nep-1',
  'name': 'Áo cotton',
  'categoryId': 'ao',
  'description': 'Mô tả',
  'material': 'Cotton',
  'style': 'Tối giản',
  'active': true,
  'tryOnSupported': true,
  'images': [
    {'url': 'assets/images/shirt.jpg', 'alt': 'Áo trắng', 'color': 'Trắng'},
  ],
  'variants': [
    {
      'sku': 'WRL-1-MAIN-M',
      'size': 'M',
      'color': 'Trắng',
      'colorHex': '#E8E7E2',
      'price': {'amount': '490000', 'currency': 'VND'},
      'available': 12,
    },
  ],
};
void main() {
  test(
    'public catalog reads do not send tokens or refresh a private session',
    () async {
      final tokens = SessionTokens()
        ..set(accessToken: 'private-access', refreshToken: 'private-refresh');
      final paths = <String>[], authorizations = <String?>[];
      final api = ApiClient(
        baseUrl: 'http://localhost/api/v1',
        tokens: tokens,
        client: MockClient((request) async {
          paths.add(request.url.path);
          authorizations.add(request.headers['authorization']);
          return http.Response('{}', 401);
        }),
      );
      final repo = RemoteProductRepository(api);
      await expectLater(
        repo.list(const ProductQuery()),
        throwsA(isA<ApiException>()),
      );
      expect(paths, ['/api/v1/products']);
      expect(authorizations, [null]);
      expect(tokens.accessToken, 'private-access');
      api.close();
    },
  );
  test('maps exact VND, images, variants and existing query filters', () async {
    final repo = RemoteProductRepository(
      ApiClient(
        baseUrl: 'http://localhost:3000/api/v1',
        client: MockClient((req) async {
          expect(req.url.path, '/api/v1/products');
          expect(req.url.queryParameters['maxPrice'], '500000');
          expect(req.url.queryParameters['inStock'], 'true');
          expect(req.url.queryParameters['size'], 'M');
          return http.Response(
            jsonEncode({
              'items': [productJson()],
              'total': 1,
              'page': 1,
              'limit': 12,
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      ),
    );
    final page = await repo.list(
      const ProductQuery(size: 'M', maxPrice: 500000, inStock: true),
    );
    expect(page.total, 1);
    expect(page.items.single.name, 'Áo cotton');
    expect(page.items.single.variants.single.price, 490000);
    expect(page.items.single.variants.single.colorHex, 0xFFE8E7E2);
    expect(page.items.single.media.single.label, 'Áo trắng');
  });
  test(
    'gets facets independently of pagination and returns null for missing product',
    () async {
      final repo = RemoteProductRepository(
        ApiClient(
          baseUrl: 'http://localhost:3000/api/v1',
          client: MockClient(
            (req) async => req.url.path.endsWith('/facets')
                ? http.Response('{"colors":["Black"]}', 200)
                : http.Response('{"error":{"code":"NOT_FOUND"}}', 404),
          ),
        ),
      );
      expect(await repo.availableColors(), ['Black']);
      expect(await repo.bySlug('missing'), isNull);
    },
  );
  test(
    'clears ephemeral tokens on unauthorized without persisting secrets',
    () async {
      final tokens = SessionTokens()
        ..set(accessToken: 'sample-access', refreshToken: 'sample-refresh');
      final client = ApiClient(
        baseUrl: 'http://localhost:3000/api/v1',
        tokens: tokens,
        client: MockClient((req) async {
          if (!req.url.path.endsWith('/auth/refresh')) {
            expect(req.headers['authorization'], 'Bearer sample-access');
          }
          return http.Response('{"error":{"code":"AUTH_REQUIRED"}}', 401);
        }),
      );
      await expectLater(
        client.get('users/me'),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'AUTH_REQUIRED'),
        ),
      );
      expect(tokens.accessToken, isNull);
      expect(tokens.refreshToken, isNull);
    },
  );
  test(
    'maps validation, timeout and connection errors to actionable exceptions',
    () async {
      for (final status in [400, 429, 503]) {
        final client = ApiClient(
          baseUrl: 'http://localhost:3000/api/v1',
          client: MockClient(
            (_) async => http.Response(
              '{"error":{"code":"TEST","message":["bad field"]}}',
              status,
            ),
          ),
        );
        await expectLater(
          client.get('products'),
          throwsA(
            isA<ApiException>().having((e) => e.status, 'status', status),
          ),
        );
      }
      final timeout = ApiClient(
        baseUrl: 'http://localhost:3000/api/v1',
        timeout: const Duration(milliseconds: 1),
        client: MockClient((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return http.Response('{}', 200);
        }),
      );
      await expectLater(
        timeout.get('products'),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'TIMEOUT')),
      );
      final offline = ApiClient(
        baseUrl: 'http://localhost:3000/api/v1',
        client: MockClient((_) async => throw http.ClientException('offline')),
      );
      await expectLater(
        offline.get('products'),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'CONNECTION_ERROR'),
        ),
      );
    },
  );
  test('rejects fractional or non-VND prices instead of rounding', () async {
    final data = productJson();
    final variants = data['variants'] as List;
    (variants.first as Map)['price'] = {'amount': '1.5', 'currency': 'VND'};
    final repo = RemoteProductRepository(
      ApiClient(
        baseUrl: 'http://localhost:3000/api/v1',
        client: MockClient((_) async => http.Response(jsonEncode(data), 200)),
      ),
    );
    await expectLater(repo.bySlug('nep-1'), throwsA(isA<ApiException>()));
  });
  test(
    'does not turn remote stock writes into simulated checkout success',
    () async {
      final repo = RemoteProductRepository(
        ApiClient(
          baseUrl: 'http://localhost:3000/api/v1',
          client: MockClient(
            (_) async => throw StateError('No request expected'),
          ),
        ),
      );
      await expectLater(
        repo.consumeStock({'sku': 1}, expectedPrices: {'sku': 1}),
        throwsA(isA<UnsupportedError>()),
      );
    },
  );
}
