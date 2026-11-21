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

Map<String, dynamic> collection() => {
  'id': 'c1',
  'title': 'Bộ sưu tập áo đầm tiếng Việt có tên rất dài',
  'slug': 'ao-dam',
  'description': 'Các thiết kế được chọn theo phong cách.',
  'style': 'Tối giản',
  'active': true,
  'position': 0,
  'version': 4,
  'coverProductId': null,
  'cover': null,
  'coverFallback': false,
  'productCount': 5,
  'totalProducts': 12,
  'createdAt': '2026-10-01T00:00:00Z',
  'updatedAt': '2026-10-24T01:00:00Z',
  'recentProducts': [
    {
      'id': 'p1',
      'name': 'Áo cotton',
      'active': true,
      'published': true,
      'images': [],
    },
  ],
};
void main() {
  Future<ProviderContainer> mount(
    WidgetTester t,
    String path,
    Future<http.Response> Function(http.Request) handle, {
    double width = 1440,
    double scale = 1,
    String role = 'ADMIN',
    Duration timeout = const Duration(seconds: 15),
  }) async {
    t.view.physicalSize = Size(width, 1000);
    t.view.devicePixelRatio = 1;
    t.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    final api = ApiClient(
      baseUrl: 'http://localhost/api/v1',
      timeout: timeout,
      client: MockClient((r) async {
        if (r.url.path.endsWith('/login')) {
          final s = sessionJson();
          (s['user'] as Map)['role'] = role;
          return jsonResponse(s);
        }
        if (r.url.path.endsWith('/summary')) {
          return jsonResponse({
            'total': 23,
            'published': 5,
            'hidden': 10,
            'waiting': 8,
          });
        }
        if (r.url.path.endsWith('/styles')) {
          return jsonResponse({
            'styles': ['Tối giản', 'Phong cách mới'],
          });
        }
        if (r.url.path.endsWith('/logout')) return jsonResponse({});
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
    return scope;
  }

  Future<void> click(WidgetTester t, Finder f) async {
    await t.ensureVisible(f);
    await t.pumpAndSettle();
    await t.tap(f);
    await t.pumpAndSettle();
  }

  Finder field(String label) => find.widgetWithText(TextFormField, label);
  for (final (width, scale) in [
    (375.0, 1.0),
    (768.0, 1.0),
    (1440.0, 1.0),
    (1920.0, 1.0),
    (2560.0, 1.0),
    (375.0, 2.0),
  ]) {
    testWidgets('collection list and editor fit $width at $scale', (t) async {
      await mount(
        t,
        '/admin/collections',
        (r) async => jsonResponse(pageJson([collection()])),
        width: width,
        scale: scale,
      );
      expect(find.text('Quản lý bộ sưu tập'), findsOneWidget);
      await click(t, find.text('Chỉnh sửa'));
      expect(find.text('Sửa bộ sưu tập'), findsOneWidget);
      expect(t.takeException(), isNull);
      await click(t, find.text('Đóng'));
      expect(find.text('Quản lý bộ sưu tập'), findsOneWidget);
    });
    testWidgets('collection detail fits $width at $scale', (t) async {
      await mount(
        t,
        '/admin/collections/c1',
        (r) async => jsonResponse(collection()),
        width: width,
        scale: scale,
      );
      expect(find.text('5 công khai / 12 sản phẩm'), findsOneWidget);
      expect(find.text('Xem sản phẩm chưa công khai'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }
  testWidgets('URL search resets paging and preserves server filters', (
    t,
  ) async {
    final queries = <Map<String, String>>[];
    await mount(
      t,
      '/admin/collections?q=ao&status=hidden&sort=title_desc&page=2',
      (r) async {
        queries.add(r.url.queryParameters);
        return jsonResponse(
          pageJson(
            [collection()],
            page: int.parse(r.url.queryParameters['page'] ?? '1'),
            total: 61,
          ),
        );
      },
    );
    await click(t, find.text('Trang sau'));
    expect(queries.last, containsPair('page', '3'));
    expect(queries.last, containsPair('status', 'hidden'));
    await t.ensureVisible(field('Tìm kiếm bộ sưu tập'));
    await t.enterText(field('Tìm kiếm bộ sưu tập'), 'Đầm');
    await click(t, find.text('Tìm kiếm'));
    expect(queries.last, containsPair('page', '1'));
    expect(queries.last, containsPair('q', 'Đầm'));
    await click(t, find.text('Xóa bộ lọc').first);
    expect(queries.last, {'page': '1', 'limit': '10'});
  });
  testWidgets('list menu opens confirmation without changing data on cancel', (
    t,
  ) async {
    var writes = 0;
    await mount(t, '/admin/collections', (r) async {
      if (r.method != 'GET') writes++;
      return jsonResponse(pageJson([collection()]));
    }, width: 375);
    final menu = find.byTooltip('Thao tác khác: ${collection()['title']}');
    await click(t, menu);
    await click(t, find.text('Ẩn bộ sưu tập'));
    expect(find.text('Xác nhận'), findsOneWidget);
    await click(t, find.text('Đóng'));
    await click(t, menu);
    await click(t, find.text('Xóa bộ sưu tập'));
    expect(find.text('Xác nhận xóa'), findsOneWidget);
    await click(t, find.text('Đóng'));
    expect(writes, 0);
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'create validates, suggests slug, retries corrected duplicates and writes once',
    (t) async {
      final writes = <Map<String, dynamic>>[];
      final pending = Completer<http.Response>();
      await mount(t, '/admin/collections', (r) async {
        if (r.method == 'GET') return jsonResponse(pageJson([]));
        writes.add(jsonDecode(r.body));
        if (writes.length == 1) {
          return jsonResponse({
            'error': {'code': 'DUPLICATE_COLLECTION'},
          }, 409);
        }
        return pending.future;
      });
      await click(t, find.text('Thêm bộ sưu tập'));
      await click(t, find.text('Lưu thay đổi'));
      expect(writes, isEmpty);
      await t.enterText(field('Tên bộ sưu tập'), 'Áo Đầm Mùa Thu');
      expect(
        t.widget<TextFormField>(field('Đường dẫn')).controller!.text,
        'ao-dam-mua-thu',
      );
      await t.ensureVisible(field('Phong cách'));
      await t.enterText(field('Phong cách'), 'Tối giản');
      await click(t, find.text('Lưu thay đổi'));
      expect(
        find.textContaining('Đường dẫn hoặc phong cách đã có'),
        findsOneWidget,
      );
      await t.ensureVisible(field('Phong cách'));
      await t.enterText(field('Phong cách'), 'Phong cách mới');
      await t.tap(find.text('Lưu thay đổi'));
      await t.pump();
      await t.tap(find.text('Lưu thay đổi'));
      await t.pump();
      expect(writes.length, 2);
      expect(writes.last, containsPair('active', false));
      expect(writes.last, containsPair('coverProductId', null));
      pending.complete(jsonResponse({'id': 'new'}));
      await t.pumpAndSettle();
      expect(find.text('Đã thêm bộ sưu tập.'), findsOneWidget);
    },
  );
  testWidgets(
    'cover picker uses paginated style query and saves selected cover and version',
    (t) async {
      final requests = <Map<String, String>>[];
      Map<String, dynamic>? saved;
      await mount(t, '/admin/collections/c1', (r) async {
        if (r.url.path.endsWith('/covers')) {
          requests.add(r.url.queryParameters);
          return jsonResponse({
            'items': [
              {
                'id': 'p2',
                'name': 'Áo làm bìa',
                'images': [
                  {'url': 'assets/images/shirt.jpg', 'alt': 'Áo'},
                ],
              },
            ],
            'total': 9,
            'page': int.parse(r.url.queryParameters['page'] ?? '1'),
            'limit': 8,
          });
        }
        if (r.method == 'PATCH') saved = jsonDecode(r.body);
        return jsonResponse(collection());
      });
      await click(t, find.text('Sửa bộ sưu tập'));
      await click(t, find.text('Chọn ảnh bìa').first);
      expect(requests.last, containsPair('style', 'Tối giản'));
      await click(t, find.text('Trang sau'));
      expect(requests.last, containsPair('page', '2'));
      await t.enterText(field('Tìm sản phẩm làm bìa'), 'áo');
      await click(t, find.byTooltip('Tìm ảnh bìa'));
      expect(requests.last, containsPair('q', 'áo'));
      expect(requests.last, containsPair('page', '1'));
      await click(t, find.text('Áo làm bìa'));
      await click(t, find.text('Lưu thay đổi'));
      expect(saved, containsPair('coverProductId', 'p2'));
      expect(saved, containsPair('expectedVersion', 4));
      expect(saved!.containsKey('slug'), false);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'deletion cancels, sends one versioned request and returns to filtered list',
    (t) async {
      final pending = Completer<http.Response>();
      var writes = 0;
      final reads = <Uri>[];
      await mount(
        t,
        '/admin/collections/c1?from=%2Fadmin%2Fcollections%3Fq%3Dao',
        (r) async {
          if (r.method == 'DELETE') {
            writes++;
            expect(jsonDecode(r.body), {'expectedVersion': 4});
            return pending.future;
          }
          reads.add(r.url);
          return jsonResponse(
            r.url.path.endsWith('/collections') ? pageJson([]) : collection(),
          );
        },
        width: 375,
      );
      await click(t, find.text('Xóa bộ sưu tập'));
      await click(t, find.text('Đóng'));
      expect(writes, 0);
      await click(t, find.text('Xóa bộ sưu tập'));
      await t.ensureVisible(find.text('Xác nhận xóa'));
      await t.tap(find.text('Xác nhận xóa'));
      await t.pump();
      await t.tap(find.text('Xác nhận xóa'));
      await t.pump();
      expect(writes, 1);
      pending.complete(jsonResponse({'deleted': true}));
      await t.pumpAndSettle();
      expect(find.text('Quản lý bộ sưu tập'), findsOneWidget);
      expect(reads.last.queryParameters['q'], 'ao');
    },
  );
  testWidgets(
    'publication confirmation retains version and stale mutation requires reload',
    (t) async {
      var writes = 0;
      Map<String, dynamic>? body;
      await mount(t, '/admin/collections/c1', (r) async {
        if (r.method == 'PATCH') {
          writes++;
          body = jsonDecode(r.body);
          return jsonResponse({
            'error': {'code': 'COLLECTION_CHANGED'},
          }, 409);
        }
        return jsonResponse(collection());
      });
      await click(t, find.text('Ẩn bộ sưu tập'));
      expect(writes, 0);
      await click(t, find.text('Xác nhận'));
      expect(body, {'active': false, 'expectedVersion': 4});
      expect(find.text('Tải lại dữ liệu'), findsOneWidget);
      expect(find.text('Xác nhận'), findsNothing);
      await click(t, find.text('Tải lại dữ liệu'));
      expect(writes, 1);
    },
  );
  testWidgets(
    'timeout followed by late creation refreshes list after dialog closes',
    (t) async {
      final pending = Completer<http.Response>();
      var committed = false, writes = 0;
      await mount(t, '/admin/collections', (r) async {
        if (r.method == 'GET') {
          return jsonResponse(pageJson(committed ? [collection()] : []));
        }
        writes++;
        return pending.future;
      }, timeout: const Duration(milliseconds: 250));
      await click(t, find.text('Thêm bộ sưu tập'));
      await t.enterText(field('Tên bộ sưu tập'), 'Áo mới');
      await t.ensureVisible(field('Phong cách'));
      await t.enterText(field('Phong cách'), 'Tối giản');
      await t.tap(find.text('Lưu thay đổi'));
      await t.pump(const Duration(milliseconds: 300));
      await t.pumpAndSettle();
      await click(t, find.text('Đóng'));
      committed = true;
      pending.complete(jsonResponse({'id': 'new'}));
      await t.pumpAndSettle();
      expect(find.text(collection()['title']), findsOneWidget);
      expect(writes, 1);
      expect(find.text('Đã thêm bộ sưu tập.'), findsNothing);
    },
  );
  testWidgets('logout while editor is open removes mutation controls', (
    t,
  ) async {
    var writes = 0;
    final scope = await mount(t, '/admin/collections', (r) async {
      if (r.method != 'GET') writes++;
      return jsonResponse(pageJson([collection()]));
    });
    await click(t, find.text('Chỉnh sửa'));
    await scope.read(adminAccountProvider.notifier).signOut();
    await t.pumpAndSettle();
    expect(find.text('Lưu thay đổi'), findsNothing);
    expect(writes, 0);
    expect(t.takeException(), isNull);
  });
  testWidgets('retry, empty results and unknown IDs offer recovery', (t) async {
    var reads = 0;
    await mount(t, '/admin/collections', (r) async {
      reads++;
      return reads == 1
          ? jsonResponse({
              'error': {'code': 'INTERNAL', 'message': 'Error'},
            }, 500)
          : jsonResponse(pageJson([], total: 0));
    });
    await click(t, find.text('Thử tải lại'));
    expect(find.text('Chưa có bộ sưu tập phù hợp'), findsOneWidget);
  });
  testWidgets('404 detail cannot mutate a missing collection', (t) async {
    await mount(
      t,
      '/admin/collections/c1',
      (r) async => jsonResponse({
        'error': {'code': 'NOT_FOUND'},
      }, 404),
    );
    expect(find.text('Không tìm thấy bộ sưu tập'), findsOneWidget);
    expect(find.text('Sửa bộ sưu tập'), findsNothing);
    expect(find.text('Xóa bộ sưu tập'), findsNothing);
  });
  testWidgets('missing cover with no replacement explains waiting state', (
    t,
  ) async {
    await mount(
      t,
      '/admin/collections/c1',
      (r) async => jsonResponse({
        ...collection(),
        'coverFallback': true,
        'coverProductId': 'old',
        'cover': null,
        'productCount': 0,
      }),
    );
    expect(find.text('Chờ sản phẩm công khai'), findsOneWidget);
    expect(find.text('Xem tại cửa hàng'), findsNothing);
    expect(
      find.textContaining('chưa có sản phẩm công khai để thay thế'),
      findsOneWidget,
    );
    await click(t, find.text('Sửa bộ sưu tập'));
    expect(
      find.textContaining('chưa có sản phẩm công khai để thay thế'),
      findsNWidgets(2),
    );
    expect(t.takeException(), isNull);
  });
  testWidgets('warehouse role never reads collection data', (t) async {
    var reads = 0;
    await mount(t, '/admin/collections', (r) async {
      reads++;
      return jsonResponse({});
    }, role: 'WAREHOUSE');
    expect(reads, 0);
    expect(find.text('Thêm bộ sưu tập'), findsNothing);
  });
}
