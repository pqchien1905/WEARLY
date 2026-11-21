import 'dart:async';
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
import 'remote_session_test.dart' show jsonResponse;
import 'remote_admin_ui_test.dart' show pageJson;

Map<String, dynamic> stock({int quantity = 3}) => {
  'id': 'i1',
  'variantId': 'v1',
  'quantity': quantity,
  'version': 7,
  'updatedAt': '2026-10-24T01:00:00Z',
  'variant': {
    'id': 'v1',
    'sku': 'LINEN-LONG-SKU-WHITE-M-2026',
    'color': 'Trắng',
    'size': 'M',
    'active': true,
    'product': {
      'id': 'p1',
      'name': 'Áo sơ mi linen dài tay với tên rất dài',
      'active': true,
      'category': {'id': 'c1', 'name': 'Áo sơ mi'},
      'images': [
        {'url': 'assets/images/shirt.jpg', 'alt': 'Áo'},
      ],
    },
  },
};
Map<String, dynamic> metrics() => {
  'skus': 55,
  'products': 20,
  'units': 160,
  'inStock': 50,
  'lowStock': 3,
  'outOfStock': 5,
  'activeUnits': 150,
  'missing': 1,
  'lowStockThreshold': 5,
  'categories': [
    {'id': 'c1', 'name': 'Áo sơ mi'},
  ],
};
Map<String, dynamic> movement() => {
  'id': 'm1',
  'delta': 2,
  'reason': 'ADMIN: Kiểm kê thực tế',
  'createdAt': '2026-10-24T01:00:00Z',
  'adjustment': {'before': 1, 'after': 3, 'actor': 'Quản trị kiểm thử'},
};
void main() {
  Future<void> mount(
    WidgetTester t,
    String path,
    Future<http.Response> Function(http.Request) handle, {
    double width = 1440,
    double scale = 1,
    String role = 'ADMIN',
  }) async {
    t.view.physicalSize = Size(width, 1000);
    t.view.devicePixelRatio = 1;
    t.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    final api = ApiClient(
      baseUrl: 'http://localhost/api/v1',
      client: MockClient((r) async {
        if (r.url.path.endsWith('/login')) {
          final s = sessionJson();
          (s['user'] as Map)['role'] = role;
          return jsonResponse(s);
        }
        if (r.url.path.endsWith('/inventory/summary')) {
          return jsonResponse(metrics());
        }
        return handle(r);
      }),
    );
    final scope = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        remoteApiProvider.overrideWithValue(true),
        adminApiClientProvider.overrideWithValue(api),
        adminSessionTokensProvider.overrideWithValue(api.tokens),
      ],
    );
    addTearDown(() {
      scope.dispose();
      api.close();
    });
    await scope
        .read(adminAccountProvider.notifier)
        .signIn('', 'admin', 'password');
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: scope,
        child: NepApp(router: createRouter(initialLocation: path)),
      ),
    );
    await t.pumpAndSettle();
  }

  Future<http.Response> reads(http.Request r) async => jsonResponse(
    r.url.path.endsWith('/movements')
        ? pageJson([movement()])
        : r.url.path.endsWith('/inventory')
        ? pageJson(
            [stock()],
            total: 55,
            page: int.parse(r.url.queryParameters['page'] ?? '1'),
          )
        : stock(),
  );
  Future<void> click(WidgetTester t, Finder finder) async {
    await t.ensureVisible(finder);
    await t.tap(finder);
    await t.pumpAndSettle();
  }

  Future<void> action(WidgetTester t, String name) async {
    await click(t, find.byTooltip('Thao tác kho').first);
    await click(t, find.text(name).last);
  }

  Future<void> select(WidgetTester t, String label, String option) async {
    await click(t, find.widgetWithText(DropdownButtonFormField<String>, label));
    await click(t, find.text(option).last);
  }

  for (final (width, scale) in [
    (360.0, 1.0),
    (768.0, 1.0),
    (1440.0, 1.0),
    (1920.0, 1.0),
    (2560.0, 1.0),
    (375.0, 1.5),
    (1440.0, 1.5),
  ]) {
    testWidgets('inventory list/detail and input fit $width at $scale', (
      t,
    ) async {
      await mount(
        t,
        '/admin/inventory',
        reads,
        width: width,
        scale: scale,
        role: 'WAREHOUSE',
      );
      expect(t.takeException(), isNull);
      await action(t, 'Chi tiết & lịch sử');
      expect(find.text('Lịch sử biến động'), findsOneWidget);
      expect(t.takeException(), isNull);
      await action(t, 'Nhập kho');
      expect(find.text('Trước: 3 → Sau: — đơn vị'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }
  testWidgets(
    'server filters, sorting, pagination and history return retain URL',
    (t) async {
      final requests = <Uri>[];
      await mount(t, '/admin/inventory?page=2', (r) async {
        requests.add(r.url);
        return reads(r);
      });
      await t.enterText(
        find.widgetWithText(TextFormField, 'Tìm kiếm kho hàng'),
        ' Áo ',
      );
      await t.enterText(find.widgetWithText(TextFormField, 'Số lượng từ'), '4');
      await t.enterText(
        find.widgetWithText(TextFormField, 'Số lượng đến'),
        '1',
      );
      final count = requests.length;
      await click(t, find.widgetWithText(FilledButton, 'Áp dụng'));
      expect(requests.length, count);
      await t.enterText(
        find.widgetWithText(TextFormField, 'Số lượng đến'),
        '10',
      );
      await click(t, find.widgetWithText(FilledButton, 'Áp dụng'));
      expect(requests.last.queryParameters, containsPair('page', '1'));
      expect(requests.last.queryParameters['q'], 'Áo');
      await select(t, 'Tồn kho', 'Sắp hết (1–5)');
      expect(requests.last.queryParameters['visibility'], 'all');
      await select(t, 'Danh mục', 'Áo sơ mi');
      await select(t, 'Trạng thái kinh doanh', 'Sản phẩm hoặc SKU đã ẩn');
      await select(t, 'Sắp xếp', 'Tồn kho ít đến nhiều');
      await click(t, find.widgetWithText(OutlinedButton, 'Trang sau'));
      expect(
        requests.last.queryParameters,
        containsPair('visibility', 'hidden'),
      );
      expect(requests.last.queryParameters['page'], '2');
      await action(t, 'Chi tiết & lịch sử');
      await click(t, find.widgetWithText(OutlinedButton, 'Về danh sách kho'));
      expect(requests.last.queryParameters['page'], '2');
      expect(requests.last.queryParameters['sort'], 'quantity_asc');
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'export blocks excess stock, previews result and prevents duplicate writes',
    (t) async {
      final pending = Completer<http.Response>();
      var writes = 0;
      Map<String, dynamic>? body;
      await mount(t, '/admin/inventory/i1', (r) async {
        if (r.method == 'POST') {
          writes++;
          body = jsonDecode(r.body);
          return pending.future;
        }
        return reads(r);
      });
      await action(t, 'Xuất kho');
      await t.enterText(
        find.widgetWithText(TextFormField, 'Số lượng xuất'),
        '4',
      );
      await t.enterText(
        find.widgetWithText(TextFormField, 'Lý do'),
        'Xuất kiểm tra',
      );
      await click(t, find.widgetWithText(FilledButton, 'Lưu thay đổi'));
      expect(writes, 0);
      await t.enterText(
        find.widgetWithText(TextFormField, 'Số lượng xuất'),
        '2',
      );
      await t.pump();
      expect(find.text('Trước: 3 → Sau: 1 đơn vị'), findsOneWidget);
      final save = find.widgetWithText(FilledButton, 'Lưu thay đổi');
      await t.tap(save);
      await t.pump();
      await t.tap(save);
      await t.pump();
      expect(writes, 1);
      expect(body, {
        'delta': -2,
        'expectedVersion': 7,
        'reason': 'Xuất kiểm tra',
        'operation': 'out',
      });
      pending.complete(jsonResponse(stock(quantity: 1)));
      await t.pumpAndSettle();
      expect(find.text('Đã cập nhật tồn kho.'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'count converts to a versioned delta and conflicts require reload',
    (t) async {
      var writes = 0;
      await mount(t, '/admin/inventory/i1', (r) async {
        if (r.method == 'POST') {
          writes++;
          expect(jsonDecode(r.body)['delta'], -3);
          return jsonResponse({
            'error': {'code': 'VERSION_CONFLICT', 'message': 'Changed'},
          }, 409);
        }
        return reads(r);
      });
      await action(t, 'Kiểm kê tồn kho');
      await t.enterText(
        find.widgetWithText(TextFormField, 'Số lượng kiểm kê'),
        '0',
      );
      await t.enterText(
        find.widgetWithText(TextFormField, 'Lý do'),
        'Kiểm đếm',
      );
      await click(t, find.widgetWithText(FilledButton, 'Lưu thay đổi'));
      expect(writes, 1);
      expect(find.widgetWithText(FilledButton, 'Lưu thay đổi'), findsNothing);
      await click(t, find.widgetWithText(FilledButton, 'Tải lại dữ liệu'));
      expect(writes, 1);
      expect(find.byType(AlertDialog), findsNothing);
    },
  );
  testWidgets(
    'uncertain stock write is not retried and reload reveals the actual balance',
    (t) async {
      var writes = 0, quantity = 3;
      await mount(t, '/admin/inventory/i1', (r) async {
        if (r.method == 'POST') {
          writes++;
          quantity = 5;
          return jsonResponse({
            'error': {'code': 'UNAVAILABLE', 'message': 'Mất kết nối'},
          }, 503);
        }
        return r.url.path.endsWith('/movements')
            ? reads(r)
            : jsonResponse(stock(quantity: quantity));
      });
      await action(t, 'Nhập kho');
      await t.enterText(
        find.widgetWithText(TextFormField, 'Số lượng nhập'),
        '2',
      );
      await t.enterText(
        find.widgetWithText(TextFormField, 'Lý do'),
        'Nhập kho',
      );
      await click(t, find.widgetWithText(FilledButton, 'Lưu thay đổi'));
      expect(writes, 1);
      expect(find.widgetWithText(FilledButton, 'Lưu thay đổi'), findsNothing);
      await click(t, find.widgetWithText(FilledButton, 'Tải lại dữ liệu'));
      expect(find.text('5 đơn vị khả dụng'), findsOneWidget);
      expect(writes, 1);
    },
  );
  testWidgets('missing inventory initialization requires confirmation', (
    t,
  ) async {
    var writes = 0;
    await mount(t, '/admin/inventory?record=missing', (r) async {
      if (r.method == 'POST') {
        writes++;
        expect(r.url.path, endsWith('/variants/v1/initialize'));
        return jsonResponse(stock());
      }
      return jsonResponse(
        pageJson([
          {...stock(), 'id': null, 'quantity': null},
        ]),
      );
    });
    await action(t, 'Khởi tạo kho 0');
    expect(writes, 0);
    expect(
      find.textContaining('Việc này không nhập thêm hàng.'),
      findsOneWidget,
    );
    await click(t, find.widgetWithText(FilledButton, 'Lưu thay đổi'));
    expect(writes, 1);
    expect(t.takeException(), isNull);
  });
  testWidgets('history validates dates and filters real linked balances', (
    t,
  ) async {
    final requests = <Uri>[];
    await mount(t, '/admin/inventory/i1', (r) async {
      requests.add(r.url);
      return reads(r);
    });
    expect(
      find.text('Trước: 1 → Sau: 3 · Người thực hiện: Quản trị kiểm thử'),
      findsOneWidget,
    );
    await t.enterText(
      find.widgetWithText(TextFormField, 'Từ ngày'),
      '2026-02-30',
    );
    final before = requests.length;
    await click(t, find.widgetWithText(FilledButton, 'Lọc lịch sử'));
    expect(requests.length, before);
    await t.enterText(
      find.widgetWithText(TextFormField, 'Từ ngày'),
      '2026-10-01',
    );
    await t.enterText(
      find.widgetWithText(TextFormField, 'Đến ngày'),
      '2026-10-24',
    );
    await click(t, find.widgetWithText(FilledButton, 'Lọc lịch sử'));
    await select(t, 'Loại biến động', 'Giảm kho');
    expect(requests.last.queryParameters, containsPair('type', 'out'));
    expect(requests.last.queryParameters['from'], '2026-10-01');
  });
  testWidgets('empty list and network failure offer retry', (t) async {
    var reads = 0;
    await mount(t, '/admin/inventory', (r) async {
      reads++;
      return reads == 1
          ? jsonResponse({
              'error': {'code': 'UNAVAILABLE', 'message': 'Mất kết nối'},
            }, 503)
          : jsonResponse(pageJson([], total: 0));
    });
    await click(t, find.text('Thử tải lại'));
    expect(find.text('Không có SKU phù hợp'), findsOneWidget);
    expect(reads, 2);
  });
  testWidgets('404 inventory is recoverable', (t) async {
    await mount(
      t,
      '/admin/inventory/missing',
      (r) async => jsonResponse({
        'error': {'code': 'NOT_FOUND', 'message': 'Missing'},
      }, 404),
    );
    expect(find.text('Không tìm thấy bản ghi kho'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets(
    'filtered totals come from all matching rows and clamped pages synchronize the URL',
    (t) async {
      final requests = <Uri>[];
      await mount(t, '/admin/inventory?page=99&q=linen&limit=20', (r) async {
        requests.add(r.url);
        return jsonResponse({
          ...pageJson([stock()], total: 21, page: 2),
          'summary': {'units': 145, 'lowStock': 4, 'outOfStock': 2},
        });
      });
      expect(find.text('145 đơn vị khả dụng trong kết quả'), findsOneWidget);
      expect(requests.last.queryParameters['page'], '2');
      expect(requests.last.queryParameters['q'], 'linen');
      expect(find.text('4 sắp hết'), findsOneWidget);
      await select(t, 'Sắp xếp', 'Ưu tiên bổ sung hàng');
      expect(requests.last.queryParameters['sort'], 'attention');
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'count unchanged and non-decimal quantity cannot create a movement',
    (t) async {
      var writes = 0;
      await mount(t, '/admin/inventory/i1', (r) async {
        if (r.method == 'POST') writes++;
        return reads(r);
      });
      await click(t, find.widgetWithText(OutlinedButton, 'Kiểm kê tồn kho'));
      await t.enterText(
        find.widgetWithText(TextFormField, 'Số lượng kiểm kê'),
        '3',
      );
      await t.enterText(
        find.widgetWithText(TextFormField, 'Lý do'),
        'Kiểm kê thực tế',
      );
      await click(t, find.widgetWithText(FilledButton, 'Lưu thay đổi'));
      expect(
        find.text('Số lượng trùng với tồn kho hiện tại. Không cần điều chỉnh.'),
        findsOneWidget,
      );
      await t.enterText(
        find.widgetWithText(TextFormField, 'Số lượng kiểm kê'),
        '0x10',
      );
      await click(t, find.widgetWithText(FilledButton, 'Lưu thay đổi'));
      expect(writes, 0);
    },
  );

  testWidgets(
    'history shows operation and scoped totals, and clears unsaved invalid dates',
    (t) async {
      await mount(t, '/admin/inventory/i1', (r) async {
        return r.url.path.endsWith('/movements')
            ? jsonResponse({
                ...pageJson([
                  {
                    ...movement(),
                    'adjustment': {
                      ...movement()['adjustment'],
                      'operation': 'count',
                    },
                  },
                ]),
                'summary': {'incoming': 9, 'outgoing': 7, 'net': 2},
              })
            : reads(r);
      });
      expect(find.text('Tăng 9'), findsOneWidget);
      expect(find.text('Giảm 7'), findsOneWidget);
      expect(find.text('Kiểm kê tồn kho'), findsNWidgets(2));
      final field = find.widgetWithText(TextFormField, 'Từ ngày');
      await t.enterText(field, '2026-02-30');
      await click(t, find.widgetWithText(FilledButton, 'Lọc lịch sử'));
      expect(find.text('Nhập ngày YYYY-MM-DD hợp lệ.'), findsOneWidget);
      await click(t, find.text('Xóa bộ lọc lịch sử'));
      expect(find.text('2026-02-30'), findsNothing);
      expect(find.text('Nhập ngày YYYY-MM-DD hợp lệ.'), findsNothing);
      await click(t, find.byTooltip('Chọn ngày bắt đầu'));
      expect(find.byType(DatePickerDialog), findsOneWidget);
      await click(t, find.text('Chọn').last);
      expect(t.takeException(), isNull);
    },
  );
}
