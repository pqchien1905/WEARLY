import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nep_storefront/app/app.dart';
import 'package:nep_storefront/app/account_state.dart';
import 'package:nep_storefront/app/api_providers.dart';
import 'package:nep_storefront/app/providers.dart';
import 'package:nep_storefront/core/network/api_client.dart';
import 'remote_account_test.dart' show sessionJson;
import 'remote_commerce_test.dart' show orderJson;
import 'remote_session_test.dart' show jsonResponse;
import 'tryon_replacement_test.dart' show PhotoPicker;

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
    Future<http.Response> Function(http.Request)? publicHandle,
  }) async {
    final api = ApiClient(
      baseUrl: 'http://localhost/api/v1',
      client: MockClient((r) async {
        if (r.url.path.endsWith('/login')) {
          final session = sessionJson();
          (session['user'] as Map)['role'] = role;
          return jsonResponse(session);
        }
        if (r.url.path.endsWith('/auth/logout')) return jsonResponse({});
        return handle(r);
      }),
    );
    final shopper = ApiClient(
      baseUrl: 'http://localhost/api/v1',
      client: MockClient(
        (r) async => publicHandle != null && !r.url.path.endsWith('/auth/login')
            ? publicHandle(r)
            : jsonResponse(sessionJson()),
      ),
    );
    final container = ProviderContainer(
      overrides: [
        remoteApiProvider.overrideWithValue(true),
        apiClientProvider.overrideWithValue(shopper),
        sessionTokensProvider.overrideWithValue(shopper.tokens),
        adminApiClientProvider.overrideWithValue(api),
        adminSessionTokensProvider.overrideWithValue(api.tokens),
      ],
    );
    addTearDown(() {
      container.dispose();
      api.close();
      shopper.close();
    });
    if (role != null) {
      await container
          .read(
            role == 'ADMIN'
                ? adminAccountProvider.notifier
                : accountProvider.notifier,
          )
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

  testWidgets(
    'a stale gallery full rejection unlocks removal after canonical reload',
    (tester) async {
      final original = FileSelectorPlatform.instance;
      addTearDown(() => FileSelectorPlatform.instance = original);
      final photo = XFile.fromData(
        Uint8List.fromList([255, 216, 255, 0]),
        name: 'photo.jpg',
      );
      FileSelectorPlatform.instance = PhotoPicker(photo, photo);
      final server = adminProduct();
      final sample = (server['images'] as List).single;
      server['images'] = List.generate(19, (_) => sample);
      var uploads = 0;
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
        if (r.method == 'POST') {
          uploads++;
          server['images'] = List.generate(20, (_) => sample);
          return jsonResponse({
            'error': {'code': 'GALLERY_FULL'},
          }, 409);
        }
        return jsonResponse(server);
      });
      final upload = find.widgetWithText(OutlinedButton, 'Tải ảnh từ máy');
      await tester.ensureVisible(upload);
      await tester.tap(upload);
      await tester.pumpAndSettle();
      expect(uploads, 1);
      expect(find.text('Kiểm tra lại ảnh tải lên'), findsNothing);
      expect(
        find.text(
          'Bộ ảnh đã đủ 20 ảnh. Bỏ bớt ảnh và lưu trước khi tải ảnh mới.',
        ),
        findsOneWidget,
      );
      final remove = find.widgetWithText(TextButton, 'Bỏ ảnh').first;
      await tester.ensureVisible(remove);
      await tester.tap(remove);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextButton, 'Bỏ ảnh'), findsNWidgets(19));
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Lưu thông tin sản phẩm'),
            )
            .onPressed,
        isNotNull,
      );
    },
  );
  for (final uncertain in [false, true]) {
    testWidgets(
      'catalog upload reconciles gallery and baseline (uncertain=$uncertain)',
      (tester) async {
        final original = FileSelectorPlatform.instance;
        addTearDown(() => FileSelectorPlatform.instance = original);
        final photo = XFile.fromData(
          Uint8List.fromList([255, 216, 255, 0]),
          name: 'photo.jpg',
        );
        final picker = PhotoPicker(photo, photo);
        FileSelectorPlatform.instance = picker;
        const image = 'catalog/images/1f9392a7-19a8-4ff2-95e3-1b1d88ee3c25';
        final server = adminProduct();
        final keys = <String>[], bodies = <Map<String, dynamic>>[];
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
          if (r.method == 'POST' && r.url.path.endsWith('/images')) {
            keys.add(r.headers['idempotency-key']!);
            server['images'] = [
              ...adminProduct()['images'] as List,
              {'url': image, 'alt': 'Uploaded', 'color': null},
            ];
            if (uncertain && keys.length == 1) {
              throw http.ClientException('Lost after commit');
            }
            return jsonResponse({'id': image.split('/').last, 'url': image});
          }
          if (r.method == 'PATCH') {
            final body = Map<String, dynamic>.from(jsonDecode(r.body));
            bodies.add(body);
            server.addAll(body);
          }
          return jsonResponse(server);
        });
        final upload = find.widgetWithText(OutlinedButton, 'Tải ảnh từ máy');
        await tester.ensureVisible(upload);
        await tester.tap(upload);
        await tester.pumpAndSettle();
        if (uncertain) {
          final save = tester.widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Lưu thông tin sản phẩm'),
          );
          expect(save.onPressed, isNull);
          final retry = find.widgetWithText(
            OutlinedButton,
            'Kiểm tra lại ảnh tải lên',
          );
          await tester.ensureVisible(retry);
          await tester.tap(retry);
          await tester.pumpAndSettle();
          expect(keys, [keys.first, keys.first]);
        }
        expect(picker.calls, 1);
        expect(find.widgetWithText(TextFormField, image), findsOneWidget);
        final name = find.widgetWithText(TextFormField, 'Tên sản phẩm');
        await tester.ensureVisible(name);
        await tester.enterText(name, 'Tên sau upload');
        final save = find.widgetWithText(
          FilledButton,
          'Lưu thông tin sản phẩm',
        );
        await tester.ensureVisible(save);
        await tester.tap(save);
        await tester.pumpAndSettle();
        expect(bodies.single, {'name': 'Tên sau upload'});
        expect((server['images'] as List).last['url'], image);
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final loseSession in [true, false]) {
    testWidgets(
      'taxonomy refresh survives ${loseSession ? 'logout before response' : 'closing after uncertain response'}',
      (tester) async {
        final response = Completer<http.Response>();
        var name = 'Tên cũ', writes = 0, publicReads = 0;
        final container = await setup(
          tester,
          '/admin/categories',
          (r) async {
            if (r.method == 'GET') {
              return jsonResponse(
                pageJson([
                  {
                    'id': 'c1',
                    'name': name,
                    'slug': 'stable',
                    '_count': {'products': 1},
                  },
                ]),
              );
            }
            writes++;
            name =
                'Tên mới'; // The server commits before the client learns the outcome.
            return response.future;
          },
          publicHandle: (r) async {
            expect(r.url.path, '/api/v1/categories');
            publicReads++;
            return jsonResponse([
              {'slug': 'stable', 'name': name},
            ]);
          },
        );
        expect(
          (await tester.runAsync(
            () => container.read(catalogCategoriesProvider.future),
          ))!['stable'],
          'Tên cũ',
        );
        await tester.tap(find.byTooltip('Đổi tên Tên cũ'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Tên hiển thị'),
          'Tên mới',
        );
        await tester.tap(find.text('Lưu thay đổi'));
        await tester.pump();
        if (loseSession) {
          await container.read(adminAccountProvider.notifier).signOut();
          await tester.pumpAndSettle();
          response.complete(
            jsonResponse({'id': 'c1', 'name': name, 'slug': 'stable'}),
          );
        } else {
          response.completeError(
            http.ClientException('Response lost after commit'),
          );
        }
        await tester.pumpAndSettle();
        if (!loseSession) {
          await tester.tap(find.text('Đóng'));
          await tester.pumpAndSettle();
        }
        expect(
          (await tester.runAsync(
            () => container.read(catalogCategoriesProvider.future),
          ))!['stable'],
          'Tên mới',
        );
        expect(publicReads, greaterThan(1));
        expect(writes, 1);
      },
    );
  }
  for (final role in [null, 'CUSTOMER']) {
    testWidgets('taxonomy gate blocks $role', (tester) async {
      var reads = 0;
      await setup(tester, '/admin/categories', (r) async {
        reads++;
        return jsonResponse({});
      }, role: role);
      expect(
        find.widgetWithText(FilledButton, 'Đăng nhập quản trị'),
        findsOneWidget,
      );
      expect(reads, 0);
    });
    testWidgets('admin gate blocks $role without loading private data', (
      tester,
    ) async {
      var reads = 0;
      await setup(tester, '/admin/products', (r) async {
        reads++;
        return jsonResponse({});
      }, role: role);
      expect(
        find.widgetWithText(FilledButton, 'Đăng nhập quản trị'),
        findsOneWidget,
      );
      expect(reads, 0);
    });
  }
  for (final kind in ['categories', 'brands']) {
    testWidgets('$kind create, validate and rename on mobile; stable slug', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(375, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final rows = <Map<String, dynamic>>[];
      final writes = <Map<String, dynamic>>[];
      await setup(tester, '/admin/$kind', (r) async {
        if (r.method == 'GET') {
          return jsonResponse(pageJson(rows, total: rows.length));
        }
        final body = jsonDecode(r.body) as Map<String, dynamic>;
        writes.add(body);
        if (r.method == 'POST') {
          rows.add({
            'id': 'new-id',
            ...body,
            '_count': {'products': 0},
          });
        }
        if (r.method == 'PATCH') rows.first['name'] = body['name'];
        return jsonResponse(rows.first);
      });
      await tester.tap(
        find.text(kind == 'categories' ? 'Thêm danh mục' : 'Thêm thương hiệu'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lưu thay đổi'));
      await tester.pumpAndSettle();
      expect(writes, isEmpty);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Tên hiển thị'),
        '  Mùa thu  ',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Đường dẫn'),
        'mua-thu',
      );
      await tester.tap(find.text('Lưu thay đổi'));
      await tester.pumpAndSettle();
      expect(writes.single, {'name': 'Mùa thu', 'slug': 'mua-thu'});
      expect(find.text('Mùa thu'), findsOneWidget);
      await tester.tap(find.byTooltip('Đổi tên Mùa thu'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextFormField, 'Đường dẫn'), findsNothing);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Tên hiển thị'),
        'Thu đông',
      );
      await tester.tap(find.text('Lưu thay đổi'));
      await tester.pumpAndSettle();
      expect(writes.last, {'name': 'Thu đông', 'expectedName': 'Mùa thu'});
      expect(find.text('Thu đông'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('taxonomy pagination, conflict reload and session loss', (
    tester,
  ) async {
    var writes = 0, reads = 0;
    final container = await setup(tester, '/admin/categories', (r) async {
      if (r.method == 'GET') {
        reads++;
        final page = int.parse(r.url.queryParameters['page']!);
        return jsonResponse(
          pageJson(
            [
              {
                'id': 'c$page',
                'name': 'Danh mục $page',
                'slug': 'c$page',
                '_count': {'products': 2},
              },
            ],
            page: page,
            total: 21,
          ),
        );
      }
      writes++;
      return jsonResponse({
        'error': {'code': 'VERSION_CONFLICT', 'message': 'Tên đã thay đổi'},
      }, 409);
    });
    await tester.tap(find.text('Trang sau'));
    await tester.pumpAndSettle();
    expect(find.text('Danh mục 2'), findsOneWidget);
    await tester.tap(find.byTooltip('Đổi tên Danh mục 2'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Tên hiển thị'),
      'Mới',
    );
    await tester.tap(find.text('Lưu thay đổi'));
    await tester.pumpAndSettle();
    expect(writes, 1);
    expect(find.text('Lưu thay đổi'), findsNothing);
    final beforeReload = reads;
    await tester.tap(find.text('Tải lại dữ liệu'));
    await tester.pumpAndSettle();
    expect(reads, greaterThan(beforeReload));
    await tester.tap(find.byTooltip('Đổi tên Danh mục 2'));
    await tester.pumpAndSettle();
    await container.read(adminAccountProvider.notifier).signOut();
    await tester.pumpAndSettle();
    expect(find.text('Lưu thay đổi'), findsNothing);
    expect(writes, 1);
  });
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
      await container.read(adminAccountProvider.notifier).signOut();
      await tester.pumpAndSettle();
      expect(find.text('Áo trang hai'), findsNothing);
      expect(
        find.widgetWithText(FilledButton, 'Đăng nhập quản trị'),
        findsOneWidget,
      );
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
