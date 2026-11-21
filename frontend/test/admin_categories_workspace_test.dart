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
import 'package:nep_storefront/features/admin/remote/taxonomy_actions.dart';
import 'remote_account_test.dart' show sessionJson;
import 'remote_session_test.dart' show jsonResponse;
import 'remote_admin_ui_test.dart' show pageJson;

Map<String, dynamic> category() => {
  'id': 'c1',
  'name': 'Áo đầm tiếng Việt với tên danh mục rất dài',
  'slug': 'ao-dam-tieng-viet',
  '_count': {'products': 12},
  'publishedProducts': 5,
  'createdAt': '2026-10-01T00:00:00Z',
  'updatedAt': '2026-10-24T01:00:00Z',
};
void main() {
  Future<void> mount(
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
        if (r.url.path.endsWith('/categories/summary')) {
          return jsonResponse({
            'total': 23,
            'empty': 3,
            'published': 15,
            'products': 80,
            'publishedProducts': 50,
          });
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

  Future<void> click(WidgetTester t, Finder finder) async {
    await t.ensureVisible(finder);
    await t.pumpAndSettle();
    await t.tap(finder);
    await t.pumpAndSettle();
  }

  test(
    'Vietnamese slug suggestion handles decomposed accents, punctuation and length',
    () {
      expect(taxonomySlug('  ÁO ĐẦM & Đồ Bé  '), 'ao-dam-do-be');
      expect(taxonomySlug('A\u0301o Đo\u0302ng'), 'ao-dong');
      expect(taxonomySlug('🎉 / ---'), '');
      expect(taxonomySlug('a' * 101).length, 100);
    },
  );
  for (final size in [
    (375.0, 1.0),
    (768.0, 1.0),
    (1440.0, 1.0),
    (375.0, 2.0),
  ]) {
    testWidgets('responsive categories ${size.$1} scale ${size.$2}', (t) async {
      await mount(
        t,
        '/admin/categories',
        (r) async => jsonResponse(pageJson([category()])),
        width: size.$1,
        scale: size.$2,
      );
      expect(find.text('Quản lý danh mục'), findsOneWidget);
      await click(t, find.byTooltip('Đổi tên ${category()['name']}'));
      expect(find.text('Đổi tên danh mục'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Đường dẫn'), findsNothing);
      expect(t.takeException(), isNull);
    });
  }
  testWidgets(
    'URL filters reach server, search resets page, pagination keeps filters',
    (t) async {
      final queries = <Map<String, String>>[];
      await mount(
        t,
        '/admin/categories?q=ao&coverage=populated&sort=products_desc&page=2',
        (r) async {
          queries.add(r.url.queryParameters);
          return jsonResponse(
            pageJson(
              [category()],
              page: int.parse(r.url.queryParameters['page'] ?? '1'),
              total: 41,
            ),
          );
        },
      );
      expect(queries.last, containsPair('coverage', 'populated'));
      expect(queries.last, containsPair('sort', 'products_desc'));
      await click(t, find.text('Trang sau'));
      expect(queries.last['page'], '3');
      expect(queries.last['q'], 'ao');
      await t.ensureVisible(
        find.widgetWithText(TextFormField, 'Tìm kiếm danh mục'),
      );
      await t.enterText(
        find.widgetWithText(TextFormField, 'Tìm kiếm danh mục'),
        'Đầm mới',
      );
      await click(t, find.text('Tìm kiếm'));
      expect(queries.last['q'], 'Đầm mới');
      expect(queries.last['page'], '1');
      await click(t, find.text('Xóa bộ lọc').first);
      expect(queries.last, {'page': '1', 'limit': '10'});
    },
  );
  testWidgets(
    'create auto slug, duplicate slug editable, no repeated in-flight write',
    (t) async {
      final writes = <Map<String, dynamic>>[];
      final pending = Completer<http.Response>();
      await mount(t, '/admin/categories', (r) async {
        if (r.method == 'GET') {
          return jsonResponse(
            r.url.path.endsWith('/categories')
                ? pageJson([], total: 0)
                : category(),
          );
        }
        writes.add(jsonDecode(r.body));
        if (writes.length == 1) {
          return jsonResponse({
            'error': {'code': 'TAXONOMY_SLUG_EXISTS', 'message': 'Duplicate'},
          }, 409);
        }
        return pending.future;
      });
      await click(t, find.text('Thêm danh mục'));
      await click(t, find.text('Lưu thay đổi'));
      expect(writes, isEmpty);
      await t.enterText(
        find.widgetWithText(TextFormField, 'Tên hiển thị'),
        'Áo Đầm',
      );
      final slug = find.widgetWithText(TextFormField, 'Đường dẫn');
      expect(t.widget<TextFormField>(slug).controller!.text, 'ao-dam');
      await click(t, find.text('Lưu thay đổi'));
      expect(
        find.text('Đường dẫn đã được sử dụng. Vui lòng chọn đường dẫn khác.'),
        findsOneWidget,
      );
      await t.enterText(slug, 'ao-dam-moi');
      await t.enterText(
        find.widgetWithText(TextFormField, 'Tên hiển thị'),
        'Tên khác',
      );
      expect(t.widget<TextFormField>(slug).controller!.text, 'ao-dam-moi');
      await t.tap(find.text('Lưu thay đổi'));
      await t.pump();
      await t.tap(find.text('Lưu thay đổi'));
      await t.pump();
      expect(writes.length, 2);
      pending.complete(jsonResponse({'id': 'new', ...writes.last}));
      await t.pumpAndSettle();
      expect(find.text('Đã thêm danh mục.'), findsOneWidget);
    },
  );
  testWidgets('detail exposes real counts and sends version on rename', (
    t,
  ) async {
    final row = category();
    Map<String, dynamic>? body;
    await mount(t, '/admin/categories/c1?from=%2Fadmin%2Fcategories%3Fq%3Dao', (
      r,
    ) async {
      if (r.method == 'PATCH') {
        body = jsonDecode(r.body);
        row['name'] = body!['name'];
      }
      return jsonResponse(row);
    });
    expect(find.text('12 sản phẩm thuộc danh mục'), findsOneWidget);
    expect(find.text('Xem tại cửa hàng'), findsOneWidget);
    await click(t, find.text('Đổi tên danh mục'));
    await t.enterText(
      find.widgetWithText(TextFormField, 'Tên hiển thị'),
      'Tên mới',
    );
    await click(t, find.text('Lưu thay đổi'));
    expect(body!['expectedUpdatedAt'], '2026-10-24T01:00:00Z');
    expect(body!['expectedName'], category()['name']);
    expect(body!.containsKey('slug'), false);
    expect(find.text('Tên mới'), findsOneWidget);
  });
  testWidgets('list failure retries and empty result has clear recovery', (
    t,
  ) async {
    var reads = 0;
    await mount(t, '/admin/categories', (r) async {
      reads++;
      return reads == 1
          ? jsonResponse({
              'error': {'code': 'INTERNAL', 'message': 'Unavailable'},
            }, 500)
          : jsonResponse(pageJson([], total: 0));
    });
    await click(t, find.text('Thử tải lại'));
    expect(find.text('Không có danh mục phù hợp'), findsOneWidget);
    expect(reads, 2);
  });
  testWidgets('warehouse role cannot read or mutate categories', (t) async {
    var calls = 0;
    await mount(t, '/admin/categories', (r) async {
      calls++;
      return jsonResponse({});
    }, role: 'WAREHOUSE');
    expect(calls, 0);
    expect(find.text('Thêm danh mục'), findsNothing);
  });
  testWidgets(
    'late completion after timeout refreshes canonical data without replay',
    (t) async {
      final pending = Completer<http.Response>();
      var committed = false, writes = 0;
      await mount(t, '/admin/categories', (r) async {
        if (r.method == 'GET') {
          return jsonResponse(
            pageJson(committed ? [category()] : [], total: committed ? 1 : 0),
          );
        }
        writes++;
        return pending.future;
      }, timeout: const Duration(milliseconds: 250));
      await click(t, find.text('Thêm danh mục'));
      await t.enterText(
        find.widgetWithText(TextFormField, 'Tên hiển thị'),
        'Áo mới',
      );
      await t.tap(find.text('Lưu thay đổi'));
      await t.pump(const Duration(milliseconds: 300));
      await t.pumpAndSettle();
      expect(find.text('Tải lại dữ liệu'), findsOneWidget);
      await click(t, find.text('Đóng'));
      committed = true;
      pending.complete(jsonResponse(category()));
      await t.pumpAndSettle();
      expect(find.text(category()['name']), findsOneWidget);
      expect(writes, 1);
      expect(find.text('Đã thêm danh mục.'), findsNothing);
    },
  );

  testWidgets(
    'deletion requires confirmation once and detail returns to its filtered list',
    (t) async {
      var writes = 0, removed = false;
      final pending = Completer<http.Response>();
      final row = {
        ...category(),
        '_count': {'products': 0},
        'publishedProducts': 0,
      };
      final reads = <Uri>[];
      await mount(
        t,
        '/admin/categories/c1?from=%2Fadmin%2Fcategories%3Fq%3Dao',
        (r) async {
          if (r.method == 'DELETE') {
            writes++;
            expect(jsonDecode(r.body), {'expectedUpdatedAt': row['updatedAt']});
            return pending.future;
          }
          reads.add(r.url);
          if (r.url.path.endsWith('/categories')) {
            return jsonResponse(pageJson([], total: 0));
          }
          return removed
              ? jsonResponse({
                  'error': {'code': 'NOT_FOUND', 'message': 'Missing'},
                }, 404)
              : jsonResponse(row);
        },
        width: 375,
      );
      await click(t, find.text('Xóa danh mục'));
      expect(writes, 0);
      expect(find.textContaining('Xóa vĩnh viễn'), findsOneWidget);
      await click(t, find.text('Đóng'));
      expect(writes, 0);
      await click(t, find.text('Xóa danh mục'));
      await t.ensureVisible(find.text('Xác nhận xóa'));
      await t.tap(find.text('Xác nhận xóa'));
      await t.pump();
      await t.tap(find.text('Xác nhận xóa'));
      await t.pump();
      expect(writes, 1);
      removed = true;
      pending.complete(jsonResponse({'id': 'c1', 'deleted': true}));
      await t.pumpAndSettle();
      expect(find.text('Quản lý danh mục'), findsOneWidget);
      expect(reads.last.queryParameters['q'], 'ao');
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'populated category explains protection without issuing deletion',
    (t) async {
      var writes = 0;
      await mount(t, '/admin/categories/c1', (r) async {
        if (r.method != 'GET') writes++;
        return jsonResponse(category());
      });
      await click(t, find.text('Xóa danh mục'));
      expect(find.text('Danh mục đang có sản phẩm'), findsOneWidget);
      expect(find.text('Xác nhận xóa'), findsNothing);
      expect(writes, 0);
      await click(t, find.text('Đóng'));
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Chi tiết danh mục'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );

  for (final code in ['CATEGORY_IN_USE', 'VERSION_CONFLICT']) {
    testWidgets('delete $code requires reload and never repeats the request', (
      t,
    ) async {
      var writes = 0;
      final row = {
        ...category(),
        '_count': {'products': 0},
        'publishedProducts': 0,
      };
      await mount(t, '/admin/categories/c1', (r) async {
        if (r.method == 'DELETE') {
          writes++;
          return jsonResponse({
            'error': {'code': code, 'message': 'Changed'},
          }, 409);
        }
        return jsonResponse(row);
      });
      await click(t, find.text('Xóa danh mục'));
      await click(t, find.text('Xác nhận xóa'));
      expect(writes, 1);
      expect(find.text('Xác nhận xóa'), findsNothing);
      await click(t, find.text('Tải lại dữ liệu'));
      expect(writes, 1);
      expect(find.byType(AlertDialog), findsNothing);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets(
    'server-clamped page replaces URL and preserves filters after deletion',
    (t) async {
      final requests = <Uri>[];
      await mount(t, '/admin/categories?q=ao&coverage=empty&page=99', (
        r,
      ) async {
        requests.add(r.url);
        return jsonResponse(pageJson([category()], total: 21, page: 2));
      });
      expect(requests.last.queryParameters, containsPair('page', '2'));
      expect(requests.last.queryParameters, containsPair('q', 'ao'));
      expect(requests.last.queryParameters, containsPair('coverage', 'empty'));
      expect(t.takeException(), isNull);
    },
  );

  testWidgets('missing category offers recovery without mutation controls', (
    t,
  ) async {
    await mount(
      t,
      '/admin/categories/c1',
      (r) async => jsonResponse({
        'error': {'code': 'NOT_FOUND', 'message': 'Missing'},
      }, 404),
    );
    expect(find.text('Không tìm thấy danh mục'), findsOneWidget);
    expect(find.text('Đổi tên danh mục'), findsNothing);
    expect(find.text('Xóa danh mục'), findsNothing);
    expect(t.takeException(), isNull);
  });

  for (final (width, scale) in [(375.0, 2.0), (768.0, 1.0), (1440.0, 1.0)]) {
    testWidgets('category detail coverage and products fit $width at $scale', (
      t,
    ) async {
      await mount(
        t,
        '/admin/categories/c1',
        (r) async => jsonResponse({
          ...category(),
          'recentProducts': [
            for (var i = 0; i < 6; i++)
              {
                'id': 'p$i',
                'name':
                    'Áo linen dài tay màu trắng với tên sản phẩm rất dài $i',
                'active': i > 0,
                'published': i > 1,
                'images': [],
              },
          ],
        }),
        width: width,
        scale: scale,
      );
      expect(find.text('5 công khai'), findsOneWidget);
      expect(find.text('7 chưa công khai'), findsOneWidget);
      expect(find.text('Xem chưa công khai'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }
}
