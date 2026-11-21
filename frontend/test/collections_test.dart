import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nep_storefront/app/api_providers.dart';
import 'package:nep_storefront/core/design/tokens.dart';
import 'package:nep_storefront/core/network/api_client.dart';
import 'package:nep_storefront/core/network/session_tokens.dart';
import 'package:nep_storefront/data/remote_collections.dart';
import 'package:nep_storefront/features/info/collection_page.dart';
import 'remote_catalog_test.dart' show productJson;

Map<String, Object?> collectionJson({String slug = 'custom-style'}) => {
  'id': 'collection-id-$slug',
  'slug': slug,
  'title': 'Bộ sưu tập $slug',
  'description': 'Các thiết kế hiện có.',
  'style': 'Tối giản',
  'productCount': 13,
  'cover': {
    'url': 'assets/images/shirt.jpg',
    'alt': 'Áo từ danh mục',
    'productId': 'product-id',
  },
};
Map<String, Object?> detailJson({int page = 1, int total = 13}) => {
  'collection': collectionJson(),
  'items': [productJson()],
  'total': total,
  'page': page,
  'limit': 12,
};
http.Response response(Object data, [int status = 200]) => http.Response(
  jsonEncode(data),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  test(
    'collections are public API reads with bounded pagination and supported filters',
    () async {
      final tokens = SessionTokens()
        ..set(accessToken: 'private', refreshToken: 'refresh');
      final api = ApiClient(
        baseUrl: 'http://localhost/api/v1',
        tokens: tokens,
        client: MockClient((r) async {
          expect(r.headers['authorization'], isNull);
          if (r.url.path.endsWith('/collections')) {
            expect(r.url.queryParameters, {'page': '1', 'limit': '12'});
            return response({
              'items': [collectionJson()],
              'total': 1,
              'page': 1,
              'limit': 12,
            });
          }
          expect(r.url.path, '/api/v1/collections/custom-style');
          expect(r.url.queryParameters, {
            'page': '10000',
            'limit': '12',
            'sort': 'newest',
            'inStock': 'true',
          });
          return response(detailJson(page: 10000));
        }),
      );
      addTearDown(api.close);
      final repo = CollectionsRepository(api);
      expect((await repo.list('page=-1')).items.single.slug, 'custom-style');
      expect(
        (await repo.detail(
          '/collections/custom-style?page=99999&sort=invalid&stock=true&style=other',
        ))!.collection.productCount,
        13,
      );
      expect(tokens.accessToken, 'private');
    },
  );
  test(
    'only 404 becomes not-found, while malformed and unavailable data stay errors',
    () async {
      var status = 404;
      final api = ApiClient(
        baseUrl: 'http://localhost/api/v1',
        client: MockClient((r) async => response({}, status)),
      );
      addTearDown(api.close);
      final repo = CollectionsRepository(api);
      expect(await repo.detail('/collections/missing'), isNull);
      status = 503;
      await expectLater(
        repo.detail('/collections/missing'),
        throwsA(isA<ApiException>()),
      );
      status = 200;
      await expectLater(
        repo.detail('/collections/missing'),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'INVALID_RESPONSE'),
        ),
      );
      await expectLater(repo.list(''), throwsA(isA<ApiException>()));
    },
  );
  Future<GoRouter> mount(
    WidgetTester tester,
    String location,
    Future<http.Response> Function(http.Request) handler,
  ) async {
    final api = ApiClient(
      baseUrl: 'http://localhost/api/v1',
      client: MockClient(handler),
    );
    final router = GoRouter(
      initialLocation: location,
      routes: [
        GoRoute(
          path: '/collections',
          builder: (_, s) => Scaffold(
            body: SingleChildScrollView(child: CollectionPage(uri: s.uri)),
          ),
        ),
        GoRoute(
          path: '/collections/:slug',
          builder: (_, s) => Scaffold(
            body: SingleChildScrollView(
              child: CollectionPage(slug: s.pathParameters['slug'], uri: s.uri),
            ),
          ),
        ),
      ],
    );
    addTearDown(api.close);
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [apiClientProvider.overrideWithValue(api)],
        child: MaterialApp.router(theme: buildTheme(), routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    return router;
  }

  for (final width in [375.0, 1440.0]) {
    testWidgets(
      'database collection cards render arbitrary slugs at $width px',
      (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final router = await mount(
          tester,
          '/collections',
          (r) async => r.url.path.endsWith('/collections')
              ? response({
                  'items': [collectionJson()],
                  'total': 1,
                  'page': 1,
                  'limit': 12,
                })
              : response(detailJson(total: 1)),
        );
        expect(find.text('Bộ sưu tập custom-style'), findsOneWidget);
        expect(find.text('Everyday, theo cách bạn.'), findsNothing);
        await tester.ensureVisible(find.text('Khám phá tối giản'));
        await tester.tap(find.text('Khám phá tối giản'));
        await tester.pumpAndSettle();
        expect(
          router.routeInformationProvider.value.uri.path,
          '/collections/custom-style',
        );
        expect(find.text('Áo cotton'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'failure retries real data and an empty catalog shows no fixture collections',
    (tester) async {
      var reads = 0;
      await mount(
        tester,
        '/collections',
        (r) async => ++reads == 1
            ? response({}, 503)
            : response({'items': [], 'total': 0, 'page': 1, 'limit': 12}),
      );
      expect(find.text('Chưa tải được bộ sưu tập'), findsOneWidget);
      await tester.ensureVisible(find.text('Thử lại'));
      await tester.tap(find.text('Thử lại'));
      await tester.pumpAndSettle();
      expect(reads, 2);
      expect(find.text('Bộ sưu tập đang được cập nhật'), findsOneWidget);
      expect(find.text('Everyday, theo cách bạn.'), findsNothing);
    },
  );
  testWidgets(
    'page navigation preserves filters and changing stock resets page',
    (tester) async {
      final router = await mount(
        tester,
        '/collections/custom-style?sort=price-asc&stock=true',
        (r) async => response(
          detailJson(page: int.parse(r.url.queryParameters['page']!)),
        ),
      );
      await tester.ensureVisible(find.text('Trang sau'));
      await tester.tap(find.text('Trang sau'));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.queryParameters, {
        'sort': 'price-asc',
        'stock': 'true',
        'page': '2',
      });
      expect(find.text('Trang 2 / 2'), findsOneWidget);
      await tester.ensureVisible(find.text('Chỉ hàng còn sẵn'));
      await tester.tap(find.text('Chỉ hàng còn sẵn'));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.queryParameters, {
        'sort': 'price-asc',
      });
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'missing collections and out-of-range pages give a recovery path',
    (tester) async {
      final router = await mount(tester, '/collections/missing', (r) async {
        if (r.url.path.endsWith('missing')) return response({}, 404);
        final page = int.parse(r.url.queryParameters['page']!);
        return response({...detailJson(page: page), if (page > 2) 'items': []});
      });
      expect(find.text('Chưa tìm thấy bộ sưu tập'), findsOneWidget);
      router.go('/collections/custom-style?page=999&stock=true');
      await tester.pumpAndSettle();
      expect(find.text('Trang này không còn sản phẩm'), findsOneWidget);
      await tester.ensureVisible(find.text('Về trang đầu'));
      await tester.tap(find.text('Về trang đầu'));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.queryParameters, {
        'stock': 'true',
      });
      expect(find.text('Áo cotton'), findsOneWidget);
    },
  );
}
