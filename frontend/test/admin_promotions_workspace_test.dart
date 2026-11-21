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
import 'package:nep_storefront/features/admin/remote/promotions_page.dart';
import 'remote_account_test.dart' show sessionJson;
import 'remote_session_test.dart' show jsonResponse;

Map<String, dynamic> promotion() => {
  'id': 'c1',
  'code': 'SUMMER_2026',
  'kind': 'PERCENT',
  'amount': '15',
  'minSubtotal': '250000',
  'maxDiscount': '100000',
  'usageLimit': 10,
  'perUserLimit': 1,
  'active': true,
  'status': 'active',
  'startsAt': null,
  'expiresAt': null,
  'version': 4,
  'historyCount': 0,
  'usedCount': 0,
  'canDelete': true,
  'discountTotal': '0',
  'createdAt': '2026-10-01T00:00:00Z',
  'updatedAt': '2026-10-24T00:00:00Z',
};
Map<String, dynamic> page(List items, {int total = 1, int page = 1}) => {
  'items': items,
  'total': total,
  'page': page,
  'limit': 10,
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
            'active': 5,
            'scheduled': 3,
            'expired': 2,
            'exhausted': 2,
            'inactive': 11,
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

  Finder field(String s) => find.widgetWithText(TextFormField, s);
  Future<void> fill(WidgetTester t, String label, String value) async {
    await t.ensureVisible(field(label));
    await t.enterText(field(label), value);
  }

  for (final (width, scale) in [
    (375.0, 1.0),
    (768.0, 1.0),
    (1024.0, 1.0),
    (1440.0, 1.0),
    (1920.0, 1.0),
    (2560.0, 1.0),
    (375.0, 1.5),
    (375.0, 2.0),
  ]) {
    testWidgets('list/detail/editor fit $width at scale $scale', (t) async {
      await mount(
        t,
        '/admin/promotions',
        (r) async => jsonResponse(
          r.url.path.endsWith('/redemptions')
              ? page([], total: 0)
              : r.url.path.endsWith('/c1')
              ? promotion()
              : page([promotion()]),
        ),
        width: width,
        scale: scale,
      );
      expect(find.text('Quản lý khuyến mãi'), findsOneWidget);
      await click(t, find.text('Xem chi tiết'));
      expect(find.text('Chi tiết khuyến mãi'), findsOneWidget);
      await click(t, find.text('Sửa mã khuyến mãi'));
      expect(
        t.widget<TextFormField>(field('Mã khuyến mãi')).initialValue,
        'SUMMER_2026',
      );
      expect(
        t
            .widget<TextField>(
              find.descendant(
                of: field('Mã khuyến mãi'),
                matching: find.byType(TextField),
              ),
            )
            .readOnly,
        true,
      );
      await click(t, find.text('Đóng'));
      expect(t.takeException(), isNull);
    });
  }
  testWidgets('search, filters and pagination keep URL query and reset page', (
    t,
  ) async {
    final queries = <Map<String, String>>[];
    await mount(
      t,
      '/admin/promotions?q=SUMMER&status=active&kind=PERCENT&page=2',
      (r) async {
        queries.add(r.url.queryParameters);
        return jsonResponse(
          page(
            [promotion()],
            total: 23,
            page: int.parse(r.url.queryParameters['page'] ?? '1'),
          ),
        );
      },
    );
    expect(queries.last, containsPair('page', '2'));
    expect(queries.last, containsPair('kind', 'PERCENT'));
    await fill(t, 'Tìm kiếm khuyến mãi', 'NEW');
    await click(t, find.text('Tìm kiếm'));
    expect(queries.last, containsPair('q', 'NEW'));
    expect(queries.last, containsPair('status', 'active'));
    expect(queries.last, containsPair('page', '1'));
    await click(t, find.text('Trang sau'));
    expect(queries.last, containsPair('page', '2'));
    await click(t, find.text('Xóa bộ lọc'));
    expect(queries.last.containsKey('status'), false);
    expect(queries.last.containsKey('q'), false);
  });
  for (final width in [375.0, 1440.0]) {
    testWidgets(
      'automatic promotion selects products without requiring a code at $width',
      (t) async {
        Map<String, dynamic>? saved;
        await mount(t, '/admin/promotions', (r) async {
          if (r.method == 'POST') {
            saved = jsonDecode(r.body);
            return jsonResponse({...promotion(), ...saved!}, 201);
          }
          if (r.url.path.endsWith('/products')) {
            return jsonResponse(
              page([
                {'id': 'p1', 'name': 'Áo thử ưu đãi', 'active': true},
              ]),
            );
          }
          return jsonResponse(page([], total: 0));
        }, width: width);
        await click(t, find.text('Thêm khuyến mãi'));
        expect(field('Mã khuyến mãi'), findsNothing);
        expect(field('Lượt tối đa mỗi khách'), findsNothing);
        await fill(t, 'Tên chương trình', 'Ưu đãi mùa mới');
        await fill(t, 'Giá trị giảm', '25000');
        await click(
          t,
          find.widgetWithText(
            DropdownButtonFormField<String>,
            'Phạm vi áp dụng',
          ),
        );
        await click(t, find.text('Một số sản phẩm').last);
        await click(t, find.text('Lưu thay đổi'));
        expect(saved, isNull);
        await click(t, find.text('Chọn sản phẩm (0)'));
        await click(t, find.text('Áo thử ưu đãi'));
        await click(t, find.text('Dùng 1 sản phẩm'));
        await click(t, find.text('Lưu thay đổi'));
        expect(saved, containsPair('application', 'AUTOMATIC'));
        expect(saved, containsPair('scope', 'PRODUCTS'));
        expect(saved!['productIds'], ['p1']);
        expect(saved!.containsKey('code'), false);
        expect(saved!['minSubtotal'], '0');
        expect(saved!['usageLimit'], isNull);
        expect(t.takeException(), isNull);
      },
    );
  }
  testWidgets('mobile list menu confirms toggle and protects used codes', (
    t,
  ) async {
    var writes = 0;
    await mount(t, '/admin/promotions', (r) async {
      if (r.method != 'GET') writes++;
      return jsonResponse(
        page([
          {...promotion(), 'canDelete': false, 'usedCount': 1},
        ]),
      );
    }, width: 375);
    final menu = find.byTooltip('Thao tác khác: SUMMER_2026');
    await click(t, menu);
    final deletion = find.ancestor(
      of: find.text('Xóa mã khuyến mãi'),
      matching: find.byWidgetPredicate((w) => w is PopupMenuItem),
    );
    expect(t.widget<PopupMenuItem>(deletion).enabled, false);
    expect(find.text('Mã có lịch sử đơn hàng chỉ có thể tắt.'), findsOneWidget);
    await click(t, find.text('Tắt mã'));
    expect(find.text('Xác nhận'), findsOneWidget);
    await click(t, find.text('Đóng'));
    expect(writes, 0);
    expect(t.takeException(), isNull);
  });
  testWidgets('unused code deletion from list can be cancelled', (t) async {
    var writes = 0;
    await mount(t, '/admin/promotions', (r) async {
      if (r.method != 'GET') writes++;
      return jsonResponse(page([promotion()]));
    });
    await click(t, find.byTooltip('Thao tác khác: SUMMER_2026'));
    await click(t, find.text('Xóa mã khuyến mãi'));
    expect(find.text('Xác nhận xóa'), findsOneWidget);
    await click(t, find.text('Đóng'));
    expect(writes, 0);
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'creation validates percentage/date range and lets duplicate code be corrected',
    (t) async {
      final writes = <Map<String, dynamic>>[];
      await mount(t, '/admin/promotions', (r) async {
        if (r.method == 'POST') {
          writes.add(jsonDecode(r.body));
          return writes.length == 1
              ? jsonResponse({
                  'error': {
                    'code': 'PROMOTION_CODE_EXISTS',
                    'message': 'Duplicate',
                  },
                }, 409)
              : jsonResponse(promotion(), 201);
        }
        return jsonResponse(page([], total: 0));
      });
      await click(t, find.text('Thêm khuyến mãi'));
      await click(
        t,
        find
            .widgetWithText(DropdownButtonFormField<String>, 'Cách áp dụng')
            .last,
      );
      await click(t, find.text('Khách nhập mã').last);
      await click(t, find.text('Lưu thay đổi'));
      expect(writes, isEmpty);
      await fill(t, 'Mã khuyến mãi', ' summer_2026 ');
      await fill(t, 'Giá trị giảm', '50000');
      await fill(t, 'Bắt đầu (UTC+7)', '2026-12-02 12:30');
      await fill(t, 'Hết hạn (UTC+7)', '2026-12-01 12:30');
      await click(t, find.text('Lưu thay đổi'));
      expect(writes, isEmpty);
      expect(find.text('Hết hạn phải sau ngày bắt đầu.'), findsOneWidget);
      await fill(t, 'Hết hạn (UTC+7)', '2026-12-03 12:30');
      await click(t, find.text('Lưu thay đổi'));
      expect(writes.length, 1);
      expect(
        writes.first,
        containsPair('startsAt', '2026-12-02T05:30:00.000Z'),
      );
      expect(writes.first, containsPair('active', false));
      expect(writes.first, containsPair('usageLimit', null));
      expect(
        find.text('Mã khuyến mãi đã tồn tại. Vui lòng nhập mã khác.'),
        findsOneWidget,
      );
      await fill(t, 'Mã khuyến mãi', 'new_code');
      await click(t, find.text('Lưu thay đổi'));
      expect(writes.last['code'], 'NEW_CODE');
      expect(find.text('Đã thêm mã khuyến mãi.'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'used codes expose history and disable deletion; toggle uses expected version',
    (t) async {
      Map<String, dynamic>? body;
      var row = promotion()
        ..addAll({
          'usedCount': 1,
          'historyCount': 2,
          'canDelete': false,
          'discountTotal': '37500',
        });
      await mount(t, '/admin/promotions/c1', (r) async {
        if (r.method == 'PATCH') {
          body = jsonDecode(r.body);
          row = {...row, 'active': false, 'status': 'inactive', 'version': 5};
          return jsonResponse(row);
        }
        if (r.url.path.endsWith('/redemptions')) {
          return jsonResponse(
            page([
              {
                'id': 'r1',
                'orderId': '12345678-1111-1111-1111-111111111111',
                'discount': '37500',
                'createdAt': '2026-10-24T00:00:00Z',
                'releasedAt': '2026-10-24T01:00:00Z',
                'order': {'status': 'CANCELLED'},
              },
            ]),
          );
        }
        return jsonResponse(row);
      });
      expect(find.text('Đã trả lượt'), findsOneWidget);
      final delete = find.widgetWithText(TextButton, 'Xóa mã khuyến mãi');
      expect(t.widget<TextButton>(delete).onPressed, isNull);
      await click(t, find.text('Tắt mã'));
      await click(t, find.text('Xác nhận'));
      expect(body, {'active': false, 'expectedVersion': 4});
      expect(find.text('Đã tắt'), findsOneWidget);
    },
  );
  testWidgets(
    'deletion confirmation preserves record on cancel and returns to filters on success',
    (t) async {
      var deletes = 0;
      Map<String, dynamic>? body;
      await mount(
        t,
        '/admin/promotions/c1?from=${Uri.encodeComponent('/admin/promotions?q=SUMMER&status=inactive')}',
        (r) async {
          if (r.method == 'DELETE') {
            deletes++;
            body = jsonDecode(r.body);
            return jsonResponse({'deleted': true});
          }
          if (r.url.path.endsWith('/c1') ||
              r.url.path.endsWith('/redemptions')) {
            expect(
              deletes,
              0,
              reason:
                  'Deleted records must not be re-fetched before navigation',
            );
          }
          return jsonResponse(
            r.url.path.endsWith('/redemptions')
                ? page([], total: 0)
                : r.url.path.endsWith('/c1')
                ? promotion()
                : page([], total: 0),
          );
        },
      );
      await click(t, find.text('Xóa mã khuyến mãi'));
      await click(t, find.text('Đóng'));
      expect(deletes, 0);
      await click(t, find.text('Xóa mã khuyến mãi'));
      await click(t, find.text('Xác nhận xóa'));
      expect(deletes, 1);
      expect(body, {'expectedVersion': 4});
      expect(find.text('Quản lý khuyến mãi'), findsOneWidget);
      expect(
        t.widget<TextFormField>(field('Tìm kiếm khuyến mãi')).controller!.text,
        'SUMMER',
      );
    },
  );
  testWidgets('list errors retry into a useful empty state', (t) async {
    var calls = 0;
    await mount(t, '/admin/promotions', (r) async {
      calls++;
      return calls == 1
          ? jsonResponse({
              'error': {'code': 'UNAVAILABLE', 'message': 'Thử lại sau'},
            }, 503)
          : jsonResponse(page([], total: 0));
    });
    expect(find.text('Chưa tải được dữ liệu'), findsOneWidget);
    await click(t, find.text('Thử tải lại'));
    expect(find.text('Chưa có mã khuyến mãi phù hợp'), findsOneWidget);
  });
  testWidgets('ended session prevents submitting an open editor', (t) async {
    var writes = 0;
    final scope = await mount(t, '/admin/promotions', (r) async {
      if (r.method == 'POST') writes++;
      return jsonResponse(page([promotion()]));
    });
    await click(t, find.text('Thêm khuyến mãi'));
    await scope.read(adminAccountProvider.notifier).signOut();
    await t.pumpAndSettle();
    expect(find.text('Lưu thay đổi'), findsNothing);
    expect(writes, 0);
    expect(t.takeException(), isNull);
  });
  testWidgets('percentage over 100 is blocked before sending an update', (
    t,
  ) async {
    var writes = 0;
    await mount(t, '/admin/promotions', (r) async {
      if (r.method == 'PATCH') writes++;
      return jsonResponse(page([promotion()]));
    });
    await click(t, find.byTooltip('Chỉnh sửa SUMMER_2026'));
    await fill(t, 'Giá trị giảm', '101');
    await click(t, find.text('Lưu thay đổi'));
    expect(find.text('Tối đa 100.'), findsOneWidget);
    expect(writes, 0);
  });
  testWidgets('missing detail returns to the list without requesting history', (
    t,
  ) async {
    var history = 0;
    await mount(t, '/admin/promotions/missing', (r) async {
      if (r.url.path.endsWith('/redemptions')) history++;
      return r.url.path.endsWith('/missing')
          ? jsonResponse({
              'error': {'code': 'NOT_FOUND', 'message': 'Missing'},
            }, 404)
          : jsonResponse(page([], total: 0));
    });
    expect(find.text('Không tìm thấy mã khuyến mãi'), findsOneWidget);
    expect(history, 0);
    await click(t, find.text('Về danh sách'));
    expect(find.text('Quản lý khuyến mãi'), findsOneWidget);
  });
  testWidgets(
    'uncertain save cannot be retried and late completion refreshes real data',
    (t) async {
      final pending = Completer<http.Response>();
      var writes = 0, reads = 0;
      await mount(t, '/admin/promotions', (r) async {
        if (r.method == 'PATCH') {
          writes++;
          return pending.future;
        }
        reads++;
        return jsonResponse(page([promotion()]));
      }, timeout: const Duration(milliseconds: 300));
      await click(t, find.byTooltip('Chỉnh sửa SUMMER_2026'));
      await t.tap(find.text('Lưu thay đổi'));
      await t.pump();
      await t.pump(const Duration(seconds: 1));
      await t.pumpAndSettle();
      expect(find.text('Tải lại dữ liệu'), findsOneWidget);
      expect(find.text('Lưu thay đổi'), findsNothing);
      expect(writes, 1);
      final before = reads;
      pending.complete(jsonResponse(promotion()));
      await t.pumpAndSettle();
      expect(reads, greaterThan(before));
      expect(writes, 1);
      await click(t, find.text('Tải lại dữ liệu'));
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('saving is single-flight while server response is pending', (
    t,
  ) async {
    final pending = Completer<http.Response>();
    var writes = 0;
    await mount(t, '/admin/promotions', (r) async {
      if (r.method == 'PATCH') {
        writes++;
        return pending.future;
      }
      return jsonResponse(page([promotion()]));
    });
    await click(t, find.byTooltip('Chỉnh sửa SUMMER_2026'));
    await t.tap(find.text('Lưu thay đổi'));
    await t.pump();
    await t.tap(find.text('Lưu thay đổi'));
    await t.pump();
    expect(writes, 1);
    pending.complete(jsonResponse(promotion()));
    await t.pumpAndSettle();
    expect(find.text('Đã cập nhật mã khuyến mãi.'), findsOneWidget);
  });
  test(
    'date validation rejects calendar overflow and zero year and preserves UTC+7',
    () {
      for (final value in [
        '2026-02-30 12:00',
        '0000-01-01 00:00',
        '2026-12-01 25:00',
        'not a date',
      ]) {
        expect(() => parsePromotionDate(value), throwsFormatException);
      }
      expect(
        parsePromotionDate('2026-12-01 00:30')!.toIso8601String(),
        '2026-11-30T17:30:00.000Z',
      );
    },
  );
}
