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
    'successful order detail cannot certify a cart whose fetch failed',
    (tester) async {
      var cartUnavailable = true;
      final api = ApiClient(
        baseUrl: 'http://localhost/api/v1',
        client: MockClient((request) async {
          if (request.url.path.endsWith('/auth/login')) {
            return jsonResponse(sessionJson());
          }
          if (request.url.path.endsWith('/cart')) {
            return cartUnavailable
                ? jsonResponse({}, 503)
                : jsonResponse(cartJson());
          }
          if (request.url.path.endsWith('/orders/order-1')) {
            return jsonResponse(orderJson());
          }
          if (request.url.path.endsWith('/orders')) {
            return jsonResponse({
              'items': [orderJson()],
              'total': 1,
              'page': 1,
              'limit': 100,
            });
          }
          throw StateError('Unexpected request');
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
      final router = createRouter(initialLocation: '/cart');
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: NepApp(router: router),
        ),
      );
      await tester.pumpAndSettle();
      await container
          .read(accountProvider.notifier)
          .signIn('', 'an@example.com', 'example-password');
      await tester.pumpAndSettle();
      expect(find.text('Chưa tải được dữ liệu'), findsOneWidget);
      router.go('/account/orders/order-1');
      await tester.pumpAndSettle();
      expect(find.text('Chi tiết đơn order-1'), findsOneWidget);
      router.go('/cart');
      await tester.pumpAndSettle();
      expect(find.text('Chưa tải được dữ liệu'), findsOneWidget);
      expect(find.text('Tủ đồ đang chờ bạn.'), findsNothing);
      cartUnavailable = false;
      final retry = find.widgetWithText(FilledButton, 'Thử tải lại');
      await tester.ensureVisible(retry);
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(find.text('Áo cotton'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'remote checkout works during style outage, retries COD safely and cancels',
    (tester) async {
      var created = false, cancelled = false;
      Map<String, Object?> snapshot() => {
        ...orderJson(status: cancelled ? 'CANCELLED' : 'PENDING'),
        'shipping': '50000',
        'total': '540000',
      };
      final keys = <String?>[], bodies = <String>[];
      final api = ApiClient(
        baseUrl: 'http://localhost/api/v1',
        client: MockClient((r) async {
          final path = r.url.path;
          if (path.endsWith('/users/me/style')) {
            return jsonResponse({}, 503);
          }
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
            return jsonResponse(snapshot());
          }
          if (path.endsWith('/orders/order-1')) {
            return jsonResponse(snapshot());
          }
          if (path.endsWith('/orders') && r.method == 'POST') {
            keys.add(r.headers['Idempotency-Key']);
            bodies.add(r.body);
            created = true;
            return keys.length == 1
                ? jsonResponse({}, 503)
                : jsonResponse(snapshot(), 201);
          }
          if (path.endsWith('/orders')) {
            return jsonResponse({
              'items': [if (created) snapshot()],
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
      await tester.ensureVisible(find.text('Giao nhanh · 50.000đ'));
      await tester.tap(find.text('Giao nhanh · 50.000đ'));
      await tester.ensureVisible(confirm);
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      final submit = find.widgetWithText(FilledButton, 'Đặt hàng COD');
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(find.textContaining('Chưa xác định được kết quả'), findsOneWidget);
      router.go('/cart');
      await tester.pumpAndSettle();
      router.go('/checkout');
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(
              find.widgetWithText(TextFormField, 'Họ và tên'),
            )
            .controller!
            .text,
        'Nguyễn An',
      );
      expect(
        tester
            .widget<CheckboxListTile>(
              find.widgetWithText(CheckboxListTile, 'Giao nhanh · 50.000đ'),
            )
            .value,
        isTrue,
      );
      expect(find.text('540.000 ₫'), findsOneWidget);
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
      expect(jsonDecode(bodies.first)['shippingMethod'], 'express');
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
    for (final path in ['/ai-stylist', '/virtual-try-on']) {
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
