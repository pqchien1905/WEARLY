import 'dart:convert';
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
import 'remote_commerce_test.dart' show orderJson;
import 'remote_session_test.dart' show jsonResponse;

Map<String, dynamic> adminProduct() => {
  'id': 'p1',
  'slug': 'shirt',
  'name': 'Áo quản trị',
  'description': 'Cotton',
  'material': 'Cotton',
  'style': 'Tối giản',
  'active': true,
  'tryOnSupported': false,
  'categoryId': 'c1',
  'brandId': 'b1',
  'category': {'name': 'Áo'},
  'brand': {'name': 'Wearly'},
  'images': [
    {'url': 'assets/images/shirt.jpg', 'alt': 'Áo', 'color': null},
  ],
  'variants': [],
};
Map<String, dynamic> pageJson(List items, {int page = 1, int total = 1}) => {
  'items': items,
  'page': page,
  'total': total,
  'limit': 20,
};

void main() {
  Future<ProviderContainer> setup(
    WidgetTester tester,
    String path,
    Future<http.Response> Function(http.Request) handle, {
    String? role = 'ADMIN',
  }) async {
    final api = ApiClient(
      baseUrl: 'http://localhost/api/v1',
      client: MockClient((r) async {
        if (r.url.path.endsWith('/auth/login')) {
          final session = sessionJson();
          (session['user'] as Map)['role'] = role;
          return jsonResponse(session);
        }
        if (r.url.path.endsWith('/auth/logout')) return jsonResponse({});
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
    addTearDown(() {
      container.dispose();
      api.close();
    });
    if (role != null) {
      await container
          .read(accountProvider.notifier)
          .signIn('', 'an@example.com', 'password');
    }
    final router = createRouter(initialLocation: path);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: NepApp(router: router),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  for (final role in [null, 'CUSTOMER']) {
    testWidgets('admin gate blocks $role without loading private data', (
      tester,
    ) async {
      var reads = 0;
      await setup(tester, '/admin/products', (r) async {
        reads++;
        return jsonResponse({});
      }, role: role);
      expect(
        find.text(
          role == null ? 'Đăng nhập để tiếp tục' : 'Cần quyền quản trị',
        ),
        findsOneWidget,
      );
      expect(reads, 0);
    });
  }
  testWidgets('demo-only admin settings disclose unavailability', (
    tester,
  ) async {
    await setup(
      tester,
      '/admin/settings',
      (r) async => throw StateError('No API call expected'),
    );
    expect(find.text('Chức năng quản trị chưa khả dụng'), findsOneWidget);
  });
  testWidgets(
    'mobile products paginate server data and logout removes records',
    (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final container = await setup(tester, '/admin/products', (r) async {
        final page = int.parse(r.url.queryParameters['page']!);
        return jsonResponse(
          pageJson(
            [
              {
                ...adminProduct(),
                'name': page == 1 ? 'Áo quản trị' : 'Áo trang hai',
              },
            ],
            page: page,
            total: 21,
          ),
        );
      });
      expect(find.text('Áo quản trị'), findsOneWidget);
      final next = find.widgetWithText(OutlinedButton, 'Trang sau');
      await tester.ensureVisible(next);
      await tester.tap(next);
      await tester.pumpAndSettle();
      expect(find.text('Áo trang hai'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await container.read(accountProvider.notifier).signOut();
      await tester.pumpAndSettle();
      expect(find.text('Áo trang hai'), findsNothing);
      expect(find.text('Đăng nhập để tiếp tục'), findsOneWidget);
    },
  );
  testWidgets(
    'stock conflict requires reload and does not retry the mutation',
    (tester) async {
      var writes = 0;
      await setup(tester, '/admin/inventory', (r) async {
        if (r.method == 'POST') {
          writes++;
          expect(jsonDecode(r.body), {
            'delta': 2,
            'expectedVersion': 7,
            'reason': 'Kiểm kho',
          });
          return jsonResponse({
            'error': {'code': 'VERSION_CONFLICT', 'message': 'Changed'},
          }, 409);
        }
        return jsonResponse(
          pageJson([
            {
              'id': 'inv',
              'quantity': 4,
              'version': 7,
              'variant': {
                'id': 'v',
                'sku': 'SKU-1',
                'size': 'M',
                'color': 'Đen',
                'active': true,
                'product': {'name': 'Áo quản trị', 'active': true},
              },
            },
          ]),
        );
      });
      await tester.tap(find.widgetWithText(OutlinedButton, 'Điều chỉnh kho'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Số lượng thay đổi'),
        '2',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Lý do'),
        'Kiểm kho',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Lưu thay đổi'));
      await tester.pumpAndSettle();
      expect(find.text('Tải lại dữ liệu'), findsOneWidget);
      expect(writes, 1);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('order detail advances exact version and keeps COD unpaid', (
    tester,
  ) async {
    var status = 'PENDING', version = 4;
    await setup(tester, '/admin/orders/order-1', (r) async {
      if (r.method == 'PATCH') {
        expect(jsonDecode(r.body), {
          'status': 'CONFIRMED',
          'expectedVersion': 4,
        });
        status = 'CONFIRMED';
        version++;
      }
      return jsonResponse({
        ...orderJson(status: status),
        'version': version,
        'user': {'email': 'buyer@example.com'},
      });
    });
    await tester.ensureVisible(
      find.widgetWithText(FilledButton, 'Xác nhận đơn'),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Xác nhận đơn'));
    await tester.pumpAndSettle();
    // The change is explicit and confirmed before the request.
    await tester.tap(find.widgetWithText(FilledButton, 'Lưu thay đổi'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Chưa thu tiền'), findsOneWidget);
    expect(
      find.widgetWithText(FilledButton, 'Bắt đầu giao hàng'),
      findsOneWidget,
    );
  });
  testWidgets(
    'metadata edit preserves a concurrent gallery and unrelated field change',
    (tester) async {
      var writes = 0;
      final server = adminProduct();
      await setup(tester, '/admin/products/p1/edit', (r) async {
        if (r.url.path.endsWith('/categories')) {
          return jsonResponse([
            {'id': 'c1', 'name': 'Áo'},
          ]);
        }
        if (r.url.path.endsWith('/brands')) {
          return jsonResponse([
            {'id': 'b1', 'name': 'Wearly'},
          ]);
        }
        if (r.method == 'PATCH') {
          writes++;
          final body = jsonDecode(r.body);
          server.addAll(Map<String, dynamic>.from(body));
        }
        return jsonResponse(server);
      });
      // Another administrator updates the server after this editor loaded.
      final newGallery = [
        {'url': 'https://example.com/new.jpg', 'alt': 'New image'},
      ];
      server['images'] = newGallery;
      server['material'] = 'Linen';
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Tên sản phẩm'),
        'Áo đã sửa',
      );
      final save = find.widgetWithText(FilledButton, 'Lưu thông tin sản phẩm');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(writes, 1);
      expect(server['images'], newGallery);
      expect(server['material'], 'Linen');
      expect(server['name'], 'Áo đã sửa');
      expect(find.text('Đã lưu thông tin sản phẩm.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'successful gallery edit becomes the baseline for later metadata saves',
    (tester) async {
      final server = adminProduct();
      final bodies = <Map<String, dynamic>>[];
      await setup(tester, '/admin/products/p1/edit', (r) async {
        if (r.url.path.endsWith('/categories')) {
          return jsonResponse([
            {'id': 'c1', 'name': 'Áo'},
          ]);
        }
        if (r.url.path.endsWith('/brands')) {
          return jsonResponse([
            {'id': 'b1', 'name': 'Wearly'},
          ]);
        }
        if (r.method == 'PATCH') {
          final body = Map<String, dynamic>.from(jsonDecode(r.body));
          bodies.add(body);
          server.addAll(body);
        }
        return jsonResponse(server);
      });
      final alt = find.widgetWithText(TextFormField, 'Mô tả ảnh');
      await tester.ensureVisible(alt);
      await tester.enterText(alt, 'Ảnh đã sửa');
      final save = find.widgetWithText(FilledButton, 'Lưu thông tin sản phẩm');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(bodies.single['images'], [
        {'url': 'assets/images/shirt.jpg', 'alt': 'Ảnh đã sửa'},
      ]);
      final gallery = [
        ...server['images'] as List,
        {'url': 'https://example.com/concurrent.jpg', 'alt': 'Concurrent'},
      ];
      server['images'] = gallery;
      final name = find.widgetWithText(TextFormField, 'Tên sản phẩm');
      await tester.ensureVisible(name);
      await tester.enterText(name, 'Tên mới');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(bodies.last, {'name': 'Tên mới'});
      expect(server['images'], gallery);
      expect(tester.takeException(), isNull);
    },
  );
}
