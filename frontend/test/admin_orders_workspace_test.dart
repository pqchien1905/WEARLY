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
import 'remote_commerce_test.dart' show orderJson;

Map<String, dynamic> listJson({
  int page = 1,
  int total = 65,
  bool empty = false,
}) => {
  'items': empty
      ? []
      : [
          {
            ...orderJson(),
            'code': 'WR0000A1',
            '_count': {'items': 1},
            'addressSnapshot': {
              'recipient': 'Nguyễn Thị Khách Hàng Với Tên Rất Dài Để Kiểm Tra',
              'phone': '0901234567',
              'address': '12 Nguyễn Huệ',
            },
            'user': {'name': 'An', 'email': 'an@example.test'},
          },
        ],
  'page': page,
  'total': empty ? 0 : total,
  'limit': 10,
  'statusCounts': {'PENDING': 40, 'DELIVERED': 25},
};

void main() {
  Future<void> mount(
    WidgetTester tester,
    String path,
    Future<http.Response> Function(http.Request) handle, {
    double width = 1440,
    double scale = 1,
    String role = 'ADMIN',
  }) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final api = ApiClient(
      baseUrl: 'http://localhost/api/v1',
      client: MockClient((r) async {
        if (r.url.path.endsWith('/login')) {
          final data = sessionJson();
          (data['user'] as Map)['role'] = role;
          return jsonResponse(data);
        }
        if (r.url.path.endsWith('/refund-state')) {
          return jsonResponse({
            'error': {'code': 'NOT_FOUND'},
          }, 404);
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

  Future<void> choose(WidgetTester tester, String label, String option) async {
    final dropdown = find.widgetWithText(
      DropdownButtonFormField<String>,
      label,
    );
    await tester.ensureVisible(dropdown);
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text(option).last);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'order filters and sorting reach the server, reset page, and survive detail navigation',
    (tester) async {
      final reads = <Uri>[];
      await mount(
        tester,
        '/admin/orders?page=3&provider=cod&sort=total_desc&from=2026-10-24&to=2026-10-24',
        (r) async {
          reads.add(r.url);
          if (r.url.path.endsWith('/order-1')) {
            return jsonResponse({...orderJson(), 'version': 0});
          }
          return jsonResponse(
            listJson(
              page: int.tryParse(r.url.queryParameters['page'] ?? '') ?? 1,
            ),
          );
        },
        role: 'WAREHOUSE',
      );
      expect(reads.last.queryParameters['page'], '3');
      await tester.enterText(find.byType(TextField), '  WR0000A1  ');
      await tester.tap(find.widgetWithText(FilledButton, 'Tìm kiếm'));
      await tester.pumpAndSettle();
      expect(reads.last.queryParameters, {
        'page': '1',
        'limit': '10',
        'provider': 'cod',
        'sort': 'total_desc',
        'from': '2026-10-24',
        'to': '2026-10-24',
        'q': 'WR0000A1',
      });
      await choose(tester, 'Thanh toán', 'COD chờ đối soát');
      expect(reads.last.queryParameters['paymentStatus'], 'COD_UNSETTLED');
      await choose(tester, 'Sắp xếp', 'Cũ nhất');
      expect(reads.last.queryParameters['sort'], 'oldest');
      final before = reads.last.queryParameters;
      await tester.ensureVisible(find.byTooltip('Xem đơn hàng').first);
      await tester.tap(find.byTooltip('Xem đơn hàng').first);
      await tester.pumpAndSettle();
      expect(find.text('Chi tiết đơn hàng'), findsOneWidget);
      await tester.tap(find.text('Về danh sách đơn'));
      await tester.pumpAndSettle();
      expect(reads.last.queryParameters, before);
      await tester.tap(find.text('Xóa bộ lọc'));
      await tester.pumpAndSettle();
      expect(reads.last.queryParameters, {'page': '1', 'limit': '10'});
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '',
      );
      expect(tester.takeException(), isNull);
    },
  );
  for (final (width, scale) in [
    (360.0, 1.0),
    (768.0, 1.0),
    (1440.0, 1.0),
    (375.0, 1.5),
    (1440.0, 1.5),
  ]) {
    testWidgets('order list and details fit $width px at scale $scale', (
      tester,
    ) async {
      await mount(
        tester,
        '/admin/orders',
        (r) async => jsonResponse(listJson()),
        width: width,
        scale: scale,
        role: 'WAREHOUSE',
      );
      expect(find.text('Quản lý đơn hàng'), findsOneWidget);
      expect(find.text('WR0000A1'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await mount(
        tester,
        '/admin/orders/order-1',
        (r) async => jsonResponse({...orderJson(), 'version': 0}),
        width: width,
        scale: scale,
        role: 'WAREHOUSE',
      );
      expect(find.text('Thông tin giao nhận'), findsOneWidget);
      expect(find.text('Tổng cộng'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('failed list offers retry and empty search remains recoverable', (
    tester,
  ) async {
    var reads = 0;
    await mount(tester, '/admin/orders?q=none', (r) async {
      reads++;
      return reads == 1
          ? jsonResponse({
              'error': {'code': 'UNAVAILABLE'},
            }, 503)
          : jsonResponse(listJson(empty: true));
    });
    expect(find.text('Chưa tải được dữ liệu'), findsOneWidget);
    await tester.ensureVisible(find.text('Thử tải lại'));
    await tester.tap(find.text('Thử tải lại'));
    await tester.pumpAndSettle();
    expect(find.text('Không tìm thấy đơn hàng'), findsOneWidget);
    expect(find.text('Xóa bộ lọc'), findsOneWidget);
    expect(reads, 2);
  });
  testWidgets(
    'a status update shows progress, sends once, refreshes and confirms success',
    (tester) async {
      var status = 'PENDING', version = 0, writes = 0;
      final pending = Completer<http.Response>();
      await mount(tester, '/admin/orders/order-1', (r) async {
        if (r.method == 'PATCH') {
          writes++;
          expect(jsonDecode(r.body), {
            'status': 'CONFIRMED',
            'expectedVersion': 0,
          });
          return pending.future;
        }
        return jsonResponse({...orderJson(status: status), 'version': version});
      }, role: 'WAREHOUSE');
      await tester.tap(find.widgetWithText(FilledButton, 'Xác nhận đơn'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Lưu thay đổi'));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(writes, 1);
      status = 'CONFIRMED';
      version = 1;
      pending.complete(
        jsonResponse({...orderJson(status: status), 'version': version}),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Đã cập nhật đơn'), findsOneWidget);
      expect(find.text('Bắt đầu giao hàng'), findsOneWidget);
      expect(writes, 1);
    },
  );
  testWidgets(
    'conflict requires canonical reload and support cannot mutate orders',
    (tester) async {
      var writes = 0;
      await mount(tester, '/admin/orders/order-1', (r) async {
        if (r.method == 'PATCH') {
          writes++;
          return jsonResponse({
            'error': {'code': 'ORDER_STATE_CONFLICT'},
          }, 409);
        }
        return jsonResponse({
          ...orderJson(status: writes == 0 ? 'PENDING' : 'CONFIRMED'),
          'version': writes,
        });
      }, role: 'WAREHOUSE');
      await tester.tap(find.widgetWithText(FilledButton, 'Xác nhận đơn'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Lưu thay đổi'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Đơn hàng đã thay đổi'), findsOneWidget);
      expect(find.text('Lưu thay đổi'), findsNothing);
      await tester.tap(find.text('Tải lại dữ liệu'));
      await tester.pumpAndSettle();
      expect(writes, 1);
      expect(find.text('Bắt đầu giao hàng'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await mount(
        tester,
        '/admin/orders/order-1',
        (r) async => jsonResponse({...orderJson(), 'version': 0}),
        role: 'SUPPORT',
      );
      expect(find.text('Xác nhận đơn'), findsNothing);
      expect(find.text('Hủy đơn trước khi gửi'), findsNothing);
      expect(find.text('Đối soát COD'), findsNothing);
    },
  );
  testWidgets(
    'missing and malformed order details have controlled recovery states',
    (tester) async {
      await mount(
        tester,
        '/admin/orders/missing',
        (r) async => jsonResponse({
          'error': {'code': 'NOT_FOUND'},
        }, 404),
        role: 'WAREHOUSE',
      );
      expect(find.text('Không tìm thấy đơn hàng'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await mount(
        tester,
        '/admin/orders/bad',
        (r) async => jsonResponse({'id': 'bad'}),
        role: 'WAREHOUSE',
      );
      expect(find.text('Dữ liệu đơn hàng chưa đầy đủ'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
