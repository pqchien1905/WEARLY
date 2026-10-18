import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:nep_storefront/app/app.dart';
import 'package:nep_storefront/app/account_state.dart';
import 'package:nep_storefront/app/api_providers.dart';
import 'package:nep_storefront/core/network/api_client.dart';
import 'remote_account_test.dart' show sessionJson;
import 'remote_commerce_test.dart' show cartJson, orderJson;
import 'remote_session_test.dart' show jsonResponse;

void main() {
  testWidgets(
    'remote checkout retries safely, shows persisted COD order and cancels it',
    (tester) async {
      var created = false, cancelled = false;
      final keys = <String?>[], bodies = <String>[];
      final api = ApiClient(
        baseUrl: 'http://localhost/api/v1',
        client: MockClient((r) async {
          final path = r.url.path;
          if (path.endsWith('/auth/login')) return jsonResponse(sessionJson());
          if (path.endsWith('/auth/logout')) return jsonResponse({});
          if (path.endsWith('/cart')) {
            return jsonResponse(cartJson(quantity: created ? 0 : 1));
          }
          if (path.endsWith('/addresses')) {
            return jsonResponse([
              {
                'id': 'address-1',
                'label': 'Nhà',
                'recipient': 'Nguyễn An',
                'phone': '0901234567',
                'address': '12 Nguyễn Huệ, TP.HCM',
                'isDefault': true,
              },
            ]);
          }
          if (path.endsWith('/cancel')) {
            cancelled = true;
            return jsonResponse(orderJson(status: 'CANCELLED'));
          }
          if (path.endsWith('/orders/order-1')) {
            return jsonResponse(
              orderJson(status: cancelled ? 'CANCELLED' : 'PENDING'),
            );
          }
          if (path.endsWith('/orders') && r.method == 'POST') {
            keys.add(r.headers['Idempotency-Key']);
            bodies.add(r.body);
            created = true;
            return keys.length == 1
                ? jsonResponse({}, 503)
                : jsonResponse(orderJson(), 201);
          }
          if (path.endsWith('/orders')) {
            return jsonResponse({
              'items': [
                if (created)
                  orderJson(status: cancelled ? 'CANCELLED' : 'PENDING'),
              ],
              'total': created ? 1 : 0,
              'page': 1,
              'limit': 100,
            });
          }
          throw StateError('Unexpected ${r.method} $path');
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
      final router = createRouter(initialLocation: '/checkout');
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: NepApp(router: router),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Đăng nhập để tiếp tục'), findsOneWidget);
      await container
          .read(accountProvider.notifier)
          .signIn('', 'an@example.com', 'example-password');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Chọn địa chỉ đã lưu'));
      await tester.tap(find.text('Chọn địa chỉ đã lưu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nhà — Nguyễn An').last);
      await tester.pumpAndSettle();
      final confirm = find.text(
        'Tôi xác nhận thông tin nhận hàng và đặt đơn COD.',
      );
      await tester.ensureVisible(confirm);
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      final submit = find.widgetWithText(FilledButton, 'Đặt hàng COD');
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(find.textContaining('Chưa xác định được kết quả'), findsOneWidget);
      final retry = find.widgetWithText(
        FilledButton,
        'Kiểm tra lại đơn vừa đặt',
      );
      await tester.ensureVisible(retry);
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(keys.length, 2);
      expect(keys.first, keys.last);
      expect(bodies.first, bodies.last);
      expect(jsonDecode(bodies.first)['addressId'], 'address-1');
      expect(find.text('Đã tiếp nhận đơn hàng'), findsOneWidget);
      expect(find.textContaining('Chưa thu tiền'), findsWidgets);
      router.go('/account/orders/order-1');
      await tester.pumpAndSettle();
      final cancel = find.widgetWithText(OutlinedButton, 'Hủy đơn hàng');
      await tester.ensureVisible(cancel);
      await tester.tap(cancel);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Xác nhận hủy'));
      await tester.pumpAndSettle();
      expect(cancelled, isTrue);
      expect(find.text('Đơn đã hủy'), findsOneWidget);
      await container.read(accountProvider.notifier).signOut();
      await tester.pumpAndSettle();
      expect(find.text('Đăng nhập để tiếp tục'), findsOneWidget);
      expect(find.text('12 Nguyễn Huệ, TP.HCM'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('unsupported remote features disclose unavailability', (
    tester,
  ) async {
    final api = ApiClient(
      baseUrl: 'http://localhost/api/v1',
      client: MockClient((r) async => jsonResponse([])),
    );
    addTearDown(api.close);
    final router = createRouter(initialLocation: '/ai-stylist');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          remoteApiProvider.overrideWithValue(true),
          apiClientProvider.overrideWithValue(api),
          sessionTokensProvider.overrideWithValue(api.tokens),
        ],
        child: NepApp(router: router),
      ),
    );
    for (final path in [
      '/ai-stylist',
      '/virtual-try-on',
      '/wishlist',
      '/account/style',
      '/forgot-password',
      '/admin/settings',
    ]) {
      router.go(path);
      await tester.pumpAndSettle();
      expect(
        find.text('Tính năng chưa được kết nối'),
        findsOneWidget,
        reason: path,
      );
    }
    expect(tester.takeException(), isNull);
  });
}
