import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nep_storefront/app/app.dart';
import 'package:nep_storefront/app/account_state.dart';
import 'package:nep_storefront/app/api_providers.dart';
import 'package:nep_storefront/core/network/api_client.dart';
import 'package:nep_storefront/core/widgets/primitives.dart' show FashionImage;
import 'remote_account_test.dart' show sessionJson;
import 'remote_session_test.dart' show jsonResponse;
import 'remote_admin_ui_test.dart' show adminProduct, pageJson;

Map<String, dynamic> product() => {
  ...adminProduct(),
  'updatedAt': '2026-10-24T01:00:00.000Z',
  'createdAt': '2026-10-20T00:00:00.000Z',
  'variants': [
    {
      'id': 'v1',
      'sku': 'LINEN-SHIRT-LONG-SKU-2026-WHITE-M',
      'size': 'M',
      'color': 'Trắng ngà',
      'colorHex': '#ffffff',
      'price': '500000',
      'active': true,
      'updatedAt': '2026-10-24T01:00:00.000Z',
      'inventory': {'id': 'i1', 'quantity': 3, 'version': 0},
    },
  ],
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
        if (r.url.path.endsWith('/products/summary')) {
          return jsonResponse({
            'total': 55,
            'active': 50,
            'hidden': 5,
            'published': 47,
            'lowStock': 3,
            'outOfStock': 2,
            'categories': 2,
          });
        }
        if (r.url.path.endsWith('/categories')) {
          return jsonResponse(
            pageJson([
              {'id': 'c1', 'name': 'Áo'},
              {'id': 'c2', 'name': 'Quần'},
            ]),
          );
        }
        if (r.url.path.endsWith('/brands')) {
          return jsonResponse(
            pageJson([
              {'id': 'b1', 'name': 'Wearly'},
            ]),
          );
        }
        return handle(r);
      }),
    );
    final container = ProviderContainer(
      retry: (_, _) => null,
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
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: NepApp(router: createRouter(initialLocation: path)),
      ),
    );
    await t.pumpAndSettle();
  }

  Future<void> click(WidgetTester t, Finder f) async {
    await t.ensureVisible(f);
    await t.tap(f);
    await t.pumpAndSettle();
  }

  Future<void> select(WidgetTester t, String label, String option) async {
    await click(t, find.widgetWithText(DropdownButtonFormField<String>, label));
    await click(t, find.text(option).last);
  }

  Future<http.Response> reads(http.Request r) async =>
      r.url.path.endsWith('/products')
      ? jsonResponse(
          pageJson(
            [product()],
            total: 55,
            page: int.parse(r.url.queryParameters['page'] ?? '1'),
          ),
        )
      : jsonResponse(product());
  testWidgets(
    'products filters, range validation, sorting, pagination and return preserve URL',
    (t) async {
      final requests = <Uri>[];
      await mount(t, '/admin/products?page=3&status=hidden', (r) async {
        requests.add(r.url);
        return reads(r);
      });
      await t.enterText(
        find.widgetWithText(TextFormField, 'Tìm kiếm sản phẩm'),
        ' Áo ',
      );
      await t.enterText(
        find.widgetWithText(TextFormField, 'Giá từ (VND)'),
        '100000',
      );
      await t.enterText(
        find.widgetWithText(TextFormField, 'Giá đến (VND)'),
        '1',
      );
      final before = requests.length;
      await click(t, find.widgetWithText(FilledButton, 'Áp dụng'));
      expect(requests.length, before);
      expect(
        find.text('Giá đến phải lớn hơn hoặc bằng giá từ.'),
        findsOneWidget,
      );
      await t.enterText(
        find.widgetWithText(TextFormField, 'Giá đến (VND)'),
        '600000',
      );
      await click(t, find.widgetWithText(FilledButton, 'Áp dụng'));
      expect(requests.last.queryParameters, containsPair('page', '1'));
      expect(requests.last.queryParameters, containsPair('minPrice', '100000'));
      expect(requests.last.queryParameters['q'], 'Áo');
      await select(t, 'Danh mục', 'Quần');
      await select(t, 'Tồn kho SKU đang bán', 'Có SKU còn 1–5');
      await select(t, 'Sắp xếp', 'Giá cao đến thấp');
      expect(requests.last.queryParameters, containsPair('categoryId', 'c2'));
      expect(requests.last.queryParameters, containsPair('stock', 'low'));
      expect(requests.last.queryParameters, containsPair('sort', 'price_desc'));
      await click(t, find.widgetWithText(OutlinedButton, 'Trang sau'));
      expect(requests.last.queryParameters['page'], '2');
      await click(t, find.byTooltip('Thao tác sản phẩm').first);
      await click(t, find.text('Xem chi tiết'));
      expect(find.text('Chi tiết sản phẩm'), findsOneWidget);
      await click(
        t,
        find.widgetWithText(OutlinedButton, 'Về danh sách sản phẩm'),
      );
      expect(requests.last.queryParameters['page'], '2');
      expect(requests.last.queryParameters['stock'], 'low');
      expect(t.takeException(), isNull);
    },
  );
  for (final (width, scale) in [
    (360.0, 1.0),
    (768.0, 1.0),
    (1440.0, 1.0),
    (375.0, 1.5),
    (1440.0, 1.5),
  ]) {
    testWidgets('products list, detail and editor fit $width at $scale', (
      t,
    ) async {
      await mount(t, '/admin/products', reads, width: width, scale: scale);
      expect(t.takeException(), isNull);
      await click(t, find.byTooltip('Thao tác sản phẩm').first);
      await click(t, find.text('Xem chi tiết'));
      expect(t.takeException(), isNull);
      await click(t, find.widgetWithText(FilledButton, 'Chỉnh sửa sản phẩm'));
      expect(find.text('Thiết lập bán hàng'), findsOneWidget);
      expect(t.takeException(), isNull);
      await click(t, find.widgetWithText(OutlinedButton, 'Thêm biến thể'));
      expect(t.takeException(), isNull);
    });
  }
  testWidgets(
    'create validates, prevents double submit and uses the returned record',
    (t) async {
      final pending = Completer<http.Response>();
      var writes = 0;
      Map<String, dynamic>? body;
      await mount(t, '/admin/products/new', (r) async {
        if (r.method == 'POST') {
          writes++;
          body = jsonDecode(r.body);
          return pending.future;
        }
        return reads(r);
      });
      await click(
        t,
        find.widgetWithText(FilledButton, 'Lưu thông tin sản phẩm'),
      );
      expect(writes, 0);
      await t.enterText(
        find.widgetWithText(TextFormField, 'Tên sản phẩm'),
        'Áo mới',
      );
      await t.enterText(
        find.widgetWithText(TextFormField, 'Đường dẫn sản phẩm'),
        'ao-moi',
      );
      await select(t, 'Danh mục', 'Áo');
      await select(t, 'Thương hiệu', 'Wearly');
      final save = find.widgetWithText(FilledButton, 'Lưu thông tin sản phẩm');
      await t.ensureVisible(save);
      await t.tap(save);
      await t.pump();
      await t.tap(save);
      await t.pump();
      expect(writes, 1);
      expect(body!['active'], false);
      pending.complete(jsonResponse({...product(), ...body!}, 201));
      await t.pumpAndSettle();
      expect(find.text('Chỉnh sửa sản phẩm'), findsOneWidget);
      expect(find.text('Biến thể & tồn kho'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('stale editor cannot overwrite changes and reload resets draft', (
    t,
  ) async {
    var server = product(), writes = 0;
    final bodies = <Map<String, dynamic>>[];
    await mount(t, '/admin/products/p1/edit', (r) async {
      if (r.method == 'PATCH') {
        writes++;
        bodies.add(jsonDecode(r.body));
        server = {
          ...server,
          'name': 'Tên mới trên server',
          'updatedAt': '2026-10-24T02:00:00.000Z',
        };
        return jsonResponse({
          'error': {'code': 'PRODUCT_CONFLICT', 'message': 'Conflict'},
        }, 409);
      }
      return jsonResponse(server);
    });
    await t.enterText(
      find.widgetWithText(TextFormField, 'Tên sản phẩm'),
      'Bản nháp cũ',
    );
    await click(
      t,
      find.widgetWithText(OutlinedButton, 'Lưu thông tin sản phẩm'),
    );
    expect(writes, 1);
    expect(bodies.single, {
      'name': 'Bản nháp cũ',
      'expectedUpdatedAt': product()['updatedAt'],
    });
    final reload = find.widgetWithText(
      FilledButton,
      'Tải lại dữ liệu sản phẩm',
    );
    final reloadBounds = t.getRect(reload);
    expect(reloadBounds.top, greaterThan(0));
    expect(
      reloadBounds.bottom,
      lessThan(t.view.physicalSize.height / t.view.devicePixelRatio),
    );
    await click(t, reload);
    expect(
      find.widgetWithText(TextFormField, 'Tên mới trên server'),
      findsOneWidget,
    );
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'gallery confirmation and reordering submit the new cover and preserve metadata',
    (t) async {
      final server = product();
      server['images'] = [
        ...(server['images'] as List),
        {'url': 'assets/images/coat.jpg', 'alt': 'Ảnh hai'},
      ];
      Map<String, dynamic>? saved;
      await mount(t, '/admin/products/p1/edit', (r) async {
        if (r.method == 'PATCH') {
          saved = jsonDecode(r.body);
          server.addAll(saved!);
        }
        return jsonResponse(server);
      });
      await click(t, find.byTooltip('Đưa ảnh lên trước').last);
      await click(
        t,
        find.widgetWithText(FilledButton, 'Lưu thông tin sản phẩm'),
      );
      expect((saved!['images'] as List).first['url'], 'assets/images/coat.jpg');
      expect(saved!.containsKey('name'), false);
      await click(t, find.widgetWithText(TextButton, 'Bỏ ảnh').last);
      await click(t, find.text('Giữ ảnh'));
      expect(find.widgetWithText(TextButton, 'Bỏ ảnh'), findsNWidgets(2));
      await click(t, find.widgetWithText(TextButton, 'Bỏ ảnh').last);
      await click(
        t,
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(TextButton, 'Bỏ ảnh'),
        ),
      );
      expect(find.widgetWithText(TextButton, 'Bỏ ảnh'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'SKU duplicate remains editable and negative price is rejected locally',
    (t) async {
      var attempts = 0;
      await mount(t, '/admin/products/p1', (r) async {
        if (r.method == 'POST') {
          attempts++;
          return jsonResponse({
            'error': {'code': 'SKU_EXISTS', 'message': 'Duplicate'},
          }, 409);
        }
        return jsonResponse(product());
      });
      await click(t, find.widgetWithText(OutlinedButton, 'Thêm biến thể'));
      for (final field in {
        'Mã SKU': 'DUP',
        'Kích cỡ': 'M',
        'Màu sắc': 'Đen',
        'Giá bán (VND)': '-1',
      }.entries) {
        await t.enterText(
          find.widgetWithText(TextFormField, field.key),
          field.value,
        );
      }
      await click(t, find.widgetWithText(FilledButton, 'Lưu thay đổi'));
      expect(attempts, 0);
      await t.enterText(
        find.widgetWithText(TextFormField, 'Giá bán (VND)'),
        '500000',
      );
      await click(t, find.widgetWithText(FilledButton, 'Lưu thay đổi'));
      expect(attempts, 1);
      expect(
        find.text('Mã SKU đã được sử dụng. Vui lòng nhập mã khác.'),
        findsOneWidget,
      );
      expect(find.widgetWithText(TextFormField, 'DUP'), findsOneWidget);
      expect(find.text('Tải lại dữ liệu'), findsNothing);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'SKU edits send only dirty fields and stop after a stale version',
    (t) async {
      final bodies = <Map<String, dynamic>>[];
      var server = product();
      await mount(t, '/admin/products/p1', (r) async {
        if (r.method == 'PATCH') {
          expect(r.url.path, endsWith('/skus/v1'));
          bodies.add(jsonDecode(r.body));
          server = {
            ...server,
            'variants': [
              {...(server['variants'] as List).single, 'price': '700000'},
            ],
          };
          return jsonResponse({
            'error': {'code': 'PRODUCT_CONFLICT', 'message': 'Stale SKU'},
          }, 409);
        }
        return jsonResponse(server);
      });
      await click(t, find.byTooltip('Sửa giá / trạng thái'));
      await t.enterText(
        find.widgetWithText(TextFormField, 'Giá bán (VND)'),
        '600000',
      );
      await click(t, find.widgetWithText(FilledButton, 'Lưu thay đổi'));
      expect(bodies.single, {
        'price': '600000',
        'expectedUpdatedAt': '2026-10-24T01:00:00.000Z',
      });
      expect(find.widgetWithText(FilledButton, 'Lưu thay đổi'), findsNothing);
      await click(t, find.widgetWithText(FilledButton, 'Tải lại dữ liệu'));
      expect(bodies.length, 1);
      expect(find.byType(AlertDialog), findsNothing);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'hide has confirmation, one pending write and refreshes the actual status',
    (t) async {
      final pending = Completer<http.Response>();
      var server = product(), writes = 0;
      Map<String, dynamic>? body;
      await mount(t, '/admin/products/p1', (r) async {
        if (r.method == 'PATCH') {
          writes++;
          body = jsonDecode(r.body);
          return pending.future;
        }
        return jsonResponse(server);
      });
      await click(t, find.widgetWithText(OutlinedButton, 'Ẩn sản phẩm'));
      expect(writes, 0);
      final save = find.widgetWithText(FilledButton, 'Lưu thay đổi');
      await t.tap(save);
      await t.pump();
      await t.tap(save);
      await t.pump();
      expect(writes, 1);
      expect(body, {'active': false, 'expectedUpdatedAt': server['updatedAt']});
      server = {...server, 'active': false};
      pending.complete(jsonResponse(server));
      await t.pumpAndSettle();
      expect(
        find.widgetWithText(OutlinedButton, 'Bật sản phẩm'),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('empty and failed list can retry without fake products', (
    t,
  ) async {
    var attempts = 0;
    await mount(t, '/admin/products', (r) async {
      attempts++;
      return attempts == 1
          ? jsonResponse({
              'error': {'code': 'UNAVAILABLE', 'message': 'Mất kết nối'},
            }, 503)
          : jsonResponse(pageJson([], total: 0));
    });
    await click(t, find.text('Thử tải lại'));
    expect(find.text('Chưa có sản phẩm'), findsOneWidget);
    expect(attempts, 2);
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'editor preview follows the draft and discard restores fields, classification and switches',
    (t) async {
      var writes = 0;
      await mount(t, '/admin/products/p1/edit', (r) async {
        if (r.method != 'GET') writes++;
        return reads(r);
      });
      await t.enterText(
        find.widgetWithText(TextFormField, 'Tên sản phẩm'),
        'Tên trong bản nháp',
      );
      await t.pumpAndSettle();
      expect(find.text('Tên trong bản nháp'), findsWidgets);
      expect(find.text('Có thay đổi chưa lưu'), findsOneWidget);
      await select(t, 'Danh mục', 'Quần');
      await click(t, find.widgetWithText(SwitchListTile, 'Hiển thị sản phẩm'));
      final add = t.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Thêm biến thể'),
      );
      expect(add.onPressed, isNull);
      await click(t, find.text('Hủy thay đổi'));
      await click(t, find.text('Bỏ thay đổi'));
      expect(
        t
            .widget<TextFormField>(
              find.widgetWithText(TextFormField, 'Tên sản phẩm'),
            )
            .controller!
            .text,
        product()['name'],
      );
      expect(
        t
            .widget<DropdownButtonFormField<String>>(
              find.widgetWithText(DropdownButtonFormField<String>, 'Danh mục'),
            )
            .initialValue,
        'c1',
      );
      expect(
        t
            .widget<SwitchListTile>(
              find.widgetWithText(SwitchListTile, 'Hiển thị sản phẩm'),
            )
            .value,
        isTrue,
      );
      expect(find.text('Có thay đổi chưa lưu'), findsNothing);
      expect(writes, 0);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'editor navigation confirms discarding unsaved edits and preserves the return filter',
    (t) async {
      await mount(
        t,
        '/admin/products/p1/edit?from=${Uri.encodeComponent('/admin/products?status=hidden')}',
        reads,
      );
      await t.enterText(
        find.widgetWithText(TextFormField, 'Tên sản phẩm'),
        'Chưa lưu',
      );
      await click(t, find.text('Về danh sách sản phẩm'));
      expect(find.text('Rời trang khi chưa lưu?'), findsOneWidget);
      await click(t, find.text('Tiếp tục chỉnh sửa'));
      expect(find.text('Chỉnh sửa sản phẩm'), findsOneWidget);
      await click(t, find.text('Về danh sách sản phẩm'));
      await click(t, find.widgetWithText(FilledButton, 'Rời trang'));
      expect(find.text('Quản lý sản phẩm'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'desktop variant table edits the selected SKU and keeps stock independent',
    (t) async {
      final server = product();
      Map<String, dynamic>? body;
      await mount(t, '/admin/products/p1/edit', (r) async {
        if (r.method == 'PATCH') {
          expect(r.url.path.endsWith('/skus/v1'), isTrue);
          body = jsonDecode(r.body);
          (server['variants'] as List).first.addAll(body!);
        }
        return jsonResponse(server);
      });
      expect(find.byType(DataTable), findsOneWidget);
      await click(t, find.text('Biến thể (1)'));
      await click(t, find.byTooltip('Sửa giá / trạng thái'));
      await t.enterText(
        find.widgetWithText(TextFormField, 'Giá bán (VND)'),
        '650000',
      );
      await click(t, find.text('Lưu thay đổi'));
      expect(body, {
        'price': '650000',
        'expectedUpdatedAt': '2026-10-24T01:00:00.000Z',
      });
      expect((server['variants'] as List).first['inventory']['quantity'], 3);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets('warehouse cannot access the product workspace', (t) async {
    await mount(t, '/admin/products/p1', reads, role: 'WAREHOUSE');
    expect(find.text('Bạn chưa có quyền truy cập'), findsOneWidget);
    expect(
      find.widgetWithText(FilledButton, 'Chỉnh sửa sản phẩm'),
      findsNothing,
    );
    expect(find.widgetWithText(OutlinedButton, 'Ẩn sản phẩm'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'Thêm biến thể'), findsNothing);
    expect(
      find.widgetWithText(OutlinedButton, 'Sửa giá / trạng thái'),
      findsNothing,
    );
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'delete confirms once, keeps filters and returns from an emptied last page',
    (t) async {
      var deleted = false, writes = 0;
      final pending = Completer<http.Response>();
      final requests = <Uri>[];
      await mount(t, '/admin/products?page=2&status=hidden&q=shirt', (r) async {
        requests.add(r.url);
        if (r.method == 'DELETE') {
          writes++;
          expect(r.url.path, endsWith('/admin/products/p1'));
          expect(jsonDecode(r.body), {
            'expectedUpdatedAt': product()['updatedAt'],
          });
          return pending.future;
        }
        final page = int.tryParse(r.url.queryParameters['page'] ?? '') ?? 1;
        return jsonResponse(
          pageJson(
            deleted ? [] : [product()],
            page: page,
            total: deleted ? 10 : 11,
          ),
        );
      });
      await click(t, find.byTooltip('Thao tác sản phẩm'));
      await click(t, find.text('Xóa sản phẩm'));
      expect(find.text('Xóa sản phẩm?'), findsOneWidget);
      await click(t, find.widgetWithText(TextButton, 'Đóng'));
      expect(writes, 0);
      await click(t, find.byTooltip('Thao tác sản phẩm'));
      await click(t, find.text('Xóa sản phẩm'));
      await t.tap(find.widgetWithText(FilledButton, 'Xác nhận xóa'));
      await t.pump();
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Xác nhận xóa'),
            )
            .onPressed,
        isNull,
      );
      expect(writes, 1);
      deleted = true;
      pending.complete(jsonResponse({'id': 'p1', 'deleted': true}));
      await t.pumpAndSettle();
      expect(find.text('Đã xóa sản phẩm.'), findsOneWidget);
      expect(requests.last.queryParameters, containsPair('page', '1'));
      expect(requests.last.queryParameters, containsPair('status', 'hidden'));
      expect(requests.last.queryParameters, containsPair('q', 'shirt'));
      expect(t.takeException(), isNull);
    },
  );
  for (final code in ['PRODUCT_IN_USE', 'PRODUCT_CONFLICT']) {
    testWidgets(
      'mobile delete preserves product on $code and requires reload',
      (t) async {
        var writes = 0;
        await mount(t, '/admin/products', (r) async {
          if (r.method == 'DELETE') {
            writes++;
            return jsonResponse({
              'error': {'code': code, 'message': 'Blocked'},
            }, 409);
          }
          return reads(r);
        }, width: 375);
        await click(t, find.byTooltip('Thao tác sản phẩm'));
        await click(t, find.text('Xóa sản phẩm'));
        await click(t, find.widgetWithText(FilledButton, 'Xác nhận xóa'));
        expect(writes, 1);
        expect(find.widgetWithText(FilledButton, 'Xác nhận xóa'), findsNothing);
        expect(
          find.widgetWithText(FilledButton, 'Tải lại dữ liệu'),
          findsOneWidget,
        );
        if (code == 'PRODUCT_IN_USE') {
          expect(find.textContaining('Hãy dùng “Ẩn sản phẩm”'), findsOneWidget);
        }
        await click(t, find.widgetWithText(TextButton, 'Đóng'));
        expect(find.byTooltip('Thao tác sản phẩm'), findsOneWidget);
        expect(t.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'detail gallery selects photos and supports zoom and keyboard navigation',
    (t) async {
      final server = product();
      server['images'] = [
        {'id': 'a', 'url': 'assets/images/shirt.jpg', 'alt': 'Ảnh áo'},
        {'id': 'b', 'url': 'assets/images/coat.jpg', 'alt': 'Ảnh khoác'},
      ];
      await mount(t, '/admin/products/p1', (r) async => jsonResponse(server));
      await click(
        t,
        find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == 'Xem ảnh 2',
        ),
      );
      expect(
        t
            .widget<FashionImage>(
              find.byKey(const ValueKey('product-gallery-image')),
            )
            .asset,
        'assets/images/coat.jpg',
      );
      await click(t, find.byTooltip('Phóng to ảnh sản phẩm'));
      expect(find.text('Ảnh 2 / 2'), findsOneWidget);
      await click(t, find.byTooltip('Phóng to'));
      expect(find.text('150%'), findsOneWidget);
      await click(t, find.byTooltip('Ảnh trước'));
      expect(find.text('Ảnh 1 / 2'), findsOneWidget);
      expect(find.text('100%'), findsOneWidget);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await t.pumpAndSettle();
      expect(find.text('Ảnh 2 / 2'), findsOneWidget);
      await click(t, find.byTooltip('Đóng ảnh lớn'));
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('2/2 ảnh · Chọn ảnh thu nhỏ để xem'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'detail filters combine without changing totals and edit the matching SKU',
    (t) async {
      final server = product(),
          base = Map<String, dynamic>.from(
            (product()['variants'] as List).single,
          );
      server['variants'] = [
        base,
        {
          ...base,
          'id': 'v2',
          'sku': 'BLUE-L',
          'size': 'L',
          'color': 'Xanh',
          'active': false,
          'inventory': {'id': 'i2', 'quantity': 9, 'version': 0},
        },
        {
          ...base,
          'id': 'v3',
          'sku': 'BLACK-S',
          'size': 'S',
          'color': 'Đen',
          'inventory': {'id': 'i3', 'quantity': 0, 'version': 0},
        },
      ];
      final writes = <http.Request>[];
      await mount(t, '/admin/products/p1', (r) async {
        if (r.method == 'PATCH') {
          writes.add(r);
          return jsonResponse({...base, ...jsonDecode(r.body)});
        }
        return jsonResponse(server);
      });
      await t.enterText(find.widgetWithText(TextField, 'Tìm biến thể'), 'blue');
      await t.pumpAndSettle();
      expect(find.text('Hiển thị 1/3 biến thể'), findsOneWidget);
      await select(t, 'Trạng thái biến thể', 'Đã ẩn');
      await select(t, 'Tồn kho biến thể', 'Hết hàng');
      expect(find.text('Hiển thị 0/3 biến thể'), findsOneWidget);
      expect(
        find.text(
          'Không có biến thể phù hợp. Thử đổi từ khóa hoặc xóa bộ lọc.',
        ),
        findsOneWidget,
      );
      expect(
        find.text('3 biến thể. Tổng tồn kho: 12 sản phẩm.'),
        findsOneWidget,
      );
      await click(t, find.text('Xóa bộ lọc biến thể'));
      await select(t, 'Tồn kho biến thể', 'Hết hàng');
      await click(t, find.byTooltip('Sửa giá / trạng thái'));
      expect(find.textContaining('BLACK-S · Đen / S'), findsOneWidget);
      await t.enterText(
        find.widgetWithText(TextFormField, 'Giá bán (VND)'),
        '550000',
      );
      await click(t, find.widgetWithText(FilledButton, 'Lưu thay đổi'));
      expect(writes.single.url.path, endsWith('/skus/v3'));
      expect(jsonDecode(writes.single.body), {
        'price': '550000',
        'expectedUpdatedAt': base['updatedAt'],
      });
      expect(find.text('Hiển thị 1/3 biến thể'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'empty detail explains publication requirements with large mobile text',
    (t) async {
      await mount(
        t,
        '/admin/products/p1',
        (r) async => jsonResponse({
          ...product(),
          'images': [],
          'variants': [],
          'description': '',
          'active': false,
        }),
        width: 375,
        scale: 1.5,
      );
      expect(find.text('Chưa có ảnh sản phẩm'), findsOneWidget);
      expect(
        find.text(
          'Hoàn tất các điều kiện trên để sản phẩm xuất hiện tại cửa hàng.',
        ),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(OutlinedButton, 'Xem tại cửa hàng'),
        findsNothing,
      );
      expect(find.widgetWithText(TextField, 'Tìm biến thể'), findsNothing);
      expect(
        find.text(
          'Chưa có biến thể. Hãy thêm size, màu và giá trước khi mở bán.',
        ),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('delete from detail returns to the original filtered list', (
    t,
  ) async {
    var deletes = 0;
    final queries = <Map<String, String>>[];
    await mount(
      t,
      '/admin/products/p1?from=%2Fadmin%2Fproducts%3Fstatus%3Dhidden%26q%3Dshirt',
      (r) async {
        if (r.method == 'DELETE') {
          deletes++;
          return jsonResponse({'id': 'p1', 'deleted': true});
        }
        if (r.url.path.endsWith('/products')) {
          queries.add(r.url.queryParameters);
          return jsonResponse(pageJson([]));
        }
        return jsonResponse(product());
      },
    );
    await click(t, find.byTooltip('Thao tác sản phẩm'));
    await click(t, find.text('Xóa sản phẩm'));
    await click(t, find.widgetWithText(FilledButton, 'Xác nhận xóa'));
    expect(deletes, 1);
    expect(queries.last, containsPair('status', 'hidden'));
    expect(queries.last, containsPair('q', 'shirt'));
    expect(find.text('Quản lý sản phẩm'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  for (final suffix in ['', '/edit']) {
    testWidgets('missing product $suffix provides a safe way back', (t) async {
      await mount(
        t,
        '/admin/products/missing$suffix',
        (r) async => jsonResponse({
          'error': {'code': 'NOT_FOUND', 'message': 'Missing'},
        }, 404),
      );
      expect(find.text('Không tìm thấy sản phẩm'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }
}
