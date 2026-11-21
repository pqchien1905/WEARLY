import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nep_storefront/app/app.dart';
import 'package:nep_storefront/app/account_state.dart';
import 'package:nep_storefront/app/api_providers.dart';
import 'package:nep_storefront/core/network/api_client.dart';
import 'package:nep_storefront/core/widgets/product_card.dart';
import 'remote_catalog_test.dart' show productJson;
import 'remote_commerce_test.dart' show cartJson;
import 'remote_session_test.dart' show jsonResponse;
import 'separate_sessions_test.dart' show loginJson;

class Fixture {
  bool failRead = false, loseDelete = false, loseAdd = false;
  int deletes = 0, adds = 0, quantity = 0;
  Completer<void>? holdAdd;
  final entries = <Map<String, Object?>>[
    for (var i = 0; i < 13; i++)
      {
        'productId': 'p$i',
        'product': i == 1
            ? null
            : {
                ...productJson(),
                'id': 'p$i',
                'name': i == 12 ? 'Đầm lụa trắng' : 'Áo cotton $i',
                'variants': [
                  {
                    ...(productJson()['variants'] as List).first as Map,
                    'available': i == 2 ? 0 : 12,
                    'price': {
                      'amount': '${490000 + i * 10000}',
                      'currency': 'VND',
                    },
                  },
                ],
              },
      },
  ];
  late ProviderContainer container;
  late GoRouter router;
  Future<void> mount(
    WidgetTester tester, {
    String path = '/wishlist',
    double width = 1440,
    double scale = 1,
  }) async {
    tester.view.physicalSize = Size(width, 1100);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final api = ApiClient(
      baseUrl: 'http://localhost/api/v1',
      client: MockClient((r) async {
        if (r.url.path.endsWith('/login')) {
          return jsonResponse(loginJson('customer'));
        }
        if (r.url.path.endsWith('/logout')) return jsonResponse({});
        if (r.url.path.contains('/wishlist')) {
          if (r.method == 'DELETE') {
            deletes++;
            entries.removeWhere(
              (e) => e['productId'] == r.url.pathSegments.last,
            );
            if (loseDelete) throw http.ClientException('lost response');
          } else if (failRead) {
            return jsonResponse({}, 503);
          }
          return jsonResponse({'items': entries, 'limit': 200});
        }
        if (r.url.path.endsWith('/cart/items')) {
          adds++;
          quantity++;
          if (holdAdd != null) await holdAdd!.future;
          if (loseAdd) throw http.ClientException('lost response');
          return jsonResponse(cartJson(quantity: quantity));
        }
        if (r.url.path.endsWith('/cart')) {
          return jsonResponse(cartJson(quantity: quantity));
        }
        if (r.url.path.endsWith('/orders')) {
          return jsonResponse({
            'items': [],
            'total': 0,
            'page': 1,
            'limit': 100,
          });
        }
        if (r.url.path.endsWith('/products/nep-1')) {
          return jsonResponse(productJson());
        }
        return jsonResponse({});
      }),
    );
    container = ProviderContainer(
      overrides: [
        remoteApiProvider.overrideWithValue(true),
        apiClientProvider.overrideWithValue(api),
        sessionTokensProvider.overrideWithValue(api.tokens),
      ],
    );
    addTearDown(() {
      container.dispose();
      api.close();
    });
    await container
        .read(accountProvider.notifier)
        .signIn('', 'customer@example.com', 'valid-password');
    router = createRouter(initialLocation: path);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: NepApp(router: router),
      ),
    );
    await tester.pumpAndSettle();
  }
}

final search = find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == 'Tìm sản phẩm đã lưu',
);
Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> openAdd(WidgetTester tester) async {
  await tap(tester, find.widgetWithText(OutlinedButton, 'Chọn size').first);
  await tap(tester, find.widgetWithText(OutlinedButton, 'M'));
}

