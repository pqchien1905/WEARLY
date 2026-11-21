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
import 'package:nep_storefront/core/contact_phone.dart';
import 'remote_account_test.dart' show sessionJson;
import 'remote_session_test.dart' show jsonResponse;
import 'remote_commerce_test.dart' show orderJson;
import 'account_profile_test.dart'
    show mountProfile, field, fieldValue, tap, submit;

const customerId = '12345678-1234-4123-8123-123456789abc';
Map<String, dynamic> customer() => {
  'id': customerId,
  'name': 'Nguyễn Thị Khách Hàng Có Họ Tên Rất Dài',
  'email': 'khach.hang.co.dia.chi.email.dai@example.test',
  'phone': '0901234567',
  'active': true,
  'createdAt': '2026-10-23T17:00:00Z',
  'updatedAt': '2026-10-24T10:00:00Z',
  '_count': {'orders': 31},
  'summary': {
    'totalOrders': 31,
    'deliveredOrders': 12,
    'deliveredValueVnd': '123456789',
    'netPaidVnd': '120000000',
  },
};
http.Response page(
  List<Map<String, dynamic>> items, {
  int current = 1,
  int total = 55,
  int limit = 10,
}) => jsonResponse({
  'items': items,
  'page': current,
  'limit': limit,
  'total': total,
});
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
        if (r.url.path.endsWith('/users/summary')) {
          return jsonResponse({
            'total': 55,
            'active': 53,
            'inactive': 2,
            'newCustomers': 7,
          });
        }
        if (r.url.path.endsWith('/refunds')) {
          return jsonResponse({
            'sources': [],
            'refunds': [],
            'refundedAmount': '0',
          });
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
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: NepApp(router: createRouter(initialLocation: path)),
      ),
    );
    await t.pumpAndSettle();
  }

  Future<void> click(WidgetTester t, Finder finder) async {
    await t.ensureVisible(finder);
    await t.tap(finder);
    await t.pumpAndSettle();
  }

  Future<void> select(WidgetTester t, String label, String option) async {
    await click(t, find.widgetWithText(DropdownButtonFormField<String>, label));
    await click(t, find.text(option).last);
  }

  Future<http.Response> reads(http.Request r) async {
    if (r.url.path.endsWith('/orders')) {
      return page(
        [
          {...orderJson(), 'code': 'WR000001'},
        ],
        limit: 10,
        total: 31,
        current: int.parse(r.url.queryParameters['page'] ?? '1'),
      );
    }
    if (r.url.path.endsWith('/order-1')) {
      return jsonResponse(orderJson());
    }
    if (r.url.path.endsWith('/$customerId')) {
      return jsonResponse(customer());
    }
    return page([
      customer(),
    ], current: int.parse(r.url.queryParameters['page'] ?? '1'));
  }

  for (final width in [360.0, 1440.0]) {
    testWidgets(
      'password reset is available from the list and validates on $width',
      (t) async {
        var writes = 0;
        await mount(
          t,
          '/admin/customers',
          (r) async {
            if (r.method == 'POST') writes++;
            return reads(r);
          },
          width: width,
          scale: 1.5,
        );
        await click(
          t,
          width >= 1400
              ? find.byTooltip('Đặt lại mật khẩu').first
              : find.widgetWithText(TextButton, 'Đặt lại mật khẩu').first,
        );
        expect(find.text('Đặt lại mật khẩu khách hàng'), findsOneWidget);
        final password = find.widgetWithText(TextFormField, 'Mật khẩu mới');
        final confirmation = find.widgetWithText(
          TextFormField,
          'Nhập lại mật khẩu mới',
        );
        expect(t.widget<TextFormField>(password).controller!.text, isEmpty);
        await t.enterText(password, 'short');
        await click(t, find.text('Xác nhận đặt lại'));
        expect(
          find.text('Mật khẩu phải có từ 8 đến 128 ký tự.'),
          findsOneWidget,
        );
        expect(writes, 0);
        await t.enterText(password, 'Customer-reset-2026');
        await t.enterText(confirmation, 'Different-reset-2026');
        await click(t, find.text('Xác nhận đặt lại'));
        expect(find.text('Mật khẩu nhập lại chưa khớp.'), findsOneWidget);
        expect(writes, 0);
        await click(t, find.byTooltip('Hiện mật khẩu mới'));
        expect(find.byTooltip('Ẩn mật khẩu mới'), findsOneWidget);
        expect(t.takeException(), isNull);
        await click(t, find.widgetWithText(TextButton, 'Đóng'));
        expect(find.text('Đặt lại mật khẩu khách hàng'), findsNothing);
        expect(writes, 0);
      },
    );
  }

  testWidgets(
    'password reset submits once, waits for success and refreshes the customer',
    (t) async {
      final pending = Completer<http.Response>();
      var current = customer(), writes = 0;
      await mount(t, '/admin/customers/$customerId', (r) async {
        if (r.method == 'POST') {
          writes++;
          expect(r.url.path, '/api/v1/admin/users/$customerId/reset-password');
          expect(jsonDecode(r.body), {
            'password': 'Customer-reset-2026',
            'expectedUpdatedAt': current['updatedAt'],
          });
          return pending.future;
        }
        if (r.url.path.endsWith('/$customerId')) return jsonResponse(current);
        return reads(r);
      }, role: 'MANAGER');
      await click(t, find.text('Đặt lại mật khẩu'));
      await t.enterText(
        find.widgetWithText(TextFormField, 'Mật khẩu mới'),
        'Customer-reset-2026',
      );
      await t.enterText(
        find.widgetWithText(TextFormField, 'Nhập lại mật khẩu mới'),
        'Customer-reset-2026',
      );
      final submit = find.widgetWithText(FilledButton, 'Xác nhận đặt lại');
      await t.ensureVisible(submit);
      await t.tap(submit);
      await t.pump();
      expect(writes, 1);
      expect(find.text('Đặt lại mật khẩu khách hàng'), findsOneWidget);
      expect(t.widget<FilledButton>(submit).onPressed, isNull);
      current = {...current, 'updatedAt': '2026-11-03T10:00:00Z'};
      pending.complete(jsonResponse(current));
      await t.pumpAndSettle();
      expect(
        find.text('Đã đặt lại mật khẩu. Khách hàng cần đăng nhập lại.'),
        findsOneWidget,
      );
      expect(find.text('Đặt lại mật khẩu khách hàng'), findsNothing);
      await click(t, find.text('Đặt lại mật khẩu'));
      expect(
        t
            .widget<TextFormField>(
              find.widgetWithText(TextFormField, 'Mật khẩu mới'),
            )
            .controller!
            .text,
        isEmpty,
      );
      expect(writes, 1);
      expect(t.takeException(), isNull);
    },
  );

  for (final status in [409, 503]) {
    testWidgets(
      'password reset $status requires reload before another attempt',
      (t) async {
        var writes = 0;
        await mount(t, '/admin/customers/$customerId', (r) async {
          if (r.method == 'POST') {
            writes++;
            return jsonResponse({
              'error': {
                'code': status == 409 ? 'CUSTOMER_CONFLICT' : 'UNAVAILABLE',
              },
            }, status);
          }
          if (r.url.path.endsWith('/$customerId')) {
            return jsonResponse({...customer(), 'active': false});
          }
          return reads(r);
        });
        await click(t, find.text('Đặt lại mật khẩu'));
        expect(
          find.textContaining('Tài khoản đang khóa sẽ vẫn bị khóa.'),
          findsOneWidget,
        );
        await t.enterText(
          find.widgetWithText(TextFormField, 'Mật khẩu mới'),
          'Customer-reset-2026',
        );
        await t.enterText(
          find.widgetWithText(TextFormField, 'Nhập lại mật khẩu mới'),
          'Customer-reset-2026',
        );
        await click(t, find.text('Xác nhận đặt lại'));
        expect(writes, 1);
        expect(find.text('Xác nhận đặt lại'), findsNothing);
        expect(
          find.text('Đã đặt lại mật khẩu. Khách hàng cần đăng nhập lại.'),
          findsNothing,
        );
        await click(t, find.text('Tải lại dữ liệu'));
        expect(find.text('Đặt lại mật khẩu khách hàng'), findsNothing);
        expect(find.text('Mở khóa tài khoản'), findsOneWidget);
        expect(writes, 1);
        expect(t.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'customer search, filters, sort, page size and detail return preserve URL state',
    (t) async {
      final requests = <Uri>[];
      await mount(t, '/admin/customers?page=3&status=hidden', (r) async {
        requests.add(r.url);
        return reads(r);
      });
      await t.enterText(find.byType(TextField), '  Khách  ');
      await click(t, find.widgetWithText(FilledButton, 'Tìm kiếm'));
      expect(requests.last.queryParameters, {
        'page': '1',
        'limit': '10',
        'q': 'Khách',
        'status': 'hidden',
      });
      await select(t, 'Lịch sử mua hàng', 'Đã có đơn hàng');
      await select(t, 'Sắp xếp', 'Nhiều đơn hàng nhất');
      expect(requests.last.queryParameters['orders'], 'has_orders');
      expect(requests.last.queryParameters['sort'], 'orders_desc');
      final before = requests.last.queryParameters;
      await click(t, find.byTooltip('Xem khách hàng').first);
      expect(find.text('Hồ sơ khách hàng'), findsOneWidget);
      await click(t, find.text('Về danh sách khách hàng'));
      expect(requests.last.queryParameters, before);
      await click(
        t,
        find.widgetWithText(DropdownButtonFormField<int>, 'Mỗi trang'),
      );
      await click(t, find.text('50 mục').last);
      expect(requests.last.queryParameters['limit'], '50');
      await click(t, find.text('Xóa bộ lọc'));
      expect(requests.last.queryParameters, {'page': '1', 'limit': '10'});
      expect(t.widget<TextField>(find.byType(TextField)).controller!.text, '');
      await click(t, find.text('Khách hàng mới'));
      expect(requests.last.queryParameters['registered'], '30d');
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
    testWidgets(
      'customer list, detail and edit modal fit $width at scale $scale',
      (t) async {
        await mount(t, '/admin/customers', reads, width: width, scale: scale);
        expect(t.takeException(), isNull);
        final view = width >= 1400
            ? find.byTooltip('Xem khách hàng').first
            : find.widgetWithText(OutlinedButton, 'Xem khách hàng').first;
        await click(t, view);
        expect(find.text('Hồ sơ khách hàng'), findsOneWidget);
        expect(t.takeException(), isNull);
        await click(t, find.text('Chỉnh sửa thông tin'));
        expect(find.text('Chỉnh sửa khách hàng'), findsOneWidget);
        expect(t.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'customer order pages scope by immutable id and survive a round trip to order detail',
    (t) async {
      final requests = <Uri>[];
      await mount(t, '/admin/customers/$customerId?orderPage=2', (r) async {
        requests.add(r.url);
        return reads(r);
      });
      final history = requests.lastWhere((u) => u.path.endsWith('/orders'));
      expect(history.queryParameters, {
        'customerId': customerId,
        'page': '2',
        'limit': '10',
      });
      await click(t, find.widgetWithText(OutlinedButton, 'Xem đơn hàng').first);
      expect(find.text('Chi tiết đơn hàng'), findsOneWidget);
      await click(t, find.text('Về khách hàng'));
      expect(find.text('Hồ sơ khách hàng'), findsOneWidget);
      expect(
        requests.lastWhere((u) => u.path.endsWith('/orders')).queryParameters,
        history.queryParameters,
      );
      await click(t, find.text('Mở trong quản lý đơn'));
      expect(find.text('Quản lý đơn hàng'), findsOneWidget);
      expect(requests.last.queryParameters['customerId'], customerId);
    },
  );
  testWidgets(
    'customer edits validate, preserve draft on duplicate phone and only submit dirty fields',
    (t) async {
      var current = customer();
      final writes = <Map<String, dynamic>>[];
      await mount(t, '/admin/customers/$customerId', (r) async {
        if (r.method == 'PATCH') {
          final data = jsonDecode(r.body) as Map<String, dynamic>;
          writes.add(data);
          if (writes.length == 1) {
            return jsonResponse({
              'error': {'code': 'PHONE_ALREADY_EXISTS'},
            }, 409);
          }
          current = {...current, ...data};
          return jsonResponse(current);
        }
        if (r.url.path.endsWith('/$customerId')) return jsonResponse(current);
        return reads(r);
      });
      await click(t, find.text('Chỉnh sửa thông tin'));
      await t.enterText(find.widgetWithText(TextFormField, 'Email'), 'bad');
      await click(t, find.text('Lưu thay đổi'));
      expect(writes, isEmpty);
      await t.enterText(
        find.widgetWithText(TextFormField, 'Email'),
        current['email'],
      );
      await t.enterText(
        find.widgetWithText(TextFormField, 'Số điện thoại'),
        '0912345678',
      );
      await click(t, find.text('Lưu thay đổi'));
      expect(
        find.textContaining('Số điện thoại đã được tài khoản khác'),
        findsOneWidget,
      );
      expect(find.text('Tải lại dữ liệu'), findsNothing);
      await t.enterText(
        find.widgetWithText(TextFormField, 'Số điện thoại'),
        '0987654321',
      );
      await click(t, find.text('Lưu thay đổi'));
      expect(writes.last, {
        'expectedUpdatedAt': '2026-10-24T10:00:00Z',
        'phone': '0987654321',
      });
      expect(find.text('Đã lưu thông tin khách hàng.'), findsOneWidget);
    },
  );
  testWidgets(
    'locking awaits one mutation, confirms result and refreshes active state',
    (t) async {
      final pending = Completer<http.Response>();
      var current = customer(), writes = 0;
      await mount(t, '/admin/customers/$customerId', (r) async {
        if (r.method == 'PATCH') {
          writes++;
          expect(r.url.path.endsWith('/status'), isTrue);
          expect(jsonDecode(r.body), {
            'active': false,
            'expectedUpdatedAt': '2026-10-24T10:00:00Z',
          });
          return pending.future;
        }
        if (r.url.path.endsWith('/$customerId')) return jsonResponse(current);
        return reads(r);
      });
      await click(t, find.text('Khóa tài khoản'));
      await t.tap(find.text('Lưu thay đổi'));
      await t.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(writes, 1);
      current = {...current, 'active': false};
      pending.complete(jsonResponse(current));
      await t.pumpAndSettle();
      expect(find.text('Mở khóa tài khoản'), findsOneWidget);
      expect(find.text('Đã khóa tài khoản khách hàng.'), findsOneWidget);
    },
  );
  testWidgets(
    'stale customer edits require reload and show the current record',
    (t) async {
      var writes = 0;
      await mount(t, '/admin/customers/$customerId', (r) async {
        if (r.method == 'PATCH') {
          writes++;
          return jsonResponse({
            'error': {'code': 'CUSTOMER_CONFLICT'},
          }, 409);
        }
        if (r.url.path.endsWith('/$customerId')) {
          return jsonResponse({
            ...customer(),
            'name': writes > 0 ? 'Tên từ máy khác' : customer()['name'],
          });
        }
        return reads(r);
      });
      await click(t, find.text('Chỉnh sửa thông tin'));
      await t.enterText(
        find.widgetWithText(TextFormField, 'Họ và tên'),
        'Tên mới',
      );
      await click(t, find.text('Lưu thay đổi'));
      expect(find.text('Lưu thay đổi'), findsNothing);
      await click(t, find.text('Tải lại dữ liệu'));
      expect(find.text('Tên từ máy khác'), findsOneWidget);
      expect(writes, 1);
    },
  );
  testWidgets(
    'list failure retries and renders empty results without fake rows',
    (t) async {
      var calls = 0;
      await mount(t, '/admin/customers?q=missing', (r) async {
        calls++;
        return calls == 1
            ? jsonResponse({
                'error': {'code': 'UNAVAILABLE'},
              }, 503)
            : page([], total: 0);
      });
      expect(find.text('Chưa tải được dữ liệu'), findsOneWidget);
      await click(t, find.text('Thử tải lại'));
      expect(find.text('Không tìm thấy khách hàng'), findsOneWidget);
      expect(find.text('Xem khách hàng'), findsNothing);
    },
  );
  testWidgets(
    'creates a customer on mobile, validates passwords and retains duplicate email draft',
    (t) async {
      final writes = <Map<String, dynamic>>[];
      await mount(t, '/admin/customers', (r) async {
        if (r.method == 'POST') {
          writes.add(jsonDecode(r.body) as Map<String, dynamic>);
          if (writes.length == 1) {
            return jsonResponse({
              'error': {'code': 'EMAIL_ALREADY_EXISTS'},
            }, 409);
          }
          return jsonResponse({...customer(), ...writes.last});
        }
        return reads(r);
      }, width: 375);
      await click(t, find.text('Thêm khách hàng'));
      await click(t, find.text('Tạo tài khoản'));
      expect(writes, isEmpty);
      await t.enterText(
        find.widgetWithText(TextFormField, 'Họ và tên'),
        ' Khách mới ',
      );
      await t.enterText(
        find.widgetWithText(TextFormField, 'Email'),
        ' NEW@EXAMPLE.TEST ',
      );
      await t.enterText(
        find.widgetWithText(TextFormField, 'Số điện thoại'),
        '0912345678',
      );
      await t.enterText(
        find.widgetWithText(TextFormField, 'Mật khẩu'),
        'Customers-test-2026',
      );
      await t.enterText(
        find.widgetWithText(TextFormField, 'Nhập lại mật khẩu'),
        'mismatch',
      );
      await click(t, find.text('Tạo tài khoản'));
      expect(find.text('Mật khẩu nhập lại chưa khớp.'), findsOneWidget);
      expect(writes, isEmpty);
      await t.enterText(
        find.widgetWithText(TextFormField, 'Nhập lại mật khẩu'),
        'Customers-test-2026',
      );
      await click(t, find.text('Tạo tài khoản'));
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Khách mới'), findsNothing);
      expect(find.text('Tải lại dữ liệu'), findsNothing);
      await t.enterText(
        find.widgetWithText(TextFormField, 'Email'),
        ' OTHER@EXAMPLE.TEST ',
      );
      await click(t, find.text('Tạo tài khoản'));
      expect(writes.last, {
        'name': 'Khách mới',
        'email': 'other@example.test',
        'phone': '0912345678',
        'password': 'Customers-test-2026',
      });
      expect(find.text('Hồ sơ khách hàng'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'list actions edit and lock directly, deletion can be cancelled then refreshes the list',
    (t) async {
      var current = customer(), deleted = false, deletes = 0;
      await mount(t, '/admin/customers', (r) async {
        if (r.method == 'PATCH') {
          current = {...current, ...jsonDecode(r.body) as Map<String, dynamic>};
          return jsonResponse(current);
        }
        if (r.method == 'DELETE') {
          deletes++;
          expect(jsonDecode(r.body), {
            'expectedUpdatedAt': current['updatedAt'],
          });
          deleted = true;
          return jsonResponse({'id': customerId});
        }
        return page(deleted ? [] : [current], total: deleted ? 0 : 1);
      });
      await click(t, find.byTooltip('Chỉnh sửa khách hàng'));
      await t.enterText(
        find.widgetWithText(TextFormField, 'Họ và tên'),
        'Tên sửa từ danh sách',
      );
      await click(t, find.text('Lưu thay đổi'));
      expect(find.text('Tên sửa từ danh sách'), findsOneWidget);
      await click(t, find.byTooltip('Khóa tài khoản'));
      await click(t, find.text('Lưu thay đổi'));
      expect(current['active'], isFalse);
      expect(find.byTooltip('Mở khóa tài khoản'), findsOneWidget);
      await click(t, find.byTooltip('Xóa tài khoản'));
      expect(
        find.textContaining('Lịch sử đơn hàng và thông tin liên quan'),
        findsOneWidget,
      );
      await click(t, find.text('Đóng'));
      expect(deletes, 0);
      await click(t, find.byTooltip('Xóa tài khoản'));
      await click(t, find.text('Xác nhận xóa'));
      expect(deletes, 1);
      expect(find.text('Chưa có khách hàng'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'deleting from detail submits once and returns to the filtered list',
    (t) async {
      final pending = Completer<http.Response>();
      var writes = 0;
      final requests = <Uri>[];
      await mount(
        t,
        '/admin/customers/$customerId?from=${Uri.encodeComponent('/admin/customers?q=khach')}',
        (r) async {
          requests.add(r.url);
          if (r.method == 'DELETE') {
            writes++;
            return pending.future;
          }
          return reads(r);
        },
      );
      await click(t, find.text('Xóa tài khoản'));
      await t.tap(find.text('Xác nhận xóa'));
      await t.pump();
      final button = t.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Xác nhận xóa'),
      );
      expect(button.onPressed, isNull);
      expect(writes, 1);
      pending.complete(jsonResponse({'id': customerId}));
      await t.pumpAndSettle();
      expect(find.text('Quản lý khách hàng'), findsOneWidget);
      expect(
        requests
            .lastWhere((u) => u.path.endsWith('/admin/users'))
            .queryParameters['q'],
        'khach',
      );
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'access checkbox creates staff on mobile, retains duplicate username draft and opens filtered staff list',
    (t) async {
      final writes = <Map<String, dynamic>>[];
      final requests = <Uri>[];
      await mount(t, '/admin/customers', (r) async {
        requests.add(r.url);
        if (r.method == 'POST') {
          writes.add(jsonDecode(r.body) as Map<String, dynamic>);
          if (writes.length == 1) {
            return jsonResponse({
              'error': {'code': 'USERNAME_ALREADY_EXISTS'},
            }, 409);
          }
          return jsonResponse({
            ...customer(),
            ...writes.last,
            'role': writes.last['adminRole'],
          });
        }
        return reads(r);
      }, width: 375);
      await click(t, find.text('Thêm khách hàng'));
      expect(find.text('Tên đăng nhập quản trị'), findsNothing);
      await t.enterText(
        find.widgetWithText(TextFormField, 'Họ và tên'),
        'Nhân sự mới',
      );
      await t.enterText(
        find.widgetWithText(TextFormField, 'Email'),
        'staff@example.test',
      );
      await t.enterText(
        find.widgetWithText(TextFormField, 'Mật khẩu'),
        'Staff-access-2026',
      );
      await t.enterText(
        find.widgetWithText(TextFormField, 'Nhập lại mật khẩu'),
        'Staff-access-2026',
      );
      await click(t, find.text('Có quyền truy cập trang quản trị'));
      expect(
        t
            .widget<DropdownButtonFormField<String>>(
              find.byType(DropdownButtonFormField<String>).last,
            )
            .initialValue,
        'MANAGER',
      );
      await click(t, find.text('Tạo tài khoản'));
      expect(writes, isEmpty);
      await t.enterText(
        find.widgetWithText(TextFormField, 'Tên đăng nhập quản trị'),
        ' STAFF.NEW ',
      );
      await select(t, 'Vai trò quản trị', 'Kho');
      await click(t, find.text('Tạo tài khoản'));
      expect(
        find.textContaining('Tên đăng nhập đã được tài khoản khác'),
        findsOneWidget,
      );
      expect(find.text('Tải lại dữ liệu'), findsNothing);
      await t.enterText(
        find.widgetWithText(TextFormField, 'Tên đăng nhập quản trị'),
        ' STAFF.OTHER ',
      );
      await click(t, find.text('Tạo tài khoản'));
      expect(writes.last, {
        'name': 'Nhân sự mới',
        'email': 'staff@example.test',
        'phone': '',
        'password': 'Staff-access-2026',
        'adminAccess': true,
        'adminRole': 'WAREHOUSE',
        'username': 'staff.other',
      });
      expect(find.text('Nhân sự & quyền truy cập'), findsOneWidget);
      expect(
        requests
            .lastWhere((u) => u.path.endsWith('/admin/staff'))
            .queryParameters['email'],
        'staff@example.test',
      );
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'access checkbox promotes an existing customer and sends the version with the selected role',
    (t) async {
      Map<String, dynamic>? saved;
      await mount(t, '/admin/customers/$customerId', (r) async {
        if (r.method == 'PATCH') {
          saved = jsonDecode(r.body) as Map<String, dynamic>;
          return jsonResponse({
            ...customer(),
            ...saved!,
            'role': saved!['adminRole'],
          });
        }
        return reads(r);
      });
      await click(t, find.text('Chỉnh sửa thông tin'));
      await click(t, find.text('Có quyền truy cập trang quản trị'));
      await t.enterText(
        find.widgetWithText(TextFormField, 'Tên đăng nhập quản trị'),
        'existing.staff',
      );
      await select(t, 'Vai trò quản trị', 'Quản trị viên');
      await click(t, find.text('Lưu thay đổi'));
      expect(saved, {
        'expectedUpdatedAt': '2026-10-24T10:00:00Z',
        'adminAccess': true,
        'adminRole': 'ADMIN',
        'username': 'existing.staff',
      });
      expect(find.text('Nhân sự & quyền truy cập'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'manager sees disabled access checkbox and can still edit customer details',
    (t) async {
      Map<String, dynamic>? saved;
      await mount(t, '/admin/customers/$customerId', (r) async {
        if (r.method == 'PATCH') {
          saved = jsonDecode(r.body) as Map<String, dynamic>;
          return jsonResponse({...customer(), ...saved!});
        }
        return reads(r);
      }, role: 'MANAGER');
      await click(t, find.text('Chỉnh sửa thông tin'));
      expect(
        t.widget<CheckboxListTile>(find.byType(CheckboxListTile)).onChanged,
        isNull,
      );
      expect(
        find.text('Chỉ Quản trị viên được cấp quyền này.'),
        findsOneWidget,
      );
      await t.enterText(
        find.widgetWithText(TextFormField, 'Họ và tên'),
        'Tên chỉnh sửa',
      );
      await click(t, find.text('Lưu thay đổi'));
      expect(saved, {
        'expectedUpdatedAt': '2026-10-24T10:00:00Z',
        'name': 'Tên chỉnh sửa',
      });
    },
  );

  testWidgets('missing customer has a safe route back', (t) async {
    await mount(
      t,
      '/admin/customers/$customerId',
      (r) async => jsonResponse({
        'error': {'code': 'NOT_FOUND'},
      }, 404),
    );
    expect(find.text('Không tìm thấy khách hàng'), findsOneWidget);
    expect(find.text('Về danh sách khách hàng'), findsOneWidget);
  });
  test(
    'contact validation accepts normalized international and domestic equivalents',
    () {
      for (final phone in [
        '0901234567',
        '+84 901 234 567',
        '0084(901)234-567',
        '84901234567',
      ]) {
        expect(normalizedContactPhone(phone), '0901234567');
        expect(contactPhoneValidation(phone), isNull);
      }
      expect(contactPhoneValidation('123'), isNotNull);
      expect(contactPhoneValidation('090abc12345'), isNotNull);
      expect(contactPhoneValidation(''), isNull);
    },
  );
  testWidgets(
    'customer profile retains a rejected duplicate phone for correction',
    (t) async {
      await mountProfile(
        t,
        (r) async => jsonResponse({
          'error': {
            'code': 'PHONE_ALREADY_EXISTS',
            'message': 'Số điện thoại đã được tài khoản khác sử dụng.',
          },
        }, 409),
      );
      await t.enterText(field('Điện thoại (không bắt buộc)'), '0987654321');
      await tap(t, submit);
      expect(
        find.textContaining('Số điện thoại đã được tài khoản khác sử dụng'),
        findsWidgets,
      );
      expect(fieldValue(t, 'Điện thoại (không bắt buộc)'), '0987654321');
    },
  );
}
