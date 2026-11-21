import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nep_storefront/app/app.dart';
import 'package:nep_storefront/app/account_state.dart';
import 'package:nep_storefront/app/api_providers.dart';
import 'package:nep_storefront/core/network/api_client.dart';
import 'remote_account_test.dart' show sessionJson;
import 'remote_session_test.dart' show jsonResponse;
import 'remote_admin_ui_test.dart' show adminProduct, pageJson;

void main() {
  Future<void> mount(
    WidgetTester tester,
    String path,
    Future<http.Response> Function(http.Request) handle, {
    Size size = const Size(1440, 1000),
    double scale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final api = ApiClient(
      baseUrl: 'http://localhost/api/v1',
      client: MockClient((r) async {
        if (r.url.path.endsWith('/login')) {
          final s = sessionJson();
          (s['user'] as Map)['role'] = 'ADMIN';
          return jsonResponse(s);
        }
        if (r.url.path.endsWith('/products/summary')) {
          return jsonResponse({
            'total': 1,
            'active': 1,
            'hidden': 0,
            'published': 1,
            'lowStock': 0,
            'outOfStock': 0,
            'categories': 1,
          });
        }
        if (r.url.path.endsWith('/inventory/summary')) {
          return jsonResponse({
            'skus': 1,
            'products': 1,
            'units': 3,
            'inStock': 1,
            'lowStock': 1,
            'outOfStock': 0,
            'activeUnits': 3,
            'missing': 0,
            'lowStockThreshold': 5,
            'categories': [],
          });
        }
        if (r.url.path.endsWith('/categories') ||
            r.url.path.endsWith('/brands')) {
          return jsonResponse(pageJson([], total: 0));
        }
        return handle(r);
      }),
    );
    final container = ProviderContainer(
      retry: (count, error) => null,
      overrides: [
        remoteApiProvider.overrideWithValue(true),
        adminApiClientProvider.overrideWithValue(api),
        adminSessionTokensProvider.overrideWithValue(api.tokens),
      ],
    );
    addTearDown(() {
      container.dispose();
      api.close();
    });
    await container
        .read(adminAccountProvider.notifier)
        .signIn('', 'admin', 'password');
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: NepApp(router: createRouter(initialLocation: path)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'server search resets pagination and keeps filters in navigation',
    (tester) async {
      final requests = <Map<String, String>>[];
      await mount(tester, '/admin/products?page=2&status=hidden', (r) async {
        requests.add(r.url.queryParameters);
        return jsonResponse(
          pageJson(
            [adminProduct()],
            page: int.parse(r.url.queryParameters['page']!),
            total: 45,
          ),
        );
      });
      expect(requests.last, {'page': '2', 'limit': '10', 'status': 'hidden'});
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Tìm kiếm sản phẩm'),
        '  Áo linen  ',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Áp dụng'));
      await tester.pumpAndSettle();
      expect(requests.last, {
        'page': '1',
        'limit': '10',
        'q': 'Áo linen',
        'status': 'hidden',
      });
      await tester.tap(find.widgetWithText(ChoiceChip, 'Đang bật (1)'));
      await tester.pumpAndSettle();
      expect(requests.last['status'], 'active');
      expect(requests.last['q'], 'Áo linen');
      await tester.tap(find.text('Xóa bộ lọc'));
      await tester.pumpAndSettle();
      expect(requests.last, {'page': '1', 'limit': '10'});
      expect(tester.takeException(), isNull);
    },
  );

  for (final (width, scale) in [
    (360.0, 1.0),
    (768.0, 1.0),
    (1440.0, 1.0),
    (375.0, 1.5),
  ]) {
    testWidgets(
      'overview fits width $width with text scale $scale and links to stock alert',
      (tester) async {
        final requests = <Uri>[];
        await mount(
          tester,
          '/admin',
          (r) async {
            requests.add(r.url);
            if (r.url.path.endsWith('/summary')) {
              return jsonResponse({
                'products': 30,
                'activeProducts': 28,
                'orders': 6,
                'pendingOrders': 2,
                'customers': 10,
                'inventoryUnits': 80,
                'lowStockVariants': 3,
                'outOfStockVariants': 1,
                'paidRevenueVnd': '1234567890',
                'paidOrders': 4,
                'codAwaitingSettlementVnd': '520000',
                'refundedVnd': '10000',
                'netCollectedVnd': '1234557890',
                'legacyRefundUnverifiedVnd': '0',
                'extraCollectedVnd': '0',
                'orderStatuses': {'PENDING': 2, 'DELIVERED': 4},
                'generatedAt': '2026-10-24T01:00:00Z',
                'recentOrders': [
                  {
                    'id': 'o1',
                    'code': 'WR2610240001',
                    'status': 'PENDING',
                    'total': '520000',
                    'createdAt': '2026-10-24T01:00:00Z',
                    'user': {'name': 'Nguyễn Thị Khách Hàng Với Tên Rất Dài'},
                  },
                ],
              });
            }
            return jsonResponse(pageJson([], total: 0));
          },
          size: Size(width, 1000),
          scale: scale,
        );
        expect(find.text('Tổng quan cửa hàng'), findsOneWidget);
        expect(find.text('1.234.567.890 ₫'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('3 biến thể sắp hết'));
        await tester.tap(find.text('3 biến thể sắp hết'));
        await tester.pumpAndSettle();
        expect(requests.last.path, endsWith('/inventory'));
        expect(requests.last.queryParameters['status'], 'low');
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('narrow list keeps long product names and retry feedback usable', (
    tester,
  ) async {
    var attempts = 0;
    await mount(
      tester,
      '/admin/products',
      (r) async {
        attempts++;
        if (attempts == 1) {
          return jsonResponse({
            'error': {
              'code': 'UNAVAILABLE',
              'message': 'Chưa kết nối được máy chủ.',
            },
          }, 503);
        }
        return jsonResponse(
          pageJson([
            {
              ...adminProduct(),
              'name':
                  'Áo sơ mi chất liệu linen với tên sản phẩm rất dài để kiểm tra xuống dòng',
            },
          ]),
        );
      },
      size: const Size(360, 1000),
      scale: 1.5,
    );
    await tester.ensureVisible(find.text('Thử tải lại'));
    await tester.tap(find.text('Thử tải lại'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Áo sơ mi chất liệu linen'), findsOneWidget);
    expect(attempts, 2);
    expect(tester.takeException(), isNull);
  });
}
