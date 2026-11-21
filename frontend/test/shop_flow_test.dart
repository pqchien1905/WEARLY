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
import 'package:nep_storefront/core/widgets/product_card.dart';
import 'package:nep_storefront/data/remote_catalog.dart';
import 'package:nep_storefront/features/catalog/catalog_page.dart';
import 'remote_catalog_test.dart' show productJson;

Future<GoRouter> mountShop(
  WidgetTester tester,
  String initial,
  Future<http.Response> Function(http.Request) products,
) async {
  tester.view.physicalSize = const Size(1440, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final api = ApiClient(
    baseUrl: 'http://localhost/api/v1',
    client: MockClient((r) async {
      if (r.url.path.endsWith('/categories')) {
        return json([
          {'slug': 'giay', 'name': 'Giày'},
        ]);
      }
      if (r.url.path.endsWith('/facets')) {
        return json({
          'colors': ['Đen'],
          'sizes': ['37'],
          'styles': ['Tối giản'],
        });
      }
      return products(r);
    }),
  );
  final router = GoRouter(
    initialLocation: initial,
    routes: [
      GoRoute(
        path: '/shop',
        builder: (_, state) => Scaffold(
          body: SingleChildScrollView(child: CatalogPage(uri: state.uri)),
        ),
      ),
    ],
  );
  addTearDown(api.close);
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        remoteApiProvider.overrideWithValue(true),
        apiClientProvider.overrideWithValue(api),
      ],
      child: MaterialApp.router(theme: buildTheme(), routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

http.Response json(Object data, [int status = 200]) => http.Response(
  jsonEncode(data),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  testWidgets(
    'inline search and clearing preserve filters and reset pagination',
    (tester) async {
      final requests = <Map<String, String>>[];
      final router = await mountShop(
        tester,
        '/shop?category=giay&page=2&sort=price-asc',
        (r) async {
          requests.add(r.url.queryParameters);
          return json({
            'items': [productJson()],
            'total': 30,
          });
        },
      );
      final field = find.widgetWithText(TextField, 'Tìm trong cửa hàng');
      await tester.enterText(field, '  ao so mi do  ');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(requests.last, containsPair('q', 'ao so mi do'));
      expect(requests.last, containsPair('page', '1'));
      expect(router.routeInformationProvider.value.uri.queryParameters, {
        'category': 'giay',
        'sort': 'price-asc',
        'q': 'ao so mi do',
      });
      await tester.tap(find.byTooltip('Xóa từ khóa'));
      await tester.pumpAndSettle();
      expect(requests.last.containsKey('q'), false);
      expect(router.routeInformationProvider.value.uri.queryParameters, {
        'category': 'giay',
        'sort': 'price-asc',
      });
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('an outdated page returns to page one without losing filters', (
    tester,
  ) async {
    final router = await mountShop(
      tester,
      '/shop?size=37&page=999',
      (r) async => json({
        'items': r.url.queryParameters['page'] == '1' ? [productJson()] : [],
        'total': 30,
      }),
    );
    expect(find.text('Trang này không còn sản phẩm'), findsOneWidget);
    await tester.ensureVisible(find.text('Về trang đầu'));
    await tester.tap(find.text('Về trang đầu'));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.queryParameters, {
      'size': '37',
    });
    expect(find.text('Trang này không còn sản phẩm'), findsNothing);
    expect(find.text('Áo cotton'), findsOneWidget);
  });
  testWidgets('API failure shows retry and never substitutes demo products', (
    tester,
  ) async {
    var unavailable = true;
    await mountShop(
      tester,
      '/shop',
      (r) async => unavailable
          ? json({
              'error': {'code': 'UNAVAILABLE'},
            }, 503)
          : json({
              'items': [productJson()],
              'total': 1,
            }),
    );
    expect(find.text('Không tải được sản phẩm'), findsOneWidget);
    expect(find.byType(ProductCard), findsNothing);
    unavailable = false;
    await tester.ensureVisible(find.text('Thử lại'));
    await tester.tap(find.text('Thử lại'));
    await tester.pumpAndSettle();
    expect(find.byType(ProductCard), findsOneWidget);
  });
  testWidgets(
    'sold out cards cannot quick add and disclose variant price differences',
    (tester) async {
      final p = RemoteProductRepository.productFromJson(productJson());
      final product = p.copyWith(
        variants: [
          p.variants.first.copyWith(stock: 0),
          p.variants.first.copyWith(stock: 0, price: 590000),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: buildTheme(),
            home: Scaffold(
              body: SizedBox(width: 240, child: ProductCard(product)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Hết hàng'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is IconButton &&
                    widget.tooltip == 'Chọn size Áo cotton',
              ),
            )
            .onPressed,
        isNull,
      );
      expect(find.textContaining('Từ '), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
