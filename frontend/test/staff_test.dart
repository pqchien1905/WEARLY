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
import 'package:nep_storefront/data/remote_account.dart';
import 'package:nep_storefront/features/admin/remote/admin_activity.dart';
import 'remote_account_test.dart' show sessionJson;
import 'remote_commerce_test.dart' show orderJson;
import 'remote_session_test.dart' show jsonResponse;
import 'returns_test.dart' show returnJson;

Map<String, Object?> page(List items) => {
  'items': items,
  'total': items.length,
  'page': 1,
  'limit': 10,
};
Map<String, Object?> staff({String id = 'staff-1'}) => {
  'id': id,
  'name': 'Nhân viên kho',
  'email': 'kho@example.test',
  'role': 'WAREHOUSE',
  'active': true,
  'staffVersion': 4,
  'createdAt': '2026-10-22T00:00:00Z',
};
void main() {
  test('promotion audit values retain their before and after units', () {
    for (final entry in [
      ('PERCENT', '10', 'PERCENT', '20', 'Giá trị giảm: 10% → 20%'),
      (
        'FIXED',
        '10000',
        'FIXED',
        '20000',
        'Giá trị giảm: 10000 VND → 20000 VND',
      ),
      ('FIXED', '10', 'PERCENT', '10', 'Giá trị giảm: 10 VND → 10%'),
      ('PERCENT', '20', 'FIXED', '10000', 'Giá trị giảm: 20% → 10000 VND'),
    ]) {
      expect(
        auditChanges({
          'before': {'kind': entry.$1, 'amount': entry.$2},
          'after': {'kind': entry.$3, 'amount': entry.$4},
        }),
        contains(entry.$5),
      );
    }
  });
  Future<ProviderContainer> setup(
    WidgetTester tester,
    String role,
    String path,
    Future<http.Response> Function(http.Request) handler,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = ApiClient(
      baseUrl: 'http://localhost/api/v1',
      client: MockClient((r) async {
        if (r.url.path.endsWith('/auth/admin/login')) {
          final s = sessionJson();
          (s['user'] as Map)['role'] = role;
          return jsonResponse(s);
        }
        return handler(r);
      }),
    );
    final container = ProviderContainer(
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
        .signIn('', 'an@example.com', 'password');
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: NepApp(router: createRouter(initialLocation: path)),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  test('all assigned staff roles can use the staff login repository', () async {
    for (final role in ['MANAGER', 'WAREHOUSE', 'SUPPORT']) {
      final api = ApiClient(
        baseUrl: 'http://localhost/api/v1',
        client: MockClient((r) async {
          final s = sessionJson();
          (s['user'] as Map)['role'] = role;
          return jsonResponse(s);
        }),
      );
      addTearDown(api.close);
      expect(
        (await RemoteAccountRepository(api, admin: true).signIn(
          name: '',
          email: 'staff@example.test',
          password: 'password',
        )).role,
        role,
      );
    }
  });
  testWidgets('support home hides forbidden navigation and mail action', (
    tester,
  ) async {
    final paths = <String>[];
    await setup(tester, 'SUPPORT', '/admin', (r) async {
      paths.add(r.url.path);
      return jsonResponse({
        'items': [],
        'nextCursor': null,
        'total': 0,
        'page': 1,
        'limit': 10,
      });
    });
    expect(find.text('Hỗ trợ khách hàng'), findsWidgets);
    expect(find.text('Biến thể & kho'), findsNothing);
    expect(find.text('Theo dõi thư'), findsNothing);
    expect(paths, contains('/api/v1/admin/support'));
    expect(paths, isNot(contains('/api/v1/admin/summary')));
  });
  testWidgets('forbidden staff deep link never loads protected data', (
    tester,
  ) async {
    final paths = <String>[];
    await setup(tester, 'SUPPORT', '/admin/inventory', (r) async {
      paths.add(r.url.path);
      return jsonResponse(page([]));
    });
    expect(find.text('Bạn chưa có quyền truy cập'), findsOneWidget);
    expect(paths, isNot(contains('/api/v1/admin/inventory')));
  });
  for (final role in ['SUPPORT', 'WAREHOUSE']) {
    testWidgets('$role order actions respect money and return permissions', (
      tester,
    ) async {
      final paths = <String>[];
      await setup(tester, role, '/admin/orders/order-1', (r) async {
        paths.add(r.url.path);
        return jsonResponse({
          ...orderJson(status: 'DELIVERED'),
          'returns': [returnJson(status: 'APPROVED')],
        });
      });
      expect(find.text('Chi tiết đơn hàng'), findsOneWidget);
      expect(find.text('Đối soát COD'), findsNothing);
      expect(
        find.text('Nhận hàng khách trả'),
        role == 'WAREHOUSE' ? findsOneWidget : findsNothing,
      );
      expect(paths.any((p) => p.endsWith('/refunds')), isFalse);
    });
  }
  testWidgets('warehouse can fulfill but cannot cancel pending orders', (
    tester,
  ) async {
    await setup(
      tester,
      'WAREHOUSE',
      '/admin/orders/order-1',
      (r) async => jsonResponse(orderJson()),
    );
    expect(find.text('Xác nhận đơn'), findsOneWidget);
    expect(find.text('Hủy đơn trước khi gửi'), findsNothing);
  });
  testWidgets(
    'staff edits send displayed version and require reload after conflict',
    (tester) async {
      final writes = <Map<String, dynamic>>[];
      await setup(tester, 'ADMIN', '/admin/staff', (r) async {
        if (r.method == 'PATCH') {
          writes.add(jsonDecode(r.body));
          return jsonResponse({
            'error': {
              'code': 'VERSION_CONFLICT',
              'message': 'Tài khoản đã thay đổi.',
            },
          }, 409);
        }
        return jsonResponse(page([staff()]));
      });
      await tester.tap(find.text('Đổi quyền'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hỗ trợ').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lưu thay đổi'));
      await tester.pumpAndSettle();
      expect(writes.single, {
        'role': 'SUPPORT',
        'active': true,
        'expectedVersion': 4,
      });
      expect(find.text('Tải lại dữ liệu'), findsOneWidget);
      await tester.tap(find.text('Tải lại dữ liệu'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    },
  );
  testWidgets('changing own role clears the revoked admin session', (
    tester,
  ) async {
    final container = await setup(tester, 'ADMIN', '/admin/staff', (r) async {
      if (r.method == 'PATCH') {
        return jsonResponse({
          ...staff(id: 'user-1'),
          'role': 'MANAGER',
          'staffVersion': 5,
        });
      }
      return jsonResponse(
        page([
          {...staff(id: 'user-1'), 'role': 'ADMIN'},
        ]),
      );
    });
    await tester.tap(find.text('Đổi quyền'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Quản lý').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lưu thay đổi'));
    await tester.pumpAndSettle();
    expect(container.read(adminAccountProvider), isNull);
    expect(container.read(adminSessionTokensProvider).accessToken, isNull);
    expect(find.text('Đăng nhập quản trị'), findsWidgets);
  });
  testWidgets('unknown admin links show a working fallback page', (
    tester,
  ) async {
    await setup(
      tester,
      'ADMIN',
      '/admin/unknown-function',
      (r) async => jsonResponse({}),
    );
    expect(find.text('Trang này không còn ở đây'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('audit renders safe old and new values', (tester) async {
    await setup(
      tester,
      'ADMIN',
      '/admin',
      (r) async => jsonResponse(
        r.url.path.endsWith('/audit')
            ? page([
                {
                  'id': 'event',
                  'actorId': 'actor',
                  'targetId': 'item',
                  'action': 'INVENTORY_ADJUSTED',
                  'createdAt': '2026-10-22T00:00:00Z',
                  'details': {
                    'before': {'quantity': 5, 'version': 0},
                    'after': {'quantity': 3, 'version': 1},
                  },
                },
              ])
            : {
                for (final key in [
                  'paidRevenueVnd',
                  'codAwaitingSettlementVnd',
                  'refundedVnd',
                  'netCollectedVnd',
                  'legacyRefundUnverifiedVnd',
                  'extraCollectedVnd',
                ])
                  key: '0',
              },
      ),
    );
    await tester.ensureVisible(find.text('Nhật ký hoạt động'));
    await tester.tap(find.text('Nhật ký hoạt động'));
    await tester.pumpAndSettle();
    expect(find.text('Số lượng: 5 → 3'), findsOneWidget);
  });
}