void main() {
  testWidgets(
    'search covers all pages, supports Vietnamese and survives breakpoints and deep links',
    (tester) async {
      final f = Fixture();
      await f.mount(tester);
      await tester.enterText(search, 'dam trang');
      await tester.pumpAndSettle();
      expect(find.text('Đầm lụa trắng'), findsOneWidget);
      expect(find.byType(ProductCard), findsOneWidget);
      expect(
        f.router.routeInformationProvider.value.uri.queryParameters['q'],
        'dam trang',
      );
      tester.view.physicalSize = const Size(375, 1100);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(search).controller!.text, 'dam trang');
      expect(find.byType(ProductCard), findsOneWidget);
      f.router.go('/wishlist?stock=sold_out&sort=price_desc');
      await tester.pumpAndSettle();
      expect(find.text('Áo cotton 2'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Tạm hết hàng'),
            )
            .onPressed,
        isNull,
      );
      await tap(tester, find.text('Đặt lại'));
      expect(
        f.router.routeInformationProvider.value.uri.queryParameters,
        isEmpty,
      );
      expect(find.byType(ProductCard), findsNWidgets(11));
      await tester.enterText(search, 'khong-ton-tai');
      await tester.pumpAndSettle();
      expect(find.text('Chưa tìm thấy món đồ phù hợp'), findsOneWidget);
      expect(find.text('Tủ đồ yêu thích còn trống'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('sorting is stable and missing products retain saved order', (
    tester,
  ) async {
    final f = Fixture();
    await f.mount(tester);
    final row = tester.getTopLeft(find.byKey(const ValueKey('p0'))).dy;
    expect(tester.getTopLeft(find.byKey(const ValueKey('p1'))).dy, row);
    expect(tester.getTopLeft(find.byKey(const ValueKey('p2'))).dy, row);
    f.router.go('/wishlist?sort=price_desc');
    await tester.pumpAndSettle();
    expect(
      tester
          .widgetList<ProductCard>(find.byType(ProductCard))
          .first
          .product
          .name,
      'Đầm lụa trắng',
    );
    f.router.go('/wishlist?stock=available&page=99');
    await tester.pumpAndSettle();
    expect(f.router.routeInformationProvider.value.uri.queryParameters, {
      'stock': 'available',
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'failed refresh keeps products readable and disables stale purchase and removal',
    (tester) async {
      final f = Fixture();
      await f.mount(tester);
      f.failRead = true;
      await tap(tester, find.widgetWithText(TextButton, 'Tải lại'));
      expect(
        find.textContaining('Chưa cập nhật được danh sách.'),
        findsOneWidget,
      );
      expect(find.text('Áo cotton 0'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Chọn size').first,
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (w) =>
                    w is IconButton &&
                    w.tooltip == 'Tải lại yêu thích Áo cotton 0',
              ),
            )
            .onPressed,
        isNull,
      );
      f.failRead = false;
      await tap(tester, find.widgetWithText(TextButton, 'Thử lại'));
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Chọn size').first,
            )
            .onPressed,
        isNotNull,
      );
    },
  );

  testWidgets(
    'lost removal response reconciles once and canonicalizes the last page',
    (tester) async {
      final f = Fixture();
      await f.mount(tester, path: '/wishlist?page=2');
      f.loseDelete = true;
      await tap(tester, find.byTooltip('Bỏ yêu thích Đầm lụa trắng'));
      expect(find.text('Đầm lụa trắng'), findsOneWidget);
      expect(find.textContaining('Chưa xác nhận được thay đổi'), findsWidgets);
      await tap(tester, find.widgetWithText(TextButton, 'Thử lại'));
      expect(find.text('Trang 1 / 1'), findsOneWidget);
      expect(
        f.router.routeInformationProvider.value.uri.queryParameters.containsKey(
          'page',
        ),
        isFalse,
      );
      expect(f.deletes, 1);
    },
  );

  testWidgets(
    'pending quick add locks duplicates and dismissal; lost response checks cart without adding again',
    (tester) async {
      final f = Fixture();
      await f.mount(tester);
      await openAdd(tester);
      expect(find.text('Còn 12 sản phẩm.'), findsOneWidget);
      f.holdAdd = Completer<void>();
      f.loseAdd = true;
      final action = tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Thêm vào giỏ'),
          )
          .onPressed!;
      action();
      action();
      await tester.pump();
      expect(f.adds, 1);
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == 'Đóng chọn nhanh',
              ),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'M'))
            .onPressed,
        isNull,
      );
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.text('Chọn nhanh'), findsOneWidget);
      f.holdAdd!.complete();
      await tester.pumpAndSettle();
      await tap(tester, find.widgetWithText(FilledButton, 'Kiểm tra giỏ hàng'));
      expect(find.text('Giỏ hàng của bạn'), findsOneWidget);
      expect(f.adds, 1);
      expect(f.quantity, 1);
      expect(f.router.routeInformationProvider.value.uri.path, '/wishlist');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('an open quick add sheet cannot add to a changed account', (
    tester,
  ) async {
    final f = Fixture();
    await f.mount(tester);
    await openAdd(tester);
    await f.container.read(accountProvider.notifier).signOut();
    await tester.pumpAndSettle();
    expect(find.text('Phiên tài khoản đã thay đổi'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Thêm vào giỏ'), findsNothing);
    expect(f.adds, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wishlist and quick add fit 320px with 200 percent text', (
    tester,
  ) async {
    final f = Fixture();
    await f.mount(tester, width: 320, scale: 2);
    expect(tester.takeException(), isNull);
    await openAdd(tester);
    expect(find.text('Còn 12 sản phẩm.'), findsOneWidget);
    await tap(tester, find.byTooltip('Đóng chọn nhanh'));
    expect(tester.takeException(), isNull);
  });
}
