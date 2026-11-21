import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nep_storefront/app/account_state.dart';
import 'package:nep_storefront/app/api_providers.dart';
import 'package:nep_storefront/core/design/tokens.dart';
import 'package:nep_storefront/core/network/api_client.dart';
import 'package:nep_storefront/features/account/orders_page.dart';
import 'remote_account_test.dart' show sessionJson;
import 'remote_commerce_test.dart' show orderJson, cartJson;
import 'remote_session_test.dart' show jsonResponse;

Map<String, Object?> row(String id, String status) =>
    orderJson(id: id, status: status)..['code'] = 'WR${id.padLeft(6, '0')}';
http.Response history(List<Object?> items, {int page = 1, int? total}) =>
    jsonResponse({
      'items': items,
      'page': page,
      'total': total ?? items.length,
      'limit': 100,
    });

Future<({ProviderContainer container, GoRouter router})> mountOrders(
  WidgetTester t,
  Future<http.Response> Function(http.Request) handle, {
  String location = '/account/orders',
  double width = 1440,
  double scale = 1,
}) async {
  t.view.devicePixelRatio = 1;
  t.view.physicalSize = Size(width, 1200);
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  final api = ApiClient(
    baseUrl: 'http://localhost/api/v1',
    client: MockClient((r) async {
      if (r.url.path.endsWith('/login')) return jsonResponse(sessionJson());
      if (r.url.path.endsWith('/cart')) {
        return jsonResponse(cartJson(quantity: 0));
      }
      return handle(r);
    }),
  );
  final container = ProviderContainer(
    overrides: [
      remoteApiProvider.overrideWithValue(true),
      apiClientProvider.overrideWithValue(api),
      sessionTokensProvider.overrideWithValue(api.tokens),
    ],
  );
  addTearDown(api.close);
  addTearDown(container.dispose);
  await t.runAsync(
    () => container
        .read(accountProvider.notifier)
        .signIn('', 'an@example.com', 'example-password'),
  );
  final router = GoRouter(
    initialLocation: location,
    routes: [
      GoRoute(
        path: '/account/orders',
        builder: (_, _) =>
            const Scaffold(body: SingleChildScrollView(child: OrdersPage())),
      ),
      GoRoute(
        path: '/account/orders/:id',
        builder: (_, s) => Scaffold(
          body: SingleChildScrollView(
            child: OrdersPage(id: s.pathParameters['id']),
          ),
        ),
      ),
      GoRoute(
        path: '/shop',
        builder: (_, _) => const Scaffold(body: Text('Catalog')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await t.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: buildTheme(),
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
  return (container: container, router: router);
}

Future<void> tap(WidgetTester t, String text, {bool settle = true}) async {
  await t.pump();
  final target = find.text(text).first;
  await t.ensureVisible(target);
  await t.tap(target);
  if (settle) {
    await t.pumpAndSettle();
  } else {
    await t.pump();
  }
}

void main() {
  testWidgets(
    'initial read is deduplicated; accentless search and counts combine',
    (t) async {
      var reads = 0;
      await mountOrders(t, (_) async {
        reads++;
        return history([row('1', 'PENDING'), row('2', 'SHIPPED')]);
      });
      expect(reads, 1);
      expect(find.text('Tất cả (2)'), findsOneWidget);
      await t.enterText(
        find.widgetWithText(TextField, 'Tìm mã đơn hoặc tên sản phẩm'),
        '  COTTON ao  ',
      );
      await t.pumpAndSettle();
      expect(find.text('WR000001'), findsOneWidget);
      await tap(t, 'Đang giao (1)');
      expect(find.text('WR000001'), findsNothing);
      expect(find.text('WR000002'), findsOneWidget);
      await tap(t, 'Xóa bộ lọc');
      expect(find.text('WR000001'), findsOneWidget);
      expect(reads, 1);
    },
  );

  testWidgets(
    'refresh retains rows and filters while loading and after errors',
    (t) async {
      final response = Completer<http.Response>();
      var reads = 0;
      await mountOrders(t, (_) {
        reads++;
        return reads == 1
            ? Future.value(history([row('1', 'PENDING')]))
            : response.future;
      });
      await t.enterText(
        find.widgetWithText(TextField, 'Tìm mã đơn hoặc tên sản phẩm'),
        'WR000001',
      );
      await tap(t, 'Cập nhật đơn hàng', settle: false);
      expect(find.widgetWithText(SelectableText, 'WR000001'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(
        t
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Cập nhật đơn hàng'),
            )
            .onPressed,
        isNull,
      );
      response.complete(jsonResponse({}, 503));
      await t.pumpAndSettle();
      expect(
        find.textContaining('Chưa cập nhật được danh sách.'),
        findsOneWidget,
      );
      expect(find.widgetWithText(SelectableText, 'WR000001'), findsOneWidget);
      expect(
        t
            .widget<TextField>(
              find.widgetWithText(TextField, 'Tìm mã đơn hoặc tên sản phẩm'),
            )
            .controller!
            .text,
        'WR000001',
      );
    },
  );

  testWidgets('load-more error preserves rows and retries the same page', (
    t,
  ) async {
    final pages = <String>[];
    var fail = true;
    await mountOrders(t, (r) async {
      final page = r.url.queryParameters['page']!;
      pages.add(page);
      if (page == '1') return history([row('1', 'PENDING')], total: 2);
      if (fail) return jsonResponse({}, 503);
      return history([row('2', 'SHIPPED')], page: 2, total: 2);
    });
    expect(find.text('1 / 2 đơn đã tải'), findsOneWidget);
    await tap(t, 'Tải thêm đơn hàng');
    expect(find.text('WR000001'), findsOneWidget);
    expect(find.textContaining('Chưa tải thêm được đơn hàng.'), findsOneWidget);
    fail = false;
    await tap(t, 'Thử tải lại');
    expect(pages, ['1', '2', '2']);
    expect(find.text('WR000002'), findsOneWidget);
    expect(find.text('Tải thêm đơn hàng'), findsNothing);
  });

  testWidgets('initial load error retries without claiming an empty history', (
    t,
  ) async {
    var fail = true;
    await mountOrders(
      t,
      (_) async => fail ? jsonResponse({}, 503) : history([]),
    );
    expect(find.text('Chưa tải được đơn hàng'), findsOneWidget);
    expect(find.text('Bạn chưa có đơn hàng'), findsNothing);
    fail = false;
    await tap(t, 'Thử tải lại');
    expect(find.text('Bạn chưa có đơn hàng'), findsOneWidget);
    await tap(t, 'Khám phá cửa hàng');
    expect(find.text('Catalog'), findsOneWidget);
  });

  testWidgets(
    'switching detail ID loads that order; missing ID has a way back',
    (t) async {
      final reads = <String>[];
      final app = await mountOrders(t, (r) async {
        if (r.url.path.endsWith('/orders')) return history([]);
        reads.add(r.url.path);
        final id = r.url.pathSegments.last;
        return id == 'missing'
            ? jsonResponse({}, 404)
            : jsonResponse(row(id, 'PENDING'));
      }, location: '/account/orders/1');
      expect(find.text('WR000001'), findsOneWidget);
      app.router.go('/account/orders/2');
      await t.pumpAndSettle();
      expect(find.text('WR000002'), findsOneWidget);
      expect(find.text('WR000001'), findsNothing);
      expect(reads, ['/api/v1/orders/1', '/api/v1/orders/2']);
      app.router.go('/account/orders/missing');
      await t.pumpAndSettle();
      expect(find.text('Không tìm thấy đơn hàng'), findsOneWidget);
      expect(find.text('Hủy đơn hàng'), findsNothing);
      await tap(t, 'Về danh sách đơn');
      expect(find.text('Đơn hàng của bạn.'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'cancel confirmation can be dismissed; conflict reloads canonical state',
    (t) async {
      var writes = 0, state = 'PENDING';
      await mountOrders(t, (r) async {
        if (r.url.path.endsWith('/orders')) return history([row('1', state)]);
        if (r.url.path.endsWith('/cancel')) {
          writes++;
          state = 'CONFIRMED';
          return jsonResponse({
            'error': {'code': 'ORDER_STATE_CONFLICT'},
          }, 409);
        }
        return jsonResponse(row('1', state));
      }, location: '/account/orders/1');
      await tap(t, 'Hủy đơn hàng');
      expect(find.textContaining('Đơn WR000001 sẽ được hủy.'), findsOneWidget);
      await tap(t, 'Giữ đơn');
      expect(writes, 0);
      await tap(t, 'Hủy đơn hàng');
      await tap(t, 'Xác nhận hủy');
      expect(writes, 1);
      expect(find.text('Đã xác nhận'), findsOneWidget);
      expect(find.text('Hủy đơn hàng'), findsNothing);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets('stale detail retains snapshot but disables cancellation', (
    t,
  ) async {
    var fail = false;
    await mountOrders(t, (r) async {
      if (r.url.path.endsWith('/orders')) return history([row('1', 'PENDING')]);
      return fail ? jsonResponse({}, 503) : jsonResponse(row('1', 'PENDING'));
    }, location: '/account/orders/1');
    fail = true;
    await tap(t, 'Cập nhật đơn hàng');
    expect(find.text('WR000001'), findsOneWidget);
    expect(
      find.textContaining('Đang hiển thị thông tin lần tải trước.'),
      findsOneWidget,
    );
    expect(
      t
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Hủy đơn hàng'),
          )
          .onPressed,
      isNull,
    );
  });

  for (final size in [
    (320.0, 1.0),
    (375.0, 2.0),
    (768.0, 1.0),
    (1440.0, 1.0),
    (2560.0, 1.0),
  ]) {
    testWidgets(
      'order filters and status labels fit ${size.$1} at scale ${size.$2}',
      (t) async {
        await mountOrders(
          t,
          (_) async => history([row('1', 'PENDING'), row('2', 'RETURNED')]),
          width: size.$1,
          scale: size.$2,
        );
        await tap(t, 'Đã hoàn về kho (1)');
        expect(find.text('WR000002'), findsOneWidget);
        expect(find.text('WR000001'), findsNothing);
        expect(t.takeException(), isNull);
      },
    );
  }
}
